import SwiftUI
import Observation

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case containers = "Containers"
    case alerts = "Alerts"

    var id: Self { self }
    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .containers: "shippingbox"
        case .alerts: "bell"
        }
    }
}

@MainActor @Observable
final class DashboardNavigation {
    var section: DashboardSection = .overview
    var systemID: HubRecordID?
    var searchText = ""
    var path = NavigationPath()

    func show(_ section: DashboardSection) {
        self.section = section
        systemID = nil
        path = NavigationPath()
        searchText = ""
    }
}

enum DashboardDestination: Hashable {
    case container(HubRecordID)
}

struct DashboardView: View {
    let appState: AppState
    @Bindable var navigation: DashboardNavigation

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(appState: appState, navigation: navigation)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            NavigationStack(path: $navigation.path) {
                Group {
                    if let id = navigation.systemID, let entry = appState.system(for: id) {
                        SystemDashboardView(appState: appState, entry: entry) {
                            navigation.show(.overview)
                        }
                        .navigationTitle(entry.name)
                    } else {
                        DashboardContent(appState: appState, navigation: navigation)
                            .navigationTitle(Text(LocalizedStringKey(navigation.section.rawValue)))
                    }
                }
                .navigationDestination(for: DashboardDestination.self) { destination in
                    switch destination {
                    case .container(let id):
                        if let entry = appState.visibleContainers.first(where: { $0.id == id }),
                           let system = appState.system(for: HubRecordID(hubID: id.hubID, recordID: entry.container.system)) {
                            ScrollView {
                                SystemChartsPanel(appState: appState, entry: system,
                                    showsContainerCharts: true, initialContainer: entry.container.name)
                                    .id(entry.id).padding(20)
                            }
                            .navigationTitle(entry.container.name)
                            .monitoringScreenBackground()
                        }
                    }
                }
            }
            .modifier(DashboardScrollEdgeModifier())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MonitoringStyle.background)
        }
        .environment(ChartPins.shared)
        .groupBoxStyle(CardGroupBoxStyle())
        .searchable(text: $navigation.searchText, prompt: "Search systems, hubs or containers")
        .toolbar {
            ToolbarItemGroup {
                if appState.isLoading {
                    ProgressView().controlSize(.small).help("Refreshing hubs")
                }
                Button {
                    appState.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh all hubs in this view")
                Button {
                    WindowManager.shared.showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: appState.visibleInstances.map(\.id)) {
            navigation.path = NavigationPath()
            if let id = navigation.systemID,
               !appState.visibleInstances.contains(where: { $0.id == id.hubID }) {
                navigation.systemID = nil
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct DashboardScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

private struct DashboardSidebar: View {
    let appState: AppState
    let navigation: DashboardNavigation

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Monitoring") {
                    ForEach(DashboardSection.allCases) { section in
                        Button {
                            navigation.show(section)
                        } label: {
                            HStack {
                                Label(LocalizedStringKey(section.rawValue), systemImage: section.icon)
                                Spacer()
                                if section == .alerts, !appState.visibleAlerts.isEmpty {
                                    Text("\(appState.visibleAlerts.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(navigation.section == section ? Color.accentColor.opacity(0.13) : Color.clear)
                        .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                    }
                }
                Section("Hubs") {
                    HubScopeRow(title: "All Hubs", icon: "square.stack.3d.up", selected: appState.showsAllHubs) {
                        navigation.show(navigation.section)
                        appState.selectInstance(nil)
                    }
                    ForEach(appState.instances) { instance in
                        HubScopeRow(title: instance.displayName, icon: "server.rack",
                                    selected: !appState.showsAllHubs && appState.selectedInstance?.id == instance.id,
                                    hasError: appState.hubSnapshots[instance.id]?.notice != nil) {
                            navigation.show(navigation.section)
                            appState.selectInstance(instance)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct HubScopeRow: View {
    let title: String
    let icon: String
    let selected: Bool
    var hasError = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(LocalizedStringKey(title), systemImage: icon).lineLimit(1)
                Spacer(minLength: 0)
                if hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).help("Hub needs attention")
                }
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DashboardContent: View {
    let appState: AppState
    let navigation: DashboardNavigation

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(navigation.section.rawValue)).font(MonitoringTypography.screenTitle)
                        Text(appState.scopeTitle).foregroundStyle(.secondary)
                    }
                    ForEach(appState.visibleInstances) { instance in
                        if let snapshot = appState.hubSnapshots[instance.id], snapshot.notice != nil {
                            HubNoticeView(instance: instance, snapshot: snapshot) { appState.refresh(instance) }
                        }
                    }
                    if appState.instances.isEmpty {
                        ContentUnavailableView {
                            Label("Welcome to BeszelBar", systemImage: "server.rack")
                        } description: {
                            Text("Add a Beszel hub to see your servers, containers and alerts here.")
                        } actions: {
                            Button("Add a Hub") { WindowManager.shared.showSettings() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        switch navigation.section {
                        case .overview:
                            OverviewView(appState: appState, searchText: navigation.searchText) {
                                navigation.systemID = $0
                            }
                        case .containers:
                            ContainersDashboardView(appState: appState, entries: appState.visibleContainers, searchText: navigation.searchText)
                        case .alerts:
                            AlertsDashboardView(entries: appState.visibleAlerts, searchText: navigation.searchText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: max(0, geometry.size.height - 48), alignment: .topLeading)
                .padding(24)
            }
        }
    }
}

private struct OverviewView: View {
    let appState: AppState
    let searchText: String
    let selectSystem: (HubRecordID) -> Void
    @State private var chartSystemID: HubRecordID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SummaryCard(title: "Systems", value: appState.visibleSystems.count, icon: "server.rack", color: .blue)
                SummaryCard(title: "Online", value: appState.visibleSystems.filter {
                    $0.system.isOnline && appState.hubSnapshots[$0.instance.id]?.errorMessage == nil
                }.count,
                            icon: "checkmark.circle", color: .green)
                SummaryCard(title: "Containers", value: appState.visibleContainers.count, icon: "shippingbox", color: .purple)
                SummaryCard(title: "Alerts", value: appState.visibleAlerts.count, icon: "bell", color: .orange)
            }
            ForEach(appState.visibleInstances) { instance in
                let snapshot = appState.hubSnapshots[instance.id] ?? HubSnapshot()
                let systems = snapshot.systems.filter {
                    searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) ||
                    instance.displayName.localizedCaseInsensitiveContains(searchText)
                }
                HubSystemsSection(instance: instance, snapshot: snapshot, systems: systems, selectSystem: selectSystem)
            }
            if searchText.isEmpty, let entry = appState.visibleSystems.first(where: { $0.id == chartSystemID }) ?? appState.visibleSystems.first {
                Divider().padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("System Charts").font(IOSFont.title2.bold())
                        Spacer()
                        Picker("System", selection: $chartSystemID) {
                            ForEach(appState.visibleSystems) { entry in
                                Text("\(entry.name) · \(entry.instance.displayName)").tag(Optional(entry.id))
                            }
                        }
                        .frame(maxWidth: 340)
                    }
                    SystemChartsPanel(appState: appState, entry: entry, showsSummary: false).id(entry.id)
                }
            }
            if !searchText.isEmpty && !appState.visibleSystems.contains(where: {
                $0.name.localizedCaseInsensitiveContains(searchText) || $0.instance.displayName.localizedCaseInsensitiveContains(searchText)
            }) {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .onAppear { if chartSystemID == nil { chartSystemID = appState.visibleSystems.first?.id } }
        .onChange(of: appState.visibleSystems.map(\.id)) { _, ids in
            if chartSystemID == nil || !ids.contains(where: { $0 == chartSystemID }) { chartSystemID = ids.first }
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedStringKey(title), systemImage: icon).font(IOSFont.footnote).foregroundStyle(.secondary)
            Text(value, format: .number).font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitoringCard()
        .accessibilityElement(children: .combine)
    }
}

private struct HubSystemsSection: View {
    @Environment(ChartPins.self) private var pins
    let instance: Instance
    let snapshot: HubSnapshot
    let systems: [SystemRecord]
    let selectSystem: (HubRecordID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubConnectionBadge(instance: instance, snapshot: snapshot)
            if snapshot.systems.isEmpty && !snapshot.isLoading && snapshot.errorMessage == nil {
                Text("No systems found on this hub.").foregroundStyle(.secondary).padding(.vertical, 12)
            }
            LazyVGrid(columns: MonitoringStyle.columns, spacing: 16) {
                ForEach(systems.sorted {
                    let a = pins.isPinned(.systemInfo, onSystem: HubRecordID(hubID: instance.id, recordID: $0.id).chartScope)
                    let b = pins.isPinned(.systemInfo, onSystem: HubRecordID(hubID: instance.id, recordID: $1.id).chartScope)
                    return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a
                }) { system in
                    let entry = HubSystem(instance: instance, system: system, connectionURL: snapshot.connectedURL)
                    SystemOverviewCard(entry: entry, stale: snapshot.errorMessage != nil,
                        details: snapshot.details[system.id], onOpen: { selectSystem(entry.id) })
                }
            }
        }
    }
}

struct SystemOverviewCard: View {
    let entry: HubSystem
    var stale = false
    var showsLink = true
    var details: SystemDetailsRecord? = nil
    var stats: DetailedSystemStats? = nil
    var onOpen: (() -> Void)? = nil
    @Environment(ChartPins.self) private var pins

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SystemSummaryCard(details: details, hubName: entry.instance.displayName,
                system: entry.system, systemInfo: entry.system.info, stats: stats,
                systemName: entry.name, status: stale ? "unknown" : entry.system.status, onOpen: onOpen,
                isPinned: pins.isPinned(.systemInfo, onSystem: entry.id.chartScope),
                onPinToggle: { pins.togglePin(for: .systemInfo, onSystem: entry.id.chartScope) })
            if stale {
                Label("Last available readings", systemImage: "clock").font(.caption).foregroundStyle(.orange)
            }
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }
}
