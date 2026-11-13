import XCTest
import SwiftUI
import AppKit

/// Native SwiftUI renders, explicitly distinct from screenshots of an app window.
@MainActor
final class ChartRenderTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testPinsPersistAndRemainIsolatedAcrossHubs() throws {
        let suite = "com.nohitdev.BeszelBar.pin-isolation-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = HubRecordID(hubID: UUID(), recordID: "same-system").chartScope
        let second = HubRecordID(hubID: UUID(), recordID: "same-system").chartScope
        let pins = ChartPins(defaults: defaults)
        pins.togglePin(for: .systemCPU, onSystem: first)
        let restored = ChartPins(defaults: defaults)
        XCTAssertTrue(restored.isPinned(.systemCPU, onSystem: first))
        XCTAssertFalse(restored.isPinned(.systemCPU, onSystem: second))
        restored.togglePin(for: .systemCPU, onSystem: first)
        XCTAssertFalse(ChartPins(defaults: defaults).isPinned(.systemCPU, onSystem: first))
    }

    func testNativeSystemCardsInBothAppearances() throws {
        let system = try JSONDecoder().decode(SystemRecord.self, from: Data(#"{"id":"sample","name":"Demo Server","status":"up","info":{"m":"Apple M4 Pro","c":12,"u":120000,"cpu":26,"mp":72,"dp":94,"la":[1.2,1.6,1.4],"bb":2300000}}"#.utf8))
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 16) {
                Text("Carte serveur · données simulées · rendu natif SwiftUI").font(.system(size: 18, weight: .semibold))
                SystemSummaryCard(details: nil, hubName: "Demo Hub", system: system, systemInfo: system.info,
                                  stats: nil, systemName: system.name, status: system.status)
            }
            .padding(24).frame(width: 620)
            .background(scheme == .dark ? Color.black : Color(red: 242/255, green: 242/255, blue: 247/255))
            .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "fr"))
            .groupBoxStyle(CardGroupBoxStyle())
            try saveRender(view, file: "system-card-\(scheme == .dark ? "dark" : "light")")
        }
    }

    func testChartLabelsAreLocalizedInTheAppBundle() throws {
        for language in ["en", "fr"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["chart.cpuUsage", "chart.memoryUsage", "charts.stacked_memory.title %@", "charts.stacked_network.title %@"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key)
            }
        }
    }

    func testRenderEveryChartFamilyInLightAndDarkAppearance() throws {
        let now = Date()
        let data = try ChartFixtures.data(now: now)
        let cards = ChartCatalog.cards(in: data)
        XCTAssertGreaterThan(cards.count, 40)
        for scheme in [ColorScheme.light, .dark] {
            for page in stride(from: 0, to: cards.count, by: 4) {
                let batch = Array(cards[page..<min(page + 4, cards.count)])
                try render(data: data, cards: batch, now: now, scheme: scheme,
                           title: "Données simulées · rendu natif SwiftUI · \(page / 4 + 1)",
                           file: "fixture-\(scheme == .dark ? "dark" : "light")-\(String(format: "%02d", page / 4 + 1))")
            }
        }
    }

    /// Opt-in integration against the locally supplied demo account. The ignored
    /// config is never copied into a distributable app or printed in test output.
    func testLiveHubHistoryAndNativeRenders() async throws {
        let configURL = root.appendingPathComponent("build/LiveChartsTestConfig.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { throw XCTSkip("No local live-test configuration") }
        struct Config: Decodable { let hubs: [Hub] }
        struct Hub: Decodable { let name: String; let url: String; let fallbackURL: String?; let email: String; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        let hub = try XCTUnwrap(config.hubs.first)
        let service = BeszelAPIService(instance: Instance(name: hub.name, url: hub.url, email: hub.email,
                                                          credential: hub.password, fallbackURL: hub.fallbackURL ?? ""))
        let systems = try await service.fetchSystems()
        XCTAssertFalse(systems.isEmpty)
        var report: [String] = []
        for (index, system) in systems.enumerated() {
            let now = Date()
            let data = try await ChartDataLoader.load(service: service, systemID: system.id, range: .hour, now: now)
            XCTAssertFalse(data.points.isEmpty, "Expected demo history")
            XCTAssertTrue(data.notices.isEmpty, "Optional history request failed: \(data.notices)")
            let cards = ChartCatalog.cards(in: data)
            report.append("\(system.name): \(data.points.count) samples, \(data.containers.count) containers, \(cards.count) charts")
            for page in stride(from: 0, to: cards.count, by: 4) {
                try render(data: data, cards: Array(cards[page..<min(page + 4, cards.count)]), now: now, scheme: .dark,
                           title: "\(system.name) · données réelles · rendu natif SwiftUI",
                           file: "live-\(index + 1)-\(String(format: "%02d", page / 4 + 1))")
            }
            // Verify the same aggregation types as iOS for every other interval.
            for range in [HistoryRange.halfDay, .day, .week, .month] {
                let records = try await service.fetchDetailedHistory(systemID: system.id, range: range, now: now)
                XCTAssertTrue(records.allSatisfy { $0.type == range.recordType })
                report.append("  \(range.rawValue): \(records.count) samples")
            }
        }
        try report.joined(separator: "\n").write(to: root.appendingPathComponent("build/live-charts-results.txt"), atomically: true, encoding: .utf8)
    }

    private func render(data: ChartDataSet, cards: [ChartDescriptor], now: Date, scheme: ColorScheme,
                        title: String, file: String) throws {
        let suite = "com.nohitdev.BeszelBar.render-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ChartSettings()
        let content = VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 20, weight: .semibold))
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(cards[row..<min(row + 2, cards.count)])) { descriptor in
                        IOSChartCard(descriptor: descriptor, data: data, scope: "render-test", range: .hour, opensDetails: false)
                            .frame(width: 464)
                    }
                }
            }
        }
        .padding(24).frame(width: 992)
        .background(scheme == .dark ? Color.black : Color(red: 242/255, green: 242/255, blue: 247/255))
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "fr"))
        .environment(\.chartXDomain, now.addingTimeInterval(-3600)...now)
        .environment(\.chartShowXGridLines, true)
        .environment(settings).environment(ChartPins(defaults: defaults))
        .groupBoxStyle(CardGroupBoxStyle())
        try saveRender(content, file: file)
    }

    private func saveRender<Content: View>(_ content: Content, file: String) throws {
        // ImageRenderer omits AppKit-backed horizontal scroll views (legends).
        // A never-shown hosting window renders the complete native view tree.
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        defer { window.close() }
        XCTAssertGreaterThan(bitmap.pixelsHigh, 200)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let folder = root.appendingPathComponent("build/screenshots-ios/renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(file + ".png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
