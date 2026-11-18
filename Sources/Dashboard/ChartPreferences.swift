import SwiftUI
import Observation

@MainActor @Observable
final class ChartSettings {
    var selectedTimeRange = HistoryRange.hour
}

@MainActor @Observable
final class ChartPins {
    static let shared = ChartPins()
    private var pinned: [String: Set<PinnedItem>]
    private let defaults: UserDefaults
    private let key = "com.nohitdev.BeszelBar.chartPins"

    init(defaults: UserDefaults? = nil) {
        #if DEBUG
        self.defaults = defaults ?? (DevelopmentSession.isEnabled
            ? UserDefaults(suiteName: "com.nohitdev.BeszelBar.testing.charts")! : .standard)
        #else
        self.defaults = defaults ?? .standard
        #endif
        pinned = self.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Set<PinnedItem>].self, from: $0) } ?? [:]
    }

    // Every caller supplies the composite hub/system ID. The optional instance
    // argument keeps the imported GPU component's API without changing identity.
    func isPinned(_ item: PinnedItem, onSystem system: String, inInstance: String? = nil) -> Bool {
        pinned[system]?.contains(item) == true
    }
    func togglePin(for item: PinnedItem, onSystem system: String, inInstance: String? = nil) {
        if pinned[system, default: []].contains(item) { pinned[system]?.remove(item) }
        else { pinned[system, default: []].insert(item) }
        if let data = try? JSONEncoder().encode(pinned) { defaults.set(data, forKey: key) }
    }
}

extension HubRecordID {
    var chartScope: String { "\(hubID.uuidString)/\(recordID)" }
}
