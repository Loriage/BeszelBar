import Foundation

/// Prepares the iOS chart input once per response, not during SwiftUI rendering.
struct ChartDataSet {
    var records: [DetailedSystemRecord] = []
    var points: [SystemDataPoint] = []
    var containers: [ProcessedContainerData] = []
    var cpu: [StackedCpuData] = []
    var memory: [StackedMemoryData] = []
    var network: [StackedNetworkData] = []
    var cpuDomain: [String] = []
    var memoryDomain: [String] = []
    var networkDomain: [String] = []
    var hasContainerNetwork = false
    var gpu = SystemGPUCharts.empty
    var sensors = SystemSensorCharts.empty
    var pools: [ZFSPoolRecord] = []
    var notices: [String] = []

    init(records: [DetailedSystemRecord] = [], containerRecords: [DetailedContainerRecord] = [],
         pools: [ZFSPoolRecord] = [], notices: [String] = []) {
        self.records = records.sorted { $0.created < $1.created }
        points = records.asDataPoints()
        containers = containerRecords.asProcessedData().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.pools = pools
        self.notices = notices
        gpu = SystemGPUCharts(dataPoints: points)
        sensors = SystemSensorCharts(dataPoints: points)
        hasContainerNetwork = containerRecords.contains { $0.stats.contains { $0.netSent != nil || $0.netReceived != nil } }
        // Match iOS: each metric stacks from lowest to highest average usage.
        // The palette follows that order, placing the largest consumer in red on top.
        cpuDomain = Self.domain(containers, value: { $0.cpu })
        memoryDomain = Self.domain(containers, value: { $0.memory })
        networkDomain = Self.domain(containers, value: { $0.netSent + $0.netReceived })
        let samples = Dictionary(grouping: containerRecords, by: \.created)
        for date in samples.keys.sorted() {
            guard let record = samples[date]?.last else { continue }
            let byName = Dictionary(record.stats.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
            var cpuTotal = 0.0, memoryTotal = 0.0, networkTotal = 0.0
            for name in cpuDomain {
                // A record contains the complete set of containers at that time.
                // Missing containers are stopped/absent; don't carry stale usage forward.
                let stat = byName[name]
                let c = max(0, stat?.cpu ?? 0)
                cpu.append(StackedCpuData(date: date, name: name, yStart: cpuTotal, yEnd: cpuTotal + c))
                cpuTotal += c
            }
            for name in memoryDomain {
                let m = max(0, byName[name]?.memory ?? 0)
                memory.append(StackedMemoryData(date: date, name: name, yStart: memoryTotal, yEnd: memoryTotal + m))
                memoryTotal += m
            }
            for name in networkDomain {
                let stat = byName[name]
                let sent = max(0, stat?.netSent ?? 0), received = max(0, stat?.netReceived ?? 0)
                network.append(StackedNetworkData(date: date, name: name, yStart: networkTotal,
                                                  yEnd: networkTotal + sent + received, netSent: sent, netReceived: received))
                networkTotal += sent + received
            }
        }
    }

    private static func domain(_ containers: [ProcessedContainerData], value: (StatPoint) -> Double) -> [String] {
        let averages: [(name: String, average: Double)] = containers.map { container in
            let points = container.statPoints
            let total = points.reduce(0.0) { $0 + value($1) }
            let average = points.isEmpty ? 0 : total / Double(points.count)
            return (name: container.name, average: average)
        }
        return averages.sorted {
            // Resolve equal averages deterministically across reloads.
            $0.average == $1.average ? $0.name < $1.name : $0.average < $1.average
        }.map(\.name)
    }
}
