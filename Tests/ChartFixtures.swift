import Foundation

enum ChartFixtures {
    static func data(now: Date = Date()) throws -> ChartDataSet {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var systemRecords: [DetailedSystemRecord] = []
        var containerRecords: [DetailedContainerRecord] = []
        for index in 0..<30 {
            let date = now.addingTimeInterval(Double(index - 30) * 120).timeIntervalSince1970
            let wave = sin(Double(index) / 3) * 10 + 25
            let stats: [String: Any] = [
                "cpu": wave, "cpub": [wave * 0.6, wave * 0.3, 2, 0, 98 - wave * 0.9],
                "cpus": [wave, wave + 10], "la": [1.2, 1.8, 1.5],
                "m": 16, "mu": 8 + wave / 20, "mp": 50 + wave / 3,
                "s": 4, "su": wave / 30, "d": 512, "du": 120 + wave, "dp": 30,
                "dio": [wave * 100_000, wave * 40_000], "dios": [8, 6, wave, 1.5, 2.5, 45],
                "diot": [Double(index + 100) * 1e9, Double(index + 50) * 1e9],
                "b": [wave * 20_000, wave * 70_000],
                "ni": ["eth0": [wave * 20_000, wave * 70_000, Double(index + 40) * 1e9, Double(index + 80) * 1e9]],
                "t": ["CPU": 45 + wave / 3, "NVMe": 38 + wave / 5],
                "bat": [80, 1], "bats": ["Internal": 60 + Double(index) / 2], "f": ["CPU Fan": 1200 + wave * 20],
                "g": ["gpu0": ["n": "Sample GPU", "u": wave, "mu": 1500 + wave * 10, "mt": 8192,
                                 "p": wave * 2, "pp": 25, "e": ["Render": wave, "Video": wave / 2]]],
                "efs": ["/data": ["d": 1024, "du": 300 + wave, "rb": wave * 1e5, "wb": wave * 2e5,
                                   "dios": [12, 8, wave, 1, 2, 40], "tr": Double(index + 50) * 1e9, "tw": Double(index + 80) * 1e9]],
                "z": ["tank": ["d": 2048, "du": 800 + wave, "rb": wave * 1e5, "wb": wave * 2e5, "h": "ONLINE"]]
            ]
            let record: [String: Any] = ["id": "sample\(index)", "created": date, "type": "1m", "stats": stats]
            systemRecords.append(try decoder.decode(DetailedSystemRecord.self, from: JSONSerialization.data(withJSONObject: record)))
            let containers: [String: Any] = ["id": "containers\(index)", "collectionId": "samples", "collectionName": "container_stats",
                "created": date, "updated": date, "system": "sample-system", "type": "1m",
                "stats": [["n": "database", "c": wave / 3, "m": 300 + wave, "ns": wave * 0.001, "nr": wave * 0.002],
                          ["n": "web", "c": wave / 2, "m": 100 + wave, "ns": wave * 0.002, "nr": wave * 0.003]]]
            containerRecords.append(try decoder.decode(DetailedContainerRecord.self, from: JSONSerialization.data(withJSONObject: containers)))
        }
        return ChartDataSet(records: systemRecords, containerRecords: containerRecords)
    }
}
