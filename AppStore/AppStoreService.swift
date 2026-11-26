import Foundation

enum AppStoreServiceError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Apple App Store returned an invalid response."
        case .httpStatus(let status):
            return "Apple App Store returned HTTP \(status)."
        }
    }
}

final class AppStoreService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        _ query: String,
        country: String = "us",
        onHTTPStatus: ((Int) -> Void)? = nil
    ) async throws -> [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let appID = Int(trimmed), appID > 0 {
            return try await lookup(appID: appID, country: country, onHTTPStatus: onHTTPStatus)
        }
        if trimmed.contains(".") {
            var bundleComponents = URLComponents(string: "https://itunes.apple.com/lookup")!
            bundleComponents.queryItems = [
                URLQueryItem(name: "bundleId", value: trimmed),
                URLQueryItem(name: "country", value: country)
            ]
            let (bundleData, bundleResponse) = try await session.data(from: bundleComponents.url!)
            guard let bundleHTTP = bundleResponse as? HTTPURLResponse else {
                throw AppStoreServiceError.invalidResponse
            }
            onHTTPStatus?(bundleHTTP.statusCode)
            guard (200...299).contains(bundleHTTP.statusCode) else {
                throw AppStoreServiceError.httpStatus(bundleHTTP.statusCode)
            }
            let bundleResults = try decode(bundleData)
            if !bundleResults.isEmpty {
                return bundleResults
            }
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
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreServiceError.invalidResponse
        }
        onHTTPStatus?(http.statusCode)
        guard (200...299).contains(http.statusCode) else {
            throw AppStoreServiceError.httpStatus(http.statusCode)
        }
        return try decode(data)
    }

    func lookup(
        appID: Int,
        country: String = "us",
        onHTTPStatus: ((Int) -> Void)? = nil
    ) async throws -> [AppRecord] {
        guard appID > 0 else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "country", value: country)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreServiceError.invalidResponse
        }
        onHTTPStatus?(http.statusCode)
        guard (200...299).contains(http.statusCode) else {
            throw AppStoreServiceError.httpStatus(http.statusCode)
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
                minimumOSVersion: item["minimumOsVersion"] as? String,
                price: (item["price"] as? NSNumber)?.doubleValue
            )
        }
    }
}
