import SwiftUI

@main
struct BeszelBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: AppState.shared)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Dashboard…") {
                    WindowManager.shared.showDashboard()
                }
                .keyboardShortcut("d")
                Button("Settings...") {
                    WindowManager.shared.showSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
