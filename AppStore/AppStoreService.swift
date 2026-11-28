import Foundation

struct AppStoreRequestDiagnostics: Equatable {
    let method: String
    let endpoint: String
    let httpStatus: Int?
    let durationMilliseconds: Int
    let responseContentType: String?
    let responseSizeBytes: Int?
    let wasRedirected: Bool?
    let retryCount: Int
    let retryAfter: String?
    let serverRequestID: String?
    let errorDomain: String?
    let errorCode: Int?

    func activityLogMessage(
        engine: String,
        provider: String = "Public iTunes Search API",
        stage: String,
        parsing: String,
        validation: String,
        result: String,
        reason: String,
        nextAction: String
    ) -> String {
        let status = httpStatus.map(String.init) ?? "N/A"
        let contentType = responseContentType ?? "N/A"
        let size = responseSizeBytes.map(String.init) ?? "N/A"
        let duration = "\(durationMilliseconds) ms"
        let redirected = wasRedirected.map { $0 ? "YES" : "NO" } ?? "N/A"
        let requestID = serverRequestID ?? "N/A"
        let error = errorDomain.map { "\($0)/\(errorCode.map(String.init) ?? "N/A")" } ?? "N/A"
        let responseSummary = httpStatus.map { "HTTP \($0) response; response body not stored." }
            ?? "No HTTP response; response body not available."
        return "Engine: \(engine) | Provider: \(provider) | Stage: \(stage) | Method: \(method) | Endpoint: \(endpoint) | HTTP Status: \(status) | Duration: \(duration) | Response Type: \(contentType) | Response Size: \(size) bytes | Redirected: \(redirected) | Retry Count: \(retryCount) | Retry-After: \(retryAfter ?? "N/A") | Server Request ID: \(requestID) | Response Summary: \(responseSummary) | Parsing: \(parsing) | Validation: \(validation) | Error Domain/Code: \(error) | Result: \(result) | Reason: \(reason) | Next Action: \(nextAction)"
    }
}

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
        onDiagnostics: ((AppStoreRequestDiagnostics) -> Void)? = nil,
        onHTTPStatus: ((Int) -> Void)? = nil
    ) async throws -> [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let appID = Int(trimmed), appID > 0 {
            return try await lookup(
                appID: appID,
                country: country,
                onDiagnostics: onDiagnostics,
                onHTTPStatus: onHTTPStatus
            )
        }
        if trimmed.contains(".") {
            var bundleComponents = URLComponents(string: "https://itunes.apple.com/lookup")!
            bundleComponents.queryItems = [
                URLQueryItem(name: "bundleId", value: trimmed),
                URLQueryItem(name: "country", value: country)
            ]
            let bundleData = try await requestData(
                from: bundleComponents.url!,
                onDiagnostics: onDiagnostics,
                onHTTPStatus: onHTTPStatus
            )
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
        let data = try await requestData(
            from: components.url!,
            onDiagnostics: onDiagnostics,
            onHTTPStatus: onHTTPStatus
        )
        return try decode(data)
    }

    func lookup(
        appID: Int,
        country: String = "us",
        onDiagnostics: ((AppStoreRequestDiagnostics) -> Void)? = nil,
        onHTTPStatus: ((Int) -> Void)? = nil
    ) async throws -> [AppRecord] {
        guard appID > 0 else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "country", value: country)
        ]
        let data = try await requestData(
            from: components.url!,
            onDiagnostics: onDiagnostics,
            onHTTPStatus: onHTTPStatus
        )
        return try decode(data)
    }

    private func requestData(
        from url: URL,
        onDiagnostics: ((AppStoreRequestDiagnostics) -> Void)?,
        onHTTPStatus: ((Int) -> Void)?
    ) async throws -> Data {
        let request = URLRequest(url: url)
        let startedAt = ProcessInfo.processInfo.systemUptime
        var didReportDiagnostics = false
        do {
            let (data, response) = try await session.data(for: request)
            let duration = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            guard let http = response as? HTTPURLResponse else {
                let error = AppStoreServiceError.invalidResponse
                let nsError = error as NSError
                onDiagnostics?(AppStoreRequestDiagnostics(
                    method: request.httpMethod ?? "GET",
                    endpoint: Self.safeEndpoint(url),
                    httpStatus: nil,
                    durationMilliseconds: duration,
                    responseContentType: response.mimeType,
                    responseSizeBytes: data.count,
                    wasRedirected: response.url.map { $0 != url },
                    retryCount: 0,
                    retryAfter: nil,
                    serverRequestID: nil,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                ))
                didReportDiagnostics = true
                throw error
            }

            onHTTPStatus?(http.statusCode)
            onDiagnostics?(AppStoreRequestDiagnostics(
                method: request.httpMethod ?? "GET",
                endpoint: Self.safeEndpoint(url),
                httpStatus: http.statusCode,
                durationMilliseconds: duration,
                responseContentType: http.value(forHTTPHeaderField: "Content-Type"),
                responseSizeBytes: data.count,
                wasRedirected: http.url.map { $0 != url },
                retryCount: 0,
                retryAfter: Self.safeHeaderValue(http.value(forHTTPHeaderField: "Retry-After")),
                serverRequestID: Self.safeHeaderValue(http.value(forHTTPHeaderField: "X-Apple-Request-UUID")),
                errorDomain: nil,
                errorCode: nil
            ))
            didReportDiagnostics = true
            guard (200...299).contains(http.statusCode) else {
                throw AppStoreServiceError.httpStatus(http.statusCode)
            }
            return data
        } catch {
            if !didReportDiagnostics {
                let nsError = error as NSError
                onDiagnostics?(AppStoreRequestDiagnostics(
                    method: request.httpMethod ?? "GET",
                    endpoint: Self.safeEndpoint(url),
                    httpStatus: nil,
                    durationMilliseconds: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000),
                    responseContentType: nil,
                    responseSizeBytes: nil,
                    wasRedirected: nil,
                    retryCount: 0,
                    retryAfter: nil,
                    serverRequestID: nil,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                ))
            }
            throw error
        }
    }

    private static func safeEndpoint(_ url: URL) -> String {
        guard let host = url.host else { return "[invalid endpoint]" }
        return "https://\(host)\(url.path)"
    }

    private static func safeHeaderValue(_ value: String?) -> String? {
        guard let value,
              value.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
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
