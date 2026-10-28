#if os(macOS)
import CoreAudio
import EQCore
import Foundation
import os

/// Captures everything the Mac plays, runs it through the EQ and plays it on one output device.
///
/// How it works (macOS 14.2+, no driver needed):
/// 1. A system-wide "process tap" captures the audio of every app except this one. While the tap is
///    being read, the apps' original sound is muted, so you only hear the processed version. If this
///    app quits or crashes, macOS unmutes them on its own.
/// 2. A private aggregate device combines that tap (as input) with the speaker (as output).
/// 3. Our callback on the aggregate device reads the tap, applies the EQ and writes to the speaker.
final class ProcessTapEngine {
    private(set) var device: AudioDevice?
    private(set) var sampleRate: Double = 48_000
    var isRunning: Bool { procID != nil }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var renderer: Renderer?

    /// Starts processing on `device`. `parameters` builds the EQ for the device's sample rate.
    func start(on device: AudioDevice, parameters: (Double) -> EQParameters) throws {
        stop()
        do {
            let ownProcess = try AudioSystem.ownProcessObject()

            let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [NSNumber(value: ownProcess)])
            tapDescription.name = "Sound Outdoor EQ"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .mutedWhenTapped
            var tap = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(tapDescription, &tap), "Capturing system audio")
            tapID = tap
            let tapUID = (try? AudioSystem.string(tap, AudioSystem.address(kAudioTapPropertyUID)))
                ?? tapDescription.uuid.uuidString

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sound Outdoor EQ",
                kAudioAggregateDeviceUIDKey: "SoundOutdoorEQ-\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: device.uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: device.uid],
                ],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true],
                ],
            ]
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            try check(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
                "Creating the EQ audio device"
            )
            aggregateID = aggregate

            let rate = AudioSystem.nominalSampleRate(aggregate) ?? AudioSystem.nominalSampleRate(device.id) ?? 48_000
            // If the speaker has a microphone, its input comes before the tap in the aggregate. Skip it.
            let speakerInputs = (try? AudioSystem.objectIDs(
                device.id, AudioSystem.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            ).count) ?? 0
            let renderer = Renderer(sampleRate: rate, parameters: parameters(rate), skipInputBuffers: speakerInputs)

            var proc: AudioDeviceIOProcID?
            try check(
                AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
                    renderer.render(input: input, output: output)
                },
                "Setting up audio processing"
            )
            procID = proc
            try check(AudioDeviceStart(aggregate, proc), "Starting audio")

            self.renderer = renderer
            self.device = device
            self.sampleRate = rate
        } catch {
            stop()
            throw error
        }
    }

    /// Sends new EQ settings to the audio thread. Safe to call often, such as while dragging a slider.
    func update(_ parameters: EQParameters) {
        renderer?.update(parameters)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        renderer = nil
        device = nil
    }

    deinit {
        stop()
    }
}

/// The part that runs on the real-time audio thread. It never allocates or waits on a lock there.
final class Renderer {
    private let processor: EQProcessor
    private let skipInputBuffers: Int

    // New settings are handed over through `pending`. The audio thread only *tries* the lock,
    // so it never waits. If the lock is busy, it picks the change up on the next buffer.
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pending: EQParameters
    private var pendingVersion = 0
    private var appliedVersion = 0

    private let inputs: UnsafeMutablePointer<ChannelPointer>
    private let outputs: UnsafeMutablePointer<ChannelPointer>

    init(sampleRate: Double, parameters: EQParameters, skipInputBuffers: Int) {
        processor = EQProcessor(sampleRate: sampleRate)
        processor.setParameters(parameters)
        pending = parameters
        self.skipInputBuffers = skipInputBuffers
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        let dummy = ChannelPointer(base: UnsafeMutablePointer<Float>(bitPattern: 0x10)!, stride: 1)
        inputs = .allocate(capacity: EQProcessor.maxChannels)
        inputs.initialize(repeating: dummy, count: EQProcessor.maxChannels)
        outputs = .allocate(capacity: EQProcessor.maxChannels)
        outputs.initialize(repeating: dummy, count: EQProcessor.maxChannels)
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
        inputs.deallocate()
        outputs.deallocate()
    }

    /// Main thread.
    func update(_ parameters: EQParameters) {
        os_unfair_lock_lock(lock)
        pending = parameters // The old value is freed here, on the main thread.
        pendingVersion &+= 1
        os_unfair_lock_unlock(lock)
    }

    /// Real-time audio thread.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        if os_unfair_lock_trylock(lock) {
            if pendingVersion != appliedVersion {
                processor.setParameters(pending)
                appliedVersion = pendingVersion
            }
            os_unfair_lock_unlock(lock)
        }

        let outList = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outList {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let (outCount, outFrames) = Self.mapChannels(outList, skip: 0, into: outputs)
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let (inCount, inFrames) = Self.mapChannels(inList, skip: skipInputBuffers, into: inputs)
        let frames = min(inFrames, outFrames)
        guard outCount > 0, inCount > 0, frames > 0 else { return }

        if outCount == 1 {
            // Mono output: mix every input channel down.
            let out = outputs[0]
            let scale = 1 / Float(inCount)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<inCount {
                    sum += inputs[c].base[i * inputs[c].stride]
                }
                out.base[i * out.stride] = sum * scale
            }
        } else {
            for c in 0..<outCount {
                let source: Int
                if c < inCount {
                    source = c
                } else if inCount == 1 {
                    source = 0
                } else {
                    continue // Extra output channels stay silent.
                }
                let src = inputs[source]
                let dst = outputs[c]
                for i in 0..<frames {
                    dst.base[i * dst.stride] = src.base[i * src.stride]
                }
            }
        }

        processor.process(outputs, channelCount: outCount, frames: frames)
    }

    /// Lists each Float32 channel in the buffer list, whether interleaved or not.
    private static func mapChannels(
        _ list: UnsafeMutableAudioBufferListPointer,
        skip: Int,
        into channels: UnsafeMutablePointer<ChannelPointer>
    ) -> (count: Int, frames: Int) {
        var count = 0
        var frames = Int.max
        var index = 0
        for buffer in list {
            defer { index += 1 }
            guard index >= skip, let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let n = Int(buffer.mNumberChannels)
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * n))
            let base = data.assumingMemoryBound(to: Float.self)
            for c in 0..<n where count < EQProcessor.maxChannels {
                channels[count] = ChannelPointer(base: base + c, stride: n)
                count += 1
            }
        }
        return (count, frames == .max ? 0 : frames)
    }
}
#endif
