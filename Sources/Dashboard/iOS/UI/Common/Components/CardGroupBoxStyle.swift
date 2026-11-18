import SwiftUI

struct CardGroupBoxStyle: GroupBoxStyle {
    var expandsToRowHeight = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: MonitoringSpacing.standard) {
            configuration.label
            configuration.content
        }
        .frame(maxHeight: expandsToRowHeight ? .infinity : nil, alignment: .top)
        .monitoringCard()
    }
}
