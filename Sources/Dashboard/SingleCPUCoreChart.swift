import SwiftUI
import Charts

private struct CoreSample: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// Identical to the per-core card in Beszel iOS's CPU details screen.
struct SingleCPUCoreChart: View {
    let index: Int
    let dataPoints: [SystemDataPoint]
    let xAxisFormat: Date.FormatStyle
    @Environment(\.chartXDomain) private var xDomain
    @Environment(\.chartShowXGridLines) private var chartShowXGridLines
    var name: String { "CPU \(index)" }
    var body: some View {
        let names = (0..<(dataPoints.compactMap { $0.cpuPerCore?.count }.max() ?? 0)).map { "CPU \($0)" }
        let coreColor = color(for: name, in: names)
        let samples: [CoreSample] = dataPoints.compactMap { point in
            guard let cores = point.cpuPerCore, index < cores.count else { return nil }
            return CoreSample(date: point.date, value: cores[index])
        }
        let maxVal = samples.map(\.value).max() ?? 0
        let (niceDomainMax, _) = niceYDomain(maxVal: maxVal > 0 ? maxVal : 100)
        let domainMax = min(niceDomainMax, 100.0)

        return GroupBox(label: HStack {
            VStack(alignment: .leading, spacing: 2) {
                (Text(name) + Text(" (%)"))
                    .font(IOSFont.headline)
                Text("chart.cpu.cores.subtitle")
                    .font(IOSFont.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }) {
            Chart(samples) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("CPU", sample.value),
                )
                .foregroundStyle(coreColor)
                AreaMark(
                    x: .value("Date", sample.date),
                    yStart: .value("", 0),
                    yEnd: .value("CPU", sample.value),
                )
                .foregroundStyle(LinearGradient(
                    colors: [coreColor.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .chartYScale(domain: 0...domainMax)
            .chartXAxis {
                AxisMarks(values: insetTickDates(for: xDomain)) { _ in
                    if chartShowXGridLines {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        AxisTick()
                    }
                    AxisValueLabel(format: xAxisFormat, collisionResolution: .disabled)
                        .font(IOSFont.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(adaptiveAxisLabel(v, domainMax: domainMax)).font(IOSFont.caption2).padding(.trailing, 6)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXScaleIfNeeded(xDomain)
            .padding(.top, 5)
            .frame(height: 200)
            .drawingGroup()
        }
    }
}
