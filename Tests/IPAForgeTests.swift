import Foundation
import XCTest
@testable import AppStoreIPADownloader

final class AnisetteURLValidatorTests: XCTestCase {
    func testAcceptsHTTPSURLWithoutCredentialsOrQuery() {
        XCTAssertNotNil(AnisetteURLValidator.validatedBaseURL("https://example.com/api"))
    }

    func testRejectsHTTPAndCredentialBearingURLs() {
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("http://example.com"))
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("https://user:pass@example.com"))
        XCTAssertNil(AnisetteURLValidator.validatedBaseURL("https://example.com?token=secret"))
    }

    func testConnectionChecksOnlyHTTPSReachability() async {
        MockURLProtocol.statusCode = 200
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AnisetteService(session: URLSession(configuration: configuration))
        let result = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(result, .connected)
        let invalidURLResult = await service.testConnection(serverURL: "http://anisette.example")
        XCTAssertEqual(invalidURLResult, .invalidURL)
    }
}

final class LogSanitizerTests: XCTestCase {
    func testRedactsCredentialFieldsAndBearerTokens() {
        let sanitized = LogSanitizer.sanitize(
            "password=hunter2 token=abc123 Bearer eyJhbGciOiJIUzI1NiJ9"
        )
        XCTAssertFalse(sanitized.contains("hunter2"))
        XCTAssertFalse(sanitized.contains("abc123"))
        XCTAssertFalse(sanitized.contains("eyJhbGciOiJIUzI1NiJ9"))
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
