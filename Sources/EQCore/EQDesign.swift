import Foundation

/// Everything the audio thread needs, precomputed from `EQSettings` for one sample rate.
public struct EQParameters: Equatable, Sendable {
    /// Always `EQDesign.sectionCount` entries: high-pass sections first, then one per band.
    public var sections: [BiquadCoefficients]
    /// Linear gains.
    public var preamp: Double
    public var leftGain: Double
    public var rightGain: Double
    public var mono: Bool
    public var limiter: Bool
    public var bypass: Bool

    public static let passthrough = EQParameters(
        sections: Array(repeating: .identity, count: EQDesign.sectionCount),
        preamp: 1, leftGain: 1, rightGain: 1, mono: false, limiter: false, bypass: true
    )
}

public enum EQDesign {
    /// Bands are an octave apart; this Q gives each one a one-octave width.
    public static let bandQ = 1.41
    /// A 4th-order Butterworth high-pass, built from two sections with these Qs.
    public static let highPassQs: [Double] = [0.5412, 1.3066]
    public static var sectionCount: Int { highPassQs.count + EQSettings.bandCount }
    /// Limiter ceiling, about -1 dBFS.
    public static let limiterCeiling: Double = 0.891

    public static func parameters(for settings: EQSettings, sampleRate: Double) -> EQParameters {
        var s = settings
        s.normalize()
        var sections: [BiquadCoefficients] = highPassQs.map { q in
            s.speakerProtection
                ? .highPass(frequency: s.highPassFrequency, q: q, sampleRate: sampleRate)
                : .identity
        }
        for (frequency, gain) in zip(EQSettings.bandFrequencies, s.gains) {
            sections.append(.peaking(frequency: frequency, q: bandQ, gainDB: gain, sampleRate: sampleRate))
        }
        return EQParameters(
            sections: sections,
            preamp: dbToLinear(s.preamp),
            leftGain: s.balance > 0 ? 1 - s.balance : 1,
            rightGain: s.balance < 0 ? 1 + s.balance : 1,
            mono: s.mono,
            limiter: s.limiter,
            bypass: s.bypass
        )
    }

    /// Total EQ response at `frequency` in dB, preamp included. Used to draw the curve.
    public static func responseDB(for settings: EQSettings, at frequency: Double, sampleRate: Double = 48_000) -> Double {
        responseDB(of: parameters(for: settings, sampleRate: sampleRate), at: frequency, sampleRate: sampleRate)
    }

    /// Same as above for already-designed parameters, so a curve with many points designs the filters once.
    public static func responseDB(of p: EQParameters, at frequency: Double, sampleRate: Double) -> Double {
        let linear = p.sections.reduce(p.preamp) { $0 * $1.magnitude(at: frequency, sampleRate: sampleRate) }
        return linearToDB(linear)
    }

    public static func dbToLinear(_ db: Double) -> Double { pow(10, db / 20) }

    public static func linearToDB(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-9)) }
}
