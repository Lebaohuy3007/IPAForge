import Foundation
import XCTest
@testable import AppStoreIPADownloader

final class AnisetteURLValidatorTests: XCTestCase {
    func testAcceptsHTTPSURLWithoutCredentialsOrQuery() {
        XCTAssertNotNil(AnisetteURLValidator.validatedBaseURL("https://example.com/api"))
        XCTAssertEqual(
            AnisetteURLValidator.normalized("https://EXAMPLE.com:443/path/"),
            "https://example.com/path"
        )
    }

    func testRejectsHTTPAndCredentialBearingURLs() {
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("http://example.com"))
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("https://user:pass@example.com"))
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("https://example.com?token=secret"))
        XCTAssertNil(AnisetteURLValidator.normalized("not a url"))
    }

    func testConnectionChecksOnlyHTTPSReachability() async {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseData = Data(#"{"X-Apple-I-MD":"otp","X-Apple-I-MD-M":"machine"}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AnisetteService(session: URLSession(configuration: configuration))
        let result = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(result.state, .validV1)
        XCTAssertNotNil(result.durationMilliseconds)

        MockURLProtocol.responseData = Data(#"{"message":"ok"}"#.utf8)
        let responseOnly = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(responseOnly.state, .responded)

        MockURLProtocol.responseData = Data(#"{"client_info":"v3 metadata","user_agent":"v3 client"}"#.utf8)
        let v3MetadataOnly = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(v3MetadataOnly.state, .responded)

        let invalidURLResult = await service.testConnection(serverURL: "http://anisette.example")
        XCTAssertEqual(invalidURLResult.state, .invalidURL)
    }

    func testTimeoutAndHTTPErrorAreNotUsable() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AnisetteService(session: URLSession(configuration: configuration))

        MockURLProtocol.stubbedError = URLError(.timedOut)
        let timedOut = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(timedOut.state, .noResponse)

        MockURLProtocol.stubbedError = nil
        MockURLProtocol.statusCode = 503
        let httpError = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(httpError.state, .responded)
        XCTAssertFalse(httpError.state.isUsable)
    }
}

@MainActor
final class AnisetteServerStoreTests: XCTestCase {
    func testAddPersistsSelectionAndDeleteClearsIt() async throws {
        configureValidAnisetteResponse()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        XCTAssertEqual(store.servers.map(\.name), ["SideStore", "jkcoxson"])
        XCTAssertTrue(store.servers.allSatisfy {
            store.probeResults[$0.id]?.state == .unchecked
        })

        let id = try await store.add(name: "  Personal  ", url: "https://personal.example/")
        XCTAssertEqual(store.servers.last?.name, "Personal")
        XCTAssertEqual(store.probeResults[id]?.state, .validV1)
        XCTAssertNil(store.selectedServerID)

        try store.select(serverID: id)
        XCTAssertEqual(store.selectedServerID, id)
        let restored = makeStore(defaults: defaults)
        XCTAssertEqual(restored.selectedServerID, id)
        XCTAssertEqual(restored.servers.last?.url, "https://personal.example")

        try store.delete(serverID: id)
        XCTAssertNil(store.selectedServerID)
        XCTAssertFalse(store.servers.contains(where: { $0.id == id }))
    }

    func testRejectsInvalidDuplicateAndUnavailableServers() async throws {
        MockURLProtocol.responseData = Data(#"{"message":"not anisette"}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)

        do {
            _ = try await store.add(name: "Bad", url: "http://insecure.example")
            XCTFail("HTTP servers must be rejected.")
        } catch {
            XCTAssertEqual(error as? AnisetteServerError, .invalidURL)
        }

        let id = try await store.add(name: "Invalid response", url: "https://invalid.example")
        XCTAssertEqual(store.probeResults[id]?.state, .responded)
        do {
            try store.select(serverID: id)
            XCTFail("A server without valid Anisette data must not be selectable.")
        } catch {
            XCTAssertEqual(error as? AnisetteServerError, .serverNotReady)
        }

        do {
            _ = try await store.add(name: "Duplicate", url: "https://INVALID.example/")
            XCTFail("Duplicate normalized URLs must be rejected.")
        } catch {
            XCTAssertEqual(error as? AnisetteServerError, .duplicateURL)
        }
    }

    func testUpdatePersistsAndDefaultServerCannotBeDeleted() async throws {
        configureValidAnisetteResponse()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        let id = try await store.add(name: "Old", url: "https://old.example")

        try await store.update(serverID: id, name: "New", url: "https://new.example/")
        XCTAssertEqual(store.servers.first(where: { $0.id == id })?.name, "New")
        XCTAssertEqual(store.servers.first(where: { $0.id == id })?.url, "https://new.example")

        let restored = makeStore(defaults: defaults)
        XCTAssertEqual(restored.servers.first(where: { $0.id == id })?.name, "New")

        let defaultServer = try XCTUnwrap(store.servers.first(where: \.isDefault))
        XCTAssertThrowsError(try store.delete(serverID: defaultServer.id)) {
            XCTAssertEqual($0 as? AnisetteServerError, .cannotModifyDefault)
        }
        do {
            try await store.update(serverID: defaultServer.id, name: "Changed", url: defaultServer.url)
            XCTFail("Default servers must not be editable.")
        } catch {
            XCTAssertEqual(error as? AnisetteServerError, .cannotModifyDefault)
        }
    }

    func testAllServersUnavailableDoesNotSelectOrFailOver() async throws {
        MockURLProtocol.stubbedError = URLError(.cannotConnectToHost)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)

        for server in store.servers {
            await store.refresh(serverID: server.id)
        }
        XCTAssertTrue(store.hasFinishedInitialChecks)
        XCTAssertFalse(store.hasUsableServer)
        XCTAssertNil(store.selectedServerID)
    }

    private func makeStore(defaults: UserDefaults) -> AnisetteServerStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AnisetteServerStore(
            service: AnisetteService(session: URLSession(configuration: configuration)),
            defaults: defaults
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "IPAForge.AnisetteTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func configureValidAnisetteResponse() {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseData = Data(
            #"{"X-Apple-I-MD":"non-empty","X-Apple-I-MD-M":"non-empty"}"#.utf8
        )
    }
}

final class LogSanitizerTests: XCTestCase {
    func testRedactsCredentialFieldsAndBearerTokens() {
        let sanitized = LogSanitizer.sanitize(
            #"{"password":"hunter2","token":"abc123","X-Apple-I-MD":"anisette-secret","X-Apple-I-Client-Time":"time-secret","identifier":"private-id","adi.pb":"blob"} Bearer eyJhbGciOiJIUzI1NiJ9"#
        )
        XCTAssertFalse(sanitized.contains("hunter2"))
        XCTAssertFalse(sanitized.contains("abc123"))
        XCTAssertFalse(sanitized.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertFalse(sanitized.contains("anisette-secret"))
        XCTAssertFalse(sanitized.contains("time-secret"))
        XCTAssertFalse(sanitized.contains("private-id"))
        XCTAssertFalse(sanitized.contains("blob"))
    }
}

final class AuthenticationServiceTests: XCTestCase {
    func testLoginFailsExplicitlyInsteadOfSimulatingSuccess() async {
        do {
            try await AuthenticationService().startLogin(
                appleID: "test@example.invalid",
                password: "not-a-real-password"
            )
            XCTFail("Authentication must not report success without an implementation.")
        } catch {
            XCTAssertEqual(error as? AuthenticationError, .unsupported)
        }
    }

    func testTwoFactorIsExplicitlyUnsupported() async {
        do {
            try await AuthenticationService().verify2FA(code: "123456")
            XCTFail("2FA must not report success without an authentication implementation.")
        } catch {
            XCTAssertEqual(error as? AuthenticationError, .unsupported)
        }
    }
}

final class ExportServiceTests: XCTestCase {
    func testRejectsMissingIPA() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing.ipa")
        XCTAssertThrowsError(try ExportService().validate(url))
    }

    func testRejectsNonIPAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ExportService().validate(url))
    }

    func testAcceptsAndReturnsExistingIPAForSharing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ExportService().shareItems(for: url), [url])
    }
}

final class AppStoreServiceTests: XCTestCase {
    func testSearchDecodesAppStoreResponse() async throws {
        MockURLProtocol.responseData = Data(#"{"results":[{"trackId":42,"bundleId":"com.example.app","trackName":"Example","sellerName":"Example Inc.","version":"1.2","artworkUrl100":"https://example.com/icon.png"}]}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))
        let app = try await service.search("example").first
        XCTAssertEqual(app?.id, 42)
        XCTAssertEqual(app?.bundleID, "com.example.app")
        XCTAssertEqual(app?.name, "Example")
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200
    static var stubbedError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = Self.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
