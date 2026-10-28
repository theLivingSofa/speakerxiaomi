import Foundation

/// Spotify's iPhone app has its own 6-band equalizer. This converts our curve into values for those six bands,
/// so the same sound can be set up on the phone when the Mac isn't around.
public enum SpotifyEQ {
    /// The bands Spotify's iPhone equalizer shows, left to right.
    public static let frequencies: [Double] = [60, 150, 400, 1000, 2400, 15000]
    public static let range: ClosedRange<Int> = -12...12

    /// Whole-dB values for Spotify's bands, read off our curve at each band's frequency.
    /// Preamp and speaker protection are left out: Spotify has no equivalent, and its sliders are relative.
    public static func gains(for settings: EQSettings) -> [Int] {
        var bandsOnly = settings
        bandsOnly.preamp = 0
        bandsOnly.speakerProtection = false
        bandsOnly.bypass = false
        let parameters = EQDesign.parameters(for: bandsOnly, sampleRate: 48_000)
        return frequencies.map { frequency in
            let db = EQDesign.responseDB(of: parameters, at: frequency, sampleRate: 48_000)
            return Int(db.rounded()).clamped(to: range)
        }
    }

    public static func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1000 {
            let k = frequency / 1000
            return k == k.rounded() ? "\(Int(k)) kHz" : String(format: "%.1f kHz", k)
        }
        return "\(Int(frequency)) Hz"
    }

    public static func gainLabel(_ gain: Int) -> String {
        gain > 0 ? "+\(gain)" : "\(gain)"
    }

    /// Plain text to paste into Notes or a message, like "60 Hz +4 · 150 Hz +2 · …".
    public static func summary(for settings: EQSettings, presetName: String? = nil) -> String {
        let values = zip(frequencies, gains(for: settings))
            .map { "\(frequencyLabel($0)) \(gainLabel($1))" }
            .joined(separator: " · ")
        let title = presetName.map { "Spotify EQ (\($0)): " } ?? "Spotify EQ: "
        return title + values
    }
}
