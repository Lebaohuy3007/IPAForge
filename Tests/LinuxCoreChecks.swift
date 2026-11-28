import Foundation

@main
private enum LinuxCoreChecks {
    static func main() {
        var checks = Checks()
        checks.run()
        print("Linux core checks passed: \(checks.count) assertions.")
    }
}

private struct Checks {
    var count = 0

    mutating func run() {
        checkDefaultProfileIsSimulatedIOS27()
        checkVersionParsingAndComparison()
        checkProfileValidation()
        checkCompatibilityRequiresKnownMetadata()
        checkCapabilityAndFamilyFailures()
        checkArchitectureSubtypesStayDistinct()
    }

    private mutating func checkDefaultProfileIsSimulatedIOS27() {
        let profile = DeviceProfile.defaultProfile
        expect(profile.family == .iPhone, "default family is iPhone")
        expect(profile.osVersion == "27.2", "default profile starts at iOS 27.2")
        expect(profile.isSimulated, "profile is explicitly simulated")
        expect(profile.availableCapabilities == nil, "unverified capabilities remain unknown")
    }

    private mutating func checkVersionParsingAndComparison() {
        guard let later = SemanticOSVersion("27.10"),
              let earlier = SemanticOSVersion("27.2") else {
            fatalError("Valid semantic versions were rejected.")
        }
        expect(later > earlier, "versions compare numerically")
        expect(SemanticOSVersion("27.invalid") == nil, "invalid versions are rejected")
    }

    private mutating func checkProfileValidation() {
        var profile = DeviceProfile.defaultProfile
        profile.osVersion = "26.9"
        expect(profile.validationError() == .requiresIOS27, "profiles below iOS 27 are rejected")
        profile.osVersion = "27.2"
        profile.supportedArchitectures = ["arm64e.x1"]
        expect(profile.validationError() == nil, "iOS 27 architecture identifiers are accepted")
    }

    private mutating func checkCompatibilityRequiresKnownMetadata() {
        let profile = makeProfile(capabilities: ["wifi"], architectures: ["arm64"])
        let missing = CompatibilityRequirements(
            minimumOSVersion: nil,
            supportedDeviceFamilies: nil,
            requiredCapabilities: nil,
            prohibitedCapabilities: nil,
            supportedPlatforms: nil,
            architectures: nil
        )
        expect(CompatibilityChecker().evaluate(requirements: missing, profile: profile).status == .unknown,
               "missing metadata yields Unknown")

        let malformedVersion = requirements(
            minimumOS: "twenty-seven",
            family: [DeviceProfileFamily.iPhone.rawValue],
            required: [],
            prohibited: [],
            architecture: ["arm64"]
        )
        expect(CompatibilityChecker().evaluate(requirements: malformedVersion, profile: profile).status == .unknown,
               "invalid minimum OS yields Unknown")

        let compatible = requirements(
            minimumOS: "16.0",
            family: [DeviceProfileFamily.iPhone.rawValue],
            required: ["wifi"],
            prohibited: [],
            architecture: ["arm64"]
        )
        expect(CompatibilityChecker().evaluate(requirements: compatible, profile: profile).status == .unknown,
               "manually entered simulated hardware values do not become verified")
    }

    private mutating func checkCapabilityAndFamilyFailures() {
        let profile = makeProfile(capabilities: ["wifi"], architectures: ["arm64"])
        let needsNFC = requirements(
            minimumOS: "16.0",
            family: [DeviceProfileFamily.iPhone.rawValue],
            required: ["nfc"],
            prohibited: [],
            architecture: ["arm64"]
        )
        let needsNFCReport = CompatibilityChecker().evaluate(requirements: needsNFC, profile: profile)
        expect(needsNFCReport.findings.first(where: { $0.criterion == .deviceCapabilities })?.status == .unknown,
               "manual simulated capability values stay Unknown")

        let tooNew = requirements(
            minimumOS: "28.0",
            family: [DeviceProfileFamily.iPhone.rawValue],
            required: [],
            prohibited: [],
            architecture: ["arm64"]
        )
        expect(CompatibilityChecker().evaluate(requirements: tooNew, profile: profile).status == .incompatible,
               "higher minimum OS yields Incompatible")

        let iPadOnly = requirements(
            minimumOS: "16.0",
            family: [DeviceProfileFamily.iPad.rawValue],
            required: [],
            prohibited: [],
            architecture: ["arm64"]
        )
        expect(CompatibilityChecker().evaluate(requirements: iPadOnly, profile: profile).status == .incompatible,
               "unsupported device family yields Incompatible")

        let catalog = AppRecord(
            id: 44,
            bundleID: "com.example.catalog",
            name: "Catalog app",
            developer: "Example",
            iconURL: nil,
            version: "1.0",
            fileSizeBytes: nil,
            minimumOSVersion: "16.0"
        )
        let catalogReport = CompatibilityChecker().evaluate(
            requirements: .fromCatalog(catalog),
            profile: profile
        )
        expect(catalogReport.status == .unknown, "catalog metadata does not guess missing requirements")
        expect(catalogReport.findings.first(where: { $0.criterion == .minimumOS })?.status == .compatible,
               "known catalog minimum OS is evaluated")
    }

    private mutating func checkArchitectureSubtypesStayDistinct() {
        let profile = makeProfile(capabilities: [], architectures: ["arm64e"])
        let requirements = requirements(
            minimumOS: "27.0",
            family: [DeviceProfileFamily.iPhone.rawValue],
            required: [],
            prohibited: [],
            architecture: ["arm64e.x1"]
        )
        let report = CompatibilityChecker().evaluate(requirements: requirements, profile: profile)
        expect(report.findings.first(where: { $0.criterion == .architecture })?.status == .unknown,
               "simulated architecture values are not treated as verified")
    }

    private func makeProfile(
        capabilities: Set<String>?,
        architectures: Set<String>?
    ) -> DeviceProfile {
        DeviceProfile(
            id: UUID(),
            name: "Linux test profile",
            model: "Generic iPhone",
            family: .iPhone,
            osVersion: "27.0",
            availableCapabilities: capabilities,
            supportedArchitectures: architectures
        )
    }

    private func requirements(
        minimumOS: String,
        family: Set<Int>,
        required: Set<String>,
        prohibited: Set<String>,
        architecture: Set<String>
    ) -> CompatibilityRequirements {
        CompatibilityRequirements(
            minimumOSVersion: minimumOS,
            supportedDeviceFamilies: family,
            requiredCapabilities: required,
            prohibitedCapabilities: prohibited,
            supportedPlatforms: ["iPhoneOS"],
            architectures: architecture
        )
    }

    private mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fatalError("FAILED: \(message)") }
    }
}
