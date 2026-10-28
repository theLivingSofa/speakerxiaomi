import Foundation

/// One audio channel inside a Float32 buffer. `stride` is 1 for separate channel buffers
/// and the channel count for interleaved buffers.
public struct ChannelPointer {
    public var base: UnsafeMutablePointer<Float>
    public var stride: Int

    public init(base: UnsafeMutablePointer<Float>, stride: Int) {
        self.base = base
        self.stride = stride
    }
}

/// Runs the EQ chain in place on Float32 audio.
///
/// Built for the real-time audio thread: all memory is allocated up front, and `setParameters`
/// and `process` don't allocate, lock or keep references to the arrays passed in.
/// Call both from the same thread.
public final class EQProcessor {
    public static let maxChannels = 8

    public let sampleRate: Double
    private let sectionCount = EQDesign.sectionCount
    private let current: UnsafeMutablePointer<BiquadCoefficients>
    private let previous: UnsafeMutablePointer<BiquadCoefficients>
    /// Two filter memory values per section per channel.
    private let state: UnsafeMutablePointer<Double>
    private let stateCount: Int

    private var preamp = 1.0, previousPreamp = 1.0
    private var leftGain = 1.0, previousLeftGain = 1.0
    private var rightGain = 1.0, previousRightGain = 1.0
    private var mono = false
    private var limiterOn = false
    private var bypass = true
    /// When true, the next buffer fades from the previous values to the current ones, which avoids clicks.
    private var ramping = false

    private var limiterGain = 1.0
    private let limiterRelease: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        current = .allocate(capacity: sectionCount)
        current.initialize(repeating: .identity, count: sectionCount)
        previous = .allocate(capacity: sectionCount)
        previous.initialize(repeating: .identity, count: sectionCount)
        stateCount = Self.maxChannels * sectionCount * 2
        state = .allocate(capacity: stateCount)
        state.initialize(repeating: 0, count: stateCount)
        // Gain recovers with a time constant of about 100 ms after a peak.
        limiterRelease = 1 - exp(-1 / (0.1 * max(sampleRate, 1)))
    }

    deinit {
        current.deallocate()
        previous.deallocate()
        state.deallocate()
    }

    /// Load new settings. They fade in over the next buffer.
    public func setParameters(_ p: EQParameters) {
        guard p.sections.count == sectionCount else { return }
        let resuming = bypass && !p.bypass
        for i in 0..<sectionCount {
            previous[i] = current[i]
            current[i] = p.sections[i]
        }
        previousPreamp = preamp
        previousLeftGain = leftGain
        previousRightGain = rightGain
        preamp = p.preamp
        leftGain = p.leftGain
        rightGain = p.rightGain
        mono = p.mono
        limiterOn = p.limiter
        bypass = p.bypass

        if resuming {
            // Filter memory is stale after a bypass, so start clean with no fade.
            reset()
            snapToCurrent()
        } else {
            ramping = true
        }
    }

    public func reset() {
        state.update(repeating: 0, count: stateCount)
        limiterGain = 1
    }

    /// Process `frames` samples of each channel in place.
    public func process(_ channels: UnsafePointer<ChannelPointer>, channelCount: Int, frames: Int) {
        guard frames > 0, channelCount > 0 else { return }
        if bypass {
            snapToCurrent()
            return
        }
        let count = min(channelCount, Self.maxChannels)
        let step = 1.0 / Double(frames)
        var unstable = false

        // 1. Preamp and filters, one channel at a time.
        for ch in 0..<count {
            let channel = channels[ch]
            let st = state + ch * sectionCount * 2
            var sample = channel.base
            for i in 0..<frames {
                let t = ramping ? Double(i + 1) * step : 1
                var x = Double(sample.pointee) * lerp(previousPreamp, preamp, t)
                for s in 0..<sectionCount {
                    let c = ramping ? blend(previous[s], current[s], t) : current[s]
                    let z = st + s * 2
                    let y = c.b0 * x + z[0]
                    z[0] = c.b1 * x - c.a1 * y + z[1]
                    z[1] = c.b2 * x - c.a2 * y
                    x = y
                }
                if !x.isFinite {
                    x = 0
                    unstable = true
                }
                sample.pointee = Float(x)
                sample += channel.stride
            }
        }

        // 2. Mono, balance and limiter, one frame at a time across channels.
        let stereo = count >= 2
        let ceiling = EQDesign.limiterCeiling
        let left = channels[0]
        let right = stereo ? channels[1] : channels[0]
        for i in 0..<frames {
            if stereo {
                let t = ramping ? Double(i + 1) * step : 1
                var l = Double(left.base[i * left.stride])
                var r = Double(right.base[i * right.stride])
                if mono {
                    let m = (l + r) * 0.5
                    l = m
                    r = m
                }
                left.base[i * left.stride] = Float(l * lerp(previousLeftGain, leftGain, t))
                right.base[i * right.stride] = Float(r * lerp(previousRightGain, rightGain, t))
            }
            if limiterOn {
                var peak = 0.0
                for ch in 0..<count {
                    let c = channels[ch]
                    peak = max(peak, abs(Double(c.base[i * c.stride])))
                }
                let target = peak > ceiling ? ceiling / peak : 1
                // Instant attack keeps every sample under the ceiling; slow release avoids pumping.
                limiterGain = min(target, limiterGain + (1 - limiterGain) * limiterRelease)
                if limiterGain < 1 {
                    for ch in 0..<count {
                        let c = channels[ch]
                        c.base[i * c.stride] = Float(Double(c.base[i * c.stride]) * limiterGain)
                    }
                }
            }
        }

        if unstable {
            reset()
        } else {
            flushTinyValues()
        }
        snapToCurrent()
    }

    private func snapToCurrent() {
        guard ramping else { return }
        for i in 0..<sectionCount { previous[i] = current[i] }
        previousPreamp = preamp
        previousLeftGain = leftGain
        previousRightGain = rightGain
        ramping = false
    }

    /// Very small filter memory values slow some CPUs down, so zero them.
    private func flushTinyValues() {
        for i in 0..<stateCount where abs(state[i]) < 1e-15 {
            state[i] = 0
        }
    }

    @inline(__always)
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    @inline(__always)
    private func blend(_ a: BiquadCoefficients, _ b: BiquadCoefficients, _ t: Double) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: lerp(a.b0, b.b0, t),
            b1: lerp(a.b1, b.b1, t),
            b2: lerp(a.b2, b.b2, t),
            a1: lerp(a.a1, b.a1, t),
            a2: lerp(a.a2, b.a2, t)
        )
    }
}
