#if os(macOS)
import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let action: String

    var errorDescription: String? {
        "\(action) failed (Core Audio error \(status)\(fourCC.map { " '\($0)'" } ?? ""))."
    }

    /// Many Core Audio errors are four readable characters, like 'who?'.
    private var fourCC: String? {
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian) { Array($0) }
        guard bytes.allSatisfy({ (32...126).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}

@discardableResult
func check(_ status: OSStatus, _ action: @autoclosure () -> String) throws -> OSStatus {
    guard status == noErr else { throw CoreAudioError(status: status, action: action()) }
    return status
}

/// An audio output the Mac knows about.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

enum AudioSystem {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Reads a fixed-size property such as an ID, a number or a flag.
    static func value<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, initial: T) throws -> T {
        var addr = addr
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result), "Reading audio property")
        return result
    }

    static func string(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> String {
        var addr = addr
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result), "Reading audio name")
        guard let result else { throw CoreAudioError(status: kAudioHardwareUnspecifiedError, action: "Reading audio name") }
        return result.takeRetainedValue() as String
    }

    static func objectIDs(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
        var addr = addr
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size), "Listing audio objects")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids), "Listing audio objects")
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Total channels a device has in the given direction.
    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func device(_ id: AudioObjectID) -> AudioDevice? {
        guard
            let uid = try? string(id, address(kAudioDevicePropertyDeviceUID)),
            let name = try? string(id, address(kAudioObjectPropertyName))
        else { return nil }
        return AudioDevice(id: id, uid: uid, name: name)
    }

    /// Real output devices, without aggregates (including the private one this app creates).
    static func outputDevices() -> [AudioDevice] {
        let ids = (try? objectIDs(system, address(kAudioHardwarePropertyDevices))) ?? []
        return ids.compactMap { id in
            guard channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0 else { return nil }
            let transport = (try? value(id, address(kAudioDevicePropertyTransportType), initial: UInt32(0))) ?? 0
            guard transport != kAudioDeviceTransportTypeAggregate else { return nil }
            return device(id)
        }
    }

    static func defaultOutputDevice() -> AudioDevice? {
        guard
            let id = try? value(system, address(kAudioHardwarePropertyDefaultOutputDevice), initial: AudioObjectID(kAudioObjectUnknown)),
            id != kAudioObjectUnknown
        else { return nil }
        return device(id)
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        let rate = try? value(device, address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))
        guard let rate, rate > 0 else { return nil }
        return rate
    }

    /// The Core Audio object for this app's own process, so the tap can leave it out.
    static func ownProcessObject() throws -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object),
            "Finding this app's audio process"
        )
        guard object != kAudioObjectUnknown else {
            throw CoreAudioError(status: kAudioHardwareBadObjectError, action: "Finding this app's audio process")
        }
        return object
    }
}
#endif
