import Foundation

enum AppStoreServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Apple App Store returned an invalid response."
    }
}

final class AppStoreService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String, country: String = "us") async throws -> [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let appID = Int(trimmed), appID > 0 {
            return try await lookup(appID: appID, country: country)
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "50")
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AppStoreServiceError.invalidResponse
        }
        return try decode(data)
    }

    func lookup(appID: Int, country: String = "us") async throws -> [AppRecord] {
        guard appID > 0 else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "country", value: country)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AppStoreServiceError.invalidResponse
        }
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> [AppRecord] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else {
            throw AppStoreServiceError.invalidResponse
        }

        return results.compactMap { item in
            guard let id = item["trackId"] as? Int,
                  let bundleID = item["bundleId"] as? String,
                  let name = item["trackName"] as? String else {
                return nil
            }
            let image = item["artworkUrl512"] as? String ?? item["artworkUrl100"] as? String
            let size = (item["fileSizeBytes"] as? String).flatMap(Int64.init)
            return AppRecord(
                id: id,
                bundleID: bundleID,
                name: name,
                developer: item["sellerName"] as? String ?? "Unknown developer",
                iconURL: image.flatMap(URL.init(string:)),
                version: item["version"] as? String ?? "Unknown",
                fileSizeBytes: size,
                minimumOSVersion: item["minimumOsVersion"] as? String
            )
        }
    }
}
