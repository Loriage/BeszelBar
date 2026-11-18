import SwiftUI

// The same card spacing, metric hierarchy and status treatment as Beszel iOS,
// using macOS semantic surfaces and controls.
enum MonitoringStyle {
    static let background = MonitoringSurface.screenBackground
    static let card = MonitoringSurface.cardBackground
    static let border = Color.primary.opacity(0.08)
    static let columns = [GridItem(.adaptive(minimum: 360), spacing: 16)]
}

struct SystemStatusBadge: View {
    let system: SystemRecord
    var stale = false

    var body: some View {
        Label(stale ? "Last known: \(system.displayStatus)" : system.displayStatus,
              systemImage: stale ? "clock" : (system.isOnline ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
            .font(.caption.weight(.medium))
            .foregroundStyle(stale ? .orange : (system.isOnline ? .green : .secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((stale ? Color.orange : (system.isOnline ? .green : .secondary)).opacity(0.1), in: Capsule())
    }
}

struct UsageMetricView: View {
    let title: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                if let value, value.isFinite {
                    Text(value / 100, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))
            ProgressView(value: min(max(value?.isFinite == true ? value! : 0, 0), 100), total: 100)
                .tint(color)
                .accessibilityLabel(title)
        }
        .accessibilityElement(children: .combine)
    }
}

enum MonitoringFormat {
    static func memory(_ megabytes: Double) -> String {
        guard megabytes.isFinite, megabytes >= 0, megabytes < Double(Int64.max) / 1_048_576 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(megabytes * 1_048_576), countStyle: .memory)
    }
}

struct HubNoticeView: View {
    let instance: Instance
    let snapshot: HubSnapshot
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(instance.displayName).font(.headline)
                Text(snapshot.notice ?? "").font(.callout).foregroundStyle(.secondary)
                if let date = snapshot.lastUpdated {
                    Text("Showing last available data from \(date.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Retry", action: retry).disabled(snapshot.isLoading)
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Connection feedback for dashboard hub sections.
struct HubConnectionBadge: View {
    let instance: Instance
    let snapshot: HubSnapshot

    private var unavailable: Bool { snapshot.errorMessage != nil }
    private var label: LocalizedStringKey {
        if unavailable { return "Unavailable" }
        if snapshot.connectedURL == nil { return "Connecting…" }
        return snapshot.usesFallback(for: instance) ? "Secondary URL" : "Primary URL"
    }
    var body: some View {
        HStack(spacing: 8) {
            Label(instance.displayName, systemImage: "server.rack")
                .font(IOSFont.footnote.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if snapshot.isLoading { ProgressView().controlSize(.mini) }
            else if let date = snapshot.lastUpdated {
                Text(date, style: .relative).font(IOSFont.caption2).foregroundStyle(.secondary)
                    .help("Time since the last successful refresh")
            }
            Label(label, systemImage: unavailable ? "exclamationmark.triangle" : "arrow.triangle.swap")
                .font(IOSFont.caption2.weight(.medium))
                .foregroundStyle(unavailable ? Color.orange : .secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background((unavailable ? Color.orange : .secondary).opacity(0.1), in: Capsule())
                .help(snapshot.connectedURL?.absoluteString ?? instance.url)
        }
    }
}
