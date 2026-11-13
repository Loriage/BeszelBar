import XCTest

final class ChartParityTests: XCTestCase {
    func testAdvancedMeasurementsReachTheIOSChartModels() throws {
        let data = try ChartFixtures.data()
        let point = try XCTUnwrap(data.points.last)
        XCTAssertEqual(point.cpuPerCore?.count, 2)
        XCTAssertEqual(point.cpuBreakdown?.count, 5)
        XCTAssertEqual(point.diskIOStats?.rAwait, 1.5)
        XCTAssertEqual(point.diskIOTotals?.read, 129e9)
        XCTAssertEqual(point.extraFilesystems.first?.totalWrite, 109e9)
        XCTAssertEqual(point.zfsPools["tank"]?.h, "ONLINE")
        XCTAssertEqual(point.networkInterfaces.first?.totalReceived, 109e9)
        XCTAssertEqual(data.gpu.memory.first?.device?.id, "gpu0")
        XCTAssertEqual(data.sensors.fans.series.count, 1)
        XCTAssertEqual(data.sensors.battery.currentValue, 74.5)
    }

    func testCatalogIncludesEveryIOSChartFamily() throws {
        let cards = ChartCatalog.cards(in: try ChartFixtures.data())
        let kinds = Set(cards.map(\.kind))
        let expected: Set<ChartKind> = [
            .metric(.systemCPUTimeBreakdown), .metric(.systemCPUCores), .core(1),
            .metric(.systemMemory), .metric(.systemSwap), .metric(.systemLoadAverage),
            .metric(.systemDiskIOUtilization), .metric(.systemDiskIOTimes), .metric(.systemDiskAwait),
            .metric(.systemDiskIOQueueDepth), .metric(.systemDiskUsage), .cumulativeRead(nil), .cumulativeWrite(nil),
            .metric(.systemBandwidthDownload), .metric(.systemBandwidthUpload),
            .metric(.systemBandwidthCumulativeDownload), .metric(.systemBandwidthCumulativeUpload),
            .metric(.systemNetworkInterfaces), .metric(.systemTemperature), .metric(.systemBattery), .metric(.systemFans),
            .metric(.systemGPU), .metric(.systemGPUPower), .metric(.gpuMemory(id: "gpu0")), .metric(.gpuEngines(id: "gpu0")),
            .metric(.extraDiskIO(name: "/data")), .metric(.extraDiskAwait(name: "/data")),
            .cumulativeRead("/data"), .cumulativeWrite("/data"), .poolUsage("tank"), .poolIO("tank"),
            .metric(.stackedContainerCPU), .metric(.stackedContainerMemory), .metric(.stackedContainerNetwork),
            .metric(.containerCPU(name: "web")), .metric(.containerMemory(name: "database"))
        ]
        XCTAssertTrue(expected.isSubset(of: kinds), "Missing: \(expected.subtracting(kinds))")
        XCTAssertEqual(kinds.count, cards.count, "Chart identities must remain unique")
    }

    func testAbsentHardwareDoesNotProduceInventedCharts() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(DetailedSystemRecord.self, from: Data(#"{"id":"old-hub","created":0,"type":"1m","stats":{"cpu":0,"mu":0,"mp":0,"du":0,"dp":0}}"#.utf8))
        let data = ChartDataSet(records: [record])
        XCTAssertEqual(Set(ChartCatalog.cards(in: data).map(\.kind)), [.metric(.systemCPU), .metric(.systemMemory)])
        XCTAssertEqual(data.points.first?.cpu, 0)
        XCTAssertFalse(data.gpu.usage.hasReadings)
        XCTAssertTrue(data.sensors.battery.series.isEmpty)
    }

    func testContainerStackTotalsAndZeroValuesMatchSourceSamples() throws {
        let data = try ChartFixtures.data()
        let date = try XCTUnwrap(data.containers.first?.statPoints.last?.date)
        let expectedCPU = data.containers.compactMap { $0.statPoints.last?.cpu }.reduce(0, +)
        let expectedMemory = data.containers.compactMap { $0.statPoints.last?.memory }.reduce(0, +)
        XCTAssertEqual(try XCTUnwrap(data.cpu.last { $0.date == date }?.yEnd), expectedCPU, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(data.memory.last { $0.date == date }?.yEnd), expectedMemory, accuracy: 0.0001)
        XCTAssertEqual(Set(data.cpu.map(\.name)), Set(data.memory.map(\.name)))
        XCTAssertEqual(Set(data.network.map(\.name)), Set(data.networkDomain))
    }

    func testStacksRankEachMetricByAverageUsageLikeIOS() {
        let start = Date(timeIntervalSince1970: 0)
        let records = [0, 1].map { index in
            DetailedContainerRecord(id: "\(index)", collectionId: "stats", collectionName: "container_stats",
                created: start.addingTimeInterval(Double(index) * 60), updated: start,
                system: "server", type: "1m", stats: [
                    ContainerStat(name: "alpha", cpu: index == 0 ? 100 : 0, memory: 10, netSent: 5, netReceived: 5),
                    ContainerStat(name: "beta", cpu: 20, memory: 30, netSent: 0, netReceived: 1),
                    ContainerStat(name: "gamma", cpu: 1, memory: 20, netSent: 3, netReceived: 0)
                ])
        }
        let data = ChartDataSet(containerRecords: records)
        XCTAssertEqual(data.cpuDomain, ["gamma", "beta", "alpha"])
        XCTAssertEqual(data.memoryDomain, ["alpha", "gamma", "beta"])
        XCTAssertEqual(data.networkDomain, ["beta", "gamma", "alpha"])
        XCTAssertEqual(data.cpu.filter { $0.date == start }.map(\.name), data.cpuDomain)
        XCTAssertEqual(data.memory.filter { $0.date == start }.map(\.name), data.memoryDomain)
        XCTAssertEqual(data.network.filter { $0.date == start }.map(\.name), data.networkDomain)
        XCTAssertEqual(data.cpu.last?.name, "alpha", "Rank by the period average, not the latest sample")
        XCTAssertEqual(data.cpu.first?.yStart, 0)
        XCTAssertEqual(data.cpu.first { $0.name == "alpha" }?.yStart, 21)
        XCTAssertEqual(data.cpu.first { $0.name == "alpha" }?.yEnd, 121)
    }
}
