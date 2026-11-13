import Foundation

/// PocketBase record IDs are only unique inside their owning hub.
struct HubRecordID: Hashable, Identifiable, Sendable {
    let hubID: UUID
    let recordID: String
    var id: Self { self }
}

struct HubSystem: Identifiable {
    let instance: Instance
    let system: SystemRecord
    var connectionURL: URL? = nil
    var id: HubRecordID { HubRecordID(hubID: instance.id, recordID: system.id) }
    var name: String { system.name.isEmpty ? system.id : system.name }
    var browserURL: URL? {
        guard let base = connectionURL ?? URL(string: instance.url),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = "/systems/\(system.id)"
        return components.url
    }
}

struct HubAlert: Identifiable {
    let instance: Instance
    let alert: AlertRecord
    let systemName: String
    var id: HubRecordID { HubRecordID(hubID: instance.id, recordID: alert.id) }
}

struct HubContainer: Identifiable {
    let instance: Instance
    let container: ContainerRecord
    let systemName: String
    var id: HubRecordID { HubRecordID(hubID: instance.id, recordID: container.id) }
}

struct HubSnapshot {
    var systems: [SystemRecord] = []
    var details: [String: SystemDetailsRecord] = [:]
    var containers: [ContainerRecord] = []
    var alerts: [AlertRecord] = []
    var isLoading = false
    var errorMessage: String?
    var resourceErrors: [String] = []
    var lastUpdated: Date?
    var connectedURL: URL?

    func usesFallback(for instance: Instance) -> Bool {
        guard let connectedURL, let fallback = HubURL.normalized(instance.fallbackURL) else { return false }
        return connectedURL.absoluteString == fallback
    }

    var notice: String? {
        errorMessage ?? (resourceErrors.isEmpty ? nil : resourceErrors.joined(separator: "\n"))
    }
}

extension Instance {
    var displayName: String { name.isEmpty ? url : name }
}

enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case hour = "1h"
    case halfDay = "12h"
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }
    var duration: TimeInterval {
        switch self {
        case .hour: 3_600
        case .halfDay: 43_200
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        }
    }
    var recordType: String {
        switch self {
        case .hour: "1m"
        case .halfDay: "10m"
        case .day: "20m"
        case .week: "120m"
        case .month: "480m"
        }
    }
    var interval: TimeInterval {
        switch self {
        case .hour: 60
        case .halfDay: 600
        case .day: 1_200
        case .week: 7_200
        case .month: 28_800
        }
    }
}

extension SystemStatsRecord {
    var date: Date? {
        // PocketBase uses a space separator and fractional seconds; older hubs can use ISO 8601.
        let normalized = created.replacingOccurrences(of: " ", with: "T")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }
}

extension HistoryRange {
    var xAxisFormat: Date.FormatStyle {
        switch self {
        case .hour, .halfDay: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        case .day: .dateTime.hour().minute()
        case .week, .month: .dateTime.day(.twoDigits).month(.twoDigits)
        }
    }
}
