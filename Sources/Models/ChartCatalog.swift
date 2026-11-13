import Foundation

enum ChartCategory: String, CaseIterable, Identifiable {
    case all = "All Charts", pinned = "Pinned", cpu = "CPU", memory = "Memory"
    case storage = "Storage", network = "Network", sensors = "Sensors & GPU", containers = "Containers"
    var id: Self { self }
}

enum ChartKind: Hashable {
    case metric(PinnedItem), core(Int), poolUsage(String), poolIO(String)
    case cumulativeRead(String?), cumulativeWrite(String?)
}

struct ChartDescriptor: Identifiable {
    let kind: ChartKind
    let category: ChartCategory
    var id: ChartKind { kind }
    var pin: PinnedItem? { if case .metric(let item) = kind { item } else { nil } }
    var containerName: String? {
        switch pin {
        case .containerCPU(let name), .containerMemory(let name): name
        default: nil
        }
    }
}

enum ChartCatalog {
    static func cards(in data: ChartDataSet) -> [ChartDescriptor] {
        let p = data.points
        guard !p.isEmpty else { return [] }
        var cards: [ChartDescriptor] = []
        func add(_ item: PinnedItem, _ category: ChartCategory, when available: Bool = true) {
            if available { cards.append(ChartDescriptor(kind: .metric(item), category: category)) }
        }
        add(.systemCPU, .cpu)
        add(.systemMemory, .memory)
        add(.systemDiskIO, .storage, when: p.contains { $0.diskIO != nil })
        add(.systemDiskUsage, .storage, when: p.contains { $0.diskUsage != nil })
        add(.systemBandwidth, .network, when: p.contains { $0.bandwidth != nil })
        add(.systemLoadAverage, .cpu, when: p.contains { $0.loadAverage != nil })
        add(.systemTemperature, .sensors, when: p.contains { !$0.temperatures.isEmpty })
        add(.systemBattery, .sensors, when: !data.sensors.battery.series.isEmpty)
        add(.systemFans, .sensors, when: !data.sensors.fans.series.isEmpty)
        add(.systemSwap, .memory, when: p.contains { $0.swap != nil })
        add(.systemGPU, .sensors, when: data.gpu.usage.hasReadings)
        add(.systemGPUPower, .sensors, when: data.gpu.power.hasReadings)
        for chart in data.gpu.memory { if let id = chart.device?.id { add(.gpuMemory(id: id), .sensors) } }
        for chart in data.gpu.engines { if let id = chart.device?.id { add(.gpuEngines(id: id), .sensors) } }
        add(.systemCPUTimeBreakdown, .cpu, when: p.contains { !($0.cpuBreakdown ?? []).isEmpty })
        add(.systemCPUCores, .cpu, when: p.contains { !($0.cpuPerCore ?? []).isEmpty })
        for core in 0..<(p.compactMap { $0.cpuPerCore?.count }.max() ?? 0) {
            cards.append(ChartDescriptor(kind: .core(core), category: .cpu))
        }
        for item: PinnedItem in [.systemDiskIOUtilization, .systemDiskIOTimes, .systemDiskAwait, .systemDiskIOQueueDepth] {
            add(item, .storage, when: p.contains { $0.diskIOStats != nil })
        }
        if p.contains(where: { $0.diskIOTotals != nil }) {
            cards += [.init(kind: .cumulativeRead(nil), category: .storage), .init(kind: .cumulativeWrite(nil), category: .storage)]
        }
        for item: PinnedItem in [.systemNetworkInterfaces, .systemBandwidthDownload, .systemBandwidthUpload] {
            add(item, .network, when: p.contains { !$0.networkInterfaces.isEmpty })
        }
        add(.systemBandwidthCumulativeDownload, .network, when: p.contains { $0.networkInterfaces.contains { $0.totalReceived != nil } })
        add(.systemBandwidthCumulativeUpload, .network, when: p.contains { $0.networkInterfaces.contains { $0.totalSent != nil } })
        for disk in Set(p.flatMap { $0.extraFilesystems.map(\.name) }).sorted() {
            let samples = p.flatMap { $0.extraFilesystems.filter { $0.name == disk } }
            add(.extraDiskUsage(name: disk), .storage)
            add(.extraDiskIO(name: disk), .storage, when: samples.contains { $0.diskRead != nil || $0.diskWrite != nil })
            for item: PinnedItem in [.extraDiskIOUtilization(name: disk), .extraDiskIOTimes(name: disk), .extraDiskAwait(name: disk), .extraDiskIOQueueDepth(name: disk)] {
                add(item, .storage, when: samples.contains { $0.diskIOStats != nil })
            }
            if samples.contains(where: { $0.totalRead != nil }) { cards.append(.init(kind: .cumulativeRead(disk), category: .storage)) }
            if samples.contains(where: { $0.totalWrite != nil }) { cards.append(.init(kind: .cumulativeWrite(disk), category: .storage)) }
        }
        for pool in Set(p.flatMap { $0.zfsPools.keys }).sorted() {
            cards += [.init(kind: .poolUsage(pool), category: .storage), .init(kind: .poolIO(pool), category: .storage)]
        }
        if !data.containers.isEmpty {
            add(.stackedContainerCPU, .containers)
            add(.stackedContainerMemory, .containers)
            add(.stackedContainerNetwork, .containers, when: data.hasContainerNetwork)
            for container in data.containers {
                add(.containerCPU(name: container.name), .containers)
                add(.containerMemory(name: container.name), .containers)
            }
        }
        return cards
    }
}
