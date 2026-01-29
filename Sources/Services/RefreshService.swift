import Foundation
import Combine

@MainActor
final class RefreshService {
    static let shared = RefreshService()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var refreshInterval: Int {
        UserDefaults.standard.integer(forKey: "refreshInterval").clamped(to: 10...300)
    }

    private init() {
        // Observe changes to refresh interval
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartIfNeeded()
            }
            .store(in: &cancellables)
    }

    func start() {
        stop()

        let interval = TimeInterval(refreshInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        // Run initial refresh immediately
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartIfNeeded() {
        guard timer != nil else { return }
        start()
    }

    private func refresh() {
        AppState.shared.loadSystems()
        AppState.shared.loadAlerts()
        AppState.shared.loadContainers()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
