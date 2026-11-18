import SwiftUI

struct ContainersDashboardView: View {
    let appState: AppState
    let entries: [HubContainer]
    let searchText: String

    private var filtered: [HubContainer] {
        entries.filter {
            searchText.isEmpty || $0.container.name.localizedCaseInsensitiveContains(searchText) ||
            $0.systemName.localizedCaseInsensitiveContains(searchText) ||
            $0.instance.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                ContentUnavailableView("No Containers", systemImage: "shippingbox",
                                       description: Text("Containers appear when your hub provides them."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                if searchText.isEmpty {
                    ContainersChartsSection(appState: appState, entries: entries)
                    Divider().padding(.vertical, 8)
                }
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                        if appState.system(for: HubRecordID(hubID: entry.instance.id, recordID: entry.container.system)) != nil {
                            NavigationLink(value: DashboardDestination.container(entry.id)) {
                                ContainerDashboardRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ContainerDashboardRow(entry: entry)
                        }
                        if index < filtered.count - 1 { Divider().padding(.horizontal, 16) }
                    }
                }
                .padding(.vertical, MonitoringSpacing.compact)
                .monitoringCardSurface()
            }
        }
    }
}

private struct ContainersChartsSection: View {
    let appState: AppState
    let entries: [HubContainer]
    @State private var selectedSystemID: HubRecordID?

    private var systems: [HubSystem] {
        let ids = Set(entries.map { HubRecordID(hubID: $0.instance.id, recordID: $0.container.system) })
        return appState.visibleSystems.filter { ids.contains($0.id) }
    }

    var body: some View {
        if let entry = systems.first(where: { $0.id == selectedSystemID }) ?? systems.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Docker Charts").font(IOSFont.title2.bold())
                    Spacer()
                    Picker("System", selection: Binding(
                        get: { selectedSystemID ?? entry.id },
                        set: { selectedSystemID = $0 }
                    )) {
                        ForEach(systems) { system in
                            Text("\(system.name) · \(system.instance.displayName)").tag(system.id)
                        }
                    }
                    .frame(maxWidth: 340)
                }
                SystemChartsPanel(appState: appState, entry: entry, showsSummary: false, showsContainerCharts: true)
                    .id(entry.id)
            }
            .onChange(of: systems.map(\.id)) { _, ids in
                if !ids.contains(where: { $0 == selectedSystemID }) { selectedSystemID = ids.first }
            }
        }
    }
}

private struct ContainerDashboardRow: View {
    let entry: HubContainer
    private var healthColor: Color {
        switch entry.container.health {
        case .healthy: .green
        case .unhealthy: .red
        case .starting: .orange
        case .none: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.container.name).font(IOSFont.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Label(MetricFormatter.percent(entry.container.cpu), systemImage: "cpu")
                    Label(MetricFormatter.memory(megabytes: entry.container.memory), systemImage: "memorychip")
                    if entry.container.net > 0 {
                        Label(MetricFormatter.throughput(bytesPerSecond: entry.container.net), systemImage: "network")
                    }
                }
                .font(IOSFont.caption).foregroundStyle(.secondary)
                Label(entry.container.image, systemImage: "shippingbox")
                    .font(IOSFont.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text("\(entry.systemName) · \(entry.instance.displayName)")
                    .font(IOSFont.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if entry.container.health != .none {
                Text(entry.container.health.displayText)
                    .font(IOSFont.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(healthColor).background(healthColor.opacity(0.15), in: Capsule())
            } else {
                Text(entry.container.status.capitalized)
                    .font(IOSFont.caption2.weight(.semibold))
                    .foregroundStyle(entry.container.status.lowercased() == "running" ? Color.green : .secondary)
            }
            Image(systemName: "chevron.right").font(IOSFont.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AlertsDashboardView: View {
    let entries: [HubAlert]
    let searchText: String

    private var filtered: [HubAlert] {
        entries.filter {
            searchText.isEmpty || $0.alert.name.localizedCaseInsensitiveContains(searchText) ||
            $0.systemName.localizedCaseInsensitiveContains(searchText) ||
            $0.instance.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                ContentUnavailableView("No Alerts Configured", systemImage: "bell.badge",
                                       description: Text("Alerts configured on the selected hubs appear here."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(filtered) { entry in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                            Image(systemName: "bell").foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.alert.name).font(IOSFont.headline)
                            Text("\(entry.systemName) · \(entry.instance.displayName)")
                                .font(IOSFont.caption).foregroundStyle(.secondary)
                            Text("\(entry.alert.displayMetric) · Threshold: \(entry.alert.displayThreshold)")
                                .font(IOSFont.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.alert.triggered == true ? "Triggered" : "Configured")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(entry.alert.triggered == true ? .orange : .secondary)
                    }
                    .monitoringCard()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: filtered.isEmpty ? .infinity : nil)
    }
}
