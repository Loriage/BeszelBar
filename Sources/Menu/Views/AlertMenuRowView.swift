import SwiftUI

struct AlertMenuRowView: View {
    let alert: AlertRecord
    let systemName: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alertIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(alertColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(systemName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text("\u{2022}")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text("\(alert.displayMetric) > \(alert.displayThreshold)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var alertIcon: String {
        guard let metric = alert.metric?.lowercased() else { return "exclamationmark.triangle" }
        switch metric {
        case "cpu": return "cpu"
        case "memory", "mem": return "memorychip"
        case "disk": return "internaldrive"
        case "temperature", "temp": return "thermometer.high"
        case "network": return "network"
        default: return "exclamationmark.triangle"
        }
    }

    private var alertColor: Color {
        alert.triggered == true ? .red : .yellow
    }
}
