import XCTest
@testable import EQCore

final class EQProcessorTests: XCTestCase {
    let sampleRate = 48_000.0

    /// Settings with the extras switched off, so only the bands and preamp apply.
    func plain(_ gains: [Double] = Array(repeating: 0, count: EQSettings.bandCount), preamp: Double = 0) -> EQSettings {
        EQSettings(gains: gains, preamp: preamp, speakerProtection: false, limiter: false)
    }

    func sine(_ frequency: Double, amplitude: Float = 0.25, seconds: Double = 1) -> [Float] {
        let count = Int(sampleRate * seconds)
        return (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// Runs separate left/right buffers through a processor in 512-frame blocks, like the audio thread would.
    func run(_ settings: EQSettings, left: [Float], right: [Float]? = nil, processor: EQProcessor? = nil) -> (left: [Float], right: [Float]) {
        let p = processor ?? EQProcessor(sampleRate: sampleRate)
        p.setParameters(EQDesign.parameters(for: settings, sampleRate: sampleRate))
        var l = left
        var r = right ?? left
        let block = 512
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                var start = 0
                while start < lp.count {
                    let frames = min(block, lp.count - start)
                    var channels = [
                        ChannelPointer(base: lp.baseAddress! + start, stride: 1),
                        ChannelPointer(base: rp.baseAddress! + start, stride: 1),
                    ]
                    channels.withUnsafeMutableBufferPointer { p.process($0.baseAddress!, channelCount: 2, frames: frames) }
                    start += frames
                }
            }
        }
        return (l, r)
    }

    /// Level in dB of the second half (after the filters settle).
    func levelDB(_ x: [Float]) -> Double {
        let tail = x[(x.count / 2)...]
        let rms = (tail.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(tail.count)).squareRoot()
        return EQDesign.linearToDB(rms)
    }

    func testFlatPassesAudioThroughUnchanged() {
        let input = sine(440)
        let out = run(plain(), left: input)
        for (a, b) in zip(input, out.left) {
            XCTAssertEqual(a, b, accuracy: 1e-5)
        }
    }

    func testBandBoostMeasuresItsGain() {
        var gains = Array(repeating: 0.0, count: EQSettings.bandCount)
        gains[5] = 6 // 1 kHz
        let input = sine(1000)
        let out = run(plain(gains), left: input)
        XCTAssertEqual(levelDB(out.left) - levelDB(input), 6, accuracy: 0.3)
    }

    func testBandCutMeasuresItsGain() {
        var gains = Array(repeating: 0.0, count: EQSettings.bandCount)
        gains[2] = -9 // 125 Hz
        let input = sine(125)
        let out = run(plain(gains), left: input)
        XCTAssertEqual(levelDB(out.left) - levelDB(input), -9, accuracy: 0.4)
    }

    func testMeasuredResponseMatchesTheDrawnCurve() {
        let settings = EQSettings.flat.applying(.outdoor)
        for frequency in [100.0, 700, 3000] {
            let input = sine(frequency)
            let out = run(settings, left: input)
            let measured = levelDB(out.left) - levelDB(input)
            let predicted = EQDesign.responseDB(for: settings, at: frequency, sampleRate: sampleRate)
            XCTAssertEqual(measured, predicted, accuracy: 0.3, "at \(frequency) Hz")
        }
    }

    func testSpeakerProtectionCutsDeepBass() {
        var settings = plain()
        settings.speakerProtection = true
        XCTAssertLessThan(levelDB(run(settings, left: sine(30)).left) - levelDB(sine(30)), -15)
        XCTAssertEqual(levelDB(run(settings, left: sine(1000)).left) - levelDB(sine(1000)), 0, accuracy: 0.1)
    }

    func testLimiterKeepsPeaksUnderTheCeiling() {
        var gains = Array(repeating: 0.0, count: EQSettings.bandCount)
        gains[1] = 12
        var settings = plain(gains, preamp: 6)
        settings.limiter = true
        let out = run(settings, left: sine(64, amplitude: 0.9))
        let peak = out.left.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(Double(peak), EQDesign.limiterCeiling + 1e-4)
        XCTAssertGreaterThan(Double(peak), 0.5)
    }

    func testBypassLeavesAudioAlone() {
        var gains = Array(repeating: 0.0, count: EQSettings.bandCount)
        gains[5] = 12
        var settings = plain(gains)
        settings.bypass = true
        let input = sine(1000)
        XCTAssertEqual(run(settings, left: input).left, input)
    }

    func testBalanceAndMono() {
        var settings = plain()
        settings.balance = 1
        let out = run(settings, left: sine(500), right: sine(500))
        XCTAssertLessThan(levelDB(out.left), -100)
        XCTAssertEqual(levelDB(out.right), levelDB(sine(500)), accuracy: 0.01)

        settings = plain()
        settings.mono = true
        let silent = [Float](repeating: 0, count: 48_000)
        let mixed = run(settings, left: sine(500), right: silent)
        XCTAssertEqual(levelDB(mixed.left), levelDB(sine(500)) - 6.02, accuracy: 0.05)
        XCTAssertEqual(mixed.left, mixed.right)
    }

    func testInterleavedBuffersMatchSeparateBuffers() {
        let settings = EQSettings.flat.applying(.bassBoost)
        let left = sine(80)
        let right = sine(2000)
        let separate = run(settings, left: left, right: right)

        var interleaved = [Float]()
        for i in 0..<left.count {
            interleaved.append(left[i])
            interleaved.append(right[i])
        }
        let p = EQProcessor(sampleRate: sampleRate)
        p.setParameters(EQDesign.parameters(for: settings, sampleRate: sampleRate))
        interleaved.withUnsafeMutableBufferPointer { buf in
            var frame = 0
            while frame < left.count {
                let frames = min(512, left.count - frame)
                let base = buf.baseAddress! + frame * 2
                var channels = [ChannelPointer(base: base, stride: 2), ChannelPointer(base: base + 1, stride: 2)]
                channels.withUnsafeMutableBufferPointer { p.process($0.baseAddress!, channelCount: 2, frames: frames) }
                frame += frames
            }
        }
        for i in stride(from: 0, to: left.count, by: 97) {
            XCTAssertEqual(interleaved[i * 2], separate.left[i], accuracy: 1e-6)
            XCTAssertEqual(interleaved[i * 2 + 1], separate.right[i], accuracy: 1e-6)
        }
    }

    func testChangingSettingsMidStreamStaysClean() {
        let p = EQProcessor(sampleRate: sampleRate)
        var gains = Array(repeating: 0.0, count: EQSettings.bandCount)
        _ = run(plain(gains), left: sine(250, seconds: 0.2), processor: p)
        gains[3] = 12
        let out = run(plain(gains, preamp: -6), left: sine(250, seconds: 0.2), processor: p)
        XCTAssertTrue(out.left.allSatisfy { $0.isFinite && abs($0) < 2 })
    }

    func testEveryPresetIsStableAtCommonSampleRates() {
        for rate in [16_000.0, 44_100, 48_000, 96_000] {
            for preset in Preset.builtIns {
                let params = EQDesign.parameters(for: EQSettings.flat.applying(preset), sampleRate: rate)
                for c in params.sections {
                    // A second-order section is stable when its poles are inside the unit circle.
                    XCTAssertLessThan(abs(c.a2), 1, "\(preset.name) @ \(rate)")
                    XCTAssertLessThan(abs(c.a1), 1 + c.a2, "\(preset.name) @ \(rate)")
                }
            }
        }
    }
}

final class SettingsTests: XCTestCase {
    func testConfigurationRoundTrips() throws {
        var config = AppConfiguration()
        config.eq.gains[4] = -3.5
        config.eq.mono = true
        config.applyToAllOutputs = true
        config.presets.save(name: "Beach", from: config.eq)
        let decoded = AppConfiguration.decode(try config.encoded())
        XCTAssertEqual(decoded, config)
    }

    func testOldOrBrokenSavedDataFallsBackToDefaults() {
        XCTAssertEqual(AppConfiguration.decode(nil), AppConfiguration())
        XCTAssertEqual(AppConfiguration.decode(Data("not json".utf8)), AppConfiguration())

        let partial = AppConfiguration.decode(Data(#"{"enabled": false, "eq": {"gains": [3, 99]}}"#.utf8))
        XCTAssertFalse(partial.enabled)
        XCTAssertEqual(partial.deviceMatch, AppConfiguration.defaultDeviceMatch)
        XCTAssertEqual(partial.eq.gains.count, EQSettings.bandCount)
        XCTAssertEqual(partial.eq.gains[0], 3)
        XCTAssertEqual(partial.eq.gains[1], 12, "out-of-range gains are clamped")
        XCTAssertTrue(partial.eq.speakerProtection)
    }

    func testDeviceMatching() {
        var config = AppConfiguration()
        XCTAssertTrue(config.shouldProcess(deviceNamed: "Xiaomi Sound Outdoor"))
        XCTAssertTrue(config.shouldProcess(deviceNamed: "XIAOMI SOUND OUTDOOR 30W"))
        XCTAssertFalse(config.shouldProcess(deviceNamed: "MacBook Pro Speakers"))

        config.applyToAllOutputs = true
        XCTAssertTrue(config.shouldProcess(deviceNamed: "MacBook Pro Speakers"))

        config.enabled = false
        XCTAssertFalse(config.shouldProcess(deviceNamed: "Xiaomi Sound Outdoor"))
    }

    func testPresetLibrary() {
        var library = PresetLibrary()
        var eq = EQSettings()
        eq.gains[0] = 2
        let saved = library.save(name: "  Pool party  ", from: eq)
        XCTAssertEqual(saved.name, "Pool party")
        XCTAssertEqual(library.all.count, Preset.builtIns.count + 1)

        eq.gains[0] = 4
        library.save(name: "pool party", from: eq)
        XCTAssertEqual(library.custom.count, 1, "same name overwrites")
        XCTAssertEqual(library.custom[0].gains[0], 4)

        XCTAssertTrue(library.rename(id: saved.id, to: "Pool"))
        XCTAssertEqual(library.preset(id: saved.id)?.name, "Pool")

        XCTAssertFalse(library.delete(id: Preset.flat.id), "built-ins can't be deleted")
        XCTAssertTrue(library.delete(id: saved.id))
        XCTAssertTrue(library.custom.isEmpty)
    }

    func testActivePresetClearsWhenSlidersMove() {
        var config = AppConfiguration()
        XCTAssertEqual(config.activePreset, .outdoor)
        config.eq.gains[6] += 1
        XCTAssertNil(config.activePreset)
    }

    func testPresetsHaveOneGainPerBand() {
        for preset in Preset.builtIns {
            XCTAssertEqual(preset.gains.count, EQSettings.bandCount, preset.name)
        }
    }
}
