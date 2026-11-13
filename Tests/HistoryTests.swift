import XCTest

final class HistoryTests: XCTestCase {
    func testHistoryPreservesZeroAndSeparatesMissingDataAndOutages() throws {
        let records: [SystemStatsRecord] = try fixture(#"""
        [
          {"id":"1","created":"2026-09-15 12:00:00.000Z","stats":{"cpu":0}},
          {"id":"2","created":"2026-09-15T12:01:00Z","stats":{"cpu":25}},
          {"id":"3","created":"2026-09-15 12:02:00.000Z","stats":{}},
          {"id":"4","created":"2026-09-15 12:03:00.000Z","stats":{"cpu":30}},
          {"id":"5","created":"2026-09-15 12:10:00.000Z","stats":{"cpu":40}}
        ]
        """#)
        let points = HistorySeries.points(from: records, metric: .cpu, range: .hour)
        XCTAssertEqual(points.map(\.value), [0, 25, 30, 40])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2])
    }

    func testBandwidthSupportsLegacyMegabytesAndNewByteArrays() throws {
        let current: SystemStatsDetail = try fixture(#"{"b":[1048576,2097152]}"#)
        let legacy: SystemStatsDetail = try fixture(#"{"ns":1,"nr":2}"#)
        XCTAssertEqual(HistoryMetric.upload.value(in: current), 1)
        XCTAssertEqual(HistoryMetric.download.value(in: current), 2)
        XCTAssertEqual(HistoryMetric.upload.value(in: legacy), 1)
        XCTAssertEqual(HistoryMetric.download.value(in: legacy), 2)
    }
}
