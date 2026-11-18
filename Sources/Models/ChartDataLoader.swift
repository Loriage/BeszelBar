import Foundation

enum ChartDataLoader {
    /// Previous data must belong to the same hub, system, range and connection revision.
    static func load(service: any BeszelServing, systemID: String, range: HistoryRange, now: Date,
                     previous: ChartDataSet? = nil) async throws -> ChartDataSet {
        async let containerResult = containers(service: service, systemID: systemID, range: range, now: now)
        let records = try await service.fetchDetailedHistory(systemID: systemID, range: range, now: now)
        try Task.checkCancellation()
        var pools: [ZFSPoolRecord] = []
        var notices: [String] = []
        if records.contains(where: { !($0.stats.zfsPools ?? [:]).isEmpty }) {
            do { pools = try await service.fetchZFSPools(systemID: systemID) }
            catch {
                try Task.checkCancellation()
                pools = previous?.pools ?? []
                notices.append("ZFS details: \(error.localizedDescription)")
            }
        }
        let (containerRecords, error) = await containerResult
        try Task.checkCancellation()
        if let error { notices.append("Container history: \(error)") }
        let retainedContainers = error == nil ? containerRecords : (previous?.containerRecords ?? [])
        return ChartDataSet(records: records, containerRecords: retainedContainers, pools: pools, notices: notices)
    }

    private static func containers(service: any BeszelServing, systemID: String, range: HistoryRange, now: Date) async -> ([DetailedContainerRecord], String?) {
        do { return (try await service.fetchContainerHistory(systemID: systemID, range: range, now: now), nil) }
        catch { return ([], error.localizedDescription) }
    }
}
