import XCTest

final class HubConnectionTests: XCTestCase {
    private let primary = "http://lan.example/beszel"
    private let secondary = "https://remote.example/monitoring"

    func testFallbackRebasesSubpathsAndRemembersReachableEndpoint() async throws {
        let transport = ConnectionTransport(failedHosts: ["lan.example"])
        let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
        var request = URLRequest(url: URL(string: primary + "/api/collections/systems/records?page=2")!)
        request.setValue("Bearer example", forHTTPHeaderField: "Authorization")
        _ = try await connection.data(for: request)
        _ = try await connection.data(for: request)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.host! }, ["lan.example", "remote.example", "remote.example"])
        XCTAssertEqual(requests[1].url!.absoluteString, secondary + "/api/collections/systems/records?page=2")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer example")
        XCTAssertLessThanOrEqual(requests[0].timeoutInterval, 4)
        let endpoint = await connection.currentEndpoint
        XCTAssertEqual(endpoint?.absoluteString, secondary)
    }

    func testReturnsToPrimaryAfterCooldown() async throws {
        let transport = ConnectionTransport(failedHosts: ["lan.example"])
        let connection = HubConnection(baseURL: primary, fallbackURL: secondary,
                                       retryPrimaryAfter: .zero, send: { try await transport.send($0) })
        let request = URLRequest(url: URL(string: primary + "/api/health")!)
        _ = try await connection.data(for: request)
        await transport.setFailedHosts([])
        _ = try await connection.data(for: request)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.host! }, ["lan.example", "remote.example", "lan.example"])
        let endpoint = await connection.currentEndpoint
        XCTAssertEqual(endpoint?.absoluteString, primary)
    }

    func testAuthenticationIsSentOnceAfterReachabilityProbe() async throws {
        let transport = ConnectionTransport(failedHosts: ["lan.example"])
        let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
        var request = URLRequest(url: URL(string: primary + "/api/collections/users/auth-with-password")!)
        request.httpMethod = "POST"
        request.httpBody = Data("test-body".utf8)
        _ = try await connection.data(for: request)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        XCTAssertEqual(requests.last?.httpBody, request.httpBody)
        XCTAssertEqual(requests.last?.url?.host, "remote.example")
    }

    func testTimedOutPostIsNeverReplayed() async throws {
        let transport = ConnectionTransport(failPost: true)
        let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
        var request = URLRequest(url: URL(string: primary + "/api/collections/users/auth-with-password")!)
        request.httpMethod = "POST"
        do {
            _ = try await connection.data(for: request)
            XCTFail("Expected a timeout")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST"])
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "lan.example" })
    }

    func testHTTPFailuresDoNotSwitchHosts() async throws {
        for status in [401, 403, 500] {
            let transport = ConnectionTransport(status: status)
            let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
            let (_, response) = try await connection.data(for: URLRequest(url: URL(string: primary + "/api/health")!))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, status)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testCertificateAndCancellationFailuresDoNotSwitchHosts() async throws {
        for code in [URLError.Code.serverCertificateUntrusted, .cancelled] {
            let transport = ConnectionTransport(failedHosts: ["lan.example"], errorCode: code)
            let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
            do {
                _ = try await connection.data(for: URLRequest(url: URL(string: primary + "/api/health")!))
                XCTFail("Expected transport failure")
            } catch { XCTAssertEqual((error as? URLError)?.code, code) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testRejectsUnrelatedRequestsWithoutSendingCredentials() async throws {
        let transport = ConnectionTransport()
        let connection = HubConnection(baseURL: primary, fallbackURL: secondary, send: { try await transport.send($0) })
        for url in ["https://unrelated.example/api/health", "http://lan.example/beszel-other/api/health"] {
            do {
                _ = try await connection.data(for: URLRequest(url: URL(string: url)!))
                XCTFail("Expected invalid scope")
            } catch { XCTAssertEqual((error as? URLError)?.code, .badURL) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testURLValidationAndBackwardsCompatibleStorage() throws {
        XCTAssertEqual(HubURL.normalized(" https://example.com/beszel/// \n"), "https://example.com/beszel")
        XCTAssertTrue(HubURL.isValidFallback(""))
        for url in ["ftp://example.com", "https://user:password@example.com", "https://example.com?token=x", "https://example.com/#fragment"] {
            XCTAssertNil(HubURL.baseURL(url))
        }
        let oldData = Data(#"{"id":"12345678-1234-1234-1234-123456789012","name":"Hub","url":"http://local.example","email":"test@example.com"}"#.utf8)
        var instance = try JSONDecoder().decode(Instance.self, from: oldData)
        XCTAssertEqual(instance.fallbackURL, "")
        instance.fallbackURL = secondary
        instance.credential = "must-not-be-stored"
        let data = try JSONEncoder().encode(instance)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(instance.credential))
        XCTAssertEqual(try JSONDecoder().decode(Instance.self, from: data).fallbackURL, secondary)
    }
}

private actor ConnectionTransport {
    private(set) var requests: [URLRequest] = []
    private var failedHosts: Set<String>
    private let failPost: Bool
    private let status: Int
    private let errorCode: URLError.Code

    init(failedHosts: Set<String> = [], failPost: Bool = false, status: Int = 200,
         errorCode: URLError.Code = .cannotConnectToHost) {
        self.failedHosts = failedHosts
        self.failPost = failPost
        self.status = status
        self.errorCode = errorCode
    }
    func setFailedHosts(_ hosts: Set<String>) { failedHosts = hosts }
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        if failPost && request.httpMethod == "POST" { throw URLError(.timedOut) }
        if failedHosts.contains(request.url!.host!) { throw URLError(errorCode) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
