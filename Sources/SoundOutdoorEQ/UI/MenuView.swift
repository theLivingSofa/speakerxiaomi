#if os(macOS)
import AppKit
import EQCore
import SwiftUI

/// The window that opens from the menu-bar icon.
struct MenuView: View {
    @EnvironmentObject private var model: AppModel

    private enum Naming: Equatable {
        case save
        case rename
    }

    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var showSpotify = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if case .failed = model.status {
                failureNotice
            }
            Divider()
            presetRow
            if naming != nil {
                nameField
            }
            ResponseCurveView(settings: model.config.eq)
                .frame(height: 80)
            EQSlidersView(gains: $model.config.eq.gains)
            preampRow
            Divider()
            optionsSection
            Divider()
            deviceRow
            Divider()
            DisclosureGroup("Spotify on iPhone", isExpanded: $showSpotify) {
                SpotifyCopyView(settings: model.config.eq, presetName: model.config.activePreset?.name)
                    .padding(.top, 6)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .saturation(model.isActive ? 1 : 0)
                .opacity(model.isActive ? 1 : 0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound Outdoor EQ").font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Toggle("EQ on", isOn: $model.config.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(model.config.enabled ? "Turn the EQ off" : "Turn the EQ on")
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .active: return model.config.eq.bypass ? .orange : .green
        case .waiting: return .yellow
        case .failed: return .red
        case .off: return .gray
        }
    }

    private var failureNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The EQ couldn't start. Your audio is playing normally without it.")
                .font(.caption)
            HStack {
                Button("Try Again") { model.retry() }
                Button("Audio Permission…") { model.openAudioCapturePrivacySettings() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
    }

    private var presetRow: some View {
        HStack {
            Text("Preset").foregroundStyle(.secondary)
            Menu(model.presetTitle) {
                Section("Built-in") {
                    ForEach(Preset.builtIns) { preset in
                        presetButton(preset)
                    }
                }
                if !model.config.presets.custom.isEmpty {
                    Section("My presets") {
                        ForEach(model.config.presets.custom) { preset in
                            presetButton(preset)
                        }
                    }
                }
            }
            .frame(maxWidth: 180)
            Spacer()
            Menu {
                Button("Save as New Preset…") { startNaming(.save, text: "") }
                if let custom = model.selectedCustomPreset {
                    if model.config.activePreset == nil {
                        Button("Update “\(custom.name)”") { model.savePreset(named: custom.name) }
                    }
                    Button("Rename “\(custom.name)”…") { startNaming(.rename, text: custom.name) }
                    Button("Delete “\(custom.name)”", role: .destructive) { model.deleteSelectedPreset() }
                }
                Divider()
                Button("Reset to Flat") { model.select(.flat) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func presetButton(_ preset: Preset) -> some View {
        Button {
            model.select(preset)
        } label: {
            if model.config.activePreset?.id == preset.id {
                Label(preset.name, systemImage: "checkmark")
            } else {
                Text(preset.name)
            }
        }
    }

    private var nameField: some View {
        HStack {
            TextField(naming == .rename ? "New name" : "Preset name", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitName)
            Button(naming == .rename ? "Rename" : "Save", action: commitName)
                .keyboardShortcut(.defaultAction)
            Button("Cancel") { naming = nil }
        }
        .controlSize(.small)
    }

    private var preampRow: some View {
        HStack {
            Text("Preamp").foregroundStyle(.secondary)
            Slider(value: $model.config.eq.preamp, in: EQSettings.preampRange, step: 0.5)
            Text("\(EQSlidersView.gainLabel(model.config.eq.preamp)) dB")
                .font(.caption.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
        .help("Lower this when you boost bands, so loud parts don't distort.")
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Toggle("Bypass (compare)", isOn: $model.config.eq.bypass)
                    .help("Hear the original sound without the EQ.")
                Toggle("Mono", isOn: $model.config.eq.mono)
                    .help("Mix left and right together. Best with a single speaker.")
            }
            HStack(spacing: 16) {
                Toggle("Speaker protection", isOn: $model.config.eq.speakerProtection)
                    .help("Cuts bass below \(Int(model.config.eq.highPassFrequency)) Hz, which this speaker can't play anyway. Keeps bass boosts cleaner.")
                Toggle("Limiter", isOn: $model.config.eq.limiter)
                    .help("Stops loud boosted parts from clipping.")
            }
            HStack {
                Text("Balance").foregroundStyle(.secondary)
                Text("L").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.config.eq.balance, in: -1...1)
                Text("R").font(.caption).foregroundStyle(.secondary)
                Button("Center") { model.config.eq.balance = 0 }
                    .controlSize(.small)
                    .disabled(model.config.eq.balance == 0)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var deviceRow: some View {
        HStack {
            Text("Use with").foregroundStyle(.secondary)
            Picker("Use with", selection: deviceChoice) {
                ForEach(deviceChoices, id: \.self) { choice in
                    Text(label(for: choice)).tag(choice)
                }
            }
            .labelsHidden()
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            if model.launchAtLoginStatus == .requiresApproval {
                Button("Approve…") { model.openLoginItemsSettings() }
                    .controlSize(.small)
                    .help("macOS needs you to allow this in Login Items.")
            }
            Spacer()
            Button {
                model.openAudioCapturePrivacySettings()
            } label: {
                Image(systemName: "lock.shield")
            }
            .buttonStyle(.borderless)
            .help("Hearing nothing? Allow Sound Outdoor EQ under System Audio Recording.")
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: Device choice

    private enum DeviceChoice: Hashable {
        case match(String)
        case all
    }

    private var deviceChoice: Binding<DeviceChoice> {
        Binding(
            get: { model.config.applyToAllOutputs ? .all : .match(model.config.deviceMatch) },
            set: { choice in
                var next = model.config
                switch choice {
                case .all:
                    next.applyToAllOutputs = true
                case .match(let text):
                    next.applyToAllOutputs = false
                    next.deviceMatch = text
                }
                model.config = next
            }
        )
    }

    private var deviceChoices: [DeviceChoice] {
        var choices: [DeviceChoice] = [.match(AppConfiguration.defaultDeviceMatch)]
        for device in model.outputDevices where !choices.contains(.match(device.name)) {
            choices.append(.match(device.name))
        }
        let current = DeviceChoice.match(model.config.deviceMatch)
        if !choices.contains(current) {
            choices.append(current)
        }
        choices.append(.all)
        return choices
    }

    private func label(for choice: DeviceChoice) -> String {
        switch choice {
        case .all:
            return "Every output"
        case .match(let text):
            if text.caseInsensitiveCompare(AppConfiguration.defaultDeviceMatch) == .orderedSame {
                return "Any Xiaomi speaker"
            }
            return text
        }
    }

    // MARK: Naming

    private func startNaming(_ mode: Naming, text: String) {
        nameText = text
        naming = mode
        NSApp.activate()
    }

    private func commitName() {
        switch naming {
        case .save: model.savePreset(named: nameText)
        case .rename: model.renameSelectedPreset(to: nameText)
        case nil: break
        }
        naming = nil
    }
}
#endif
