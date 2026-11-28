import Foundation
import XCTest
import ZIPFoundation
@testable import AppStoreIPADownloader

final class AppLanguageTests: XCTestCase {
    func testVietnameseStorefrontSelectsVietnamese() {
        XCTAssertEqual(AppLanguage.forStorefront(countryCode: "VNM"), .vietnamese)
        XCTAssertEqual(AppLanguage.forStorefront(countryCode: "vnm"), .vietnamese)
    }

    func testOtherAndUnknownStorefrontsDefaultToEnglish() {
        XCTAssertEqual(AppLanguage.forStorefront(countryCode: "RUS"), .english)
        XCTAssertEqual(AppLanguage.forStorefront(countryCode: nil), .english)
    }
}

final class AnisetteURLValidatorTests: XCTestCase {
    func testServerEditorKeepsHTTPSPrefixOutsideEditableText() {
        XCTAssertEqual(AnisetteServerURLInput.suffix(from: "example.com/api"), "example.com/api")
        XCTAssertEqual(AnisetteServerURLInput.suffix(from: "https://example.com/api"), "example.com/api")
        XCTAssertEqual(AnisetteServerURLInput.suffix(from: "HTTP://example.com/api"), "example.com/api")
        XCTAssertEqual(
            AnisetteServerURLInput.fullURL(from: "https://example.com/api"),
            "https://example.com/api"
        )
    }

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

    func testSameOriginRequiresHTTPSAndMatchingPort() {
        XCTAssertTrue(AnisetteURLValidator.hasSameHTTPSOrigin(
            URL(string: "https://example.com"),
            URL(string: "https://EXAMPLE.com:443/path")
        ))
        XCTAssertFalse(AnisetteURLValidator.hasSameHTTPSOrigin(
            URL(string: "https://example.com"),
            URL(string: "https://example.com:8443")
        ))
        XCTAssertFalse(AnisetteURLValidator.hasSameHTTPSOrigin(
            URL(string: "https://example.com"),
            URL(string: "http://example.com")
        ))
        XCTAssertTrue(AnisetteURLValidator.hasSameWSSOrigin(
            URL(string: "wss://example.com"),
            URL(string: "wss://EXAMPLE.com:443/session")
        ))
        XCTAssertTrue(AnisetteURLValidator.hasSameWSSOrigin(
            URL(string: "https://example.com"),
            URL(string: "wss://example.com/session")
        ))
        XCTAssertFalse(AnisetteURLValidator.hasSameWSSOrigin(
            URL(string: "wss://example.com"),
            URL(string: "wss://other.example/session")
        ))
        XCTAssertFalse(AnisetteURLValidator.hasSameWSSOrigin(
            URL(string: "wss://example.com"),
            URL(string: "ws://example.com/session")
        ))
    }

    func testConnectionRecognizesV3ClientInfoOrAnisetteHeaderResponse() async {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AnisetteService(session: URLSession(configuration: configuration))

        MockURLProtocol.responseHandler = { request in
            if request.url?.path == "/" {
                return Data(#"{"X-Apple-I-MD":"test-md","X-Apple-I-MD-M":"test-machine"}"#.utf8)
            }
            return Data(#"{"message":"not client info"}"#.utf8)
        }
        defer { MockURLProtocol.responseHandler = nil }
        let result = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(result.state, .validV3)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url?.path }, ["/v3/client_info", "/"])

        MockURLProtocol.responseHandler = nil
        MockURLProtocol.responseData = Data(#"{"message":"ok"}"#.utf8)
        let responseOnly = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(responseOnly.state, .responded)

        MockURLProtocol.responseData = Data(#"{"client_info":"v3 metadata","user_agent":"v3 client"}"#.utf8)
        let v3MetadataOnly = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(v3MetadataOnly.state, .validV3)

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

    func testAnisetteProbeLogsActualHTTPDiagnosticsWithoutResponseBody() async {
        let logger = await MainActor.run { LoggingService() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.statusCode = 503
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseData = Data("private-response-body".utf8)
        MockURLProtocol.retryAfter = "7"
        MockURLProtocol.responseHandler = nil
        defer {
            MockURLProtocol.retryAfter = nil
            MockURLProtocol.responseData = Data()
        }
        let service = AnisetteService(
            session: URLSession(configuration: configuration),
            logger: logger
        )

        _ = await service.testConnection(serverURL: "https://anisette.example")
        let logText = await MainActor.run { logger.text }

        XCTAssertTrue(logText.contains("HTTP Status: 503"))
        XCTAssertTrue(logText.contains("Response Type: application/json"))
        XCTAssertTrue(logText.contains("Response Size: 21 bytes"))
        XCTAssertTrue(logText.contains("Retry-After: 7"))
        XCTAssertTrue(logText.contains("HTTP 503"))
        XCTAssertFalse(logText.contains("private-response-body"))
    }

    func testFetchV3HeadersReusesEncryptedIdentityAndCallsV3Endpoints() async throws {
        let identity = StoredAnisetteIdentity(
            identifier: "stable-local-id",
            deviceID: UUID().uuidString,
            adiPB: Data([1, 2, 3]).base64EncodedString()
        )
        let identityStore = MockAnisetteIdentityStore(identity: identity)
        try identityStore.approveServer(forServer: "https://anisette.example")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.requests = []
        MockURLProtocol.responseHandler = { request in
            switch request.url?.path {
            case "/v3/client_info":
                return Data(#"{"client_info":"client OS 10.12.6","user_agent":"agent OS 10.12.6","serial":"0"}"#.utf8)
            case "/v3/get_headers":
                return Data(#"{"X-Apple-I-MD":"otp","X-Apple-I-MD-M":"machine","X-Apple-I-MD-RINFO":"1"}"#.utf8)
            default:
                return Data()
            }
        }
        defer { MockURLProtocol.responseHandler = nil }

        let service = AnisetteService(
            session: URLSession(configuration: configuration),
            identityStore: identityStore
        )
        let headers = try await service.fetchAnisetteV3(serverURL: "https://anisette.example")

        XCTAssertEqual(headers["X-Apple-I-MD"], "otp")
        XCTAssertEqual(headers["X-Apple-I-MD-M"], "machine")
        XCTAssertEqual(headers["X-Apple-I-MD-LU"], identity.identifier)
        XCTAssertEqual(headers["X-MMe-Client-Info"], "client OS 10.12.6")
        XCTAssertEqual(headers["User-Agent"], "agent OS 10.12.6")
        XCTAssertEqual(
            MockURLProtocol.requests.compactMap { $0.url?.path },
            ["/v3/client_info", "/v3/get_headers"]
        )
        let getHeadersRequest = try XCTUnwrap(MockURLProtocol.requests.last)
        let body = try XCTUnwrap(getHeadersRequest.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload["identifier"], identity.identifier)
        XCTAssertEqual(payload["adi_pb"], identity.adiPB)
    }

    func testV3ProvisioningExchangesAppleChallengesAndPersistsIdentity() async throws {
        let provisioningData = Data([4, 5, 6]).base64EncodedString()
        let socket = MockAnisetteWebSocket(messages: [
            #"{"result":"GiveIdentifier"}"#,
            #"{"result":"GiveStartProvisioningData"}"#,
            #"{"result":"GiveEndProvisioningData","cpim":"client-challenge"}"#,
            #"{"result":"ProvisioningSuccess","adi_pb":"\#(provisioningData)"}"#
        ])
        let socketFactory = MockAnisetteWebSocketFactory(connection: socket)
        let identityStore = MockAnisetteIdentityStore(identity: nil)
        try identityStore.approveServer(forServer: "https://anisette.example")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.requests = []
        MockURLProtocol.responseHandler = { request in
            switch request.url?.path {
            case "/v3/client_info":
                return Data(#"{"client_info":"client","user_agent":"agent","serial":"0"}"#.utf8)
            case "/grandslam/GsService2/lookup":
                return Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>urls</key><dict>
                <key>midStartProvisioning</key><string>https://gsa.apple.com/start</string>
                <key>midFinishProvisioning</key><string>https://gsa.apple.com/finish</string>
                </dict></dict></plist>
                """.utf8)
            case "/start":
                return Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>Response</key><dict>
                <key>spim</key><string>server-challenge</string>
                </dict></dict></plist>
                """.utf8)
            case "/finish":
                return Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>Response</key><dict>
                <key>ptm</key><string>provisioning-token</string>
                <key>tk</key><string>trust-key</string>
                </dict></dict></plist>
                """.utf8)
            case "/v3/get_headers":
                return Data(#"{"X-Apple-I-MD":"otp","X-Apple-I-MD-M":"machine"}"#.utf8)
            default:
                return Data()
            }
        }
        defer { MockURLProtocol.responseHandler = nil }

        let service = AnisetteService(
            session: URLSession(configuration: configuration),
            identityStore: identityStore,
            webSocketFactory: socketFactory
        )
        let headers = try await service.fetchAnisetteV3(serverURL: "https://anisette.example")

        XCTAssertEqual(headers["X-Apple-I-MD"], "otp")
        XCTAssertEqual(identityStore.identity?.adiPB, provisioningData)
        XCTAssertEqual(socket.sent.count, 3)
        let sentMessages = try socket.sent.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String])
        }
        XCTAssertEqual(sentMessages[0]["identifier"], identityStore.identity?.identifier)
        XCTAssertEqual(sentMessages[1]["spim"], "server-challenge")
        XCTAssertEqual(sentMessages[2]["ptm"], "provisioning-token")
        XCTAssertEqual(sentMessages[2]["tk"], "trust-key")
        XCTAssertEqual(socketFactory.connectedURL?.absoluteString, "wss://anisette.example/v3/provisioning_session")
    }

    func testV3IdentityIsNotSentUntilServerIsApproved() async throws {
        let identity = StoredAnisetteIdentity(
            identifier: "stable-local-id",
            deviceID: UUID().uuidString,
            adiPB: Data([1, 2, 3]).base64EncodedString()
        )
        let identityStore = MockAnisetteIdentityStore(identity: identity)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requests = []
        let service = AnisetteService(
            session: URLSession(configuration: configuration),
            identityStore: identityStore
        )

        do {
            _ = try await service.fetchAnisetteV3(serverURL: "https://anisette.example")
            XCTFail("Anisette identity must not be sent before explicit approval.")
        } catch let error as AnisetteV3Error {
            XCTAssertTrue(error.localizedDescription.contains("approve"))
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }
}

@MainActor
final class AnisetteServerStoreTests: XCTestCase {
    func testStikStoreDefaultURLMigratesToAppDomainAndPreservesSelection() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let stikStoreID = UUID()
        let persisted = AnisetteService.defaultServers.map { server -> [String: Any] in
            let isStikStore = server.name == "StikStore"
            return [
                "id": (isStikStore ? stikStoreID : server.id).uuidString,
                "name": server.name,
                "url": isStikStore ? "https://ani3.stikstore.com" : server.url,
                "isDefault": true
            ]
        }
        defaults.set(persisted, forKey: "anisette.servers.v1")
        defaults.set(stikStoreID.uuidString, forKey: "anisette.selectedServerID.v1")

        let store = makeStore(defaults: defaults)

        let stikStores = store.servers.filter { $0.name == "StikStore" }
        XCTAssertEqual(stikStores.count, 1)
        XCTAssertEqual(stikStores.first?.id, stikStoreID)
        XCTAssertEqual(stikStores.first?.url, "https://ani3.stikstore.app")
        XCTAssertEqual(store.selectedServerID, stikStoreID)
    }

    func testSideStoreIsDefaultAndCustomSelectionPersists() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        XCTAssertEqual(store.servers.map(\.name), ["SideStore", "jkcoxson"])
        let sideStoreID = try XCTUnwrap(
            store.servers.first(where: { $0.name == "SideStore" })?.id
        )
        XCTAssertEqual(store.selectedServerID, sideStoreID)

        let id = try await store.add(name: "  Personal  ", url: "https://personal.example/")
        XCTAssertEqual(store.servers.last?.name, "Personal")
        XCTAssertEqual(store.selectedServerID, sideStoreID)

        try store.select(serverID: id)
        XCTAssertEqual(store.selectedServerID, id)
        let restored = makeStore(defaults: defaults)
        XCTAssertEqual(restored.selectedServerID, id)
        XCTAssertEqual(restored.servers.last?.url, "https://personal.example")

        try store.delete(serverID: id)
        XCTAssertEqual(store.selectedServerID, sideStoreID)
        XCTAssertFalse(store.servers.contains(where: { $0.id == id }))
    }

    func testRejectsInvalidDuplicateAndAllowsSelectingServer() async throws {
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
        try store.select(serverID: id)
        XCTAssertEqual(store.selectedServerID, id)

        do {
            _ = try await store.add(name: "Duplicate", url: "https://INVALID.example/")
            XCTFail("Duplicate normalized URLs must be rejected.")
        } catch {
            XCTAssertEqual(error as? AnisetteServerError, .duplicateURL)
        }
    }

    func testUpdatePersistsAndDefaultServerCannotBeDeleted() async throws {
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

}

final class LogSanitizerTests: XCTestCase {
    func testRedactsCredentialFieldsAndBearerTokens() {
        let sanitized = LogSanitizer.sanitize(
            #"{"password":"hunter2","token":"abc123","X-Apple-I-MD":"anisette-secret","X-Apple-I-Client-Time":"time-secret","X-Apple-AMD":"amd-secret","X-Apple-ActionSignature":"sap-secret","DSID":"directory-secret","passwordToken":"password-token-secret","identifier":"private-id","adi.pb":"blob"} Bearer eyJhbGciOiJIUzI1NiJ9"#
        )
        XCTAssertFalse(sanitized.contains("hunter2"))
        XCTAssertFalse(sanitized.contains("abc123"))
        XCTAssertFalse(sanitized.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertFalse(sanitized.contains("anisette-secret"))
        XCTAssertFalse(sanitized.contains("time-secret"))
        XCTAssertFalse(sanitized.contains("private-id"))
        XCTAssertFalse(sanitized.contains("blob"))
        XCTAssertFalse(sanitized.contains("amd-secret"))
        XCTAssertFalse(sanitized.contains("sap-secret"))
        XCTAssertFalse(sanitized.contains("directory-secret"))
        XCTAssertFalse(sanitized.contains("password-token-secret"))
    }
}

@MainActor
final class LoggingServiceTests: XCTestCase {
    func testActivityEntriesCarryEventAndCorrelationIDs() {
        let logger = LoggingService()
        let correlationID = UUID()

        logger.log(.info, "Public metadata request.", correlationID: correlationID)

        let entry = logger.entries[0]
        XCTAssertTrue(entry.formatted.contains("Event ID: \(entry.id.uuidString)"))
        XCTAssertTrue(entry.formatted.contains("Correlation ID: \(correlationID.uuidString)"))
    }

    func testLoginLogsUpdateClearIndependentlyAndRedactSecrets() {
        let logger = LoggingService()
        logger.log(.info, "Application launched.")
        logger.logLogin(.info, "Starting authentication.")
        logger.logLogin(.error, #"{"password":"secret-value","token":"session-secret"}"#)

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.loginEntries.map(\.level), [.info, .error])
        XCTAssertFalse(logger.loginEntries[1].message.contains("secret-value"))
        XCTAssertFalse(logger.loginEntries[1].message.contains("session-secret"))

        logger.clearLogin()

        XCTAssertTrue(logger.loginEntries.isEmpty)
        XCTAssertEqual(logger.entries.count, 1)
    }
}

@MainActor
final class AuthenticationServiceTests: XCTestCase {
    func testSignInWaitsForTwoFactorAndPersistsOnlyEncryptedSession() async throws {
        let keychain = MockKeychainDataStore()
        let account = makeAccount()
        let provider = MockAppleAuthenticationProvider(account: account, requiresTwoFactor: true)
        let vault = AppleAccountVault(keychain: keychain)
        let service = AuthenticationService(vault: vault, provider: provider)
        let loginTask = Task {
            try await service.startLogin(
                appleID: account.appleID,
                password: "",
                anisetteHeaders: [:]
            )
        }

        for _ in 0..<1_000 where !service.isAwaitingVerification {
            await Task.yield()
        }
        XCTAssertTrue(service.isAwaitingVerification)
        XCTAssertThrowsError(try service.submitVerificationCode("123")) {
            XCTAssertEqual($0 as? AuthenticationError, .invalidVerificationCode)
        }

        try service.submitVerificationCode("123456")
        let signedInAccount = try await loginTask.value

        XCTAssertEqual(provider.receivedVerificationCode, "123456")
        XCTAssertEqual(service.currentAccount, account)
        XCTAssertEqual(signedInAccount, account)
        XCTAssertEqual(try vault.accounts(), [account])
        XCTAssertEqual(try vault.selectedAccountID(), account.id)
        XCTAssertFalse(keychain.values.values.contains {
            $0.range(of: account.sessionData) != nil
        })
    }

    func testCancellingTwoFactorDoesNotSaveAccount() async {
        let keychain = MockKeychainDataStore()
        let account = makeAccount()
        let vault = AppleAccountVault(keychain: keychain)
        let service = AuthenticationService(
            vault: vault,
            provider: MockAppleAuthenticationProvider(account: account, requiresTwoFactor: true)
        )
        let loginTask = Task {
            try await service.startLogin(
                appleID: account.appleID,
                password: "",
                anisetteHeaders: [:]
            )
        }

        for _ in 0..<1_000 where !service.isAwaitingVerification {
            await Task.yield()
        }
        service.cancelLogin()

        do {
            _ = try await loginTask.value
            XCTFail("Cancelling 2FA must not report a successful sign-in.")
        } catch is CancellationError {
            XCTAssertTrue(try vault.accounts().isEmpty)
            XCTAssertNil(service.currentAccount)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestoreRefreshesStoredAccountWithoutSavingPassword() async throws {
        let account = makeAccount()
        let vault = AppleAccountVault(keychain: MockKeychainDataStore())
        try vault.save(account)
        let provider = MockAppleAuthenticationProvider(account: account)
        let service = AuthenticationService(vault: vault, provider: provider)

        let restored = try await service.restore(account: account, anisetteHeaders: [:])

        XCTAssertEqual(restored, account)
        XCTAssertEqual(provider.restoreCallCount, 1)
        XCTAssertNil(restored.savedPassword)
        XCTAssertEqual(service.currentAccount, account)
    }

    private func makeAccount() -> StoredAppleAccount {
        StoredAppleAccount(
            id: UUID(),
            appleID: "test@example.invalid",
            sessionData: Data([0x4D, 0x53, 0x54, 0x01, 0xFE]),
            teams: [AppleDeveloperTeam(id: "team-1", name: "Test Team")],
            selectedTeamID: "team-1",
            savedPassword: nil,
            storeCountry: nil
        )
    }
}

final class AppleAccountVaultTests: XCTestCase {
    func testStoreCountryValidation() throws {
        let valid = StoredAppleAccount(
            id: UUID(),
            appleID: "test@example.invalid",
            sessionData: Data([1, 2, 3]),
            teams: [AppleDeveloperTeam(id: "team-1", name: "Test Team")],
            selectedTeamID: "team-1",
            savedPassword: nil,
            storeCountry: "vn"
        )
        XCTAssertNoThrow(try valid.validate())

        let invalid = StoredAppleAccount(
            id: UUID(),
            appleID: "test@example.invalid",
            sessionData: Data([1, 2, 3]),
            teams: [],
            selectedTeamID: nil,
            savedPassword: nil,
            storeCountry: "vietnam"
        )
        XCTAssertThrowsError(try invalid.validate()) {
            XCTAssertEqual($0 as? AppleAccountVaultError, .invalidAccount)
        }
    }

    func testEncryptsAndRestoresMultipleAccountsAndSelection() throws {
        let keychain = MockKeychainDataStore()
        let vault = AppleAccountVault(keychain: keychain)
        let first = makeAccount(appleID: "one@example.invalid")
        let second = makeAccount(appleID: "two@example.invalid")

        try vault.save(first)
        try vault.save(second)
        try vault.setSelectedAccountID(second.id)

        let restoredVault = AppleAccountVault(keychain: keychain)
        XCTAssertEqual(
            try restoredVault.accounts(),
            [first, second].sorted { $0.id.uuidString < $1.id.uuidString }
        )
        XCTAssertEqual(try restoredVault.selectedAccountID(), second.id)
        XCTAssertFalse(keychain.values.values.contains {
            String(decoding: $0, as: UTF8.self).contains("one@example.invalid")
        })
    }

    func testDeletingSelectedAccountClearsSelectionAndRejectsUnknownSelection() throws {
        let vault = AppleAccountVault(keychain: MockKeychainDataStore())
        let account = makeAccount()
        try vault.save(account)
        try vault.setSelectedAccountID(account.id)

        try vault.deleteAccount(id: account.id)

        XCTAssertTrue(try vault.accounts().isEmpty)
        XCTAssertNil(try vault.selectedAccountID())
        XCTAssertThrowsError(try vault.setSelectedAccountID(UUID()))
    }

    func testAnisetteIdentityIsEncryptedAndScopedToServer() throws {
        let keychain = MockKeychainDataStore()
        let vault = AppleAccountVault(keychain: keychain)
        let serverURL = "https://anisette.example"
        let identity = StoredAnisetteIdentity(
            identifier: "local-user-id",
            deviceID: UUID().uuidString,
            adiPB: Data([1, 2, 3]).base64EncodedString()
        )

        try vault.saveAnisetteIdentity(identity, forServer: serverURL)

        XCTAssertEqual(try vault.anisetteIdentity(forServer: serverURL), identity)
        XCTAssertFalse(try vault.isAnisetteServerApproved(forServer: serverURL))
        try vault.approveAnisetteServer(forServer: serverURL)
        XCTAssertTrue(try vault.isAnisetteServerApproved(forServer: serverURL))
        XCTAssertNil(try vault.anisetteIdentity(forServer: "https://another.example"))
        XCTAssertFalse(keychain.values.values.contains {
            String(decoding: $0, as: UTF8.self).contains(identity.adiPB)
        })

        try vault.clearAnisetteIdentity(forServer: serverURL)
        XCTAssertNil(try vault.anisetteIdentity(forServer: serverURL))
        XCTAssertFalse(try vault.isAnisetteServerApproved(forServer: serverURL))
    }

    func testRejectsTamperedRecordsAndInvalidAccountData() throws {
        let keychain = MockKeychainDataStore()
        let vault = AppleAccountVault(keychain: keychain)
        let account = makeAccount()
        try vault.save(account)
        keychain.values["account.\(account.id.uuidString.lowercased())"] = Data("tampered".utf8)

        XCTAssertThrowsError(try vault.accounts()) {
            XCTAssertEqual($0 as? AppleAccountVaultError, .corruptRecord)
        }

        let invalid = StoredAppleAccount(
            id: UUID(),
            appleID: " ",
            sessionData: Data(),
            teams: [],
            selectedTeamID: nil,
            savedPassword: nil,
            storeCountry: nil
        )
        XCTAssertThrowsError(try vault.save(invalid)) {
            XCTAssertEqual($0 as? AppleAccountVaultError, .invalidAccount)
        }
    }

    func testMissingEncryptionKeyDoesNotCreateReplacementKey() throws {
        let keychain = MockKeychainDataStore()
        let vault = AppleAccountVault(keychain: keychain)
        try vault.save(makeAccount())
        keychain.values.removeValue(forKey: "encryption-key")

        XCTAssertThrowsError(try vault.accounts()) {
            XCTAssertEqual($0 as? AppleAccountVaultError, .missingEncryptionKey)
        }
        XCTAssertNil(keychain.values["encryption-key"])
    }

    private func makeAccount(appleID: String = "test@example.invalid") -> StoredAppleAccount {
        StoredAppleAccount(
            id: UUID(),
            appleID: appleID,
            sessionData: Data([1, 2, 3]),
            teams: [AppleDeveloperTeam(id: "team-1", name: "Test Team")],
            selectedTeamID: "team-1",
            savedPassword: nil,
            storeCountry: nil
        )
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
        MockURLProtocol.responseData = Data(#"{"results":[{"trackId":42,"bundleId":"com.example.app","trackName":"Example","sellerName":"Example Inc.","version":"1.2","price":0,"artworkUrl100":"https://example.com/icon.png"}]}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))
        var statusCode: Int?
        let app = try await service.search("example", onHTTPStatus: { statusCode = $0 }).first
        XCTAssertEqual(app?.id, 42)
        XCTAssertEqual(app?.bundleID, "com.example.app")
        XCTAssertEqual(app?.name, "Example")
        XCTAssertEqual(app?.price, 0)
        XCTAssertEqual(statusCode, 200)
    }

    func testBundleIDSearchUsesLookupEndpoint() async throws {
        MockURLProtocol.responseData = Data(#"{"results":[{"trackId":42,"bundleId":"com.example.app","trackName":"Example","sellerName":"Example Inc.","version":"1.2","artworkUrl100":"https://example.com/icon.png"}]}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))

        let apps = try await service.search("com.example.app", country: "vn")

        XCTAssertEqual(apps.map(\.bundleID), ["com.example.app"])
    }

    func testNumericSearchIsAppStoreIDLookup() async throws {
        MockURLProtocol.responseData = Data(#"{"results":[{"trackId":123456,"bundleId":"com.example.app","trackName":"Example","sellerName":"Example Inc.","version":"1.2"}]}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))

        let apps = try await service.search("123456", country: "us")

        XCTAssertEqual(apps.map(\.id), [123456])
    }

    func testNonSuccessHTTPStatusIsReported() async {
        defer { MockURLProtocol.retryAfter = nil }
        MockURLProtocol.responseData = Data(#"{"results":[]}"#.utf8)
        MockURLProtocol.statusCode = 503
        MockURLProtocol.retryAfter = "17"
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))
        var statusCode: Int?
        var diagnostics: AppStoreRequestDiagnostics?

        do {
            _ = try await service.search(
                "example",
                onDiagnostics: { diagnostics = $0 },
                onHTTPStatus: { statusCode = $0 }
            )
            XCTFail("Expected an HTTP status error.")
        } catch {
            XCTAssertEqual(error as? AppStoreServiceError, AppStoreServiceError.httpStatus(503))
        }
        XCTAssertEqual(statusCode, 503)
        XCTAssertEqual(diagnostics?.httpStatus, 503)
        XCTAssertEqual(diagnostics?.method, "GET")
        XCTAssertEqual(diagnostics?.endpoint, "https://itunes.apple.com/search")
        XCTAssertEqual(diagnostics?.retryAfter, "17")
        XCTAssertEqual(diagnostics?.retryCount, 0)
        XCTAssertEqual(diagnostics?.wasRedirected, false)
    }

    func testMalformedPublicResponseIsRejected() async {
        MockURLProtocol.responseData = Data("not json".utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))

        do {
            _ = try await service.lookup(appID: 375_380_948)
            XCTFail("Expected malformed JSON to be rejected.")
        } catch {
            XCTAssertEqual(error as? AppStoreServiceError, AppStoreServiceError.invalidResponse)
        }
    }

    func testPublicRequestNetworkFailurePropagates() async {
        MockURLProtocol.stubbedError = URLError(.notConnectedToInternet)
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))
        var diagnostics: AppStoreRequestDiagnostics?

        do {
            _ = try await service.search("example", onDiagnostics: { diagnostics = $0 })
            XCTFail("Expected the network error to propagate.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(diagnostics?.httpStatus)
        XCTAssertEqual(diagnostics?.errorDomain, NSURLErrorDomain)
        XCTAssertEqual(diagnostics?.errorCode, URLError.notConnectedToInternet.rawValue)
        MockURLProtocol.stubbedError = nil
    }
}

@MainActor
final class AppStoreExperimentServiceTests: XCTestCase {
    func testAnonymousExperimentReportsMetadataAndBlockedAuthentication() async {
        let response = Data(#"{"resultCount":1,"results":[{"trackId":375380948,"bundleId":"com.apple.store.Jolly","trackName":"Apple Store","sellerName":"Apple Inc.","version":"6.10","price":0,"minimumOsVersion":"26.0"}]}"#.utf8)
        MockURLProtocol.responseData = response
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseHandler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let logger = LoggingService()
        let experiments = AppStoreExperimentService(
            appStore: AppStoreService(session: URLSession(configuration: configuration)),
            logger: logger
        )

        await experiments.run()

        guard let checks = experiments.report?.checks else {
            return XCTFail("The experiment should publish its report.")
        }
        XCTAssertEqual(checks.first(where: { $0.name == "A · Search" })?.status, .passed)
        XCTAssertEqual(checks.first(where: { $0.name == "A · Metadata" })?.status, .passed)
        XCTAssertEqual(checks.first(where: { $0.name == "A · Binary access" })?.status, .unsupported)
        XCTAssertEqual(checks.first(where: { $0.name == "A · IPA download" })?.status, .notTested)
        XCTAssertEqual(checks.first(where: { $0.name == "B · Authentication" })?.status, .blocked)
        XCTAssertTrue(logger.text.contains("HTTP 200"))
        XCTAssertTrue(logger.text.contains("Experiment A final result"))
        XCTAssertTrue(logger.text.contains("Experiment B final result"))
        XCTAssertFalse(logger.text.localizedCaseInsensitiveContains("password="))
        XCTAssertFalse(logger.text.localizedCaseInsensitiveContains("session token="))
    }
}

final class IPAForgeVersionTests: XCTestCase {
    func testVersionUsesDeclaredShortVersion() {
        XCTAssertEqual(
            IPAForgeVersion.displayValue(shortVersion: "2.3.4"),
            "2.3.4"
        )
    }

    func testVersionUsesFallbackWhenShortVersionIsMissing() {
        XCTAssertEqual(
            IPAForgeVersion.displayValue(shortVersion: nil),
            "1.0.0"
        )
    }
}

private final class MockKeychainDataStore: KeychainDataStoring {
    var values: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        values[key]
    }

    func setData(_ data: Data, for key: String) throws {
        values[key] = data
    }

    func deleteData(for key: String) throws {
        values.removeValue(forKey: key)
    }

    func keys(withPrefix prefix: String) throws -> [String] {
        values.keys.filter { $0.hasPrefix(prefix) }
    }
}

@MainActor
private final class MockAppleAuthenticationProvider: AppleAuthenticationProviding {
    let account: StoredAppleAccount
    let requiresTwoFactor: Bool
    private(set) var receivedVerificationCode: String?
    private(set) var restoreCallCount = 0

    init(account: StoredAppleAccount, requiresTwoFactor: Bool = false) {
        self.account = account
        self.requiresTwoFactor = requiresTwoFactor
    }

    func signIn(
        appleID: String,
        password: String,
        anisetteHeaders: [String: String],
        requestVerificationCode: @escaping () async -> String?
    ) async throws -> StoredAppleAccount {
        if requiresTwoFactor {
            guard let code = await requestVerificationCode() else {
                throw CancellationError()
            }
            receivedVerificationCode = code
        }
        return account
    }

    func restore(
        account: StoredAppleAccount,
        anisetteHeaders: [String: String]
    ) async throws -> StoredAppleAccount {
        restoreCallCount += 1
        return self.account
    }
}

private final class MockAnisetteIdentityStore: AnisetteIdentityStoring {
    var identity: StoredAnisetteIdentity?
    private var approvedServers = Set<String>()

    init(identity: StoredAnisetteIdentity?) {
        self.identity = identity
    }

    func loadIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity? {
        identity
    }

    func saveIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws {
        self.identity = identity
    }

    func isServerApproved(forServer serverURL: String) throws -> Bool {
        approvedServers.contains(serverURL)
    }

    func approveServer(forServer serverURL: String) throws {
        approvedServers.insert(serverURL)
    }

    func clearIdentity(forServer serverURL: String) throws {
        identity = nil
        approvedServers.remove(serverURL)
    }
}

private final class MockAnisetteWebSocket: AnisetteWebSocketConnection {
    private var messages: [String]
    private(set) var sent: [String] = []

    init(messages: [String]) {
        self.messages = messages
    }

    func send(_ text: String) async throws {
        sent.append(text)
    }

    func receive() async throws -> String {
        guard !messages.isEmpty else {
            throw AnisetteV3Error(message: "No mock provisioning message remains.")
        }
        return messages.removeFirst()
    }

    func cancel() {}
}

private final class MockAnisetteWebSocketFactory: AnisetteWebSocketCreating {
    let connection: AnisetteWebSocketConnection
    private(set) var connectedURL: URL?

    init(connection: AnisetteWebSocketConnection) {
        self.connection = connection
    }

    func connect(to url: URL) -> AnisetteWebSocketConnection {
        connectedURL = url
        return connection
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200
    static var stubbedError: Error?
    static var responseHandler: ((URLRequest) -> Data)?
    static var requests: [URLRequest] = []
    static var retryAfter: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let error = Self.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "Retry-After": Self.retryAfter
            ].compactMapValues { $0 }
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseHandler?(request) ?? Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class DeviceProfileTests: XCTestCase {
    func testDefaultProfileIsAnIOS27SimulatedProfile() {
        let profile = DeviceProfile.defaultProfile
        XCTAssertEqual(profile.family, .iPhone)
        XCTAssertEqual(profile.osVersion, "27.2")
        XCTAssertTrue(profile.isSimulated)
        XCTAssertNil(profile.availableCapabilities)
        XCTAssertNil(profile.supportedArchitectures)
    }

    func testVersionComparisonAndProfileValidation() {
        XCTAssertGreaterThan(SemanticOSVersion("27.2.1")!, SemanticOSVersion("27.2")!)
        XCTAssertLessThan(SemanticOSVersion("27.10")!, SemanticOSVersion("28.0")!)

        var profile = DeviceProfile.defaultProfile
        profile.model = "iPhone Air"
        profile.osVersion = "27.2"
        profile.supportedArchitectures = ["arm64e.x1"]
        XCTAssertNil(profile.validationError())

        profile.osVersion = "26.9"
        XCTAssertEqual(profile.validationError(), .requiresIOS27)
        profile.osVersion = "27.invalid"
        XCTAssertEqual(profile.validationError(), .invalidOSVersion)
    }

    func testProfilesPersistAndRestoreSelectedModelAndVersion() throws {
        let suite = "IPAForge.DeviceProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DeviceProfileStore(defaults: defaults)
        var profile = store.selectedProfile
        profile.name = "iPhone Air test"
        profile.model = "iPhone Air"
        profile.osVersion = "27.2"
        try store.save(profile)

        let restored = DeviceProfileStore(defaults: defaults)
        XCTAssertEqual(restored.selectedProfile, profile)
        XCTAssertTrue(restored.selectedProfile.isSimulated)
    }

    func testMultipleProfilesCanBeSelectedAndLastProfileCannotBeDeleted() throws {
        let suite = "IPAForge.DeviceProfileTests.Multiple.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceProfileStore(defaults: defaults)
        let firstID = store.selectedProfileID

        let second = store.createProfile()
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.selectedProfileID, second.id)

        store.select(profileID: firstID)
        XCTAssertEqual(store.selectedProfileID, firstID)
        store.delete(profileID: second.id)
        XCTAssertEqual(store.profiles.map(\.id), [firstID])
        store.delete(profileID: firstID)
        XCTAssertEqual(store.profiles.map(\.id), [firstID])
    }
}

final class CompatibilityCheckerTests: XCTestCase {
    func testUserEnteredHardwareValuesDoNotVerifyASimulatedProfile() {
        let profile = makeProfile(capabilities: ["wifi", "arm64"], architectures: ["arm64"])
        let requirements = CompatibilityRequirements(
            minimumOSVersion: "16.0",
            supportedDeviceFamilies: [1],
            requiredCapabilities: ["wifi"],
            prohibitedCapabilities: ["nfc"],
            supportedPlatforms: ["iPhoneOS"],
            architectures: ["arm64"]
        )

        let report = CompatibilityChecker().evaluate(requirements: requirements, profile: profile)

        XCTAssertEqual(report.status, .unknown)
        XCTAssertTrue(report.hasUnknownChecks)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .deviceCapabilities })?.status, .unknown)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .architecture })?.status, .unknown)
    }

    func testMinimumOSAndDeviceFamilyCanBeIncompatible() {
        let profile = makeProfile(osVersion: "27.0", family: .iPhone)
        let requirements = CompatibilityRequirements(
            minimumOSVersion: "28.0",
            supportedDeviceFamilies: [2],
            requiredCapabilities: [],
            prohibitedCapabilities: [],
            supportedPlatforms: ["iPhoneOS"],
            architectures: ["arm64"]
        )

        let report = CompatibilityChecker().evaluate(requirements: requirements, profile: profile)

        XCTAssertEqual(report.status, .incompatible)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .minimumOS })?.status, .incompatible)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .deviceFamily })?.status, .incompatible)
    }

    func testUnknownIsReturnedForMissingOrInvalidRequirements() {
        let profile = makeProfile()
        let missing = CompatibilityRequirements(
            minimumOSVersion: nil,
            supportedDeviceFamilies: nil,
            requiredCapabilities: nil,
            prohibitedCapabilities: nil,
            supportedPlatforms: nil,
            architectures: nil
        )
        let malformedVersion = CompatibilityRequirements(
            minimumOSVersion: "twenty-seven",
            supportedDeviceFamilies: [1],
            requiredCapabilities: [],
            prohibitedCapabilities: [],
            supportedPlatforms: ["iPhoneOS"],
            architectures: ["arm64"]
        )

        XCTAssertEqual(CompatibilityChecker().evaluate(requirements: missing, profile: profile).status, .unknown)
        XCTAssertEqual(CompatibilityChecker().evaluate(requirements: malformedVersion, profile: profile).status, .unknown)
    }

    func testCapabilitiesAndArchitectureUseOnlyDeclaredProfileData() {
        let requirements = CompatibilityRequirements(
            minimumOSVersion: "16.0",
            supportedDeviceFamilies: [1],
            requiredCapabilities: ["nfc"],
            prohibitedCapabilities: ["wifi"],
            supportedPlatforms: ["iPhoneOS"],
            architectures: ["arm64"]
        )
        let unknownProfile = makeProfile()
        let knownProfile = makeProfile(capabilities: ["wifi"], architectures: ["x86_64"])

        let unknownReport = CompatibilityChecker().evaluate(requirements: requirements, profile: unknownProfile)
        let manualDataReport = CompatibilityChecker().evaluate(requirements: requirements, profile: knownProfile)

        XCTAssertEqual(unknownReport.findings.first(where: { $0.criterion == .deviceCapabilities })?.status, .unknown)
        XCTAssertEqual(manualDataReport.findings.first(where: { $0.criterion == .deviceCapabilities })?.status, .unknown)
        XCTAssertEqual(manualDataReport.findings.first(where: { $0.criterion == .architecture })?.status, .unknown)
    }

    func testArm64eAndArm64eX1AreNotTreatedAsPlainArm64() {
        let requirements = CompatibilityRequirements(
            minimumOSVersion: "27.0",
            supportedDeviceFamilies: [1],
            requiredCapabilities: [],
            prohibitedCapabilities: [],
            supportedPlatforms: ["iPhoneOS"],
            architectures: ["arm64e.x1"]
        )
        let profile = makeProfile(architectures: ["arm64e"])

        let report = CompatibilityChecker().evaluate(requirements: requirements, profile: profile)

        XCTAssertEqual(report.findings.first(where: { $0.criterion == .architecture })?.status, .unknown)
    }

    func testCatalogMetadataDoesNotGuessMissingDeviceRequirements() {
        let app = makeApp(minimumOSVersion: "16.0")
        let report = CompatibilityChecker().evaluate(
            requirements: .fromCatalog(app),
            profile: makeProfile()
        )

        XCTAssertEqual(report.status, .unknown)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .minimumOS })?.status, .compatible)
        XCTAssertEqual(report.findings.first(where: { $0.criterion == .deviceFamily })?.status, .unknown)
    }

    private func makeProfile(
        osVersion: String = "27.0",
        family: DeviceProfileFamily = .iPhone,
        capabilities: Set<String>? = nil,
        architectures: Set<String>? = nil
    ) -> DeviceProfile {
        DeviceProfile(
            id: UUID(),
            name: "Test profile",
            model: family == .iPhone ? "Generic iPhone" : "Generic iPad",
            family: family,
            osVersion: osVersion,
            availableCapabilities: capabilities,
            supportedArchitectures: architectures
        )
    }

    private func makeApp(minimumOSVersion: String?) -> AppRecord {
        AppRecord(
            id: 1,
            bundleID: "com.example.app",
            name: "Example",
            developer: "Example",
            iconURL: nil,
            version: "1.0",
            fileSizeBytes: nil,
            minimumOSVersion: minimumOSVersion
        )
    }
}

final class IPAInspectorTests: XCTestCase {
    func testValidIPAReadsMetadataAndMachOArchitecture() throws {
        let url = try writeFixtureIPA()
        defer { try? FileManager.default.removeItem(at: url) }

        let inspection = try IPAInspector().inspect(url)

        XCTAssertEqual(inspection.bundleIdentifier, "com.example.profiled")
        XCTAssertEqual(inspection.version, "2.1.0")
        XCTAssertEqual(inspection.buildNumber, "42")
        XCTAssertEqual(inspection.minimumOSVersion, "16.0")
        XCTAssertEqual(inspection.deviceFamilies, [1])
        XCTAssertEqual(inspection.requiredCapabilities, ["arm64", "wifi"])
        XCTAssertEqual(inspection.supportedPlatforms, ["iPhoneOS"])
        XCTAssertEqual(inspection.architectures, ["arm64"])
        XCTAssertEqual(inspection.archiveEntryCount, 2)
    }

    func testInspectorRejectsWrongExtensionAndCorruptedZIP() throws {
        let fixture = try Self.fixtureDataForDownload()
        let wrongExtension = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        try fixture.write(to: wrongExtension)
        defer { try? FileManager.default.removeItem(at: wrongExtension) }
        XCTAssertThrowsError(try IPAInspector().inspect(wrongExtension)) {
            XCTAssertEqual($0 as? IPAInspectionError, .notIPA)
        }

        var corrupted = fixture
        let centralDirectorySignature = Data([0x50, 0x4B, 0x01, 0x02])
        let centralDirectory = try XCTUnwrap(corrupted.range(of: centralDirectorySignature))
        corrupted[centralDirectory.lowerBound + 16] ^= 0x01
        let damagedIPA = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ipa")
        try corrupted.write(to: damagedIPA)
        defer { try? FileManager.default.removeItem(at: damagedIPA) }
        XCTAssertThrowsError(try IPAInspector().inspect(damagedIPA)) { error in
            guard case IPAInspectionError.invalidArchive(let reason) = error else {
                return XCTFail("Expected a CRC/archive error, got \(error).")
            }
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("crc"), reason)
        }
    }

    func testInspectorRequiresPayloadAndAppInfoPlist() throws {
        let (noPayload, noPayloadRoot) = try makeArchive(files: [("README.txt", Data("test".utf8))])
        defer { try? FileManager.default.removeItem(at: noPayloadRoot) }
        XCTAssertThrowsError(try IPAInspector().inspect(noPayload)) {
            XCTAssertEqual($0 as? IPAInspectionError, .missingAppInfo)
        }

        let (noInfoPlist, noInfoRoot) = try makeArchive(files: [
            ("Payload/Example.app/Example", Data([0x00, 0x01]))
        ])
        defer { try? FileManager.default.removeItem(at: noInfoRoot) }
        XCTAssertThrowsError(try IPAInspector().inspect(noInfoPlist)) {
            XCTAssertEqual($0 as? IPAInspectionError, .missingAppInfo)
        }
    }

    func testInspectorRejectsInvalidInfoPlistAndMissingExecutable() throws {
        let (invalidPlist, invalidPlistRoot) = try makeArchive(files: [
            ("Payload/Example.app/Info.plist", Data("not a property list".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: invalidPlistRoot) }
        XCTAssertThrowsError(try IPAInspector().inspect(invalidPlist)) {
            XCTAssertEqual($0 as? IPAInspectionError, .invalidInfoPlist)
        }

        let info = try makeInfoPlist()
        let (missingExecutable, missingExecutableRoot) = try makeArchive(files: [
            ("Payload/Example.app/Info.plist", info)
        ])
        defer { try? FileManager.default.removeItem(at: missingExecutableRoot) }
        XCTAssertThrowsError(try IPAInspector().inspect(missingExecutable)) {
            XCTAssertEqual($0 as? IPAInspectionError, .missingExecutable)
        }
    }

    func testInspectorRejectsInvalidMachO() throws {
        let info = try makeInfoPlist()
        let (ipa, root) = try makeArchive(files: [
            ("Payload/Example.app/Info.plist", info),
            ("Payload/Example.app/Example", Data([0x00, 0x01, 0x02, 0x03]))
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try IPAInspector().inspect(ipa)) {
            XCTAssertEqual($0 as? IPAInspectionError, .invalidExecutable)
        }
    }

    private func writeFixtureIPA() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Self.fixtureDataForDownload().write(to: url)
        return url
    }

    static func fixtureDataForDownload() throws -> Data {
        let encoded = "UEsDBBQAAAAIALIoel27S+DZXAEAAOcCAAAeAAAAUGF5bG9hZC9FeGFtcGxlLmFwcC9JbmZvLnBsaXN0fZLRboIwFIav51Mw7qXTGLMsiJmACYmbZMCSXVZ61JMV6EqZ+vYrokZRd9eec/6vX9ra423GjV+QJRb5yOxZT6YBeVowzFcjM4mn3Wdz7HTsR2/uxl+hbwiOpTLCZDILXMPsEvIqBAdCvNgzwlkQxYZmEOK/m4a5Vkq8ELLZbCxaT1lpkdWDJQllIUCq3UzDujpgMcVMfUxDv9DRVYapcjoP9jfsHHc6qXLGwd9CWim64GCTuq7bpZLa2vG3NBN1+bBvBQMGucIlgmwHtZ0FTdgSslgiB3aPEq0LqT4bz2g/0ab1LW1/N14JoQHAQk7VspBZeYpTKWm9OIEwXBc5zKNzFjlOXVAPPm2TQb+t8YY5ZlU2j+4kesNr9STw4BdTmNIM+e6GLuYKViCdnk2OyyvTJPiAnwolsAbmUkEXyFEh/HMDVGbDwZnPqbHR73jrWmzSfBmb7D+U0/kDUEsDBBQAAAAIALIoel31qLUoDQAAACAAAAAbAAAAUGF5bG9hZC9FeGFtcGxlLmFwcC9FeGFtcGxlO//r7T8eBgZGBhwAAFBLAQIUAxQAAAAIALIoel27S+DZXAEAAOcCAAAeAAAAAAAAAAAAAACAAQAAAABQYXlsb2FkL0V4YW1wbGUuYXBwL0luZm8ucGxpc3RQSwECFAMUAAAACACyKHpd9ai1KA0AAAAgAAAAGwAAAAAAAAAAAAAAgAGYAQAAUGF5bG9hZC9FeGFtcGxlLmFwcC9FeGFtcGxlUEsFBgAAAAACAAIAlQAAAN4BAAAAAA=="
        return try XCTUnwrap(Data(base64Encoded: encoded))
    }

    private func makeInfoPlist() throws -> Data {
        let values: [String: Any] = [
            "CFBundleIdentifier": "com.example.archivecheck",
            "CFBundleExecutable": "Example"
        ]
        return try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    private func makeArchive(files: [(String, Data)]) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let input = root.appendingPathComponent("input", isDirectory: true)
        let archiveURL = root.appendingPathComponent("fixture.ipa")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)

        for (path, data) in files {
            let fileURL = input.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        }

        do {
            let archive = try Archive(url: archiveURL, accessMode: .create)
            for (path, _) in files {
                try archive.addEntry(with: path, fileURL: input.appendingPathComponent(path))
            }
        }
        return (archiveURL, root)
    }
}

@MainActor
final class DownloadServiceTests: XCTestCase {
    func testUnavailableProviderDoesNotClaimAuthenticationOrMetadataProgress() async throws {
        let logger = LoggingService()
        let service = DownloadService(logger: logger)

        XCTAssertFalse(service.start(app: makeApp()))
        for _ in 0..<100 where service.tasks.first?.status.isInProgress == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(service.tasks.first?.status, .failed)
        XCTAssertTrue(logger.text.contains("internal engine unavailable"))
        XCTAssertFalse(logger.text.localizedCaseInsensitiveContains("authenticating"))
        XCTAssertFalse(logger.text.localizedCaseInsensitiveContains("fetching metadata"))
    }

    func testLateProgressCannotReplaceVerifyingState() async throws {
        let inspectionStarted = expectation(description: "IPA inspection started")
        let inspector = SuspendedIPAInspector(started: inspectionStarted)
        defer { inspector.resume() }
        let service = DownloadService(
            provider: FixtureDownloadProvider(data: try IPAInspectorTests.fixtureDataForDownload()),
            ipaInspector: inspector
        )

        XCTAssertFalse(service.start(app: makeApp()))
        let taskID = try XCTUnwrap(service.tasks.first?.id)
        await fulfillment(of: [inspectionStarted], timeout: 3)
        XCTAssertEqual(service.tasks.first?.status, .verifying)

        service.reportDownloadProgress(taskID: taskID, downloaded: 90, total: 100)

        XCTAssertEqual(service.tasks.first?.status, .verifying)
        XCTAssertEqual(service.tasks.first?.downloadedBytes, 0)

        inspector.resume()
        for _ in 0..<100 where service.tasks.first?.status.isInProgress == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(service.tasks.first?.status, .completed)
    }

    func testProgressUsesActualBytesAndCancellationReachesProvider() async throws {
        let started = expectation(description: "provider started")
        let cancelled = expectation(description: "provider observed cancellation")
        let provider = CancellationAwareDownloadProvider(started: started, cancelled: cancelled)
        let service = DownloadService(provider: provider)

        XCTAssertFalse(service.start(app: makeApp()))
        let taskID = try XCTUnwrap(service.tasks.first?.id)
        await fulfillment(of: [started], timeout: 3)

        for _ in 0..<100 where service.tasks.first?.downloadedBytes != 37 {
            await Task.yield()
        }
        let progress = try XCTUnwrap(service.tasks.first?.progress)
        XCTAssertEqual(progress, 0.37, accuracy: 0.0001)

        service.cancel(taskID: taskID)
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertEqual(service.tasks.first?.status, .cancelled)

        service.reportDownloadProgress(taskID: taskID, downloaded: 100, total: 100)
        XCTAssertEqual(service.tasks.first?.status, .cancelled)
        XCTAssertEqual(service.tasks.first?.downloadedBytes, 37)
    }

    func testDownloadCompletesOnlyAfterIPAInspectionAndSavesValidatedFile() async throws {
        let provider = FixtureDownloadProvider(data: try IPAInspectorTests.fixtureDataForDownload())
        let service = DownloadService(provider: provider)

        XCTAssertFalse(service.start(app: makeApp()))
        let taskID = try XCTUnwrap(service.tasks.first?.id)
        for _ in 0..<1_000 where service.tasks.first?.status.isInProgress == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let task = try XCTUnwrap(service.tasks.first)
        XCTAssertEqual(task.status, .completed, task.errorMessage ?? "Expected a validated IPA download.")
        let fileURL = try XCTUnwrap(task.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNoThrow(try IPAInspector().inspect(fileURL))

        try service.remove(taskID: taskID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFailureCanBeRetriedAsANewQueueTask() async throws {
        let service = DownloadService(provider: FailingDownloadProvider())
        XCTAssertFalse(service.start(app: makeApp()))
        let firstID = try XCTUnwrap(service.tasks.first?.id)
        for _ in 0..<100 where service.tasks.first?.status.isInProgress == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(service.tasks.first?.status, .failed)

        XCTAssertTrue(service.retry(taskID: firstID))
        XCTAssertEqual(service.tasks.count, 2)
        XCTAssertNotEqual(service.tasks[0].id, service.tasks[1].id)
    }

    func testTimeoutRemovesPartialIPAAndLogsConnectionFailure() async throws {
        let provider = PartialTimeoutDownloadProvider()
        let logger = LoggingService()
        let service = DownloadService(provider: provider, logger: logger)

        XCTAssertFalse(service.start(app: makeApp()))
        for _ in 0..<100 where service.tasks.first?.status.isInProgress == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(service.tasks.first?.status, .failed)
        let recordedURL = await provider.partialFileURL()
        let partialURL = try XCTUnwrap(recordedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertTrue(logger.text.contains("connection error code \(URLError.timedOut.rawValue)"))
    }

    private func makeApp() -> AppRecord {
        AppRecord(
            id: 7,
            bundleID: "com.example.test",
            name: "Test App",
            developer: "Test",
            iconURL: nil,
            version: "1.0",
            fileSizeBytes: nil,
            minimumOSVersion: "16.0"
        )
    }
}

private final class SuspendedIPAInspector: IPAInspecting, @unchecked Sendable {
    private let started: XCTestExpectation
    private let releaseInspection = DispatchSemaphore(value: 0)

    init(started: XCTestExpectation) {
        self.started = started
    }

    func inspect(_ url: URL) throws -> IPAInspection {
        started.fulfill()
        _ = releaseInspection.wait(timeout: .now() + 5)
        return try IPAInspector().inspect(url)
    }

    func resume() {
        releaseInspection.signal()
    }
}

private final class CancellationAwareDownloadProvider: AppStoreDownloadProviding, @unchecked Sendable {
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = app
        _ = destination
        progress(37, 100)
        started.fulfill()
        try await withTaskCancellationHandler {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw AppStoreDownloadError.directEngineUnavailable
        } onCancel: {
            cancelled.fulfill()
        }
    }
}

private struct FixtureDownloadProvider: AppStoreDownloadProviding {
    let data: Data

    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = app
        try data.write(to: destination, options: .atomic)
        progress(Int64(data.count), Int64(data.count))
        return destination
    }
}

private struct FailingDownloadProvider: AppStoreDownloadProviding {
    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = (app, destination, progress)
        throw URLError(.notConnectedToInternet)
    }
}

private actor PartialTimeoutDownloadProvider: AppStoreDownloadProviding {
    private var recordedPartialFileURL: URL?

    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = app
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: destination)
        recordedPartialFileURL = destination
        progress(4, 100)
        throw URLError(.timedOut)
    }

    func partialFileURL() -> URL? {
        recordedPartialFileURL
    }
}
