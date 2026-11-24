import Foundation
import Combine
import Dispatch

enum AnisetteProbeState: Equatable {
    case unchecked
    case invalidURL
    case noResponse
    case responded
    case validV1

    var title: String {
        switch self {
        case .unchecked: return "Chưa kiểm tra"
        case .invalidURL: return "URL không hợp lệ"
        case .noResponse: return "Không phản hồi"
        case .responded: return "Có phản hồi · chưa xác minh Anisette"
        case .validV1: return "Anisette v1 hợp lệ"
        }
    }

    var isUsable: Bool { self == .validV1 }
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
    case serverNotReady

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Nhập một URL HTTPS hợp lệ."
        case .duplicateURL: return "Anisette Server này đã có trong danh sách."
        case .notFound: return "Không tìm thấy Anisette Server."
        case .cannotModifyDefault: return "Không thể sửa hoặc xóa nguồn mặc định."
        case .serverNotReady: return "Server chưa trả về Anisette v1 hợp lệ. Hãy kiểm tra lại hoặc chọn server khác."
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
}

protocol AnisetteServiceProtocol {
    func testConnection(serverURL: String) async -> AnisetteProbeResult
}

final class AnisetteService: AnisetteServiceProtocol {
    static let defaultURL = "https://mac-ani.jkcoxson.com"
    static let defaultServers = [
        AnisetteServer(name: "SideStore", url: "https://ani.sidestore.io", isDefault: true),
        AnisetteServer(name: "jkcoxson", url: defaultURL, isDefault: true)
    ]

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func testConnection(serverURL: String) async -> AnisetteProbeResult {
        guard let baseURL = AnisetteURLValidator.validatedBaseURL(serverURL) else {
            return AnisetteProbeResult(state: .invalidURL, durationMilliseconds: nil)
        }

        var request = URLRequest(url: baseURL)
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
            guard http.url?.scheme?.lowercased() == "https" else {
                return AnisetteProbeResult(state: .responded, durationMilliseconds: elapsed)
            }
            guard (200...299).contains(http.statusCode) else {
                return AnisetteProbeResult(state: .responded, durationMilliseconds: elapsed)
            }
            let state = Self.isValidV1Response(data) ? AnisetteProbeState.validV1 : .responded
            return AnisetteProbeResult(state: state, durationMilliseconds: elapsed)
        } catch {
            return AnisetteProbeResult(state: .noResponse, durationMilliseconds: nil)
        }
    }

    private static func isValidV1Response(_ data: Data) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var headers: [String: String] = [:]
        for (key, value) in raw {
            guard let string = value as? String else { continue }
            headers[key.lowercased()] = string
        }
        let required = ["x-apple-i-md", "x-apple-i-md-m"]
        return required.allSatisfy { key in
            guard let value = headers[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }
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
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        servers[index].name = cleanName.isEmpty ? (URL(string: normalizedURL)?.host ?? "Server") : cleanName
        servers[index].url = normalizedURL
        if oldURL != normalizedURL {
            probeResults[serverID] = AnisetteProbeResult(state: .unchecked, durationMilliseconds: nil)
            if selectedServerID == serverID {
                selectID(nil)
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
        servers.removeAll { $0.id == serverID }
        probeResults.removeValue(forKey: serverID)
        if selectedServerID == serverID { selectID(nil) }
        persistServers()
    }

    func select(serverID: UUID) throws {
        guard servers.contains(where: { $0.id == serverID }) else {
            throw AnisetteServerError.notFound
        }
        guard probeResults[serverID]?.state.isUsable == true else {
            throw AnisetteServerError.serverNotReady
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
