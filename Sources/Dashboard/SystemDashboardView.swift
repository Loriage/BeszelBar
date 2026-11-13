import SwiftUI

struct SystemDashboardView: View {
    let appState: AppState
    let entry: HubSystem
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: back) { Label("Overview", systemImage: "chevron.left") }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                        Text(entry.name).font(.largeTitle.bold())
                        Text(entry.instance.displayName).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = entry.browserURL {
                        Link(destination: url) { Label("Open in Browser", systemImage: "arrow.up.right.square") }
                    }
                }
                if let snapshot = appState.hubSnapshots[entry.instance.id], snapshot.notice != nil {
                    HubNoticeView(instance: entry.instance, snapshot: snapshot) { appState.refresh(entry.instance) }
                }
                SystemChartsPanel(appState: appState, entry: entry)
                    .id(entry.id)
            }
            .padding(20)
        }
        .monitoringScreenBackground()
        .groupBoxStyle(CardGroupBoxStyle())
    }
}

private struct ChartRequest: Equatable {
    let id: HubRecordID
    let range: HistoryRange
    let revision: Int
    let refreshed: Date?
    let retry: Int
    func hasSameContent(as other: Self?) -> Bool {
        guard let other else { return false }
        return id == other.id && range == other.range && revision == other.revision
    }
}

struct SystemChartsPanel: View {
    let appState: AppState
    let entry: HubSystem
    var showsSummary = true
    let showsContainerCharts: Bool
    @Environment(ChartPins.self) private var pins
    @State private var settings = ChartSettings()
    @State private var category = ChartCategory.all
    @State private var containerName = ""
    @State private var data = ChartDataSet()
    @State private var cards: [ChartDescriptor] = []
    @State private var loaded: ChartRequest?
    @State private var error: String?
    @State private var retry = 0
    @State private var chartEnd = Date()

    init(appState: AppState, entry: HubSystem, showsSummary: Bool = true,
         showsContainerCharts: Bool = false, initialContainer: String = "") {
        self.appState = appState
        self.entry = entry
        self.showsSummary = showsSummary
        self.showsContainerCharts = showsContainerCharts
        _category = State(initialValue: showsContainerCharts ? .containers : .all)
        _containerName = State(initialValue: initialContainer)
    }

    private var request: ChartRequest {
        ChartRequest(id: entry.id, range: settings.selectedTimeRange, revision: appState.connectionRevision,
                     refreshed: appState.hubSnapshots[entry.instance.id]?.lastUpdated, retry: retry)
    }
    private var visibleCards: [ChartDescriptor] {
        cards.filter { card in
            guard (card.category == .containers) == showsContainerCharts else { return false }
            if category == .pinned {
                return card.pin.map { pins.isPinned($0, onSystem: entry.id.chartScope) } ?? false
            }
            if let name = card.containerName { return category == .containers && name == containerName }
            return category == .all || card.category == category
        }
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 16) {
            if showsSummary {
                SystemOverviewCard(entry: entry, stale: appState.hubSnapshots[entry.instance.id]?.errorMessage != nil,
                    showsLink: false, details: appState.hubSnapshots[entry.instance.id]?.details[entry.system.id],
                    stats: request.hasSameContent(as: loaded) ? data.records.last?.stats : nil)
            }
            ChartPanelControls(settings: settings, category: $category, containerName: $containerName,
                containers: data.containers.map(\.name), count: visibleCards.count,
                loading: loaded != request, showsContainerCharts: showsContainerCharts)
            if !request.hasSameContent(as: loaded) {
                ProgressView("Loading history…").frame(maxWidth: .infinity).padding(40)
            } else {
                if let error {
                    ChartLoadingNotice(message: error) { retry += 1 }
                }
                ForEach(data.notices, id: \.self) { notice in
                    ChartLoadingNotice(message: notice) { retry += 1 }
                }
                if data.points.isEmpty {
                    ContentUnavailableView("No History Yet", systemImage: "chart.xyaxis.line",
                                           description: Text("No samples are available for this time range."))
                } else if visibleCards.isEmpty {
                    ContentUnavailableView(category == .pinned ? "No Pinned Charts" : "No Measurements",
                        systemImage: category == .pinned ? "pin" : "chart.xyaxis.line",
                        description: Text(category == .pinned ? "Pin charts to find them here." : "This system has no readings in this category for the selected time range."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(visibleCards) { descriptor in
                            IOSChartCard(descriptor: descriptor, data: data, scope: entry.id.chartScope, range: settings.selectedTimeRange)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .groupBoxStyle(CardGroupBoxStyle(expandsToRowHeight: true))
                    .environment(\.chartXDomain, chartEnd.addingTimeInterval(-settings.selectedTimeRange.duration)...chartEnd)
                    .environment(\.chartShowXGridLines, true)
                    .environment(settings)
                }
            }
        }
        .groupBoxStyle(CardGroupBoxStyle())
        .task(id: request) { await load(request) }
    }

    @MainActor private func load(_ request: ChartRequest) async {
        let now = Date()
        do {
            let result = try await ChartDataLoader.load(service: appState.chartService(for: entry.id),
                                                       systemID: entry.system.id, range: request.range, now: now)
            try Task.checkCancellation()
            data = result
            cards = ChartCatalog.cards(in: result)
            error = nil
            chartEnd = now
        } catch {
            guard !Task.isCancelled else { return }
            if !request.hasSameContent(as: loaded) { data = ChartDataSet(); cards = [] }
            self.error = error.localizedDescription
        }
        loaded = request
    }
}

private struct ChartLoadingNotice: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Spacer()
            Button("Retry", action: retry)
        }
        .font(.callout).padding(12).monitoringCardSurface()
    }
}

private struct ChartPanelControls: View {
    @Bindable var settings: ChartSettings
    @Binding var category: ChartCategory
    @Binding var containerName: String
    let containers: [String]
    let count: Int
    let loading: Bool
    let showsContainerCharts: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filter
                Spacer(minLength: 8)
                chartStatus
                period.frame(width: 240)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    filter
                    Spacer(minLength: 8)
                    chartStatus
                }
                period.frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .monitoringCardSurface()
    }

    @ViewBuilder private var filter: some View {
        if !showsContainerCharts {
            Picker("Charts", selection: $category) {
                ForEach(ChartCategory.allCases.filter { $0 != .containers }) {
                    Text(LocalizedStringKey($0.rawValue)).tag($0)
                }
            }
            .frame(width: 240)
        } else if !containers.isEmpty {
            Picker("Container", selection: $containerName) {
                Text("All containers").tag("")
                ForEach(containers, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 280)
        }
    }

    private var chartStatus: some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView().controlSize(.mini).accessibilityLabel("Loading history…")
            }
            Text("\(count) charts").font(IOSFont.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var period: some View {
        Picker("Time range", selection: $settings.selectedTimeRange) {
            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }
}
