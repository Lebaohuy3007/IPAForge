import Foundation

enum CompatibilityStatus: String, Codable {
    case compatible
    case incompatible
    case unknown

    var title: String {
        switch self {
        case .compatible: return "Compatible"
        case .incompatible: return "Incompatible"
        case .unknown: return "Unknown"
        }
    }
}

enum CompatibilityCriterion: String, Codable, CaseIterable, Identifiable {
    case minimumOS
    case deviceFamily
    case deviceCapabilities
    case platform
    case architecture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimumOS: return "Minimum OS"
        case .deviceFamily: return "Device family"
        case .deviceCapabilities: return "Hardware capabilities"
        case .platform: return "Platform"
        case .architecture: return "Architecture"
        }
    }
}

struct CompatibilityFinding: Equatable, Identifiable {
    let criterion: CompatibilityCriterion
    let status: CompatibilityStatus
    let detail: String

    var id: CompatibilityCriterion { criterion }
}

struct CompatibilityRequirements: Equatable {
    let minimumOSVersion: String?
    let supportedDeviceFamilies: Set<Int>?
    /// Nil means the field was unavailable; an empty set means it was inspected and no capability is required.
    let requiredCapabilities: Set<String>?
    let prohibitedCapabilities: Set<String>?
    let supportedPlatforms: Set<String>?
    let architectures: Set<String>?

    static func fromCatalog(_ app: AppRecord) -> CompatibilityRequirements {
        CompatibilityRequirements(
            minimumOSVersion: app.minimumOSVersion,
            supportedDeviceFamilies: nil,
            requiredCapabilities: nil,
            prohibitedCapabilities: nil,
            supportedPlatforms: nil,
            architectures: nil
        )
    }
}

struct CompatibilityReport: Equatable {
    let status: CompatibilityStatus
    let profileName: String
    let model: String
    let osVersion: String
    let findings: [CompatibilityFinding]

    var hasUnknownChecks: Bool {
        findings.contains(where: { $0.status == .unknown })
    }
}

struct CompatibilityChecker {
    func evaluate(
        requirements: CompatibilityRequirements,
        profile: DeviceProfile
    ) -> CompatibilityReport {
        let findings = [
            checkMinimumOS(requirements.minimumOSVersion, profile: profile),
            checkFamily(requirements.supportedDeviceFamilies, profile: profile),
            checkCapabilities(
                required: requirements.requiredCapabilities,
                prohibited: requirements.prohibitedCapabilities,
                profile: profile
            ),
            checkPlatform(requirements.supportedPlatforms),
            checkArchitecture(requirements.architectures, profile: profile)
        ]
        let status: CompatibilityStatus
        if findings.contains(where: { $0.status == .incompatible }) {
            status = .incompatible
        } else if findings.contains(where: { $0.status == .unknown }) {
            status = .unknown
        } else {
            status = .compatible
        }
        return CompatibilityReport(
            status: status,
            profileName: profile.name,
            model: profile.model,
            osVersion: profile.osVersion,
            findings: findings
        )
    }

    private func checkMinimumOS(_ minimum: String?, profile: DeviceProfile) -> CompatibilityFinding {
        guard let minimum,
              let requiredVersion = SemanticOSVersion(minimum),
              let profileVersion = SemanticOSVersion(profile.osVersion) else {
            return CompatibilityFinding(
                criterion: .minimumOS,
                status: .unknown,
                detail: "A valid minimum OS or profile OS version is missing."
            )
        }
        if profileVersion < requiredVersion {
            return CompatibilityFinding(
                criterion: .minimumOS,
                status: .incompatible,
                detail: "App requires iOS \(minimum); profile is iOS \(profile.osVersion)."
            )
        }
        return CompatibilityFinding(
            criterion: .minimumOS,
            status: .compatible,
            detail: "Profile iOS \(profile.osVersion) meets minimum iOS \(minimum)."
        )
    }

    private func checkFamily(_ families: Set<Int>?, profile: DeviceProfile) -> CompatibilityFinding {
        guard let families, !families.isEmpty else {
            return CompatibilityFinding(
                criterion: .deviceFamily,
                status: .unknown,
                detail: "UIDeviceFamily was not available in the source metadata."
            )
        }
        if families.contains(profile.family.rawValue) {
            return CompatibilityFinding(
                criterion: .deviceFamily,
                status: .compatible,
                detail: "The app declares \(profile.family.title) support."
            )
        }
        if profile.family == .iPad && families.contains(DeviceProfileFamily.iPhone.rawValue) {
            return CompatibilityFinding(
                criterion: .deviceFamily,
                status: .unknown,
                detail: "The app declares iPhone support only; iPad compatibility mode was not verified."
            )
        }
        return CompatibilityFinding(
            criterion: .deviceFamily,
            status: .incompatible,
            detail: "The app does not declare support for \(profile.family.title)."
        )
    }

    private func checkCapabilities(
        required: Set<String>?,
        prohibited: Set<String>?,
        profile: DeviceProfile
    ) -> CompatibilityFinding {
        guard !profile.isSimulated else {
            return CompatibilityFinding(
                criterion: .deviceCapabilities,
                status: .unknown,
                detail: "Hardware capability values on a simulated profile are not verified device data."
            )
        }
        guard let required, let prohibited else {
            return CompatibilityFinding(
                criterion: .deviceCapabilities,
                status: .unknown,
                detail: "UIRequiredDeviceCapabilities was not available in the source metadata."
            )
        }
        if required.isEmpty && prohibited.isEmpty {
            return CompatibilityFinding(
                criterion: .deviceCapabilities,
                status: .compatible,
                detail: "The inspected Info.plist declares no required or prohibited capabilities."
            )
        }
        guard let available = profile.availableCapabilities else {
            return CompatibilityFinding(
                criterion: .deviceCapabilities,
                status: .unknown,
                detail: "The simulated profile has no verified capability inventory."
            )
        }
        let missing = required.subtracting(available).sorted()
        let disallowed = prohibited.intersection(available).sorted()
        if !missing.isEmpty || !disallowed.isEmpty {
            let details = [
                missing.isEmpty ? nil : "Missing: \(missing.joined(separator: ", "))",
                disallowed.isEmpty ? nil : "Must not be present: \(disallowed.joined(separator: ", "))"
            ].compactMap { $0 }.joined(separator: ". ")
            return CompatibilityFinding(
                criterion: .deviceCapabilities,
                status: .incompatible,
                detail: details
            )
        }
        return CompatibilityFinding(
            criterion: .deviceCapabilities,
            status: .compatible,
            detail: "The profile's declared capabilities satisfy the inspected requirements."
        )
    }

    private func checkPlatform(_ platforms: Set<String>?) -> CompatibilityFinding {
        guard let platforms, !platforms.isEmpty else {
            return CompatibilityFinding(
                criterion: .platform,
                status: .unknown,
                detail: "CFBundleSupportedPlatforms was not available in the source metadata."
            )
        }
        if platforms.contains("iPhoneOS") {
            return CompatibilityFinding(
                criterion: .platform,
                status: .compatible,
                detail: "The package declares the iPhoneOS platform."
            )
        }
        return CompatibilityFinding(
            criterion: .platform,
            status: .incompatible,
            detail: "The package does not declare the iPhoneOS platform."
        )
    }

    private func checkArchitecture(_ architectures: Set<String>?, profile: DeviceProfile) -> CompatibilityFinding {
        guard !profile.isSimulated else {
            return CompatibilityFinding(
                criterion: .architecture,
                status: .unknown,
                detail: "Architecture values on a simulated profile are not verified device data."
            )
        }
        guard let architectures, !architectures.isEmpty,
              let supported = profile.supportedArchitectures,
              !supported.isEmpty else {
            return CompatibilityFinding(
                criterion: .architecture,
                status: .unknown,
                detail: "Executable slices or verified profile architectures were not available."
            )
        }
        let appArchitectures = Set(architectures.map { $0.lowercased() })
        let profileArchitectures = Set(supported.map { $0.lowercased() })
        if !appArchitectures.isDisjoint(with: profileArchitectures) {
            return CompatibilityFinding(
                criterion: .architecture,
                status: .compatible,
                detail: "The package contains a slice supported by the profile."
            )
        }
        return CompatibilityFinding(
            criterion: .architecture,
            status: .incompatible,
            detail: "No package architecture matches the profile's verified architectures."
        )
    }
}
