import SwiftUI

struct IOSChartCard: View {
    let descriptor: ChartDescriptor
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    var opensDetails = true
    var body: some View {
        Group {
        switch descriptor.kind {
        case .metric(let item):
            switch descriptor.category {
            case .cpu, .memory: CPUAndMemoryChartCard(item: item, data: data, scope: scope, range: range)
            case .storage: DiskChartCard(item: item, data: data, scope: scope, range: range)
            case .network: NetworkChartCard(item: item, data: data, scope: scope, range: range)
            case .sensors: SensorChartCard(item: item, data: data, scope: scope, range: range)
            case .containers: ContainerChartCard(item: item, data: data, scope: scope, range: range, opensDetails: opensDetails)
            default: EmptyView()
            }
        case .core(let index): SingleCPUCoreChart(index: index, dataPoints: data.points, xAxisFormat: range.xAxisFormat)
        case .poolUsage(let name):
            StorageHistoryChart(metric: .poolUsage(name), dataPoints: data.points, xAxisFormat: range.xAxisFormat, contextName: name)
        case .poolIO(let name):
            StorageHistoryChart(metric: .poolIO(name), dataPoints: data.points, xAxisFormat: range.xAxisFormat, contextName: name)
        case .cumulativeRead(let disk):
            StorageHistoryChart(metric: .cumulativeRead(disk: disk), dataPoints: data.points, xAxisFormat: range.xAxisFormat, contextName: disk)
        case .cumulativeWrite(let disk):
            StorageHistoryChart(metric: .cumulativeWrite(disk: disk), dataPoints: data.points, xAxisFormat: range.xAxisFormat, contextName: disk)
        }
        }
        .compactChartAccessibilityForTesting()
    }

}

private struct CPUAndMemoryChartCard: View {
    let item: PinnedItem
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    @Environment(ChartPins.self) private var pins
    private var isPinned: Bool { pins.isPinned(item, onSystem: scope) }
    private func togglePin() { pins.togglePin(for: item, onSystem: scope) }
    var body: some View {
        switch item {
        case .systemCPUTimeBreakdown: SystemCpuTimeBreakdownChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemCPUCores: SystemCpuCoresChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemLoadAverage: SystemLoadChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemSwap: SystemSwapChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemCPU: SystemMetricChartView(title: "chart.cpuUsage", xAxisFormat: range.xAxisFormat, dataPoints: data.points, valueKeyPath: \.cpu, color: .blue, subtitle: "chart.cpuUsage.subtitle", unit: "%", isPinned: isPinned, onPinToggle: togglePin)
        case .systemMemory: SystemMetricChartView(title: "chart.memoryUsage", xAxisFormat: range.xAxisFormat, dataPoints: data.points, valueKeyPath: \.memoryPercent, color: .green, subtitle: "chart.memoryUsage.subtitle", unit: "%", isPinned: isPinned, onPinToggle: togglePin)
        default: EmptyView()
        }
    }
}

private struct DiskChartCard: View {
    let item: PinnedItem
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    @Environment(ChartPins.self) private var pins
    private var isPinned: Bool { pins.isPinned(item, onSystem: scope) }
    private func togglePin() { pins.togglePin(for: item, onSystem: scope) }
    var body: some View {
        switch item {
        case .systemDiskIO: SystemDiskIOChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemDiskUsage: SystemDiskUsageChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemDiskIOUtilization: SystemDiskIOUtilizationChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemDiskIOTimes: SystemDiskIOTimesChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemDiskAwait: SystemDiskAwaitChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemDiskIOQueueDepth: SystemDiskIOQueueDepthChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskUsage(let name): ExtraDiskUsageChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskIO(let name): ExtraDiskIOChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskIOUtilization(let name): ExtraDiskIOUtilizationChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskIOTimes(let name): ExtraDiskIOTimesChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskAwait(let name): ExtraDiskAwaitChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .extraDiskIOQueueDepth(let name): ExtraDiskIOQueueDepthChartView(diskName: name, dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        default: EmptyView()
        }
    }
}

private struct NetworkChartCard: View {
    let item: PinnedItem
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    @Environment(ChartPins.self) private var pins
    private var isPinned: Bool { pins.isPinned(item, onSystem: scope) }
    private func togglePin() { pins.togglePin(for: item, onSystem: scope) }
    var body: some View {
        switch item {
        case .systemBandwidth: SystemBandwidthChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemNetworkInterfaces: SystemNetworkInterfacesChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemBandwidthDownload: BandwidthDownloadChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemBandwidthUpload: BandwidthUploadChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemBandwidthCumulativeDownload: BandwidthCumulativeDownloadChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemBandwidthCumulativeUpload: BandwidthCumulativeUploadChartView(dataPoints: data.points, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        default: EmptyView()
        }
    }
}

private struct SensorChartCard: View {
    let item: PinnedItem
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    @Environment(ChartPins.self) private var pins
    private var isPinned: Bool { pins.isPinned(item, onSystem: scope) }
    private func togglePin() { pins.togglePin(for: item, onSystem: scope) }
    var body: some View {
        switch item {
        case .systemTemperature: SystemTemperatureChartView(xAxisFormat: range.xAxisFormat, dataPoints: data.points, isPinned: isPinned, onPinToggle: togglePin)
        case .systemBattery: SensorHistoryChart(history: data.sensors.battery, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemFans: SensorHistoryChart(history: data.sensors.fans, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemGPU: SystemGPUChartView(history: data.gpu.usage, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .systemGPUPower: SystemGPUChartView(history: data.gpu.power, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
        case .gpuMemory(let id):
            if let chart = data.gpu.memory.first(where: { $0.device?.id == id }) {
                SystemGPUChartView(history: chart, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
            }
        case .gpuEngines(let id):
            if let chart = data.gpu.engines.first(where: { $0.device?.id == id }) {
                SystemGPUChartView(history: chart, xAxisFormat: range.xAxisFormat, isPinned: isPinned, onPinToggle: togglePin)
            }
        default: EmptyView()
        }
    }
}

private struct ContainerChartCard: View {
    let item: PinnedItem
    let data: ChartDataSet
    let scope: String
    let range: HistoryRange
    var opensDetails = true
    @Environment(ChartPins.self) private var pins
    private var isPinned: Bool { pins.isPinned(item, onSystem: scope) }
    private func togglePin() { pins.togglePin(for: item, onSystem: scope) }
    var body: some View {
        switch item {
        case .stackedContainerCPU:
            StackedCpuChartView(stackedData: data.cpu, domain: data.cpuDomain, opensDetails: opensDetails, systemID: scope)
        case .stackedContainerMemory:
            StackedMemoryChartView(stackedData: data.memory, domain: data.memoryDomain, opensDetails: opensDetails, systemID: scope)
        case .stackedContainerNetwork:
            StackedNetworkChartView(stackedData: data.network, domain: data.networkDomain, opensDetails: opensDetails, systemID: scope)
        case .containerCPU(let name):
            if let container = data.containers.first(where: { $0.name == name }) {
                ContainerMetricChartView(titleKey: "chart.cpuUsage", containerName: name, xAxisFormat: range.xAxisFormat,
                    container: container, valueKeyPath: \.cpu, color: .blue, subtitleKey: "chart.container.cpuUsage.subtitle",
                    isPinned: isPinned, onPinToggle: togglePin, yAxisUnit: "%")
            }
        case .containerMemory(let name):
            if let container = data.containers.first(where: { $0.name == name }) {
                ContainerMetricChartView(titleKey: "chart.memoryUsage", containerName: name, xAxisFormat: range.xAxisFormat,
                    container: container, valueKeyPath: \.memory, color: .green, subtitleKey: "chart.container.memoryUsage.subtitle",
                    isPinned: isPinned, onPinToggle: togglePin, yAxisUnit: "MB")
            }
        default: EmptyView()
        }
    }
}

extension View {
    @ViewBuilder
    func compactChartAccessibilityForTesting() -> some View {
        #if DEBUG
        if DevelopmentSession.isEnabled {
            // The Mac automation service crashes while expanding Swift Charts'
            // native AX tree. Keep the real rendering and pointer interactions,
            // but expose one AX element per chart in isolated demo sessions.
            self.accessibilityElement(children: .ignore).accessibilityLabel("Chart")
        } else {
            self
        }
        #else
        self
        #endif
    }
}
