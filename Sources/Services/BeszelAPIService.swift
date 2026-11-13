import Foundation

protocol BeszelServing: Sendable {
    func fetchSystems() async throws -> [SystemRecord]
    func fetchSystemDetails() async throws -> [SystemDetailsRecord]
    func fetchContainers(filter: String?) async throws -> [ContainerRecord]
    func fetchAlerts(filter: String?) async throws -> [AlertRecord]
    func fetchHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [SystemStatsRecord]
    func fetchDetailedHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedSystemRecord]
    func fetchContainerHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedContainerRecord]
    func fetchZFSPools(systemID: String) async throws -> [ZFSPoolRecord]
    func currentEndpoint() async -> URL?
}

extension BeszelServing {
    func fetchDetailedHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedSystemRecord] { [] }
    func fetchContainerHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedContainerRecord] { [] }
    func fetchZFSPools(systemID: String) async throws -> [ZFSPoolRecord] { [] }
    func currentEndpoint() async -> URL? { nil }
}

actor BeszelAPIService: BeszelServing {
    private let instance: Instance
    private var authToken: String?
    private var authenticationTask: Task<String, Error>?

    private let connection: HubConnection

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = DateFormatter.pocketBase.date(from: value) { return date }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            guard let date = iso.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid sample date"))
            }
            return date
        }
        return decoder
    }()

    init(instance: Instance, session: URLSession? = nil) {
        var normalized = instance
        normalized.url = HubURL.normalized(instance.url) ?? instance.url
        normalized.fallbackURL = HubURL.normalized(instance.fallbackURL) ?? ""
        self.instance = normalized
        let configuredSession: URLSession
        if let session {
            configuredSession = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            configuredSession = URLSession(configuration: config)
        }
        self.connection = HubConnection(baseURL: normalized.url, fallbackURL: normalized.fallbackURL) { request in
            try await configuredSession.data(for: request)
        }
    }

    func currentEndpoint() async -> URL? { await connection.currentEndpoint }

    private func getValidToken() async throws -> String {
        if let currentToken = authToken {
            return currentToken
        }

        if let authenticationTask { return try await authenticationTask.value }
        let credential = instance.credential
        guard !credential.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let task = Task {
            if isJWT(credential) { return try await refreshToken(currentToken: credential) }
            return try await loginWithPassword(password: credential)
        }
        authenticationTask = task
        defer { authenticationTask = nil }
        return try await task.value
    }

    private func isJWT(_ str: String) -> Bool {
        let parts = str.components(separatedBy: ".")
        return parts.count == 3 && str.hasPrefix("ey")
    }

    private func loginWithPassword(password: String) async throws -> String {
        guard let url = URL(string: "\(instance.url)/api/collections/users/auth-with-password") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["identity": instance.email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await connection.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        let authResponse = try jsonDecoder.decode(AuthResponse.self, from: data)
        self.authToken = authResponse.token
        return authResponse.token
    }

    private func refreshToken(currentToken: String) async throws -> String {
        guard let url = URL(string: "\(instance.url)/api/collections/users/auth-refresh") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await connection.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        let authResponse = try jsonDecoder.decode(AuthResponse.self, from: data)
        self.authToken = authResponse.token
        return authResponse.token
    }

    private func performRequest<T: Decodable>(with url: URL, retryCount: Int = 0) async throws -> T {
        let token = try await getValidToken()

        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await connection.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return try jsonDecoder.decode(T.self, from: data)
            } else if httpResponse.statusCode == 401 && retryCount < 1 {
                authToken = nil
                return try await performRequest(with: url, retryCount: retryCount + 1)
            } else {
                throw BeszelAPIError.httpError(statusCode: httpResponse.statusCode, url: url.absoluteString)
            }
        } else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchSystems() async throws -> [SystemRecord] {
        try await fetchAllPages(path: "/api/collections/systems/records", filter: nil)
    }

    func fetchSystemDetails() async throws -> [SystemDetailsRecord] {
        do {
            return try await fetchAllPages(path: "/api/collections/system_details/records", filter: nil)
        } catch let error as BeszelAPIError {
            if case .httpError(404, _) = error { return [] }
            throw error
        }
    }

    private func historyFilter(systemID: String, range: HistoryRange, now: Date) -> String {
        let formatter = DateFormatter.pocketBase
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let start = formatter.string(from: now.addingTimeInterval(-range.duration - range.interval))
        let escapedID = systemID.replacingOccurrences(of: "'", with: "\\'")
        return "system = '\(escapedID)' && type = '\(range.recordType)' && created >= '\(start)'"
    }

    func fetchHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [SystemStatsRecord] {
        try await fetchAllPages(path: "/api/collections/system_stats/records", filter: historyFilter(systemID: systemID, range: range, now: now))
    }

    func fetchDetailedHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedSystemRecord] {
        try await fetchAllPages(path: "/api/collections/system_stats/records", filter: historyFilter(systemID: systemID, range: range, now: now))
    }

    func fetchContainerHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [DetailedContainerRecord] {
        do {
            return try await fetchAllPages(path: "/api/collections/container_stats/records", filter: historyFilter(systemID: systemID, range: range, now: now))
        } catch BeszelAPIError.httpError(404, _) { return [] }
    }

    func fetchZFSPools(systemID: String) async throws -> [ZFSPoolRecord] {
        do {
            return try await fetchAllPages(path: "/api/collections/zfs_pools/records", filter: "system = '\(systemID)'")
        } catch BeszelAPIError.httpError(404, _) { return [] }
    }

    func fetchSystemStats(systemID: String, limit: Int = 1) async throws -> [SystemStatsRecord] {
        guard var components = URLComponents(string: instance.url) else {
            throw URLError(.badURL)
        }
        components.path += "/api/collections/system_stats/records"
        components.queryItems = [
            URLQueryItem(name: "perPage", value: String(limit)),
            URLQueryItem(name: "sort", value: "-created"),
            URLQueryItem(name: "filter", value: "system = '\(systemID)'")
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let response: PocketBaseListResponse<SystemStatsRecord> = try await performRequest(with: url)
        return response.items
    }

    func fetchAlerts(filter: String? = nil) async throws -> [AlertRecord] {
        try await fetchAllPages(path: "/api/collections/alerts/records", filter: filter)
    }

    func fetchLatestAlerts(limit: Int = 10) async throws -> [AlertRecord] {
        guard var components = URLComponents(string: instance.url) else {
            throw URLError(.badURL)
        }
        components.path += "/api/collections/alerts/records"
        components.queryItems = [
            URLQueryItem(name: "perPage", value: String(limit)),
            URLQueryItem(name: "sort", value: "-created")
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let response: PocketBaseListResponse<AlertRecord> = try await performRequest(with: url)
        return response.items
    }

    func fetchContainers(filter: String? = nil) async throws -> [ContainerRecord] {
        do {
            return try await fetchAllPages(path: "/api/collections/containers/records", filter: filter)
        } catch let error as BeszelAPIError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                return [] // Containers collection doesn't exist
            }
            throw error
        }
    }

    func fetchContainers(for systemID: String) async throws -> [ContainerRecord] {
        try await fetchContainers(filter: "system = '\(systemID)'")
    }

    func fetchContainerStats(systemID: String, limit: Int = 1) async throws -> [ContainerStatsRecord] {
        guard var components = URLComponents(string: instance.url) else {
            throw URLError(.badURL)
        }
        components.path += "/api/collections/container_stats/records"
        components.queryItems = [
            URLQueryItem(name: "perPage", value: String(limit * 100)), // Get latest for multiple containers
            URLQueryItem(name: "sort", value: "-created"),
            URLQueryItem(name: "filter", value: "system = '\(systemID)'")
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        do {
            let response: PocketBaseListResponse<ContainerStatsRecord> = try await performRequest(with: url)

            var latestPerContainer: [String: ContainerStatsRecord] = [:]
            for stat in response.items {
                if latestPerContainer[stat.containerID] == nil {
                    latestPerContainer[stat.containerID] = stat
                }
            }
            return Array(latestPerContainer.values)
        } catch let error as BeszelAPIError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                return []
            }
            throw error
        }
    }

    private func fetchAllPages<T: Codable>(path: String, filter: String?) async throws -> [T] {
        var allItems: [T] = []
        var currentPage = 1
        var totalPages = 1

        repeat {
            try Task.checkCancellation()
            let url = try buildURL(for: path, filter: filter, page: currentPage)
            let response: PocketBaseListResponse<T> = try await performRequest(with: url)

            allItems.append(contentsOf: response.items)
            totalPages = response.totalPages
            currentPage += 1
        } while currentPage <= totalPages

        return allItems
    }

    private func buildURL(for path: String, filter: String?, page: Int = 1) throws -> URL {
        guard var components = URLComponents(string: instance.url) else {
            throw URLError(.badURL)
        }

        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([components.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = [
            URLQueryItem(name: "perPage", value: "500"),
            URLQueryItem(name: "page", value: String(page))
        ]

        if let filter = filter {
            components.queryItems?.append(URLQueryItem(name: "filter", value: filter))
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return url
    }
}

enum BeszelAPIError: LocalizedError {
    case httpError(statusCode: Int, url: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, _):
            switch statusCode {
            case 401: return "Your session has expired. Check this hub's credentials in Settings."
            case 403: return "This account does not have access to the requested data."
            default: return "The hub could not complete the request (HTTP \(statusCode))."
            }
        }
    }
}
