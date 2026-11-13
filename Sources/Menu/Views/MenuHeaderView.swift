import SwiftUI

struct MenuHeaderView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BeszelBar")
                        .font(.system(size: 13, weight: .semibold))
                    if appState.isShowingMultipleHubs {
                        Text("All Hubs")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let selected = appState.visibleHubs.first {
                        Text(selected.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                let systems = appState.visibleSystems
                if !systems.isEmpty {
                    let online = systems.filter { $0.isOnline }.count
                    let offline = systems.count - online

                    HStack(spacing: 6) {
                        StatusBubble(count: online, color: .green, icon: "checkmark.circle.fill")
                        if offline > 0 {
                            StatusBubble(count: offline, color: .red, icon: "xmark.circle.fill")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
        }
        .frame(width: 300, height: 46)
    }
}

struct StatusBubble: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
