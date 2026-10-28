import Foundation

/// Everything that shapes the sound. Saved to disk and restored at launch.
public struct EQSettings: Codable, Equatable, Sendable {
    public static let bandFrequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static var bandCount: Int { bandFrequencies.count }
    public static let gainRange: ClosedRange<Double> = -12...12
    public static let preampRange: ClosedRange<Double> = -12...6
    public static let highPassRange: ClosedRange<Double> = 30...120
    /// The speaker is rated down to 60 Hz. Cutting just below that keeps the driver from wasting power.
    public static let defaultHighPassFrequency: Double = 55

    /// Gain per band in dB, same order as `bandFrequencies`.
    public var gains: [Double]
    /// Overall gain in dB applied before the bands. Lower it when boosting to avoid distortion.
    public var preamp: Double
    /// Pass audio through untouched, for comparing with and without the EQ.
    public var bypass: Bool
    /// Low cut below `highPassFrequency` to protect the speaker.
    public var speakerProtection: Bool
    public var highPassFrequency: Double
    /// Keeps the output from clipping when bands are boosted.
    public var limiter: Bool
    /// -1 is fully left, 0 is centered, 1 is fully right.
    public var balance: Double
    /// Mix left and right together. Useful with a single speaker.
    public var mono: Bool

    public init(
        gains: [Double] = Array(repeating: 0, count: EQSettings.bandCount),
        preamp: Double = 0,
        bypass: Bool = false,
        speakerProtection: Bool = true,
        highPassFrequency: Double = EQSettings.defaultHighPassFrequency,
        limiter: Bool = true,
        balance: Double = 0,
        mono: Bool = false
    ) {
        self.gains = gains
        self.preamp = preamp
        self.bypass = bypass
        self.speakerProtection = speakerProtection
        self.highPassFrequency = highPassFrequency
        self.limiter = limiter
        self.balance = balance
        self.mono = mono
        normalize()
    }

    public static let flat = EQSettings()

    /// Clamps every value into range and fixes the band count, so bad saved data can't break playback.
    public mutating func normalize() {
        var fixed = gains.prefix(Self.bandCount).map { Self.clamp($0, Self.gainRange) }
        if fixed.count < Self.bandCount {
            fixed += Array(repeating: 0, count: Self.bandCount - fixed.count)
        }
        gains = fixed
        preamp = Self.clamp(preamp, Self.preampRange)
        highPassFrequency = Self.clamp(highPassFrequency, Self.highPassRange)
        balance = Self.clamp(balance, -1...1)
    }

    /// Copies a preset's curve and preamp, keeping the other switches as they are.
    public func applying(_ preset: Preset) -> EQSettings {
        var copy = self
        copy.gains = preset.gains
        copy.preamp = preset.preamp
        copy.normalize()
        return copy
    }

    /// True when the bands and preamp match the preset.
    public func matches(_ preset: Preset) -> Bool {
        let other = EQSettings.flat.applying(preset)
        return zip(gains, other.gains).allSatisfy { abs($0 - $1) < 0.05 } && abs(preamp - other.preamp) < 0.05
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0.0.clamped(to: range) }
        return value.clamped(to: range)
    }

    // Missing keys fall back to defaults, so older saved settings keep loading after updates.
    private enum CodingKeys: String, CodingKey {
        case gains, preamp, bypass, speakerProtection, highPassFrequency, limiter, balance, mono
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EQSettings()
        self.init(
            gains: try c.decodeIfPresent([Double].self, forKey: .gains) ?? defaults.gains,
            preamp: try c.decodeIfPresent(Double.self, forKey: .preamp) ?? defaults.preamp,
            bypass: try c.decodeIfPresent(Bool.self, forKey: .bypass) ?? defaults.bypass,
            speakerProtection: try c.decodeIfPresent(Bool.self, forKey: .speakerProtection) ?? defaults.speakerProtection,
            highPassFrequency: try c.decodeIfPresent(Double.self, forKey: .highPassFrequency) ?? defaults.highPassFrequency,
            limiter: try c.decodeIfPresent(Bool.self, forKey: .limiter) ?? defaults.limiter,
            balance: try c.decodeIfPresent(Double.self, forKey: .balance) ?? defaults.balance,
            mono: try c.decodeIfPresent(Bool.self, forKey: .mono) ?? defaults.mono
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
