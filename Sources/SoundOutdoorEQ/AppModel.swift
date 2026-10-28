#if os(macOS)
import AppKit
import CoreAudio
import EQCore
import Foundation
import ServiceManagement

/// Saves settings in the app's preferences so they survive restarts.
struct SettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "configuration.v1"
    private let launchAtLoginOfferedKey = "launchAtLoginOffered"

    func load() -> AppConfiguration {
        AppConfiguration.decode(defaults.data(forKey: key))
    }

    func save(_ configuration: AppConfiguration) {
        if let data = try? configuration.encoded() {
            defaults.set(data, forKey: key)
        }
    }

    /// True only the first time it's called.
    func takeFirstLaunch() -> Bool {
        guard !defaults.bool(forKey: launchAtLoginOfferedKey) else { return false }
        defaults.set(true, forKey: launchAtLoginOfferedKey)
        return true
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Status: Equatable {
        case off
        case waiting
        case active(String)
        case failed(String)
    }

    @Published var config: AppConfiguration {
        didSet { configurationChanged(from: oldValue) }
    }
    @Published private(set) var status: Status = .off
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var currentOutput: AudioDevice?
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = SMAppService.mainApp.status

    private let engine = ProcessTapEngine()
    private let store = SettingsStore()
    /// Which device and sample rate the engine was started for, so repeated events don't restart it.
    private var runningKey: String?
    private var refreshWork: DispatchWorkItem?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: (id: AudioObjectID, block: AudioObjectPropertyListenerBlock)?

    private init() {
        config = store.load()
        if store.takeFirstLaunch() {
            setLaunchAtLogin(true)
        }
        installSystemListeners()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Bluetooth reconnects after sleep, so rebuild from scratch.
            MainActor.assumeIsolated {
                self?.runningKey = nil
                self?.scheduleRefresh(after: 2)
            }
        }
        refresh()
    }

    // MARK: Status

    var isActive: Bool {
        if case .active = status { return true }
        return false
    }

    var statusText: String {
        switch status {
        case .off:
            return "Off"
        case .waiting:
            if config.applyToAllOutputs { return "No output device" }
            return "Waiting for \(deviceLabel(config.deviceMatch))"
        case .active(let name):
            return config.eq.bypass ? "Bypassed on \(name)" : "Active on \(name)"
        case .failed(let message):
            return message
        }
    }

    func deviceLabel(_ match: String) -> String {
        match.caseInsensitiveCompare(AppConfiguration.defaultDeviceMatch) == .orderedSame
            ? "the Xiaomi speaker" : match
    }

    // MARK: Presets

    var presetTitle: String {
        config.activePreset?.name ?? "Custom"
    }

    var selectedCustomPreset: Preset? {
        guard let preset = config.presets.preset(id: config.selectedPresetID), !preset.isBuiltIn else { return nil }
        return preset
    }

    func select(_ preset: Preset) {
        var next = config
        next.eq = next.eq.applying(preset)
        next.selectedPresetID = preset.id
        config = next
    }

    func savePreset(named name: String) {
        var next = config
        let preset = next.presets.save(name: name, from: next.eq)
        next.selectedPresetID = preset.id
        config = next
    }

    func renameSelectedPreset(to name: String) {
        guard let preset = selectedCustomPreset else { return }
        config.presets.rename(id: preset.id, to: name)
    }

    func deleteSelectedPreset() {
        guard let preset = selectedCustomPreset else { return }
        var next = config
        next.presets.delete(id: preset.id)
        next.selectedPresetID = nil
        config = next
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sound Outdoor EQ: launch at login change failed: \(error)")
        }
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openAudioCapturePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Engine control

    func retry() {
        runningKey = nil
        refresh()
    }

    func shutdown() {
        engine.stop()
        runningKey = nil
    }

    private func configurationChanged(from old: AppConfiguration) {
        store.save(config)
        if old.eq != config.eq {
            engine.update(EQDesign.parameters(for: config.eq, sampleRate: engine.sampleRate))
        }
        if old.enabled != config.enabled
            || old.deviceMatch != config.deviceMatch
            || old.applyToAllOutputs != config.applyToAllOutputs
            || old.keepMacMicrophone != config.keepMacMicrophone {
            refresh()
        }
    }

    /// If the speaker's microphone has become the Mac's input, switch to the Mac's own mic.
    /// A Bluetooth speaker whose mic is in use drops into low-quality call mode, which makes music sound muffled.
    private func fixMicrophone() {
        guard
            let input = AudioSystem.defaultInputDevice(),
            config.shouldReplaceMicrophone(named: input.name),
            let mic = AudioSystem.builtInMicrophone(),
            mic.id != input.id
        else { return }
        do {
            try AudioSystem.setDefaultInputDevice(mic.id)
            NSLog("Sound Outdoor EQ: switched microphone from \(input.name) to \(mic.name)")
        } catch {
            NSLog("Sound Outdoor EQ: couldn't switch microphone: \(error.localizedDescription)")
        }
    }

    /// Decides whether the EQ should run right now, and starts or stops it. Safe to call any time.
    func refresh() {
        fixMicrophone()
        outputDevices = AudioSystem.outputDevices()
        let output = AudioSystem.defaultOutputDevice()
        currentOutput = output
        watch(output)

        guard config.enabled else {
            stopEngine()
            status = .off
            return
        }
        guard let output, config.shouldProcess(deviceNamed: output.name) else {
            stopEngine()
            status = .waiting
            return
        }

        let rate = AudioSystem.nominalSampleRate(output.id) ?? 0
        if engine.isRunning, runningKey == key(output, rate) {
            status = .active(output.name)
            return
        }

        do {
            let eq = config.eq
            try engine.start(on: output) { rate in EQDesign.parameters(for: eq, sampleRate: rate) }
            // Read the rate again: starting can change it, and we don't want to restart for that.
            runningKey = key(output, AudioSystem.nominalSampleRate(output.id) ?? rate)
            status = .active(output.name)
        } catch {
            runningKey = nil
            status = .failed(error.localizedDescription)
        }
    }

    private func stopEngine() {
        guard engine.isRunning else { return }
        engine.stop()
        runningKey = nil
    }

    private func key(_ device: AudioDevice, _ rate: Double) -> String {
        "\(device.uid)@\(Int(rate))"
    }

    /// Several audio events usually arrive together (for example when Bluetooth connects), so wait for them to settle.
    private func scheduleRefresh(after delay: TimeInterval = 0.4) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Core Audio change notifications

    private func installSystemListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        systemListener = block
        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDevices,
        ] {
            var addr = AudioSystem.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioSystem.system, &addr, .main, block)
        }
    }

    /// Follows sample-rate changes on the current output (Bluetooth switches rate when the mic is used).
    private func watch(_ device: AudioDevice?) {
        guard deviceListener?.id != device?.id else { return }
        if let old = deviceListener {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                var addr = AudioSystem.address(selector)
                AudioObjectRemovePropertyListenerBlock(old.id, &addr, .main, old.block)
            }
            deviceListener = nil
        }
        guard let device else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
            var addr = AudioSystem.address(selector)
            AudioObjectAddPropertyListenerBlock(device.id, &addr, .main, block)
        }
        deviceListener = (device.id, block)
    }
}
#endif
