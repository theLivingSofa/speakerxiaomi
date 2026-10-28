import Foundation

/// Everything the app saves between launches.
public struct AppConfiguration: Codable, Equatable, Sendable {
    /// Matches the speaker's Bluetooth name. Any output whose name contains this text is treated as the speaker.
    public static let defaultDeviceMatch = "Xiaomi"

    /// Master switch. When off, the app leaves audio alone.
    public var enabled: Bool
    /// Text matched (case-insensitively) against the output device name.
    public var deviceMatch: String
    /// Apply the EQ to whatever the current output is, not just the speaker.
    public var applyToAllOutputs: Bool
    /// When the speaker's microphone becomes the Mac's input, switch to the Mac's own mic.
    /// Using a Bluetooth speaker's mic forces low-quality call mode, which makes music sound muffled.
    public var keepMacMicrophone: Bool
    public var eq: EQSettings
    public var selectedPresetID: String?
    public var presets: PresetLibrary

    public init(
        enabled: Bool = true,
        deviceMatch: String = AppConfiguration.defaultDeviceMatch,
        applyToAllOutputs: Bool = false,
        keepMacMicrophone: Bool = true,
        eq: EQSettings = EQSettings.flat.applying(.outdoor),
        selectedPresetID: String? = Preset.outdoor.id,
        presets: PresetLibrary = PresetLibrary()
    ) {
        self.enabled = enabled
        self.deviceMatch = deviceMatch
        self.applyToAllOutputs = applyToAllOutputs
        self.keepMacMicrophone = keepMacMicrophone
        self.eq = eq
        self.selectedPresetID = selectedPresetID
        self.presets = presets
    }

    /// Whether the EQ should run on an output device with this name.
    public func shouldProcess(deviceNamed name: String) -> Bool {
        guard enabled else { return false }
        if applyToAllOutputs { return true }
        return isSpeaker(name)
    }

    /// Whether the Mac's input should be moved off a microphone with this name.
    public func shouldReplaceMicrophone(named name: String) -> Bool {
        keepMacMicrophone && isSpeaker(name)
    }

    /// True when the device name contains the speaker match text.
    public func isSpeaker(_ name: String) -> Bool {
        let match = deviceMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !match.isEmpty else { return false }
        return name.range(of: match, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The selected preset, or nil if the sliders were moved away from it.
    public var activePreset: Preset? {
        guard let preset = presets.preset(id: selectedPresetID), eq.matches(preset) else { return nil }
        return preset
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, deviceMatch, applyToAllOutputs, keepMacMicrophone, eq, selectedPresetID, presets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfiguration()
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled,
            deviceMatch: try c.decodeIfPresent(String.self, forKey: .deviceMatch) ?? d.deviceMatch,
            applyToAllOutputs: try c.decodeIfPresent(Bool.self, forKey: .applyToAllOutputs) ?? d.applyToAllOutputs,
            keepMacMicrophone: try c.decodeIfPresent(Bool.self, forKey: .keepMacMicrophone) ?? d.keepMacMicrophone,
            eq: try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? d.eq,
            selectedPresetID: try c.decodeIfPresent(String.self, forKey: .selectedPresetID),
            presets: try c.decodeIfPresent(PresetLibrary.self, forKey: .presets) ?? d.presets
        )
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Falls back to defaults if the saved data is missing or unreadable.
    public static func decode(_ data: Data?) -> AppConfiguration {
        guard let data, let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        return config
    }
}
