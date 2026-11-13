import AppKit
import Foundation

final class MenuActions: NSObject {
    static let shared = MenuActions()

    private override init() { super.init() }

    @objc func openSettings(_ sender: Any?) {
        Task { @MainActor in
            WindowManager.shared.showSettings()
        }
    }

    @objc func refreshNow(_ sender: Any?) {
        Task { @MainActor in
            AppState.shared.refresh()
        }
    }

    @objc func switchHub(_ sender: NSMenuItem) {
        Task { @MainActor in
            guard let instanceID = sender.representedObject as? UUID,
                  let instance = AppState.shared.instances.first(where: { $0.id == instanceID }) else { return }
            AppState.shared.selectInstance(instance)
        }
    }

    @objc func showAllHubs(_ sender: Any?) {
        Task { @MainActor in AppState.shared.selectInstance(nil) }
    }

    @objc func openDashboard(_ sender: Any?) {
        let id = (sender as? NSMenuItem)?.representedObject as? HubRecordID
        Task { @MainActor in WindowManager.shared.showDashboard(systemID: id) }
    }

    @objc func openSystemInBrowser(_ sender: NSMenuItem) {
        Task { @MainActor in
            guard let id = sender.representedObject as? HubRecordID,
                  let url = AppState.shared.system(for: id)?.browserURL else { return }
            NSWorkspace.shared.open(url)
        }
    }

    @objc func copyToClipboard(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func quit(_ sender: Any?) {
        Task { @MainActor in
            NSApp.terminate(nil)
        }
    }
}
