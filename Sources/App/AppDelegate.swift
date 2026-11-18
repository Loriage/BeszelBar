import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
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

        // Menu bar stats settings live in UserDefaults, which Observation doesn't track.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                AppState.shared.loadPinnedSystem()
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func observeState() {
        guard isObserving else { return }
        withObservationTracking {
            _ = AppState.shared.instances
            _ = AppState.shared.selectedInstance
            _ = AppState.shared.showsAllHubs
            _ = AppState.shared.hubSnapshots
            _ = AppState.shared.pinnedSystem
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
        updateStatusButton()
        // Keep the tracked menu stable while users navigate its submenus; the status button can still update.
        guard !menuIsOpen else { return }
        statusItem?.menu = MenuBuilder.build(appState: AppState.shared)
        statusItem?.menu?.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        refreshMenu()
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let appState = AppState.shared

        let alertCount = appState.activeAlerts.count
        let font = NSFont.menuBarFont(ofSize: 0)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

        let settings = MenuBarStatsSettings.current()
        var stats: NSAttributedString?
        if let settings, let system = appState.menuBarSystem {
            stats = MenuBarStatsFormatter.attributedString(for: system, settings: settings, font: font)
        }

        // Only hide the icon while stats are visible, so the item never becomes empty.
        let hideIcon = stats != nil && settings?.hideIcon == true

        if hideIcon {
            button.image = nil
        } else {
            let symbolName = alertCount > 0 ? "server.rack.fill" : "server.rack"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BeszelBar")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        var parts: [NSAttributedString] = []
        if alertCount > 0 {
            let alert = NSMutableAttributedString()
            if hideIcon {
                // Without the filled icon, mark the alert count explicitly.
                alert.append(MenuBarStatsFormatter.icon("exclamationmark.triangle.fill", font: font))
                alert.append(NSAttributedString(string: " ", attributes: plain))
            }
            alert.append(NSAttributedString(string: "\(alertCount)", attributes: plain))
            parts.append(alert)
        }
        if let stats {
            parts.append(stats)
        }

        let title = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " · ", attributes: plain))
            } else if !hideIcon {
                title.append(NSAttributedString(string: " ", attributes: plain))
            }
            title.append(part)
        }

        button.attributedTitle = title
    }
}

@MainActor
enum MenuBarStatsFormatter {
    private struct Metric {
        let icon: String
        let value: Double
        let text: String
        let warning: Double
        let critical: Double
    }

    /// Returns nil when there is nothing to show (no metrics enabled or available).
    static func attributedString(for system: SystemRecord, settings: MenuBarStatsSettings, font: NSFont) -> NSAttributedString? {
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let plain: [NSAttributedString.Key: Any] = [.font: digitsFont, .foregroundColor: NSColor.labelColor]
        let result = NSMutableAttributedString()

        guard system.isOnline else {
            result.append(NSAttributedString(string: "●", attributes: [.font: digitsFont, .foregroundColor: NSColor.systemRed]))
            result.append(NSAttributedString(string: " Offline", attributes: plain))
            return result
        }

        var metrics: [Metric] = []
        if settings.showCPU, let cpu = system.cpuPercentage {
            metrics.append(Metric(icon: "cpu", value: cpu, text: "\(Int(cpu))%", warning: 70, critical: 90))
        }
        if settings.showMemory, let mem = system.memoryPercentage {
            metrics.append(Metric(icon: "memorychip", value: mem, text: "\(Int(mem))%", warning: 70, critical: 90))
        }
        if settings.showDisk, let disk = system.diskPercentage {
            metrics.append(Metric(icon: "internaldrive", value: disk, text: "\(Int(disk))%", warning: 70, critical: 90))
        }
        if settings.showTemperature, let temp = system.temperature {
            metrics.append(Metric(icon: "thermometer.medium", value: temp, text: String(format: "%.0f°C", temp), warning: 60, critical: 80))
        }

        guard !metrics.isEmpty else { return nil }

        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: plain))
            }

            var valueAttributes = plain
            if settings.colorThresholds, let color = thresholdColor(for: metric) {
                valueAttributes[.foregroundColor] = color
            }

            result.append(icon(metric.icon, font: digitsFont))
            result.append(NSAttributedString(string: " \(metric.text)", attributes: valueAttributes))
        }

        return result
    }

    /// An SF Symbol sized to the menu bar font and vertically centered on the text.
    static func icon(_ name: String, font: NSFont) -> NSAttributedString {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 1, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return NSAttributedString()
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        let y = ((font.capHeight - image.size.height) / 2).rounded()
        attachment.bounds = CGRect(x: 0, y: y, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func thresholdColor(for metric: Metric) -> NSColor? {
        if metric.value >= metric.critical { return .systemRed }
        if metric.value >= metric.warning { return .systemOrange }
        return nil
    }
}
