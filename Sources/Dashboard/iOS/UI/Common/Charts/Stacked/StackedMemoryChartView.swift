import SwiftUI
import Charts

struct StackedMemoryChartView: View {
    let stackedData: [StackedMemoryData]
    let domain: [String]

    @Environment(ChartSettings.self) var settingsManager
    @Environment(\.chartXDomain) private var chartXDomain
    @Environment(\.chartShowXGridLines) private var chartShowXGridLines

    var opensDetails = true
    let systemID: String?
    var systemName: String? = nil

    private var uniqueDates: [Date] {
        Array(Set(stackedData.map { $0.date })).sorted()
    }

    private var maxMemory: Double {
        stackedData.max(by: { $0.yEnd < $1.yEnd })?.yEnd ?? 0
    }

    var memoryUnit: String {
        maxMemory >= 1024 ? "GB" : "MB"
    }

    var memoryLabelScale: Double {
        maxMemory >= 1024 ? 1024 : 1
    }

    private var xAxisFormat: Date.FormatStyle {
        settingsManager.selectedTimeRange.xAxisFormat
    }

    var body: some View {
        if opensDetails {
        NavigationLink(destination: DetailedMemoryChartView(
            stackedData: stackedData,
            domain: domain,
            uniqueDates: uniqueDates,
            memoryUnit: memoryUnit,
            memoryLabelScale: memoryLabelScale,
            xAxisFormat: xAxisFormat,
            systemID: systemID,
            settingsManager: settingsManager,
            xDomain: chartXDomain
        )
        .environment(\.chartShowXGridLines, chartShowXGridLines)
        ) {
            chartCard
        }
        .buttonStyle(PlainButtonStyle())
        } else {
            chartCard
        }
    }

    private var chartCard: some View {
            GroupBox(label: HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("charts.stacked_memory.title \(memoryUnit)")
                        .font(IOSFont.headline)
                    if systemName == nil {
                        Text("charts.stacked_memory.subtitle")
                            .font(IOSFont.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let systemName = systemName {
                        Text(systemName)
                            .font(IOSFont.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(IOSFont.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }) {
                ZStack {
                    Chart(stackedData) { data in
                        AreaMark(
                            x: .value("Date", data.date),
                            yStart: .value("Start", data.yStart),
                            yEnd: .value("End", data.yEnd),
                        )
                        .foregroundStyle(by: .value("Conteneur", data.name))
                        .interpolationMethod(.monotone)
                    }
                    .chartForegroundStyleScale(domain: domain, range: gradientRange(for: domain))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            if let yValue = value.as(Double.self) {
                                let scaledValue = yValue / memoryLabelScale
                                let s = scaledValue == 0 ? "0"
                                    : scaledValue.truncatingRemainder(dividingBy: 1) == 0
                                        ? String(format: "%.0f", scaledValue)
                                        : String(format: "%.1f", scaledValue)
                                AxisGridLine()
                                AxisValueLabel {
                                    Text(s).font(IOSFont.caption2).padding(.trailing, 6)
                                }
                            }
                        }
                    }
                    .padding(.top, 5)
                }
                .commonChartCustomization(xAxisFormat: xAxisFormat, xDomain: chartXDomain)
            }
    }
}
