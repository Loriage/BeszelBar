import SwiftUI
import Charts

struct StackedCpuChartView: View {
    let stackedData: [StackedCpuData]
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

    var body: some View {
        if opensDetails {
        NavigationLink(destination: DetailedCpuChartView(
            stackedData: stackedData,
            domain: domain,
            uniqueDates: uniqueDates,
            xAxisFormat: settingsManager.selectedTimeRange.xAxisFormat,
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
                    (Text("charts.stacked_cpu.title") + Text(" (%)"))
                        .font(IOSFont.headline)
                    if systemName == nil {
                        Text("charts.stacked_cpu.subtitle")
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
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(String(format: "%.0f", v)).font(IOSFont.caption2).padding(.trailing, 6)
                                }
                            }
                        }
                    }
                    .padding(.top, 5)
                }
                .commonChartCustomization(xAxisFormat: settingsManager.selectedTimeRange.xAxisFormat, xDomain: chartXDomain)
            }
    }
}
