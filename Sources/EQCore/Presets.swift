import Foundation

/// A named EQ curve. Built-in presets can't be renamed or deleted.
public struct Preset: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Gain per band in dB, same order as `EQSettings.bandFrequencies`.
    public var gains: [Double]
    public var preamp: Double
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, name: String, gains: [Double], preamp: Double, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.gains = gains
        self.preamp = preamp
        self.isBuiltIn = isBuiltIn
    }
}

extension Preset {
    //                                       32   64  125  250  500   1k   2k   4k   8k  16k
    public static let flat = builtIn("flat", "Flat",
                                            [0,   0,   0,   0,   0,   0,   0,   0,   0,   0], preamp: 0)
    /// Open air has no walls to reinforce bass, so lift the lows, trim the boxy mids
    /// and add presence so vocals carry further.
    public static let outdoor = builtIn("outdoor", "Outdoor",
                                            [0,   4,   3,   0,  -2,   0,   2,   3,   2,   1], preamp: -4)
    public static let bassBoost = builtIn("bass", "Bass Boost",
                                            [0,   6,   5,   3,   0,   0,   0,   0,   0,   0], preamp: -6)
    public static let vocal = builtIn("vocal", "Vocal / Podcast",
                                            [0,  -3,  -2,   0,   1,   3,   4,   3,   1,   0], preamp: -4)
    public static let treble = builtIn("treble", "Treble",
                                            [0,   0,   0,   0,   0,   0,   1,   3,   5,   6], preamp: -6)
    /// Less bass so it carries less through walls, with a little clarity to stay intelligible quietly.
    public static let night = builtIn("night", "Night",
                                            [0,  -5,  -4,  -2,   0,   1,   2,   1,   0,  -1], preamp: -2)

    public static let builtIns: [Preset] = [.flat, .outdoor, .bassBoost, .vocal, .treble, .night]

    private static func builtIn(_ id: String, _ name: String, _ gains: [Double], preamp: Double) -> Preset {
        Preset(id: "builtin.\(id)", name: name, gains: gains, preamp: preamp, isBuiltIn: true)
    }
}

/// Built-in presets plus the user's own, with the edits the UI needs.
public struct PresetLibrary: Codable, Equatable, Sendable {
    public private(set) var custom: [Preset]

    public init(custom: [Preset] = []) {
        self.custom = custom.filter { !$0.isBuiltIn }
    }

    public var all: [Preset] { Preset.builtIns + custom }

    public func preset(id: String?) -> Preset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Saves the current curve as a new preset. If a custom preset with that name exists, it is overwritten.
    @discardableResult
    public mutating func save(name: String, from settings: EQSettings) -> Preset {
        let trimmed = Self.cleanName(name)
        if let index = custom.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            custom[index].gains = settings.gains
            custom[index].preamp = settings.preamp
            return custom[index]
        }
        let preset = Preset(name: trimmed, gains: settings.gains, preamp: settings.preamp)
        custom.append(preset)
        return preset
    }

    /// Returns false for built-in or unknown presets.
    @discardableResult
    public mutating func rename(id: String, to name: String) -> Bool {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return false }
        custom[index].name = Self.cleanName(name)
        return true
    }

    /// Returns false for built-in or unknown presets.
    @discardableResult
    public mutating func delete(id: String) -> Bool {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return false }
        custom.remove(at: index)
        return true
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "My Preset" : String(trimmed.prefix(40))
    }
}
