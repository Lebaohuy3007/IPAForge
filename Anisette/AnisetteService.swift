import Foundation
import Combine
import CryptoKit

enum AnisetteProbeState: Equatable {
    case invalidURL
    case noResponse
    case responded
    case validV3

    var isUsable: Bool { self == .validV3 }
}

struct AnisetteProbeResult: Equatable {
    let state: AnisetteProbeState
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

    static func hasSameWSSOrigin(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second,
              ["wss", "https"].contains(first.scheme?.lowercased() ?? ""),
              second.scheme?.lowercased() == "wss",
              first.host?.lowercased() == second.host?.lowercased() else {
            return false
        }
        return (first.port ?? 443) == (second.port ?? 443)
    }
}

protocol AnisetteServiceProtocol {
    func testConnection(serverURL: String) async -> AnisetteProbeResult
    func isServerApproved(serverURL: String) throws -> Bool
    func approveServer(serverURL: String) throws
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
    func isServerApproved(forServer serverURL: String) throws -> Bool
    func approveServer(forServer serverURL: String) throws
    func clearIdentity(forServer serverURL: String) throws
}

extension AppleAccountVault: AnisetteIdentityStoring {
    func loadIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity? {
        try anisetteIdentity(forServer: serverURL)
    }

    func saveIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws {
        try saveAnisetteIdentity(identity, forServer: serverURL)
    }

    func isServerApproved(forServer serverURL: String) throws -> Bool {
        try isAnisetteServerApproved(forServer: serverURL)
    }

    func approveServer(forServer serverURL: String) throws {
        try approveAnisetteServer(forServer: serverURL)
    }

    func clearIdentity(forServer serverURL: String) throws {
        try clearAnisetteIdentity(forServer: serverURL)
    }
}

protocol AnisetteWebSocketConnection {
    var response: URLResponse? { get }
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

extension AnisetteWebSocketConnection {
    var response: URLResponse? { nil }
}

private final class AnisetteSameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let sameOrigin = AnisetteURLValidator.hasSameHTTPSOrigin(response.url, request.url)
            || AnisetteURLValidator.hasSameWSSOrigin(response.url, request.url)
        guard sameOrigin else {
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

    var response: URLResponse? { task.response }

    func send(_ text: String) async throws {
        try await withTaskCancellationHandler {
            try await task.send(.string(text))
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    func receive() async throws -> String {
        let message = try await withTaskCancellationHandler {
            try await task.receive()
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
        switch message {
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
        AnisetteServer(name: "SideStore (New)", url: "https://new.ani.sidestore.io", isDefault: true),
        AnisetteServer(name: "jkcoxson", url: defaultURL, isDefault: true),
        AnisetteServer(name: "iloader", url: "https://ani.iloader.app", isDefault: true),
        AnisetteServer(name: "StikStore", url: "https://ani3.stikstore.app", isDefault: true)
    ]

    private let session: URLSession
    private let redirectDelegate: AnisetteSameOriginRedirectDelegate?
    private let identityStore: AnisetteIdentityStoring?
    private let webSocketFactory: AnisetteWebSocketCreating
    private let logger: LoggingService?

    init(
        session: URLSession? = nil,
        identityStore: AnisetteIdentityStoring? = nil,
        webSocketFactory: AnisetteWebSocketCreating? = nil,
        logger: LoggingService? = nil
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
        self.logger = logger
    }

    func testConnection(serverURL: String) async -> AnisetteProbeResult {
        guard let baseURL = AnisetteURLValidator.validatedBaseURL(serverURL) else {
            return AnisetteProbeResult(state: .invalidURL)
        }

        let correlationID = UUID()
        let clientInfoResult = await probe(
            url: Self.endpoint("client_info", at: baseURL),
            isValidResponse: Self.isValidV3ClientInfo,
            correlationID: correlationID,
            provider: baseURL.host ?? "Anisette Server",
            stage: "Client Info Probe"
        )
        guard clientInfoResult.state != .validV3 else {
            return clientInfoResult
        }
        guard clientInfoResult.state == .responded else {
            return clientInfoResult
        }

        let rootResult = await probe(
            url: baseURL,
            isValidResponse: Self.isValidV3HeadersResponse,
            correlationID: correlationID,
            provider: baseURL.host ?? "Anisette Server",
            stage: "Server Root Probe"
        )
        return rootResult.state == .validV3 ? rootResult : clientInfoResult
    }

    private func probe(
        url: URL,
        isValidResponse: (Data) -> Bool,
        correlationID: UUID,
        provider: String,
        stage: String
    ) async -> AnisetteProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "The server response was not HTTP.",
                    nextAction: "Check the configured Anisette Server response.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .error
                )
                return AnisetteProbeResult(state: .responded)
            }
            guard AnisetteURLValidator.hasSameHTTPSOrigin(http.url, request.url) else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "The request redirected outside its configured HTTPS origin.",
                    nextAction: "Use a server that keeps the request on the same HTTPS origin.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .error
                )
                return AnisetteProbeResult(state: .responded)
            }
            guard (200...299).contains(http.statusCode) else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                reason: Self.httpFailureReason(http.statusCode),
                    nextAction: "Check the server status before selecting it.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .warning
                )
                return AnisetteProbeResult(state: .responded)
            }
            let valid = isValidResponse(data)
            await recordNetworkRequest(
                request: request,
                response: response,
                data: data,
                provider: provider,
                stage: stage,
                parsing: valid ? "PASS" : "FAIL",
                validation: valid ? "PASS" : "FAIL",
                result: valid ? "PASS" : "PARTIAL",
                reason: valid ? "Response matches the expected Anisette v3 shape." : "Server responded but did not match the expected Anisette v3 shape.",
                nextAction: valid ? "None." : "Check the server's Anisette v3 compatibility.",
                startedAt: startedAt,
                correlationID: correlationID,
                level: valid ? .success : .warning
            )
            let state = valid ? AnisetteProbeState.validV3 : .responded
            return AnisetteProbeResult(state: state)
        } catch {
            let nsError = error as NSError
            let cancelled = error is CancellationError || nsError.code == NSURLErrorCancelled
            await recordNetworkRequest(
                request: request,
                response: nil,
                data: nil,
                provider: provider,
                stage: stage,
                parsing: "NOT RUN",
                validation: "NOT RUN",
                result: cancelled ? "CANCELLED" : "FAIL",
                reason: Self.networkFailureReason(error),
                nextAction: cancelled ? "Start a new probe only if needed." : "Check the network connection and server host.",
                startedAt: startedAt,
                correlationID: correlationID,
                level: cancelled ? .warning : .error,
                error: error
            )
            return AnisetteProbeResult(state: .noResponse)
        }
    }

    func clearIdentity(forServer serverURL: String) throws {
        guard let normalizedURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        try identityStore?.clearIdentity(forServer: normalizedURL)
    }

    func isServerApproved(serverURL: String) throws -> Bool {
        guard let normalizedURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        return try identityStore?.isServerApproved(forServer: normalizedURL) ?? false
    }

    func approveServer(serverURL: String) throws {
        guard let normalizedURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        guard let identityStore else {
            throw AnisetteV3Error(message: "Secure Anisette identity storage is unavailable.")
        }
        try identityStore.approveServer(forServer: normalizedURL)
    }

    private static func isValidV3ClientInfo(_ data: Data) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return nonEmptyString(raw["client_info"] as? String) != nil
            && nonEmptyString(raw["user_agent"] as? String) != nil
    }

    private static func isValidV3HeadersResponse(_ data: Data) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return nonEmptyString(raw["X-Apple-I-MD"] as? String) != nil
            && nonEmptyString(raw["X-Apple-I-MD-M"] as? String) != nil
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func endpoint(_ name: String, at baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v3").appendingPathComponent(name)
    }

    private func recordNetworkRequest(
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        provider: String,
        stage: String,
        parsing: String,
        validation: String,
        result: String,
        reason: String,
        nextAction: String,
        startedAt: TimeInterval,
        correlationID: UUID,
        level: LogLevel,
        error: Error? = nil
    ) async {
        let http = response as? HTTPURLResponse
        let errorInfo: NSError?
        if let error {
            errorInfo = error as NSError
        } else {
            errorInfo = nil
        }
        let requestID = Self.safeRequestID(http?.value(forHTTPHeaderField: "X-Apple-Request-UUID"))
        let diagnostics = AppStoreRequestDiagnostics(
            method: request.httpMethod ?? "GET",
            endpoint: Self.safeEndpoint(request.url),
            httpStatus: http?.statusCode,
            durationMilliseconds: max(0, Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)),
            responseContentType: Self.safeLogField(http?.value(forHTTPHeaderField: "Content-Type") ?? response?.mimeType),
            responseSizeBytes: data?.count,
            wasRedirected: response?.url.map { $0 != request.url },
            retryCount: 0,
            retryAfter: Self.safeLogField(http?.value(forHTTPHeaderField: "Retry-After")),
            serverRequestID: requestID,
            errorDomain: errorInfo?.domain,
            errorCode: errorInfo?.code
        )
        await logAnisette(
            level,
            diagnostics.activityLogMessage(
                engine: "Anisette v3",
                provider: Self.safeLogField(provider) ?? "Anisette Server",
                stage: stage,
                parsing: parsing,
                validation: validation,
                result: result,
                reason: reason,
                nextAction: nextAction
            ),
            correlationID: correlationID
        )
    }

    private func logAnisette(_ level: LogLevel, _ message: String, correlationID: UUID) async {
        await logger?.log(level, message, correlationID: correlationID)
    }

    private func logParsing(
        provider: String,
        stage: String,
        result: String,
        reason: String,
        correlationID: UUID
    ) async {
        let level: LogLevel = result == "PASS" ? .success : .error
        await logAnisette(
            level,
            "Engine: Anisette v3 | Provider: \(Self.safeLogField(provider) ?? "Anisette Server") | Stage: \(stage) | Parsing: \(result) | Result: \(result) | Reason: \(reason)",
            correlationID: correlationID
        )
    }

    private func checkCancellation(
        stage: String,
        provider: String,
        correlationID: UUID
    ) async throws {
        do {
            try Task.checkCancellation()
        } catch {
            await logAnisette(
                .warning,
                "Engine: Anisette v3 | Provider: \(Self.safeLogField(provider) ?? "Anisette Server") | Stage: \(stage) | Result: CANCELLED | Reason: Request cancelled before the next operation.",
                correlationID: correlationID
            )
            throw error
        }
    }

    private static func safeEndpoint(_ url: URL?) -> String {
        guard let url, let host = url.host else { return "[invalid endpoint]" }
        let route = url.path.isEmpty || url.path == "/" ? "root" : url.lastPathComponent
        let safeRoute = route.range(of: #"^[A-Za-z0-9_-]{1,48}$"#, options: .regularExpression) != nil
            ? route
            : "[path omitted]"
        let scheme = url.scheme?.lowercased() == "wss" ? "wss" : "https"
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)/…/\(safeRoute)"
    }

    private static func safeLogField(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.count <= 160,
              !value.contains("|"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private static func safeRequestID(_ value: String?) -> String? {
        guard let value, value.count <= 128,
              value.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func httpFailureReason(_ statusCode: Int) -> String {
        if (300...399).contains(statusCode) {
            return "HTTP \(statusCode) redirect response was not followed outside the approved origin."
        }
        return "HTTP \(statusCode)."
    }

    private static func networkFailureReason(_ error: Error) -> String {
        let nsError = error as NSError
        guard let urlError = error as? URLError else {
            return "Network error \(nsError.domain)/\(nsError.code)."
        }
        let description: String
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed:
            description = "Network unavailable."
        case .cannotFindHost, .dnsLookupFailed:
            description = "DNS lookup failed."
        case .timedOut:
            description = "Request timed out."
        case .networkConnectionLost:
            description = "Network connection was lost."
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            description = "TLS certificate or secure connection failed."
        case .cannotConnectToHost:
            description = "Could not connect to the host."
        case .cancelled:
            description = "Request cancelled."
        case .unsupportedURL:
            description = "Unsupported request URL."
        default:
            description = "Network request failed."
        }
        return "\(description) Error: \(nsError.domain)/\(nsError.code)."
    }
}

extension AnisetteService {
    func fetchAnisetteV3(serverURL: String, correlationID: UUID? = nil) async throws -> [String: String] {
        let requestID = correlationID ?? UUID()
        guard let baseURL = AnisetteURLValidator.validatedBaseURL(serverURL),
              let normalizedServerURL = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        guard let identityStore else {
            throw AnisetteV3Error(message: "Secure Anisette identity storage is unavailable.")
        }
        guard try identityStore.isServerApproved(forServer: normalizedServerURL) else {
            throw AnisetteV3Error(
                message: "Review and approve this Anisette Server before sending stored identity data to it."
            )
        }

        let clientInfo = try await fetchClientInfo(from: baseURL, correlationID: requestID)
        try await checkCancellation(
            stage: "Identity Preparation",
            provider: baseURL.host ?? "Anisette Server",
            correlationID: requestID
        )
        let identity: StoredAnisetteIdentity
        if let storedIdentity = try identityStore.loadIdentity(forServer: normalizedServerURL) {
            try storedIdentity.validate()
            identity = storedIdentity
        } else {
            do {
                identity = try await provisionIdentity(
                    at: baseURL,
                    clientInfo: clientInfo,
                    correlationID: requestID
                )
            } catch {
                let nsError = error as NSError
                let cancelled = error is CancellationError || nsError.code == NSURLErrorCancelled
                let responseStatus = (connection.response as? HTTPURLResponse)?.statusCode
                let reason = responseStatus.map(Self.httpFailureReason)
                    ?? (error as? AnisetteV3Error)?.message
                    ?? (cancelled ? "Request cancelled." : Self.networkFailureReason(error))
                await logAnisette(
                    cancelled ? .warning : .error,
                    "Engine: Anisette v3 | Provider: \(baseURL.host ?? "Anisette Server") | Stage: Identity Provisioning | Parsing: NOT RUN | Result: \(cancelled ? "CANCELLED" : "FAIL") | Reason: \(reason)",
                    correlationID: requestID
                )
                throw error
            }
            try await checkCancellation(
                stage: "Identity Persistence",
                provider: baseURL.host ?? "Anisette Server",
                correlationID: requestID
            )
            try identityStore.saveIdentity(identity, forServer: normalizedServerURL)
            await logAnisette(
                .success,
                "Engine: Anisette v3 | Provider: \(baseURL.host ?? "Anisette Server") | Stage: Identity Provisioning | Parsing: PASS | Result: PASS. Identity values were not logged.",
                correlationID: requestID
            )
        }

        try await checkCancellation(
            stage: "Get Headers",
            provider: baseURL.host ?? "Anisette Server",
            correlationID: requestID
        )
        let response = try await fetchHeaders(at: baseURL, identity: identity, correlationID: requestID)
        guard let oneTimePassword = Self.nonEmptyString(response["X-Apple-I-MD"]),
              let machineID = Self.nonEmptyString(response["X-Apple-I-MD-M"]) else {
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Header Assembly",
                result: "FAIL",
                reason: "Required Anisette response headers are missing.",
                correlationID: requestID
            )
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
        await logAnisette(
            .success,
            "Anisette v3 | Stage: Header assembly | Parsing: PASS | Result: PASS. No header values were written to the log.",
            correlationID: requestID
        )
        return headers
    }

    private func fetchClientInfo(from baseURL: URL, correlationID: UUID) async throws -> AnisetteV3ClientInfo {
        let url = Self.endpoint("client_info", at: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await perform(
            request,
            provider: baseURL.host ?? "Anisette Server",
            stage: "Client Info",
            correlationID: correlationID
        )
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientInfo = Self.validHeaderValue(raw["client_info"] as? String),
              let userAgent = Self.validHeaderValue(raw["user_agent"] as? String) else {
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Client Info",
                result: "FAIL",
                reason: "The response was not valid JSON with the required client_info and user_agent fields.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Anisette Server does not provide v3 client information.")
        }
        await logParsing(
            provider: baseURL.host ?? "Anisette Server",
            stage: "Client Info",
            result: "PASS",
            reason: "Required client metadata fields are present; values were not logged.",
            correlationID: correlationID
        )
        return AnisetteV3ClientInfo(
            clientInfo: clientInfo,
            userAgent: userAgent,
            serialNumber: Self.validHeaderValue(raw["serial"] as? String) ?? "0"
        )
    }

    private func fetchHeaders(
        at baseURL: URL,
        identity: StoredAnisetteIdentity,
        correlationID: UUID
    ) async throws -> [String: String] {
        var request = URLRequest(url: Self.endpoint("get_headers", at: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": identity.identifier,
            "adi_pb": identity.adiPB
        ])
        let data = try await perform(
            request,
            provider: baseURL.host ?? "Anisette Server",
            stage: "Get Headers",
            correlationID: correlationID
        )
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Get Headers",
                result: "FAIL",
                reason: "The response was not a JSON object.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Anisette Server returned an invalid v3 response.")
        }
        var headers: [String: String] = [:]
        for key in ["X-Apple-I-MD", "X-Apple-I-MD-M", "X-Apple-I-MD-RINFO"] {
            if let value = Self.validHeaderValue(raw[key] as? String) {
                headers[key] = value
            }
        }
        guard headers["X-Apple-I-MD"] != nil, headers["X-Apple-I-MD-M"] != nil else {
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Get Headers",
                result: "FAIL",
                reason: "Required Anisette response headers are missing or invalid.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Anisette Server rejected the v3 request.")
        }
        await logParsing(
            provider: baseURL.host ?? "Anisette Server",
            stage: "Get Headers",
            result: "PASS",
            reason: "Required Anisette response headers are present; values were not logged.",
            correlationID: correlationID
        )
        return headers
    }

    private func provisionIdentity(
        at baseURL: URL,
        clientInfo: AnisetteV3ClientInfo,
        correlationID: UUID
    ) async throws -> StoredAnisetteIdentity {
        let randomIdentifier = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let identifier = SHA256.hash(data: Data(randomIdentifier.base64EncodedString().utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        let deviceID = UUID().uuidString.uppercased()
        let provisioningURLs = try await fetchProvisioningURLs(
            identifier: identifier,
            deviceID: deviceID,
            clientInfo: clientInfo,
            correlationID: correlationID
        )

        var socketComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        socketComponents?.scheme = "wss"
        socketComponents?.path = Self.endpointPath("provisioning_session", basePath: baseURL.path)
        guard let socketURL = socketComponents?.url else {
            throw AnisetteV3Error(message: "Anisette Server WebSocket URL is invalid.")
        }
        let connection = webSocketFactory.connect(to: socketURL)
        defer { connection.cancel() }
        var webSocketRequest = URLRequest(url: socketURL)
        webSocketRequest.httpMethod = "GET"
        webSocketRequest.timeoutInterval = 30
        let webSocketStartedAt = ProcessInfo.processInfo.systemUptime
        var didLogWebSocketHandshake = false

        var adiPB: String?
        for _ in 0..<8 {
            try await checkCancellation(
                stage: "Provisioning WebSocket",
                provider: baseURL.host ?? "Anisette Server",
                correlationID: correlationID
            )
            let message: String
            do {
                message = try await receiveProvisioningMessage(from: connection)
            } catch {
                let nsError = error as NSError
                let cancelled = error is CancellationError || nsError.code == NSURLErrorCancelled
                let reason = (error as? AnisetteV3Error)?.message
                    ?? (cancelled ? "Request cancelled." : Self.networkFailureReason(error))
                await recordNetworkRequest(
                    request: webSocketRequest,
                    response: connection.response,
                    data: nil,
                    provider: baseURL.host ?? "Anisette Server",
                    stage: "Provisioning WebSocket Handshake",
                    parsing: "NOT RUN",
                    validation: "NOT RUN",
                    result: cancelled ? "CANCELLED" : "FAIL",
                    reason: reason,
                    nextAction: "Check the WebSocket handshake, network, and TLS response before retrying.",
                    startedAt: webSocketStartedAt,
                    correlationID: correlationID,
                    level: cancelled ? .warning : .error,
                    error: error
                )
                throw error
            }
            if !didLogWebSocketHandshake {
                if let http = connection.response as? HTTPURLResponse,
                   http.statusCode != 101 {
                    await recordNetworkRequest(
                        request: webSocketRequest,
                        response: connection.response,
                        data: nil,
                        provider: baseURL.host ?? "Anisette Server",
                        stage: "Provisioning WebSocket Handshake",
                        parsing: "NOT RUN",
                        validation: "FAIL",
                        result: "FAIL",
                        reason: "WebSocket handshake requires HTTP 101; received HTTP \(http.statusCode).",
                        nextAction: "Check the actual HTTP response before retrying.",
                        startedAt: webSocketStartedAt,
                        correlationID: correlationID,
                        level: .error
                    )
                    throw AnisetteV3Error(message: "Anisette Server WebSocket handshake returned HTTP \(http.statusCode).")
                }
                let responseURL = connection.response?.url
                if let responseURL,
                   !AnisetteURLValidator.hasSameWSSOrigin(responseURL, socketURL) {
                    await recordNetworkRequest(
                        request: webSocketRequest,
                        response: connection.response,
                        data: nil,
                        provider: baseURL.host ?? "Anisette Server",
                        stage: "Provisioning WebSocket Handshake",
                        parsing: "NOT RUN",
                        validation: "FAIL",
                        result: "FAIL",
                        reason: "The WebSocket response came from a different secure origin.",
                        nextAction: "Use an endpoint that keeps the WebSocket on the configured WSS origin.",
                        startedAt: webSocketStartedAt,
                        correlationID: correlationID,
                        level: .error
                    )
                    throw AnisetteV3Error(message: "Anisette Server WebSocket changed origin.")
                }
                await recordNetworkRequest(
                    request: webSocketRequest,
                    response: connection.response,
                    data: nil,
                    provider: baseURL.host ?? "Anisette Server",
                    stage: "Provisioning WebSocket Handshake",
                    parsing: "NOT RUN",
                    validation: "NOT RUN",
                    result: "PARTIAL",
                    reason: "The WebSocket delivered a server message; protocol parsing continues.",
                    nextAction: "Inspect the provisioning protocol result for this correlation ID.",
                    startedAt: webSocketStartedAt,
                    correlationID: correlationID,
                    level: .info
                )
                didLogWebSocketHandshake = true
            }
            guard let json = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
                  let result = json["result"] as? String else {
                await logParsing(
                    provider: baseURL.host ?? "Anisette Server",
                    stage: "Provisioning WebSocket Message",
                    result: "FAIL",
                    reason: "The server message was not a JSON object with a recognized result field.",
                    correlationID: correlationID
                )
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
                    clientInfo: clientInfo,
                    correlationID: correlationID
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
                    clientInfo: clientInfo,
                    correlationID: correlationID
                )
                try await send([
                    "ptm": provisioningResult.ptm,
                    "tk": provisioningResult.trustKey
                ], through: connection)
            case "ProvisioningSuccess":
                adiPB = Self.nonEmptyString(json["adi_pb"] as? String)
            case "Timeout":
                await logParsing(
                    provider: baseURL.host ?? "Anisette Server",
                    stage: "Provisioning WebSocket Message",
                    result: "FAIL",
                    reason: "The server reported that provisioning timed out.",
                    correlationID: correlationID
                )
                throw AnisetteV3Error(message: "Anisette Server provisioning timed out.")
            default:
                await logParsing(
                    provider: baseURL.host ?? "Anisette Server",
                    stage: "Provisioning WebSocket Message",
                    result: "FAIL",
                    reason: "The server requested an unsupported provisioning step.",
                    correlationID: correlationID
                )
                throw AnisetteV3Error(message: "Anisette Server rejected v3 provisioning.")
            }
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Provisioning WebSocket Message",
                result: "PASS",
                reason: "The expected provisioning step was recognized; message values were not logged.",
                correlationID: correlationID
            )
            if adiPB != nil {
                break
            }
        }

        guard let adiPB, Data(base64Encoded: adiPB)?.isEmpty == false else {
            await logParsing(
                provider: baseURL.host ?? "Anisette Server",
                stage: "Identity Validation",
                result: "FAIL",
                reason: "The provisioning response omitted valid base64 identity data.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Anisette Server did not complete v3 provisioning.")
        }
        let identity = StoredAnisetteIdentity(
            identifier: identifier,
            deviceID: deviceID,
            adiPB: adiPB
        )
        try identity.validate()
        try await checkCancellation(
            stage: "Identity Validation",
            provider: baseURL.host ?? "Anisette Server",
            correlationID: correlationID
        )
        return identity
    }

    private func fetchProvisioningURLs(
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo,
        correlationID: UUID
    ) async throws -> (start: URL, finish: URL) {
        guard let lookupURL = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup") else {
            throw AnisetteV3Error(message: "Apple provisioning endpoint is invalid.")
        }
        let data = try await perform(
            appleRequest(
                url: lookupURL,
                method: "GET",
                body: nil,
                identifier: identifier,
                deviceID: deviceID,
                clientInfo: clientInfo
            ),
            provider: "Apple GSA",
            stage: "Provisioning Endpoint Lookup",
            correlationID: correlationID
        )
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urls = plist["urls"] as? [String: String],
              let startString = urls["midStartProvisioning"],
              let finishString = urls["midFinishProvisioning"],
              let startURL = URL(string: startString),
              let finishURL = URL(string: finishString),
              Self.isSafeAppleEndpoint(startURL),
              Self.isSafeAppleEndpoint(finishURL) else {
            await logParsing(
                provider: "Apple GSA",
                stage: "Provisioning Endpoint Lookup",
                result: "FAIL",
                reason: "Apple's response did not contain safe HTTPS provisioning endpoints on the default Apple origin.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Apple did not return valid Anisette provisioning endpoints.")
        }
        await logParsing(
            provider: "Apple GSA",
            stage: "Provisioning Endpoint Lookup",
            result: "PASS",
            reason: "Apple returned HTTPS provisioning endpoints on apple.com.",
            correlationID: correlationID
        )
        return (startURL, finishURL)
    }

    private func startProvisioning(
        at url: URL,
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo,
        correlationID: UUID
    ) async throws -> String {
        let data = try await perform(
            appleRequest(
                url: url,
                method: "POST",
                body: try provisioningPlist(request: [:]),
                identifier: identifier,
                deviceID: deviceID,
                clientInfo: clientInfo
            ),
            provider: "Apple GSA",
            stage: "Start Provisioning",
            correlationID: correlationID
        )
        guard let response = try? appleResponse(from: data),
              let spim = Self.nonEmptyString(response["spim"] as? String) else {
            await logParsing(
                provider: "Apple GSA",
                stage: "Start Provisioning",
                result: "FAIL",
                reason: "Apple's plist response did not contain the expected provisioning challenge.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Apple returned invalid start-provisioning data.")
        }
        await logParsing(
            provider: "Apple GSA",
            stage: "Start Provisioning",
            result: "PASS",
            reason: "The expected provisioning challenge was present; challenge values were not logged.",
            correlationID: correlationID
        )
        return spim
    }

    private func finishProvisioning(
        at url: URL,
        cpim: String,
        identifier: String,
        deviceID: String,
        clientInfo: AnisetteV3ClientInfo,
        correlationID: UUID
    ) async throws -> (ptm: String, trustKey: String) {
        let data = try await perform(
            appleRequest(
                url: url,
                method: "POST",
                body: try provisioningPlist(request: ["cpim": cpim]),
                identifier: identifier,
                deviceID: deviceID,
                clientInfo: clientInfo
            ),
            provider: "Apple GSA",
            stage: "Finish Provisioning",
            correlationID: correlationID
        )
        guard let response = try? appleResponse(from: data),
              let ptm = Self.nonEmptyString(response["ptm"] as? String),
              let trustKey = Self.nonEmptyString(response["tk"] as? String) else {
            await logParsing(
                provider: "Apple GSA",
                stage: "Finish Provisioning",
                result: "FAIL",
                reason: "Apple's plist response did not contain the expected provisioning values.",
                correlationID: correlationID
            )
            throw AnisetteV3Error(message: "Apple returned invalid finish-provisioning data.")
        }
        await logParsing(
            provider: "Apple GSA",
            stage: "Finish Provisioning",
            result: "PASS",
            reason: "Required provisioning values were present; values were not logged.",
            correlationID: correlationID
        )
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

    private func perform(
        _ request: URLRequest,
        provider: String,
        stage: String,
        correlationID: UUID
    ) async throws -> Data {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard request.url?.scheme?.lowercased() == "https" else {
            await recordNetworkRequest(
                request: request,
                response: nil,
                data: nil,
                provider: provider,
                stage: stage,
                parsing: "NOT RUN",
                validation: "FAIL",
                result: "BLOCKED",
                reason: "The request URL is not HTTPS.",
                nextAction: "Use an HTTPS Anisette or Apple endpoint.",
                startedAt: startedAt,
                correlationID: correlationID,
                level: .error
            )
            throw AnisetteV3Error(message: "Anisette requests require HTTPS.")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "The server response was not HTTP.",
                    nextAction: "Check the configured endpoint response.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .error
                )
                throw AnisetteV3Error(message: "An Anisette or Apple service returned an invalid response.")
            }

            guard AnisetteURLValidator.hasSameHTTPSOrigin(http.url, request.url) else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "The request redirected outside its configured HTTPS origin.",
                    nextAction: "Use an endpoint that keeps the request on the same HTTPS origin.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .error
                )
                throw AnisetteV3Error(message: "An Anisette or Apple service redirected to a different origin.")
            }

            guard (200...299).contains(http.statusCode) else {
                await recordNetworkRequest(
                    request: request,
                    response: response,
                    data: data,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: Self.httpFailureReason(http.statusCode),
                    nextAction: "Check the reported status before retrying.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .warning
                )
                throw AnisetteV3Error(message: "An Anisette or Apple service returned HTTP \(http.statusCode).")
            }

            await recordNetworkRequest(
                request: request,
                response: response,
                data: data,
                provider: provider,
                stage: stage,
                parsing: "NOT RUN",
                validation: "NOT RUN",
                result: "PARTIAL",
                reason: "HTTP response received; application parsing has not run yet.",
                nextAction: "Inspect the parsing result for this correlation ID.",
                startedAt: startedAt,
                correlationID: correlationID,
                level: .info
            )
            return data
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                let nsError = error as NSError
                await recordNetworkRequest(
                    request: request,
                    response: nil,
                    data: nil,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "NOT RUN",
                    result: "CANCELLED",
                    reason: "Request cancelled; error \(nsError.domain)/\(nsError.code).",
                    nextAction: "Start a new request only if needed.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .warning,
                    error: error
                )
            } else if !(error is AnisetteV3Error) {
                let nsError = error as NSError
                await recordNetworkRequest(
                    request: request,
                    response: nil,
                    data: nil,
                    provider: provider,
                    stage: stage,
                    parsing: "NOT RUN",
                    validation: "NOT RUN",
                    result: "FAIL",
                    reason: Self.networkFailureReason(error),
                    nextAction: "Check network reachability and TLS, then retry once the cause is resolved.",
                    startedAt: startedAt,
                    correlationID: correlationID,
                    level: .error,
                    error: error
                )
            }
            throw error
        }
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

    private static func isSafeAppleEndpoint(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              isAppleHost(url.host),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              (url.port ?? 443) == 443 else {
            return false
        }
        return true
    }
}

@MainActor
final class AnisetteServerStore: ObservableObject {
    @Published private(set) var servers: [AnisetteServer]
    @Published private(set) var selectedServerID: UUID?

    private let service: AnisetteServiceProtocol
    private let defaults: UserDefaults
    private let serversKey = "anisette.servers.v1"
    private let selectedIDKey = "anisette.selectedServerID.v1"

    init(service: AnisetteServiceProtocol, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        let didMigrateDefaults: Bool
        if let stored = defaults.array(forKey: serversKey) as? [[String: Any]],
           let persisted = Self.decodeServers(stored), !persisted.isEmpty {
            let merged = Self.mergingDefaultServers(into: persisted)
            servers = merged
            didMigrateDefaults = merged != persisted
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
            didMigrateDefaults = true
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
        if didMigrateDefaults {
            persistServers()
        }
    }

    var selectedServer: AnisetteServer? {
        servers.first { $0.id == selectedServerID }
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
        persistServers()
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
            if selectedServerID == serverID {
                selectID(nil)
                selectSideStoreIfNeeded()
            }
        }
        persistServers()
    }

    func delete(serverID: UUID) throws {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        guard !server.isDefault else { throw AnisetteServerError.cannotModifyDefault }
        try service.clearIdentity(forServer: server.url)
        servers.removeAll { $0.id == serverID }
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

    func hasAnisetteApproval(serverID: UUID) throws -> Bool {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        return try service.isServerApproved(serverURL: server.url)
    }

    func approveAnisetteUse(serverID: UUID) throws {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        try service.approveServer(serverURL: server.url)
    }

    func forgetAnisetteIdentity(serverID: UUID) throws {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        try service.clearIdentity(forServer: server.url)
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

    private static func mergingDefaultServers(into persisted: [AnisetteServer]) -> [AnisetteServer] {
        let defaults = AnisetteService.defaultServers
        let legacyStikStoreURL = AnisetteURLValidator.normalized("https://ani3.stikstore.com")
        let defaultURLs = Set(
            defaults.compactMap { AnisetteURLValidator.normalized($0.url) }
                + [legacyStikStoreURL].compactMap { $0 }
        )
        let builtIns = defaults.map { defaultServer in
            guard let normalizedURL = AnisetteURLValidator.normalized(defaultServer.url),
                  let stored = persisted.first(where: {
                      AnisetteURLValidator.normalized($0.url) == normalizedURL
                          || (defaultServer.name == "StikStore"
                              && AnisetteURLValidator.normalized($0.url) == legacyStikStoreURL)
                  }) else {
                return defaultServer
            }
            return AnisetteServer(
                id: stored.id,
                name: defaultServer.name,
                url: defaultServer.url,
                isDefault: true
            )
        }
        let custom = persisted.filter {
            guard let normalizedURL = AnisetteURLValidator.normalized($0.url) else { return true }
            return !defaultURLs.contains(normalizedURL)
        }
        return builtIns + custom
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
