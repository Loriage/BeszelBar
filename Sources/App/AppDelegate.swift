import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var isObserving = false
    private var menuIsOpen = false

    func applicationDidFinishLaunching(_: Notification) {
        #if DEBUG
        if DevelopmentSession.isTestHost { return }
        #endif
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "BeszelBar")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        item.menu = MenuBuilder.build(appState: AppState.shared)
        item.menu?.delegate = self
        self.statusItem = item

        RefreshService.shared.start()
        startObserving()

        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if DevelopmentSession.isEnabled { WindowManager.shared.showDashboard() }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        if DevelopmentSession.isTestHost { return }
        #endif
        RefreshService.shared.stop()
        isObserving = false
        AppState.shared.stopRefreshing()
    }

    private func startObserving() {
        isObserving = true
        observeState()
    }

    private func observeState() {
        guard isObserving else { return }
        withObservationTracking {
            _ = AppState.shared.instances
            _ = AppState.shared.selectedInstance
            _ = AppState.shared.showsAllHubs
            _ = AppState.shared.hubSnapshots
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isObserving else { return }
                self.refreshMenu()
                self.observeState()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showDashboard()
        return true
    }

    private func refreshMenu() {
        // Keep the tracked menu stable while users navigate its submenus.
        guard !menuIsOpen else { return }
        let appState = AppState.shared

        if let button = statusItem?.button {
            let alertCount = appState.activeAlerts.count
            if alertCount > 0 {
                button.image = NSImage(systemSymbolName: "server.rack.fill", accessibilityDescription: "BeszelBar")
                button.title = " \(alertCount)"
            } else {
                button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "BeszelBar")
                button.title = ""
            }
            button.image?.size = NSSize(width: 18, height: 18)
        }

        statusItem?.menu = MenuBuilder.build(appState: appState)
        statusItem?.menu?.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        refreshMenu()
    }
}
