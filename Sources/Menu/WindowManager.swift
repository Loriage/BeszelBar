import SwiftUI
import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private let navigation = DashboardNavigation()

    private init() {}

    func showDashboard(systemID: HubRecordID? = nil) {
        if let systemID {
            let state = AppState.shared
            if !state.visibleInstances.contains(where: { $0.id == systemID.hubID }),
               let instance = state.instances.first(where: { $0.id == systemID.hubID }) {
                state.selectInstance(instance)
            }
            navigation.show(.overview)
            navigation.systemID = systemID
        }
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "BeszelBar"
        window.contentView = NSHostingView(rootView: DashboardView(appState: AppState.shared, navigation: navigation))
        window.minSize = NSSize(width: 840, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BeszelBarDashboard")
        window.center()
        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView(appState: AppState.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "BeszelBar"
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
