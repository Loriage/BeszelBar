import XCTest

final class APITests: XCTestCase {
    func testPublicHubFetchesWithoutAuthentication() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.append(request)
            return Data(#"{"page":1,"perPage":500,"totalPages":1,"totalItems":1,"items":[{"id":"server","name":"Server"}]}"#.utf8)
        }
        defer { StubURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = BeszelAPIService(instance: Instance(name: "Public", url: "https://hub.example", email: "", credential: "ignored-credential", isPublic: true), session: session)
        let systems = try await service.fetchSystems()
        XCTAssertEqual(systems.map(\.id), ["server"])
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertNil(recorder.requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(recorder.requests[0].url!.path.hasSuffix("systems/records"))
    }

    func testMissingCredentialDoesNotAutomaticallyUsePublicAccess() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in recorder.append(request); return Data() }
        defer { StubURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = BeszelAPIService(instance: Instance(name: "Private", url: "https://hub.example", email: "", credential: ""), session: session)
        do {
            _ = try await service.fetchSystems()
            XCTFail("Expected an authentication error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .userAuthenticationRequired)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testPublicHubDoesNotRetryUnauthorizedRequests() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.statusCode = 401
        StubURLProtocol.handler = { request in recorder.append(request); return Data() }
        defer { StubURLProtocol.handler = nil; StubURLProtocol.statusCode = 200 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = BeszelAPIService(instance: Instance(name: "Public", url: "https://hub.example", email: "", credential: "", isPublic: true), session: session)
        do {
            _ = try await service.fetchSystems()
            XCTFail("Expected an HTTP error")
        } catch let BeszelAPIError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 401)
        }
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testPaginationSubpathHistoryAndAuthenticationReuse() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.append(request)
            let path = request.url!.path
            if path.hasSuffix("auth-with-password") {
                return Data(#"{"token":"test-token"}"#.utf8)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let page = items.first { $0.name == "page" }?.value ?? "1"
            if path.hasSuffix("systems/records") {
                return Data(#"{"page":\#(page),"perPage":1,"totalPages":2,"totalItems":2,"items":[{"id":"server\#(page)","name":"Server \#(page)"}]}"#.utf8)
            }
            return Data(#"{"page":1,"perPage":500,"totalPages":1,"totalItems":0,"items":[]}"#.utf8)
        }
        defer { StubURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = BeszelAPIService(instance: Instance(name: "Hub", url: "https://hub.example/beszel/",
                                                        email: "test@example.com", credential: "password"), session: session)
        let systems = try await service.fetchSystems()
        _ = try await service.fetchHistory(systemID: "server2", range: .day, now: Date(timeIntervalSince1970: 0))
        let requests = recorder.requests
        XCTAssertEqual(systems.map(\.id), ["server1", "server2"])
        XCTAssertEqual(requests.filter { $0.url!.path.hasSuffix("auth-with-password") }.count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.url!.path.hasPrefix("/beszel/api/") })
        let filter = URLComponents(url: requests.last!.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "filter" }!.value!
        XCTAssertTrue(filter.contains("system = 'server2'"))
        XCTAssertTrue(filter.contains("type = '20m'"))
        XCTAssertTrue(filter.contains("created >="))
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { storage.append(request) } }
    var requests: [URLRequest] { lock.withLock { storage } }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
