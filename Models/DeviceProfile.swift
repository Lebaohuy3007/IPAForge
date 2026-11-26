import Foundation

enum DeviceProfileFamily: Int, CaseIterable, Codable, Identifiable {
    case iPhone = 1
    case iPad = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        }
    }
}

struct DeviceProfile: Codable, Equatable, Identifiable {
    /// Local profile record ID only. This value is never used as an Apple device identity.
    let id: UUID
    var name: String
    var model: String
    var family: DeviceProfileFamily
    var osVersion: String
    /// Nil means the profile's hardware inventory has not been verified.
    var availableCapabilities: Set<String>?
    /// Nil means executable architecture compatibility has not been verified.
    var supportedArchitectures: Set<String>?

    static let defaultProfile = DeviceProfile(
        id: UUID(uuidString: "E986CB58-3501-4B4D-9F5A-2B9B56A9D270")!,
        name: "iOS 27 iPhone",
        model: "iPhone 17 Pro",
        family: .iPhone,
        osVersion: "27.0",
        availableCapabilities: nil,
        supportedArchitectures: nil
    )

    static func modelOptions(for family: DeviceProfileFamily) -> [String] {
        switch family {
        case .iPhone:
            return ["Generic iPhone", "iPhone 17 Pro", "iPhone 17", "iPhone Air"]
        case .iPad:
            return ["Generic iPad", "iPad Pro", "iPad Air", "iPad mini"]
        }
    }

    var isSimulated: Bool { true }

    func validationError() -> DeviceProfileError? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyName
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyModel
        }
        guard let version = SemanticOSVersion(osVersion) else {
            return .invalidOSVersion
        }
        guard version >= SemanticOSVersion(major: 27, minor: 0, patch: 0) else {
            return .requiresIOS27
        }
        if let availableCapabilities,
           availableCapabilities.contains(where: Self.invalidCapability) {
            return .invalidCapability
        }
        if let supportedArchitectures,
           supportedArchitectures.contains(where: Self.invalidArchitecture) {
            return .invalidArchitecture
        }
        return nil
    }

    private static func invalidCapability(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || value.contains(where: { $0.isWhitespace })
    }

    private static func invalidArchitecture(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.isEmpty
            || !normalized.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") }
    }
}

enum DeviceProfileError: LocalizedError, Equatable {
    case emptyName
    case emptyModel
    case invalidOSVersion
    case requiresIOS27
    case invalidCapability
    case invalidArchitecture

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for this device profile."
        case .emptyModel: return "Choose or enter a device model."
        case .invalidOSVersion: return "Enter an OS version such as 27.0 or 27.1."
        case .requiresIOS27: return "Device profiles in this tool must use iOS 27.0 or later."
        case .invalidCapability: return "Capabilities must be non-empty identifiers without spaces."
        case .invalidArchitecture: return "Enter valid architecture names such as arm64."
        }
    }
}

struct SemanticOSVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = parts.count == 3 ? (Int(parts[2]) ?? -1) : 0
        guard self.patch >= 0 else { return nil }
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemanticOSVersion, rhs: SemanticOSVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

