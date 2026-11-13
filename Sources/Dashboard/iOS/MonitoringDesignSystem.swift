import SwiftUI

enum MonitoringSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let section: CGFloat = 16
    static let screen: CGFloat = 20
}

enum MonitoringRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
}

enum MonitoringTypography {
    static let screenTitle = IOSFont.largeTitle.bold()
    static let sectionTitle = IOSFont.headline
    static let badge = IOSFont.caption2.weight(.semibold)
    static let metricLabel = IOSFont.caption.weight(.semibold)
    static let metricValue = IOSFont.caption.monospacedDigit().weight(.medium)
}

enum MonitoringSurface {
    static let screenBackground = Color(nsColor: .iosGroupedBackground)
    static let cardBackground = Color(nsColor: .iosCardBackground)
    static let border = Color(nsColor: .separatorColor).opacity(0.35)
    static let borderWidth: CGFloat = 0.5
}

enum MonitoringStatus: Equatable, Sendable {
    case operational
    case offline
    case paused
    case pending
    case unknown

    init(_ rawValue: String?) {
        switch rawValue?.lowercased() {
        case "up": self = .operational
        case "down": self = .offline
        case "paused": self = .paused
        case "pending": self = .pending
        default: self = .unknown
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .operational: "status.operational"
        case .offline: "status.offline"
        case .paused: "status.paused"
        case .pending: "status.pending"
        case .unknown: "status.unknown"
        }
    }

    var iconName: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .offline: "exclamationmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .pending: "clock.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .operational: .green
        case .offline: .red
        case .paused: .yellow
        case .pending: .orange
        case .unknown: .secondary
        }
    }
}

enum MetricSeverity: Equatable, Sendable {
    case normal
    case elevated
    case critical

    init(fraction: Double, elevatedThreshold: Double = 0.65, criticalThreshold: Double = 0.9) {
        if fraction >= criticalThreshold {
            self = .critical
        } else if fraction >= elevatedThreshold {
            self = .elevated
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .elevated: .orange
        case .critical: .red
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .normal: "accessibility.loadStatus.normal"
        case .elevated: "accessibility.loadStatus.high"
        case .critical: "accessibility.loadStatus.critical"
        }
    }
}

enum MetricFormatter {
    static func percent(_ value: Double, fractionDigits: Int = 1, locale: Locale = .current) -> String {
        (value / 100).formatted(
            .percent
                .locale(locale)
                .precision(.fractionLength(fractionDigits))
        )
    }

    static func memory(megabytes: Double) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64((megabytes * 1_048_576).rounded()),
            countStyle: .memory
        )
    }

    static func throughput(bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond.rounded()),
            countStyle: .decimal
        ) + "/s"
    }
}

enum MonitoringErrorMessage {
    static func message(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        if urlError.code == .userAuthenticationRequired {
            return String(localized: "common.error.authFailed")
        }
        return String(localized: "onboarding.error.network")
    }
}

struct MonitoringCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                MonitoringSurface.cardBackground,
                in: RoundedRectangle(cornerRadius: MonitoringRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MonitoringRadius.card, style: .continuous)
                    .stroke(MonitoringSurface.border, lineWidth: MonitoringSurface.borderWidth)
            }
    }
}

struct MonitoringCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(MonitoringSpacing.section)
            .modifier(MonitoringCardSurfaceModifier())
    }
}

struct MonitoringMetricRow: View {
    let label: LocalizedStringResource
    let fraction: Double
    let displayValue: String

    private var normalizedFraction: Double {
        min(max(fraction, 0), 1)
    }

    private var severity: MetricSeverity {
        MetricSeverity(fraction: normalizedFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(MonitoringTypography.metricLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayValue)
                    .font(MonitoringTypography.metricValue)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.fill.tertiary)
                    Capsule()
                        .fill(severity.color)
                        .frame(width: geometry.size.width * normalizedFraction)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue("\(displayValue), \(String(localized: severity.title))")
    }
}

// UIKit grouped surfaces, including their dark appearance, reproduced on macOS.
extension NSColor {
    static let iosGroupedBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            : NSColor(srgbRed: 242/255, green: 242/255, blue: 247/255, alpha: 1)
    }
    static let iosCardBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1) : .white
    }
}
extension View {
    func monitoringCard() -> some View { modifier(MonitoringCardModifier()) }
    func monitoringCardSurface() -> some View { modifier(MonitoringCardSurfaceModifier()) }
    func monitoringScreenBackground() -> some View { background(MonitoringSurface.screenBackground) }
}

struct MonitoringStatusBadge: View {
    let status: MonitoringStatus
    var detail: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(status.title)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .monospacedDigit()
            }
        }
        .font(MonitoringTypography.badge)
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}


// Match the iOS typography instead of macOS's smaller semantic font defaults.
enum IOSFont {
    static let largeTitle = Font.system(size: 34)
    static let title2 = Font.system(size: 22)
    static let title3 = Font.system(size: 20)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let subheadline = Font.system(size: 15)
    static let body = Font.system(size: 17)
    static let callout = Font.system(size: 16)
    static let footnote = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let caption2 = Font.system(size: 11)
}
