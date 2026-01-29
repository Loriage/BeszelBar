import SwiftUI

struct ContainerMenuRowView: View {
    let container: ContainerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(container.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                HealthBadge(health: container.health)
            }

            HStack(spacing: 8) {
                Label(String(format: "%.1f%%", container.cpu), systemImage: "cpu")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Label(formatMemory(container.memory), systemImage: "memorychip")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                Text(container.status)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            if !container.image.isEmpty {
                Label {
                    Text(container.image)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "shippingbox")
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

struct HealthBadge: View {
    let health: ContainerHealth

    var textColor: Color {
        switch health {
        case .none: return .gray
        case .starting: return Color(red: 0.7, green: 0.4, blue: 0.0)
        case .healthy: return Color(red: 0.1, green: 0.5, blue: 0.2)
        case .unhealthy: return Color(red: 0.7, green: 0.1, blue: 0.1)
        }
    }

    var bgColor: Color {
        switch health {
        case .none: return .gray
        case .starting: return .orange
        case .healthy: return .green
        case .unhealthy: return .red
        }
    }

    var body: some View {
        Text(health.displayText)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor.opacity(0.15))
            .cornerRadius(4)
    }
}
