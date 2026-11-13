import SwiftUI

struct PinButtonView: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isPinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin")))
        .help(Text(isPinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin")))
    }
}
