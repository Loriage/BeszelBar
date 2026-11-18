import Foundation
import SwiftUI

struct HistoryPoint: Identifiable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
}

enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case download = "Download"
    case upload = "Upload"

    var id: Self { self }
    var isPercentage: Bool { self == .cpu || self == .memory || self == .disk }
    var color: Color {
        switch self {
        case .cpu: .blue
        case .memory: .green
        case .disk: .purple
        case .download: .teal
        case .upload: .orange
        }
    }
    func value(in stats: SystemStatsDetail) -> Double? {
        switch self {
        case .cpu: stats.cpu
        case .memory: stats.mp
        case .disk: stats.dp
        case .download: stats.b.flatMap { $0.count >= 2 ? $0[1] / 1_048_576 : nil } ?? stats.nr
        case .upload: stats.b.flatMap { $0.first.map { $0 / 1_048_576 } } ?? stats.ns
        }
    }
}

enum HistorySeries {
    static func points(from records: [SystemStatsRecord], metric: HistoryMetric, range: HistoryRange) -> [HistoryPoint] {
        let records = records.compactMap { record -> (Date, SystemStatsDetail)? in
            guard let date = record.date, let stats = record.stats else { return nil }
            return (date, stats)
        }.sorted { $0.0 < $1.0 }
        var points: [HistoryPoint] = []
        var segment = 0
        var previous: Date?
        for (date, stats) in records {
            guard let value = metric.value(in: stats), value.isFinite, value >= 0 else {
                segment += 1
                previous = nil
                continue
            }
            if let previous, date.timeIntervalSince(previous) > range.interval * 2 {
                segment += 1
            }
            if points.last?.date == date { continue }
            points.append(HistoryPoint(date: date, value: value, segment: segment))
            previous = date
        }
        return points
    }
}
