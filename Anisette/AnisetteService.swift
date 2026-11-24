import Foundation
import Combine
import CryptoKit
import Dispatch

enum AnisetteProbeState: Equatable {
    case unchecked
    case invalidURL
    case noResponse
    case responded
    case validV3

    var title: String {
        switch self {
        case .unchecked: return "Chưa kiểm tra"
        case .invalidURL: return "URL không hợp lệ"
        case .noResponse: return "Không phản hồi"
        case .responded: return "Có phản hồi · chưa xác minh Anisette"
        case .validV3: return "Metadata Anisette v3 hợp lệ"
        }
    }

    var isUsable: Bool { self == .validV3 }
}

struct AnisetteProbeResult: Equatable {
    let state: AnisetteProbeState
    let durationMilliseconds: Int?
}

struct AnisetteServer: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: String
    let isDefault: Bool

    init(id: UUID = UUID(), name: String, url: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.isDefault = isDefault
    }
}

enum AnisetteServerError: LocalizedError, Equatable {
    case invalidURL
    case duplicateURL
    case notFound
    case cannotModifyDefault

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Nhập một URL HTTPS hợp lệ."
        case .duplicateURL: return "Anisette Server này đã có trong danh sách."
        case .notFound: return "Không tìm thấy Anisette Server."
        case .cannotModifyDefault: return "Không thể sửa hoặc xóa nguồn mặc định."
        }
    }
}

enum AnisetteURLValidator {
    static func validatedBaseURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            return nil
        }
        return url
    }

    static func normalized(_ value: String) -> String? {
        guard let url = validatedBaseURL(value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 443 { components.port = nil }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        return components.string
    }

    static func hasSameHTTPSOrigin(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second,
              first.scheme?.lowercased() == "https",
              second.scheme?.lowercased() == "https",
              first.host?.lowercased() == second.host?.lowercased() else {
            return false
        }
        return (first.port ?? 443) == (second.port ?? 443)
    }
}

protocol AnisetteServiceProtocol {
    func testConnection(serverURL: String) async -> AnisetteProbeResult
    func clearIdentity(forServer serverURL: String) throws
}

struct AnisetteV3ClientInfo {
    let clientInfo: String
    let userAgent: String
    let serialNumber: String
}

struct AnisetteV3Error: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

protocol AnisetteIdentityStoring {
    func loadIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity?
    func saveIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws
    func clearIdentity(forServer serverURL: String) throws
}

extension AppleAccountVault: AnisetteIdentityStoring {
    func loadIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity? {
        try anisetteIdentity(forServer: serverURL)
    }

    func saveIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws {
        try saveAnisetteIdentity(identity, forServer: serverURL)
    }

    func clearIdentity(forServer serverURL: String) throws {
        try clearAnisetteIdentity(forServer: serverURL)
    }
}

protocol AnisetteWebSocketConnection {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func cancel()
}

protocol AnisetteWebSocketCreating {
    func connect(to url: URL) -> AnisetteWebSocketConnection
}

private final class URLSessionAnisetteWebSocketFactory: AnisetteWebSocketCreating {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func connect(to url: URL) -> AnisetteWebSocketConnection {
        URLSessionAnisetteWebSocket(session.webSocketTask(with: url))
    }
}

private final class AnisetteSameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard AnisetteURLValidator.hasSameHTTPSOrigin(response.url, request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private final class URLSessionAnisetteWebSocket: AnisetteWebSocketConnection {
    private let task: URLSessionWebSocketTask

    init(_ task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let value):
            return value
        case .data(let value):
            guard let text = String(data: value, encoding: .utf8) else {
                throw AnisetteV3Error(message: "Anisette Server returned an invalid WebSocket message.")
            }
            return text
        @unknown default:
            throw AnisetteV3Error(message: "Anisette Server returned an unsupported WebSocket message.")
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

final class AnisetteService: AnisetteServiceProtocol {
    static let defaultURL = "https://mac-ani.jkcoxson.com"
    static let defaultServers = [
        AnisetteServer(name: "SideStore", url: "https://ani.sidestore.io", isDefault: true),
        AnisetteServer(name: "jkcoxson", url: defaultURL, isDefault: true)
    ]

    private let session: URLSession
    private let redirectDelegate: AnisetteSameOriginRedirectDelegate?
    private let identityStore: AnisetteIdentityStoring?
    private let webSocketFactory: AnisetteWebSocketCreating

    init(
        session: URLSession? = nil,
        identityStore: AnisetteIdentityStoring? = nil,
        webSocketFactory: AnisetteWebSocketCreating? = nil
    ) {
        let resolvedSession: URLSession
        let resolvedRedirectDelegate: AnisetteSameOriginRedirectDelegate?
        if let session {
            resolvedSession = session
            resolvedRedirectDelegate = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            let delegate = AnisetteSameOriginRedirectDelegate()
            resolvedRedirectDelegate = delegate
            resolvedSession = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
        }
        self.session = resolvedSession
        self.redirectDelegate = resolvedRedirectDelegate
        self.identityStore = identityStore
        self.webSocketFactory = webSocketFactory
            ?? URLSessionAnisetteWebSocketFactory(session: resolvedSession)
    }

    func testConnection(serverURL: String) async -> AnisetteProbeResult {
        guard let baseURL = AnisetteURLValidator.validatedBaseURL(serverURL) else {
            return AnisetteProbeResult(state: .invalidURL, durationMilliseconds: nil)
        }

        var request = URLRequest(url: Self.endpoint("client_info", at: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000)
            guard let http = response as? HTTPURLResponse else {
                return AnisetteProbeResult(state: .responded, durationMilliseconds: elapsed)
            }
            guard AnisetteURLValidator.hasSameHTTPSOrigin(http.url, request.url) else {
                return AnisetteProbeResult(state: .responded, durationMilliseconds: elapsed)
            }
            guard (200...299).contains(http.statusCode) else {
                return AnisetteProbeResult(state: .responded, durationMilliseconds: elapsed)
            }
            let state = Self.isValidV3ClientInfo(data) ? AnisetteProbeState.validV3 : .responded
            return AnisetteProbeResult(state: state, durationMilliseconds: elapsed)
        } catch {
            return AnisetteProbeResult(state: .noResponse, durationMilliseconds: nil)
        }
    }

    func clearIdentity(forServer serverURL: String) throws {
        guard let normalizedURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        try identityStore?.clearIdentity(forServer: normalizedURL)
    }

    private static func isValidV3ClientInfo(_ data: Data) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return nonEmptyString(raw["client_info"] as? String) != nil
            && nonEmptyString(raw["user_agent"] as? String) != nil
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func endpoint(_ name: String, at baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v3").appendingPathComponent(name)
    }
}

extension AnisetteService {
    func fetchAnisetteV3(serverURL: String) async throws -> [String: String] {
        guard let baseURL = AnisetteURLValidator.validatedBaseURL(serverURL),
              let normalizedServerURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        guard let identityStore else {
            throw AnisetteV3Error(message: "Secure Anisette identity storage is unavailable.")
        }

        let clientInfo = try await fetchClientInfo(from: baseURL)
        let identity: StoredAnisetteIdentity
        if let storedIdentity = try identityStore.loadIdentity(forServer: normalizedServerURL) {
            try storedIdentity.validate()
            identity = storedIdentity
        } else {
            identity = try await provisionIdentity(
                at: baseURL,
                clientInfo: clientInfo
            )
            try identityStore.saveIdentity(identity, forServer: normalizedServerURL)
        }

        let response = try await fetchHeaders(at: baseURL, identity: identity)
        guard let oneTimePassword = Self.nonEmptyString(response["X-Apple-I-MD"]),
              let machineID = Self.nonEmptyString(response["X-Apple-I-MD-M"]) else {
            throw AnisetteV3Error(message: "Anisette Server returned incomplete v3 headers.")
        }

        var headers = response
        headers["X-Apple-I-MD"] = oneTimePassword
        headers["X-Apple-I-MD-M"] = machineID
        headers["X-Apple-I-MD-LU"] = identity.identifier
        headers["X-Mme-Device-Id"] = identity.deviceID
        headers["X-MMe-Client-Info"] = clientInfo.clientInfo
        headers["User-Agent"] = clientInfo.userAgent
        headers["X-Apple-I-SRL-NO"] = clientInfo.serialNumber
        headers["X-Apple-Client-Time"] = Self.appleClientTime()
        headers["X-Apple-I-TimeZone"] = TimeZone.current.abbreviation() ?? "UTC"
        headers["X-Apple-Locale"] = Locale.current.identifier
        return headers
    }

    private func fetchClientInfo(from baseURL: URL) async throws -> AnisetteV3ClientInfo {
        let data = try await perform(URLRequest(url: Self.endpoint("client_info", at: baseURL)))
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientInfo = Self.validHeaderValue(raw["client_info"] as? String),
              let userAgent = Self.validHeaderValue(raw["user_agent"] as? String) else {
            throw AnisetteV3Error(message: "Anisette Server does not provide v3 client information.")
        }
        return AnisetteV3ClientInfo(
            clientInfo: clientInfo,
            userAgent: userAgent,
            serialNumber: Self.validHeaderValue(raw["serial"] as? String) ?? "0"
        )
    }

    private func fetchHeaders(
        at baseURL: URL,
        identity: StoredAnisetteIdentity
    ) async throws -> [String: String] {
        var request = URLRequest(url: Self.endpoint("get_headers", at: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": identity.identifier,
            "adi_pb": identity.adiPB
        ])
        let data = try await perform(request)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnisetteV3Error(message: "Anisette Server returned an invalid v3 response.")
        }
        var headers: [String: String] = [:]
        for key in ["X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-RINFO"] {
            if let value = Self.validHeaderValue(raw[key] as? String) {
                headers[key] = value
            }
        }
        guard headers["X-Apple-I-MD"] != nil, headers["X-Apple-I-MD-M"] != nil else {
            throw AnisetteV3Error(message: "Anisette Server rejected the v3 request.")
        }
        return headers
    }

    private func provisionIdentity(
        at baseURL: URL,
        clientInfo: AnisetteV3ClientInfo
    ) async throws -> StoredAnisetteIdentity {
        let randomIdentifier = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let identifier = SHA256.hash(data: Data(randomIdentifier.base64EncodedString().utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        let deviceID = UUID().uuidString.uppercased()
        let provisioningURLs = try await fetchProvisioningURLs(
            identifier: identifier,
            deviceID: deviceID,
            clientInfo: clientInfo
        )

        var socketComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        socketComponents?.scheme = "wss"
        socketComponents?.path = Self.endpointPath("provisioning_session", basePath: baseURL.path)
        guard let socketURL = socketComponents?.url else {
            throw AnisetteV3Error(message: "Anisette Server WebSocket URL is invalid.")
        }
        let connection = webSocketFactory.connect(to: socketURL)
        defer { connection.cancel() }

        var adiPB: String?
        for _ in 0..<8 {
            let message = try await receiveProvisioningMessage(from: connection)
            guard let json = try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
                  let result = json["result"] as? String else {
                throw AnisetteV3Error(message: "Anisette Server sent an invalid provisioning message.")
            }
            switch result {
            case "GiveIdentifier":
                try await send(["identifier": identifier], through: connection)
            case "GiveStartProvisioningData":
                let spim = try await startProvisioning(
                    at: provisioningURLs.start,
                    identifier: identifier,
                    deviceID: deviceID,
                    clientInfo: clientInfo
                )
                try await send(["spim": spim], through: connection)
            case "GiveEndProvisioningData":
                guard let cpim = Self.nonEmptyString(json["cpim"] as? String) else {
                    throw AnisetteV3Error(message: "Anisette Server omitted Apple provisioning data.")
                }
                let provisioningResult = try await finishProvisioning(
                    at: provisioningURLs.finish,
                    cpim: cpim,
                    identifier: identifier,
                    deviceID: deviceID,
                    clientInfo: clientInfo
                )
                try await send([
                    "ptm": provisioningResult.ptm,
                    "tk": provisioningResult.trustKey
                ], through: connection)
            case "ProvisioningSuccess":
                adiPB = Self.nonEmptyString(json["adi_pb"] as? String)
            case "Timeout":
                throw AnisetteV3Error(message: "Anisette Server provisioning timed out.")
            default:
                throw AnisetteV3Error(message: "Anisette Server rejected v3 provisioning.")
            }
            if adiPB != nil {
                break
            }
        }

        guard let adiPB, Data(base64Encoded: adiPB)?.isEmpty == false else {
            throw AnisetteV3Error(message: "Anisette Server did not complete v3 provisioning.")
        }
        let identity = StoredAnisetteIdentity(
            identifier: identifier,
            deviceID: deviceID,
            adiPB: adiPB
        )
        try identity.validate()
        return identity
    }

    private func fetchProvisioningURLs(
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo
    ) async throws -> (start: URL, finish: URL) {
        guard let lookupURL = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup") else {
            throw AnisetteV3Error(message: "Apple provisioning endpoint is invalid.")
        }
        let data = try await perform(appleRequest(
            url: lookupURL,
            method: "GET",
            body: nil,
            identifier: identifier,
            deviceID: deviceID,
            clientInfo: clientInfo
        ))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urls = plist["urls"] as? [String: String],
              let startString = urls["midStartProvisioning"],
              let finishString = urls["midFinishProvisioning"],
              let startURL = URL(string: startString),
              let finishURL = URL(string: finishString),
              startURL.scheme?.lowercased() == "https",
              finishURL.scheme?.lowercased() == "https",
              Self.isAppleHost(startURL.host),
              Self.isAppleHost(finishURL.host) else {
            throw AnisetteV3Error(message: "Apple did not return valid Anisette provisioning endpoints.")
        }
        return (startURL, finishURL)
    }

    private func startProvisioning(
        at url: URL,
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo
    ) async throws -> String {
        let data = try await perform(appleRequest(
            url: url,
            method: "POST",
            body: try provisioningPlist(request: [:]),
            identifier: identifier,
            deviceID: deviceID,
            clientInfo: clientInfo
        ))
        guard let response = try appleResponse(from: data),
              let spim = Self.nonEmptyString(response["spim"] as? String) else {
            throw AnisetteV3Error(message: "Apple returned invalid start-provisioning data.")
        }
        return spim
    }

    private func finishProvisioning(
        at url: URL,
        cpim: String,
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo
    ) async throws -> (ptm: String, trustKey: String) {
        let data = try await perform(appleRequest(
            url: url,
            method: "POST",
            body: try provisioningPlist(request: ["cpim": cpim]),
            identifier: identifier,
            deviceID: deviceID,
            clientInfo: clientInfo
        ))
        guard let response = try appleResponse(from: data),
              let ptm = Self.nonEmptyString(response["ptm"] as? String),
              let trustKey = Self.nonEmptyString(response["tk"] as? String) else {
            throw AnisetteV3Error(message: "Apple returned invalid finish-provisioning data.")
        }
        return (ptm, trustKey)
    }

    private func appleRequest(
        url: URL,
        method: String,
        body: Data?,
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue(clientInfo.clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(clientInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(identifier, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(deviceID, forHTTPHeaderField: "X-Mme-Device-Id")
        request.setValue(Self.appleClientTime(), forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation() ?? "UTC", forHTTPHeaderField: "X-Apple-I-TimeZone")
        request.httpBody = body
        return request
    }

    private func provisioningPlist(request: [String: String]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["Header": [String: String](), "Request": request],
            format: .xml,
            options: 0
        )
    }

    private func appleResponse(from data: Data) throws -> [String: Any]? {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["Response"] as? [String: Any]
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              AnisetteURLValidator.hasSameHTTPSOrigin(http.url, request.url),
              (200...299).contains(http.statusCode) else {
            throw AnisetteV3Error(message: "An Anisette or Apple service returned an unsuccessful response.")
        }
        return data
    }

    private func receiveProvisioningMessage(
        from connection: AnisetteWebSocketConnection
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await connection.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw AnisetteV3Error(message: "Anisette Server provisioning timed out.")
            }
            defer { group.cancelAll() }
            guard let message = try await group.next() else {
                throw AnisetteV3Error(message: "Anisette Server closed the provisioning session.")
            }
            return message
        }
    }

    private func send(
        _ values: [String: String],
        through connection: AnisetteWebSocketConnection
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: values)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AnisetteV3Error(message: "Could not encode the provisioning message.")
        }
        try await connection.send(text)
    }

    private static func endpointPath(_ name: String, basePath: String) -> String {
        let prefix = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        return "\(prefix)/v3/\(name)"
    }

    private static func appleClientTime() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private static func validHeaderValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 4096,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private static func isAppleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com")
    }
}

@MainActor
final class AnisetteServerStore: ObservableObject {
    @Published private(set) var servers: [AnisetteServer]
    @Published private(set) var probeResults: [UUID: AnisetteProbeResult] = [:]
    @Published private(set) var checkingIDs: Set<UUID> = []
    @Published private(set) var selectedServerID: UUID?

    private let service: AnisetteServiceProtocol
    private let defaults: UserDefaults
    private let serversKey = "anisette.servers.v1"
    private let selectedIDKey = "anisette.selectedServerID.v1"
    private let refreshInterval: TimeInterval = 30
    private var probeDates: [UUID: Date] = [:]

    init(service: AnisetteServiceProtocol, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        if let stored = defaults.array(forKey: serversKey) as? [[String: Any]],
           let persisted = Self.decodeServers(stored), !persisted.isEmpty {
            servers = persisted
        } else {
            var initialServers = AnisetteService.defaultServers
            if let legacyURL = defaults.string(forKey: "anisetteServerURL"),
               let normalized = AnisetteURLValidator.normalized(legacyURL),
               !initialServers.contains(where: {
                   AnisetteURLValidator.normalized($0.url) == normalized
               }) {
                initialServers.append(AnisetteServer(
                    name: URL(string: normalized)?.host ?? "Server",
                    url: normalized
                ))
            }
            servers = initialServers
            persistServers()
        }
        if let storedID = defaults.string(forKey: selectedIDKey) {
            let id = UUID(uuidString: storedID)
            selectedServerID = id.flatMap { value in
                servers.contains(where: { $0.id == value }) ? value : nil
            }
            if selectedServerID == nil {
                defaults.removeObject(forKey: selectedIDKey)
            }
        }
        selectSideStoreIfNeeded()
        for server in servers {
            probeResults[server.id] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
        }
    }

    var selectedServer: AnisetteServer? {
        servers.first { $0.id == selectedServerID }
    }

    var hasFinishedInitialChecks: Bool {
        checkingIDs.isEmpty && servers.allSatisfy {
            probeResults[$0.id]?.state != .unchecked
        }
    }

    var hasUsableServer: Bool {
        servers.contains { probeResults[$0.id]?.state.isUsable == true }
    }

    func add(name: String, url: String) async throws -> UUID {
        guard let normalizedURL = AnisetteURLValidator.normalized(url) else {
            throw AnisetteServerError.invalidURL
        }
        guard !servers.contains(where: {
            AnisetteURLValidator.normalized($0.url) == normalizedURL
        }) else {
            throw AnisetteServerError.duplicateURL
        }
        let host = URL(string: normalizedURL)?.host ?? "Server"
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = AnisetteServer(
            name: cleanName.isEmpty ? host : cleanName,
            url: normalizedURL
        )
        servers.append(server)
        probeResults[server.id] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
        persistServers()
        await refresh(serverID: server.id)
        return server.id
    }

    func update(serverID: UUID, name: String, url: String) async throws {
        guard let index = servers.firstIndex(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        guard !servers[index].isDefault else { throw AnisetteServerError.cannotModifyDefault }
        guard let normalizedURL = AnisetteURLValidator.normalized(url) else {
            throw AnisetteServerError.invalidURL
        }
        guard !servers.enumerated().contains(where: {
            $0.offset != index && AnisetteURLValidator.normalized($0.element.url) == normalizedURL
        }) else {
            throw AnisetteServerError.duplicateURL
        }
        let oldURL = servers[index].url
        let oldNormalizedURL = AnisetteURLValidator.normalized(oldURL)
        if let oldNormalizedURL, oldNormalizedURL != normalizedURL {
            try service.clearIdentity(forServer: oldNormalizedURL)
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        servers[index].name = cleanName.isEmpty ? (URL(string: normalizedURL)?.host ?? "Server") : cleanName
        servers[index].url = normalizedURL
        if oldURL != normalizedURL {
            probeResults[serverID] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
            if selectedServerID == serverID {
                selectID(nil)
                selectSideStoreIfNeeded()
            }
        }
        persistServers()
        await refresh(serverID: serverID)
    }

    func delete(serverID: UUID) throws {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        guard !server.isDefault else { throw AnisetteServerError.cannotModifyDefault }
        try service.clearIdentity(forServer: server.url)
        servers.removeAll { $0.id == serverID }
        probeResults.removeValue(forKey: serverID)
        if selectedServerID == serverID {
            selectID(nil)
            selectSideStoreIfNeeded()
        }
        persistServers()
    }

    func select(serverID: UUID) throws {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        selectID(serverID)
    }

    func refresh(serverID: UUID) async {
        guard let server = servers.first(where: { $0.id == serverID }),
              !checkingIDs.contains(serverID) else { return }
        checkingIDs.insert(serverID)
        probeResults[serverID] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
        await performProbe(server: server)
    }

    func refreshAll(force: Bool = false) {
        for server in servers {
            guard !checkingIDs.contains(server.id) else { continue }
            if !force,
               let lastProbe = probeDates[server.id],
               Date().timeIntervalSince(lastProbe) < refreshInterval {
                continue
            }
            checkingIDs.insert(server.id)
            probeResults[server.id] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
            Task { await performProbe(server: server) }
        }
    }

    private func performProbe(server: AnisetteServer) async {
        let result = await service.testConnection(serverURL: server.url)
        probeResults[server.id] = result
        probeDates[server.id] = Date()
        checkingIDs.remove(server.id)
    }

    private func selectID(_ id: UUID?) {
        selectedServerID = id
        if let id {
            defaults.set(id.uuidString, forKey: selectedIDKey)
        } else {
            defaults.removeObject(forKey: selectedIDKey)
        }
    }

    private func selectSideStoreIfNeeded() {
        guard selectedServerID == nil,
              let sideStore = AnisetteService.defaultServers.first(where: { $0.name == "SideStore" }),
              let server = servers.first(where: {
                  AnisetteURLValidator.normalized($0.url) ==
                    AnisetteURLValidator.normalized(sideStore.url)
              }) else {
            return
        }
        selectID(server.id)
    }

    private func persistServers() {
        defaults.set(servers.map {
            [
                "id": $0.id.uuidString,
                "name": $0.name,
                "url": $0.url,
                "isDefault": $0.isDefault
            ] as [String: Any]
        }, forKey: serversKey)
    }

    private static func decodeServers(_ stored: [[String: Any]]) -> [AnisetteServer]? {
        let decoded = stored.compactMap { item -> AnisetteServer? in
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = item["name"] as? String,
                  let url = item["url"] as? String else {
                return nil
            }
            return AnisetteServer(
                id: id,
                name: name,
                url: url,
                isDefault: item["isDefault"] as? Bool ?? false
            )
        }
        return decoded.count == stored.count ? decoded : nil
    }
}
