import CryptoKit
import Foundation
import Security

struct AppleDeveloperTeam: Codable, Equatable, Identifiable {
    let id: String
    let name: String
}

struct StoredAppleAccount: Codable, Equatable, Identifiable {
    let id: UUID
    let appleID: String
    let sessionData: Data
    let teams: [AppleDeveloperTeam]
    let selectedTeamID: String?
    let savedPassword: String?
    let storeCountry: String?

    func validate() throws {
        guard !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sessionData.isEmpty,
              teams.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              Set(teams.map(\.id)).count == teams.count,
              selectedTeamID == nil || teams.contains(where: { $0.id == selectedTeamID }),
              storeCountry == nil || (storeCountry!.count == 2) else {
            throw AppleAccountVaultError.invalidAccount
        }
    }
}

struct StoredAnisetteIdentity: Codable, Equatable {
    let identifier: String
    let deviceID: String
    let adiPB: String

    func validate() throws {
        guard !identifier.isEmpty,
              UUID(uuidString: deviceID) != nil,
              let provisioningData = Data(base64Encoded: adiPB),
              !provisioningData.isEmpty else {
            throw AppleAccountVaultError.invalidAnisetteIdentity
        }
    }
}

enum AppleAccountVaultError: LocalizedError, Equatable {
    case invalidAccount
    case invalidAnisetteIdentity
    case accountNotFound
    case keychainFailure(Int32)
    case missingEncryptionKey
    case invalidEncryptionKey
    case corruptRecord
    case encryptionFailure

    var errorDescription: String? {
        switch self {
        case .invalidAccount:
            return "The saved Apple Account session is incomplete or inconsistent."
        case .invalidAnisetteIdentity:
            return "The saved Anisette identity is incomplete or invalid."
        case .accountNotFound:
            return "The saved Apple Account could not be found."
        case .keychainFailure:
            return "Secure account storage is unavailable."
        case .missingEncryptionKey:
            return "The key for the saved Apple Account sessions is missing."
        case .invalidEncryptionKey:
            return "The secure account encryption key is invalid."
        case .corruptRecord:
            return "A saved Apple Account record could not be verified."
        case .encryptionFailure:
            return "The Apple Account session could not be encrypted."
        }
    }
}

protocol KeychainDataStoring {
    func data(for key: String) throws -> Data?
    func setData(_ data: Data, for key: String) throws
    func deleteData(for key: String) throws
    func keys(withPrefix prefix: String) throws -> [String]
}

final class AppleAccountVault {
    private let keychain: KeychainDataStoring
    private let encryptionKeyLock = NSLock()
    private let accountKeyPrefix = "account."
    private let encryptionKeyName = "encryption-key"
    private let selectedAccountName = "selected-account"

    init(keychain: KeychainDataStoring = SystemKeychainDataStore()) {
        self.keychain = keychain
    }

    func accounts() throws -> [StoredAppleAccount] {
        try keychain.keys(withPrefix: accountKeyPrefix)
            .map { key in
                guard let accountID = UUID(uuidString: String(key.dropFirst(accountKeyPrefix.count))),
                      let encryptedRecord = try keychain.data(for: key) else {
                    throw AppleAccountVaultError.corruptRecord
                }
                let plaintext = try open(encryptedRecord, for: key)
                let account = try JSONDecoder().decode(StoredAppleAccount.self, from: plaintext)
                try account.validate()
                guard account.id == accountID else {
                    throw AppleAccountVaultError.corruptRecord
                }
                return account
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func save(_ account: StoredAppleAccount) throws {
        try account.validate()
        let key = accountKey(for: account.id)
        let plaintext = try JSONEncoder().encode(account)
        try keychain.setData(seal(plaintext, for: key), for: key)
    }

    func deleteAccount(id: UUID) throws {
        let key = accountKey(for: id)
        guard try keychain.data(for: key) != nil else {
            throw AppleAccountVaultError.accountNotFound
        }
        let selectedID = try selectedAccountID()
        if selectedID == id {
            try setSelectedAccountID(nil)
        }
        try keychain.deleteData(for: key)
    }

    func deleteAllAccounts() throws {
        try setSelectedAccountID(nil)
        for key in try keychain.keys(withPrefix: accountKeyPrefix) {
            try keychain.deleteData(for: key)
        }
    }

    func selectedAccountID() throws -> UUID? {
        guard let encryptedID = try keychain.data(for: selectedAccountName) else {
            return nil
        }
        let plaintext = try open(encryptedID, for: selectedAccountName)
        return try JSONDecoder().decode(UUID.self, from: plaintext)
    }

    func setSelectedAccountID(_ id: UUID?) throws {
        guard let id else {
            try keychain.deleteData(for: selectedAccountName)
            return
        }
        guard try keychain.data(for: accountKey(for: id)) != nil else {
            throw AppleAccountVaultError.accountNotFound
        }
        let plaintext = try JSONEncoder().encode(id)
        try keychain.setData(seal(plaintext, for: selectedAccountName), for: selectedAccountName)
    }

    func anisetteIdentity(forServer serverURL: String) throws -> StoredAnisetteIdentity? {
        let key = anisetteIdentityKey(for: serverURL)
        guard let encryptedRecord = try keychain.data(for: key) else {
            return nil
        }
        let plaintext = try open(encryptedRecord, for: key)
        let identity = try JSONDecoder().decode(StoredAnisetteIdentity.self, from: plaintext)
        try identity.validate()
        return identity
    }

    func saveAnisetteIdentity(_ identity: StoredAnisetteIdentity, forServer serverURL: String) throws {
        try identity.validate()
        let key = anisetteIdentityKey(for: serverURL)
        let plaintext = try JSONEncoder().encode(identity)
        try keychain.setData(seal(plaintext, for: key), for: key)
    }

    func clearAnisetteIdentity(forServer serverURL: String) throws {
        let normalizedURL = try normalizedAnisetteServerURL(serverURL)
        try keychain.deleteData(for: anisetteConsentKey(for: normalizedURL))
        try keychain.deleteData(for: anisetteIdentityKey(for: normalizedURL))
    }

    func isAnisetteServerApproved(forServer serverURL: String) throws -> Bool {
        let normalizedURL = try normalizedAnisetteServerURL(serverURL)
        let key = anisetteConsentKey(for: normalizedURL)
        guard let encryptedApproval = try keychain.data(for: key) else { return false }
        return try open(encryptedApproval, for: key) == Data([1])
    }

    func approveAnisetteServer(forServer serverURL: String) throws {
        let normalizedURL = try normalizedAnisetteServerURL(serverURL)
        let key = anisetteConsentKey(for: normalizedURL)
        try keychain.setData(seal(Data([1]), for: key), for: key)
    }

    private func accountKey(for id: UUID) -> String {
        accountKeyPrefix + id.uuidString.lowercased()
    }

    private func anisetteIdentityKey(for serverURL: String) -> String {
        let digest = SHA256.hash(data: Data(serverURL.utf8))
        return "anisette." + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func anisetteConsentKey(for serverURL: String) -> String {
        let digest = SHA256.hash(data: Data(serverURL.utf8))
        return "anisette-consent." + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedAnisetteServerURL(_ serverURL: String) throws -> String {
        guard let normalized = AnisetteURLValidator.normalized(serverURL) else {
            throw AnisetteServerError.invalidURL
        }
        return normalized
    }

    private func seal(_ plaintext: Data, for recordName: String) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext,
            using: encryptionKey(createIfMissing: true),
            authenticating: Data("IPAForge.account.v1:\(recordName)".utf8)
        )
        guard let combined = box.combined else {
            throw AppleAccountVaultError.encryptionFailure
        }
        return combined
    }

    private func open(_ ciphertext: Data, for recordName: String) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(
                box,
                using: encryptionKey(createIfMissing: false),
                authenticating: Data("IPAForge.account.v1:\(recordName)".utf8)
            )
        } catch is CryptoKitError {
            throw AppleAccountVaultError.corruptRecord
        }
    }

    private func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey {
        encryptionKeyLock.lock()
        defer { encryptionKeyLock.unlock() }

        if let storedKey = try keychain.data(for: encryptionKeyName) {
            guard storedKey.count == 32 else {
                throw AppleAccountVaultError.invalidEncryptionKey
            }
            return SymmetricKey(data: storedKey)
        }
        guard createIfMissing else {
            throw AppleAccountVaultError.missingEncryptionKey
        }
        let key = SymmetricKey(size: .bits256)
        let rawKey = key.withUnsafeBytes { Data($0) }
        try keychain.setData(rawKey, for: encryptionKeyName)
        return key
    }
}

private final class SystemKeychainDataStore: KeychainDataStoring {
    private let service = Bundle.main.bundleIdentifier ?? "com.Lebaohuy3007.ipaforge"

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppleAccountVaultError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw AppleAccountVaultError.corruptRecord
        }
        return data
    }

    func setData(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let updates = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, updates)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppleAccountVaultError.keychainFailure(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppleAccountVaultError.keychainFailure(addStatus)
        }
    }

    func deleteData(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleAccountVaultError.keychainFailure(status)
        }
    }

    func keys(withPrefix prefix: String) throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        query[kSecAttrSynchronizable as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw AppleAccountVaultError.keychainFailure(status)
        }

        let attributes: [[String: Any]]
        if let values = result as? [[String: Any]] {
            attributes = values
        } else if let value = result as? [String: Any] {
            attributes = [value]
        } else {
            throw AppleAccountVaultError.corruptRecord
        }
        return attributes.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
    }
}
