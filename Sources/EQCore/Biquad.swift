import Foundation

/// Coefficients of one second-order filter section, already divided by a0.
public struct BiquadCoefficients: Equatable, Sendable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// Passes audio through unchanged.
    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// Bell-shaped boost or cut around `frequency` (RBJ Audio EQ Cookbook).
    public static func peaking(frequency: Double, q: Double, gainDB: Double, sampleRate: Double) -> BiquadCoefficients {
        guard gainDB != 0, let w0 = angularFrequency(frequency, sampleRate) else { return .identity }
        let a = pow(10, gainDB / 40)
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha / a
        return BiquadCoefficients(
            b0: (1 + alpha * a) / a0,
            b1: (-2 * cosW0) / a0,
            b2: (1 - alpha * a) / a0,
            a1: (-2 * cosW0) / a0,
            a2: (1 - alpha / a) / a0
        )
    }

    /// Removes content below `frequency` (RBJ Audio EQ Cookbook).
    public static func highPass(frequency: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        guard let w0 = angularFrequency(frequency, sampleRate) else { return .identity }
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha
        return BiquadCoefficients(
            b0: ((1 + cosW0) / 2) / a0,
            b1: (-(1 + cosW0)) / a0,
            b2: ((1 + cosW0) / 2) / a0,
            a1: (-2 * cosW0) / a0,
            a2: (1 - alpha) / a0
        )
    }

    /// Linear gain of this section at `frequency`.
    public func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(w), s1 = sin(w)
        let c2 = cos(2 * w), s2 = sin(2 * w)
        let numRe = b0 + b1 * c1 + b2 * c2
        let numIm = -(b1 * s1 + b2 * s2)
        let denRe = 1 + a1 * c1 + a2 * c2
        let denIm = -(a1 * s1 + a2 * s2)
        let num = numRe * numRe + numIm * numIm
        let den = denRe * denRe + denIm * denIm
        guard den > 0 else { return 1 }
        return (num / den).squareRoot()
    }

    /// Returns nil for frequencies the filter can't represent at this sample rate.
    private static func angularFrequency(_ frequency: Double, _ sampleRate: Double) -> Double? {
        guard sampleRate > 0, frequency > 0, frequency < sampleRate * 0.49 else { return nil }
        return 2 * Double.pi * frequency / sampleRate
    }
}
