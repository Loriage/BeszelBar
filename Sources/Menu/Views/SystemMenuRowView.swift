import SwiftUI

struct SystemMenuRowView: View {
    let system: SystemRecord
    @AppStorage("showStatsInMenu") private var showStatsInMenu = true

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(system.name.isEmpty ? system.id : system.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if showStatsInMenu, hasStats {
                    HStack(spacing: 4) {
                        if let cpu = system.cpuPercentage {
                            StatPill(value: "\(Int(cpu))%", icon: "cpu")
                        }
                        if let mem = system.memoryPercentage {
                            StatPill(value: "\(Int(mem))%", icon: "memorychip")
                        }
                        if let disk = system.diskPercentage {
                            StatPill(value: "\(Int(disk))%", icon: "internaldrive")
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var hasStats: Bool {
        system.cpuPercentage != nil || system.memoryPercentage != nil || system.diskPercentage != nil
    }

    private var statusColor: Color {
        guard let status = system.status?.lowercased() else { return .gray }
        switch status {
        case "up", "online": return .green
        case "down", "offline": return .red
        case "pending": return .orange
        default: return .gray
        }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 12, height: 12)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

struct StatPill: View {
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}
