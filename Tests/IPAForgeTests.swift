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
    }

    func testConnectionRecognizesOnlyAnisetteV3ClientInfo() async {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.responseData = Data(#"{"X-Apple-I-MD":"otp","X-Apple-I-MD-M":"machine"}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AnisetteService(session: URLSession(configuration: configuration))
        let result = await service.testConnection(serverURL: "https://anisette.example")
        XCTAssertEqual(result.state, .responded)
        XCTAssertNotNil(result.durationMilliseconds)

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

    func testFetchV3HeadersReusesEncryptedIdentityAndCallsV3Endpoints() async throws {
        let identity = StoredAnisetteIdentity(
            identifier: "stable-local-id",
            deviceID: UUID().uuidString,
            adiPB: Data([1, 2, 3]).base64EncodedString()
        )
        let identityStore = MockAnisetteIdentityStore(identity: identity)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
        MockURLProtocol.requests = []
        MockURLProtocol.responseHandler = { request in
            switch request.url?.path {
            case "/v3/client_info":
                return Data(#"{"client_info":"client","user_agent":"agent","serial":"0"}"#.utf8)
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
}

@MainActor
final class AnisetteServerStoreTests: XCTestCase {
    func testSideStoreIsDefaultAndCustomSelectionPersists() async throws {
        configureValidAnisetteResponse()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        XCTAssertEqual(store.servers.map(\.name), ["SideStore", "jkcoxson"])
        let sideStoreID = try XCTUnwrap(
            store.servers.first(where: { $0.name == "SideStore" })?.id
        )
        XCTAssertEqual(store.selectedServerID, sideStoreID)
        XCTAssertTrue(store.servers.allSatisfy {
            store.probeResults[$0.id]?.state == .unchecked
        })

        let id = try await store.add(name: "  Personal  ", url: "https://personal.example/")
        XCTAssertEqual(store.servers.last?.name, "Personal")
        XCTAssertEqual(store.probeResults[id]?.state, .validV3)
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

    func testRejectsInvalidDuplicateAndAllowsSelectingUnavailableServer() async throws {
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

    func testAllServersUnavailableKeepsDefaultWithoutFailingOver() async throws {
        MockURLProtocol.stubbedError = URLError(.cannotConnectToHost)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        let sideStoreID = try XCTUnwrap(
            store.servers.first(where: { $0.name == "SideStore" })?.id
        )

        for server in store.servers {
            await store.refresh(serverID: server.id)
        }
        XCTAssertTrue(store.hasFinishedInitialChecks)
        XCTAssertFalse(store.hasUsableServer)
        XCTAssertEqual(store.selectedServerID, sideStoreID)
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
            #"{"client_info":"v3 client","user_agent":"v3 agent"}"#.utf8
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

@MainActor
final class LoggingServiceTests: XCTestCase {
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
        XCTAssertNil(try vault.anisetteIdentity(forServer: "https://another.example"))
        XCTAssertFalse(keychain.values.values.contains {
            String(decoding: $0, as: UTF8.self).contains(identity.adiPB)
        })

        try vault.clearAnisetteIdentity(forServer: serverURL)
        XCTAssertNil(try vault.anisetteIdentity(forServer: serverURL))
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

    func testBundleIDSearchUsesLookupEndpoint() async throws {
        MockURLProtocol.responseData = Data(#"{"results":[{"trackId":42,"bundleId":"com.example.app","trackName":"Example","sellerName":"Example Inc.","version":"1.2","artworkUrl100":"https://example.com/icon.png"}]}"#.utf8)
        MockURLProtocol.statusCode = 200
        MockURLProtocol.stubbedError = nil
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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = AppStoreService(session: URLSession(configuration: configuration))

        let apps = try await service.search("123456", country: "us")

        XCTAssertEqual(apps.map(\.id), [123456])
    }
}

final class IPAForgeVersionTests: XCTestCase {
    func testVersionUsesShortVersionAndCommitHash() {
        XCTAssertEqual(
            IPAForgeVersion.displayValue(shortVersion: "1.0.0", commitHash: "a1b2c3d"),
            "1.0.0 (a1b2c3d)"
        )
    }

    func testVersionUsesFallbackWhenCommitHashIsMissing() {
        XCTAssertEqual(
            IPAForgeVersion.displayValue(shortVersion: nil, commitHash: nil),
            "1.0.0 (unknown)"
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

    init(identity: StoredAnisetteIdentity?) {
        self.identity = identity
    }

    func loadIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity? {
        identity
    }

    func saveIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws {
        self.identity = identity
    }

    func clearIdentity(forServer serverURL: String) throws {
        identity = nil
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
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseHandler?(request) ?? Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
