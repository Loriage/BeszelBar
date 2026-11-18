import SwiftUI
import AppKit

@MainActor
enum MenuBuilder {
    private static let menuWidth: CGFloat = 320

    static func build(appState: AppState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let actions = MenuActions.shared

        let headerItem = NSMenuItem()
        let headerView = NSHostingView(rootView: MenuHeaderView(appState: appState))
        headerView.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 46)
        headerItem.view = headerView
        menu.addItem(headerItem)

        if !appState.activeAlerts.isEmpty {
            menu.addItem(createAlertsSubmenu(alerts: appState.activeAlerts))
            menu.addItem(NSMenuItem.separator())
        }

        if appState.instances.isEmpty {
            menu.addItem(createInfoItem("No Hub Configured", subtext: "Open Settings to add a hub"))
        } else {
            for instance in appState.visibleInstances {
                let snapshot = appState.hubSnapshots[instance.id] ?? HubSnapshot()
                if appState.showsAllHubs {
                    let heading = NSMenuItem.sectionHeader(title: instance.displayName)
                    menu.addItem(heading)
                }
                if let notice = snapshot.notice {
                    menu.addItem(createInfoItem("Hub needs attention", subtext: notice))
                }
                if snapshot.isLoading && snapshot.systems.isEmpty {
                    menu.addItem(createInfoItem("Loading…", subtext: nil))
                } else if snapshot.systems.isEmpty && snapshot.errorMessage == nil {
                    menu.addItem(createInfoItem("No Systems Found", subtext: nil))
                }
                for system in snapshot.systems {
                    menu.addItem(createSystemItem(for: HubSystem(instance: instance, system: system, connectionURL: snapshot.connectedURL), appState: appState))
                }
            }
        }

        menu.addItem(NSMenuItem.separator())

        if appState.instances.count > 1 {
            menu.addItem(createHubSwitcherSubmenu(appState: appState))
        }

        let dashboardItem = NSMenuItem(title: "Open Dashboard…", action: #selector(MenuActions.openDashboard(_:)), keyEquivalent: "d")
        dashboardItem.target = actions
        dashboardItem.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)
        menu.addItem(dashboardItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(MenuActions.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = actions
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.image?.size = NSSize(width: 14, height: 14)
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(MenuActions.refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = actions
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshItem.image?.size = NSSize(width: 14, height: 14)
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit BeszelBar",
            action: #selector(MenuActions.quit),
            keyEquivalent: "q"
        )
        quitItem.target = MenuActions.shared
        menu.addItem(quitItem)

        return menu
    }

    private static func createHubSwitcherSubmenu(appState: AppState) -> NSMenuItem {
        let item = NSMenuItem(title: "Show Hubs", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        item.image?.size = NSSize(width: 14, height: 14)

        let submenu = NSMenu()
        let allItem = NSMenuItem(title: "All Hubs", action: #selector(MenuActions.showAllHubs(_:)), keyEquivalent: "")
        allItem.target = MenuActions.shared
        allItem.state = appState.showsAllHubs ? .on : .off
        submenu.addItem(allItem)
        submenu.addItem(.separator())
        for instance in appState.instances {
            let hubItem = NSMenuItem(
                title: instance.name.isEmpty ? instance.url : instance.name,
                action: #selector(MenuActions.switchHub(_:)),
                keyEquivalent: ""
            )
            hubItem.target = MenuActions.shared
            hubItem.representedObject = instance.id

            if !appState.showsAllHubs && instance.id == appState.selectedInstance?.id {
                hubItem.state = .on
            }

            submenu.addItem(hubItem)
        }

        item.submenu = submenu
        return item
    }

    private static func createAlertsSubmenu(alerts: [HubAlert]) -> NSMenuItem {
        let item = NSMenuItem(title: "Alerts (\(alerts.count))", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        item.image?.size = NSSize(width: 14, height: 14)
        item.image?.isTemplate = false

        let submenu = NSMenu()

        for entry in alerts.prefix(10) {
            let alert = entry.alert
            let systemName = "\(entry.systemName) · \(entry.instance.displayName)"
            let alertItem = NSMenuItem()

            let view = NSHostingView(rootView: AlertMenuRowView(alert: alert, systemName: systemName))
            view.frame = NSRect(x: 0, y: 0, width: menuWidth - 20, height: 44)
            alertItem.view = view

            submenu.addItem(alertItem)
        }

        if alerts.count > 10 {
            submenu.addItem(NSMenuItem.separator())
            let moreItem = NSMenuItem(title: "+\(alerts.count - 10) more alerts", action: nil, keyEquivalent: "")
            moreItem.isEnabled = false
            submenu.addItem(moreItem)
        }

        item.submenu = submenu
        return item
    }

    private static func createInfoItem(_ title: String, subtext: String?) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: InfoMenuRowView(title: title, subtext: subtext))
        view.frame = NSRect(x: 0, y: 0, width: menuWidth, height: subtext != nil ? 40 : 28)
        item.view = view
        item.isEnabled = true
        return item
    }

    private static func createSystemItem(for entry: HubSystem, appState: AppState) -> NSMenuItem {
        let system = entry.system
        let item = NSMenuItem(
            title: system.name.isEmpty ? system.id : system.name,
            action: #selector(MenuActions.openSystemInBrowser(_:)),
            keyEquivalent: ""
        )
        item.target = MenuActions.shared
        item.representedObject = entry.id

        let hostingView = NSHostingView(rootView: SystemMenuRowView(system: system))
        hostingView.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 44)

        let wrapper = NSView(frame: hostingView.frame)
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = .clear
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        wrapper.addSubview(hostingView)
        hostingView.frame = wrapper.bounds

        item.view = wrapper

        let snapshot = appState.hubSnapshots[entry.instance.id] ?? HubSnapshot()
        let containers = snapshot.containers.filter { $0.system == system.id }
        let submenu = createSystemSubmenu(for: entry, containers: containers, appState: appState)
        item.submenu = submenu

        return item
    }

    private static func createSystemSubmenu(for entry: HubSystem, containers: [ContainerRecord], appState: AppState) -> NSMenu {
        let submenu = NSMenu()
        let system = entry.system
        let details = appState.hubSnapshots[entry.instance.id]?.details[system.id]

        let detailItem = NSMenuItem()
        let detailView = NSHostingView(rootView: SystemDetailView(system: system, details: details))
        detailView.frame = NSRect(x: 0, y: 0, width: 250, height: 180)
        detailItem.view = detailView
        submenu.addItem(detailItem)

        if !containers.isEmpty {
            submenu.addItem(NSMenuItem.separator())

            let headerItem = NSMenuItem()
            let headerView = NSHostingView(rootView:
                HStack {
                    Label("Containers (\(containers.count))", systemImage: "shippingbox.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            )
            headerView.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            headerItem.view = headerView
            submenu.addItem(headerItem)

            let sortedContainers = containers.sorted { $0.name.lowercased() < $1.name.lowercased() }

            for container in sortedContainers.prefix(10) {
                let containerItem = NSMenuItem()
                let view = NSHostingView(rootView: ContainerMenuRowView(container: container))
                view.frame = NSRect(x: 0, y: 0, width: 260, height: 50)
                containerItem.view = view
                submenu.addItem(containerItem)
            }

            if containers.count > 10 {
                let moreItem = NSMenuItem(title: "+\(containers.count - 10) more containers", action: nil, keyEquivalent: "")
                moreItem.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
                moreItem.image?.size = NSSize(width: 12, height: 12)

                let moreSubmenu = NSMenu()
                for container in sortedContainers.dropFirst(10) {
                    let containerItem = NSMenuItem()
                    let view = NSHostingView(rootView: ContainerMenuRowView(container: container))
                    view.frame = NSRect(x: 0, y: 0, width: 260, height: 50)
                    containerItem.view = view
                    moreSubmenu.addItem(containerItem)
                }
                moreItem.submenu = moreSubmenu
                submenu.addItem(moreItem)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        let dashboardItem = NSMenuItem(title: "View Charts…", action: #selector(MenuActions.openDashboard(_:)), keyEquivalent: "")
        dashboardItem.target = MenuActions.shared
        dashboardItem.representedObject = entry.id
        submenu.addItem(dashboardItem)

        let openItem = NSMenuItem(
            title: "Open in Browser",
            action: #selector(MenuActions.openSystemInBrowser(_:)),
            keyEquivalent: ""
        )
        openItem.target = MenuActions.shared
        openItem.representedObject = entry.id
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        openItem.image?.size = NSSize(width: 14, height: 14)
        submenu.addItem(openItem)

        let hostname = details?.hostname ?? system.info?.h
        if let hostname = hostname {
            let copyItem = NSMenuItem(
                title: "Copy Hostname",
                action: #selector(MenuActions.copyToClipboard(_:)),
                keyEquivalent: ""
            )
            copyItem.target = MenuActions.shared
            copyItem.representedObject = hostname
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            copyItem.image?.size = NSSize(width: 14, height: 14)
            submenu.addItem(copyItem)
        }

        return submenu
    }
}
