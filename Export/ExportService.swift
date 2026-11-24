import Foundation

enum ExportServiceError: LocalizedError {
    case fileMissing
    case notIPA
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .fileMissing: return "The IPA file no longer exists."
        case .notIPA: return "The exported file is not an .ipa package."
        case .invalidPackage: return "The .ipa file does not have a ZIP archive signature."
        }
    }
}

struct ExportService {
    func validate(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExportServiceError.fileMissing
        }
        guard url.pathExtension.lowercased() == "ipa" else {
            throw ExportServiceError.notIPA
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else {
            throw ExportServiceError.invalidPackage
        }
    }

    func shareItems(for url: URL) throws -> [URL] {
        try validate(url)
        return [url]
    }
}
