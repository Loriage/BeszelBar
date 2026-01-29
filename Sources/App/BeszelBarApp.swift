import SwiftUI

@main
struct BeszelBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: AppState.shared)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    WindowManager.shared.showSettings()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(after: .appTermination) {
                Button("Quit BeszelBar") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
