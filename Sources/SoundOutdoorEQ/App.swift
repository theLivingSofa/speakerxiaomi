#if os(macOS)
import AppKit
import SwiftUI

@main
struct SoundOutdoorEQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isActive && !model.config.eq.bypass ? "hifispeaker.fill" : "hifispeaker")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Hand audio back to the apps right away. macOS would also do this once the process exits.
        MainActor.assumeIsolated {
            AppModel.shared.shutdown()
        }
    }
}
#else
/// The app needs macOS. This stub only lets the package build on other systems, for running the EQCore tests.
@main
enum SoundOutdoorEQUnsupported {
    static func main() {
        print("Sound Outdoor EQ runs on macOS 14.2 or newer.")
    }
}
#endif
