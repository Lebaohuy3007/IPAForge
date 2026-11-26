import Foundation
import CoreFoundation
import ZIPFoundation

enum IPAInspectionError: LocalizedError, Equatable, Sendable {
    case fileNotFound
    case notIPA
    case notZipArchive
    case invalidArchive(String)
    case tooManyEntries
    case archiveTooLarge
    case unsafeEntryPath(String)
    case duplicateEntry(String)
    case missingAppInfo
    case ambiguousAppInfo
    case invalidInfoPlist
    case incompleteAppMetadata
    case missingExecutable
    case invalidExecutable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "The IPA file could not be read."
        case .notIPA: return "Choose a file with the .ipa extension."
        case .notZipArchive: return "The file does not have an IPA ZIP signature."
        case .invalidArchive(let reason): return "The IPA archive is invalid: \(reason)"
        case .tooManyEntries: return "The IPA contains too many archive entries to inspect safely."
        case .archiveTooLarge: return "The IPA expands beyond the supported inspection limit."
        case .unsafeEntryPath(let path): return "The IPA contains an unsafe archive path: \(path)"
        case .duplicateEntry(let path): return "The IPA contains a duplicate archive entry: \(path)"
        case .missingAppInfo: return "The IPA does not contain Payload/<App>.app/Info.plist."
        case .ambiguousAppInfo: return "The IPA contains more than one top-level app Info.plist."
        case .invalidInfoPlist: return "The app Info.plist is not a valid property list."
        case .incompleteAppMetadata: return "The app Info.plist is missing its bundle identifier or executable name."
        case .missingExecutable: return "The app executable listed in Info.plist is missing from the IPA."
        case .invalidExecutable: return "The app executable is not a recognized Mach-O binary."
        case .cancelled: return "IPA inspection was cancelled."
        }
    }
}

struct IPAInspection: Equatable, Sendable {
    let fileName: String
    let fileSizeBytes: Int64
    let archiveEntryCount: Int
    let bundleIdentifier: String
    let version: String?
    let buildNumber: String?
    let minimumOSVersion: String?
    let deviceFamilies: Set<Int>
    let requiredCapabilities: Set<String>?
    let prohibitedCapabilities: Set<String>?
    let supportedPlatforms: Set<String>?
    let architectures: Set<String>
    let executableName: String

    var compatibilityRequirements: CompatibilityRequirements {
        CompatibilityRequirements(
            minimumOSVersion: minimumOSVersion,
            supportedDeviceFamilies: deviceFamilies.isEmpty ? nil : deviceFamilies,
            requiredCapabilities: requiredCapabilities,
            prohibitedCapabilities: prohibitedCapabilities,
            supportedPlatforms: supportedPlatforms,
            architectures: architectures.isEmpty ? nil : architectures
        )
    }
}

struct IPAInspector: Sendable {
    private static let maximumEntries = 100_000
    private static let maximumExpandedBytes: UInt64 = 30 * 1024 * 1024 * 1024
    private static let maximumInfoPlistBytes = 8 * 1024 * 1024
    private static let executableHeaderBytes = 4 * 1024
    private static let archiveBufferSize = 64 * 1024

    func inspect(_ url: URL) throws -> IPAInspection {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw IPAInspectionError.fileNotFound
        }
        guard url.pathExtension.lowercased() == "ipa" else {
            throw IPAInspectionError.notIPA
        }
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize, fileSize >= 4 else {
            throw IPAInspectionError.notZipArchive
        }
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        guard try fileHandle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else {
            throw IPAInspectionError.notZipArchive
        }

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw IPAInspectionError.invalidArchive(error.localizedDescription)
        }

        let entries = Array(archive)
        guard !entries.isEmpty else {
            throw IPAInspectionError.invalidArchive("the archive is empty")
        }
        guard entries.count <= Self.maximumEntries else {
            throw IPAInspectionError.tooManyEntries
        }

        var paths = Set<String>()
        var expandedBytes: UInt64 = 0
        for entry in entries {
            let path = entry.path
            guard Self.isSafeArchivePath(path, isDirectory: entry.type == .directory) else {
                throw IPAInspectionError.unsafeEntryPath(path)
            }
            guard paths.insert(path).inserted else {
                throw IPAInspectionError.duplicateEntry(path)
            }
            let (newSize, overflow) = expandedBytes.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, newSize <= Self.maximumExpandedBytes else {
                throw IPAInspectionError.archiveTooLarge
            }
            expandedBytes = newSize
        }

        let appInfoEntries = entries.filter(Self.isTopLevelAppInfo)
        guard !appInfoEntries.isEmpty else { throw IPAInspectionError.missingAppInfo }
        guard appInfoEntries.count == 1, let infoEntry = appInfoEntries.first else {
            throw IPAInspectionError.ambiguousAppInfo
        }

        let infoPath = infoEntry.path
        let appDirectory = String(infoPath.dropLast("Info.plist".count))
        var infoData = Data()
        guard infoEntry.uncompressedSize <= Self.maximumInfoPlistBytes else {
            throw IPAInspectionError.invalidInfoPlist
        }
        let infoChecksum: CRC32
        do {
            infoChecksum = try archive.extract(
                infoEntry,
                bufferSize: Self.archiveBufferSize,
                skipCRC32: false,
                consumer: { chunk in
                    if Task.isCancelled { throw IPAInspectionError.cancelled }
                    guard infoData.count + chunk.count <= Self.maximumInfoPlistBytes else {
                        throw IPAInspectionError.invalidInfoPlist
                    }
                    infoData.append(chunk)
                }
            )
        } catch let error as IPAInspectionError {
            throw error
        } catch Archive.ArchiveError.invalidCRC32 {
            throw IPAInspectionError.invalidArchive("CRC mismatch in \(infoPath)")
        } catch {
            if Task.isCancelled { throw IPAInspectionError.cancelled }
            throw IPAInspectionError.invalidArchive(error.localizedDescription)
        }
        guard infoChecksum == infoEntry.checksum else {
            throw IPAInspectionError.invalidArchive("CRC mismatch in \(infoPath)")
        }
        let metadata = try Self.parseInfoPlist(infoData)
        let executablePath = appDirectory + metadata.executable
        guard entries.contains(where: { $0.path == executablePath && $0.type == .file }) else {
            throw IPAInspectionError.missingExecutable
        }

        // Stream every regular entry and compare its CRC. This checks the archive contents
        // without extracting untrusted paths or holding the package in memory.
        var executableHeader: Data?
        for entry in entries where entry.type != .directory && entry.path != infoPath {
            if Task.isCancelled { throw IPAInspectionError.cancelled }
            var header = Data()
            let checksum: CRC32
            do {
                checksum = try archive.extract(
                    entry,
                    bufferSize: Self.archiveBufferSize,
                    skipCRC32: false,
                    consumer: { chunk in
                        if Task.isCancelled { throw IPAInspectionError.cancelled }
                        if entry.path == executablePath, header.count < Self.executableHeaderBytes {
                            let remaining = Self.executableHeaderBytes - header.count
                            header.append(chunk.prefix(remaining))
                        }
                    }
                )
            } catch let error as IPAInspectionError {
                throw error
            } catch Archive.ArchiveError.invalidCRC32 {
                throw IPAInspectionError.invalidArchive("CRC mismatch in \(entry.path)")
            } catch {
                if Task.isCancelled { throw IPAInspectionError.cancelled }
                throw IPAInspectionError.invalidArchive(error.localizedDescription)
            }
            guard checksum == entry.checksum else {
                throw IPAInspectionError.invalidArchive("CRC mismatch in \(entry.path)")
            }
            if entry.path == executablePath {
                executableHeader = header
            }
        }

        guard let executableHeader,
              let architectures = Self.machOArchitectures(from: executableHeader) else {
            throw IPAInspectionError.invalidExecutable
        }

        return IPAInspection(
            fileName: url.lastPathComponent,
            fileSizeBytes: Int64(fileSize),
            archiveEntryCount: entries.count,
            bundleIdentifier: metadata.bundleIdentifier,
            version: metadata.version,
            buildNumber: metadata.buildNumber,
            minimumOSVersion: metadata.minimumOSVersion,
            deviceFamilies: metadata.deviceFamilies,
            requiredCapabilities: metadata.requiredCapabilities,
            prohibitedCapabilities: metadata.prohibitedCapabilities,
            supportedPlatforms: metadata.supportedPlatforms,
            architectures: architectures,
            executableName: metadata.executable
        )
    }

    private struct ParsedInfoPlist {
        let bundleIdentifier: String
        let executable: String
        let version: String?
        let buildNumber: String?
        let minimumOSVersion: String?
        let deviceFamilies: Set<Int>
        let requiredCapabilities: Set<String>?
        let prohibitedCapabilities: Set<String>?
        let supportedPlatforms: Set<String>?
    }

    private static func parseInfoPlist(_ data: Data) throws -> ParsedInfoPlist {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw IPAInspectionError.invalidInfoPlist
        }
        guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty,
              !executable.contains("/"),
              !executable.contains("\\"),
              executable != ".",
              executable != ".." else {
            throw IPAInspectionError.incompleteAppMetadata
        }

        let families = Self.parseDeviceFamilies(plist["UIDeviceFamily"]) ?? []
        let requiredPlatforms = (plist["CFBundleSupportedPlatforms"] as? [String]).map { Set($0) }
        let capabilities = Self.parseCapabilities(plist["UIRequiredDeviceCapabilities"])

        return ParsedInfoPlist(
            bundleIdentifier: bundleIdentifier,
            executable: executable,
            version: plist["CFBundleShortVersionString"] as? String,
            buildNumber: plist["CFBundleVersion"] as? String,
            minimumOSVersion: plist["MinimumOSVersion"] as? String,
            deviceFamilies: families,
            requiredCapabilities: capabilities?.required,
            prohibitedCapabilities: capabilities?.prohibited,
            supportedPlatforms: requiredPlatforms
        )
    }

    private static func parseCapabilities(_ value: Any?) -> (required: Set<String>, prohibited: Set<String>)? {
        guard let value else { return nil }
        if let names = value as? [String] {
            return (Set(names), [])
        }
        if let dictionary = value as? [String: Any] {
            var required = Set<String>()
            var prohibited = Set<String>()
            for (name, value) in dictionary {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
                let enabled = number.boolValue
                if enabled {
                    required.insert(name)
                } else {
                    prohibited.insert(name)
                }
            }
            return (required, prohibited)
        }
        return nil
    }

    private static func parseDeviceFamilies(_ value: Any?) -> Set<Int>? {
        guard let value else { return nil }
        let values: [NSNumber]
        if let array = value as? [NSNumber] {
            values = array
        } else if let number = value as? NSNumber {
            values = [number]
        } else {
            return nil
        }

        var families = Set<Int>()
        for number in values {
            let numericValue = number.doubleValue
            guard CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID(),
                  numericValue.isFinite,
                  numericValue.rounded(.towardZero) == numericValue,
                  let family = Int(exactly: numericValue) else { return nil }
            families.insert(family)
        }
        return families
    }

    private static func isTopLevelAppInfo(_ entry: Entry) -> Bool {
        guard entry.type == .file, entry.path.hasPrefix("Payload/"), entry.path.hasSuffix(".app/Info.plist") else {
            return false
        }
        let components = entry.path.split(separator: "/")
        return components.count == 3 && components[1].hasSuffix(".app") && components[2] == "Info.plist"
    }

    private static func isSafeArchivePath(_ path: String, isDirectory: Bool) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let normalized = isDirectory && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !normalized.isEmpty else { return false }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." })
    }

    private static func machOArchitectures(from header: Data) -> Set<String>? {
        guard header.count >= 4 else { return nil }
        let magic = Array(header.prefix(4))
        if magic == [0xCF, 0xFA, 0xED, 0xFE] || magic == [0xFE, 0xED, 0xFA, 0xCF] {
            guard header.count >= 32 else { return nil }
            let littleEndian = magic[0] == 0xCF
            let cpuType = readUInt32(header, offset: 4, littleEndian: littleEndian)
            let cpuSubtype = readUInt32(header, offset: 8, littleEndian: littleEndian)
            return Set([architectureName(cpuType, cpuSubtype: cpuSubtype)].compactMap { $0 })
        }

        let fat32Big = magic == [0xCA, 0xFE, 0xBA, 0xBE]
        let fat32Little = magic == [0xBE, 0xBA, 0xFE, 0xCA]
        let fat64Big = magic == [0xCA, 0xFE, 0xBA, 0xBF]
        let fat64Little = magic == [0xBF, 0xBA, 0xFE, 0xCA]
        guard fat32Big || fat32Little || fat64Big || fat64Little, header.count >= 8 else { return nil }

        let littleEndian = fat32Little || fat64Little
        let is64 = fat64Big || fat64Little
        let count = Int(readUInt32(header, offset: 4, littleEndian: littleEndian))
        let stride = is64 ? 32 : 20
        guard count > 0, count <= 64, 8 + count * stride <= header.count else { return nil }
        var architectures = Set<String>()
        for index in 0..<count {
            let offset = 8 + index * stride
            let cpuType = readUInt32(header, offset: offset, littleEndian: littleEndian)
            let cpuSubtype = readUInt32(header, offset: offset + 4, littleEndian: littleEndian)
            if let architecture = architectureName(cpuType, cpuSubtype: cpuSubtype) {
                architectures.insert(architecture)
            }
        }
        return architectures
    }

    private static func architectureName(_ cpuType: UInt32, cpuSubtype: UInt32) -> String? {
        let subtype = cpuSubtype & 0x00FF_FFFF
        switch cpuType {
        case 7:
            return subtype == 3 ? "i386" : nil
        case 12:
            switch subtype {
            case 9: return "armv7"
            case 11: return "armv7s"
            case 12: return "armv7k"
            default: return nil
            }
        case 0x0100_0007:
            switch subtype {
            case 3: return "x86_64"
            case 8: return "x86_64h"
            default: return nil
            }
        case 0x0100_000C:
            switch subtype {
            case 0, 1: return "arm64"
            case 2: return "arm64e"
            case 12: return "arm64e.x1"
            default: return nil
            }
        case 0x0200_000C:
            return subtype == 1 ? "arm64_32" : nil
        default: return nil
        }
    }

    private static func readUInt32(_ data: Data, offset: Int, littleEndian: Bool) -> UInt32 {
        let bytes = (0..<4).map { UInt32(data[offset + $0]) }
        if littleEndian {
            return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
        }
        return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }
}
