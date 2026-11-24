import Foundation

enum AnisetteStatus: Equatable {
    case unknown
    case connected
    case serverUnavailable
    case invalidURL
    case requestTimeout
    case invalidResponse

    var label: String {
        switch self {
        case .unknown: return "Not Checked"
        case .connected: return "Connected (HTTPS endpoint reachable)"
        case .serverUnavailable: return "Server Unavailable"
        case .invalidURL: return "Invalid URL"
        case .requestTimeout: return "Request Timeout"
        case .invalidResponse: return "Invalid Response"
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
}

protocol AnisetteServiceProtocol {
    func testConnection(serverURL: String) async -> AnisetteStatus
}

final class AnisetteService: AnisetteServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func testConnection(serverURL: String) async -> AnisetteStatus {
        guard let url = AnisetteURLValidator.validatedBaseURL(serverURL) else {
            return .invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .invalidResponse }
            guard (200...299).contains(http.statusCode) || http.statusCode == 405 else {
                return .invalidResponse
            }
            return .connected
        } catch let error as URLError where error.code == .timedOut {
            return .requestTimeout
        } catch {
            return .serverUnavailable
        }
    }
}
