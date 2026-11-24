import Foundation
import StosSign_API
import StosSign_Auth
import StosSign_Common

enum StosSignAuthenticationError: LocalizedError {
    case invalidAnisetteData
    case invalidSession
    case accountMismatch

    var errorDescription: String? {
        switch self {
        case .invalidAnisetteData:
            return "The selected Anisette Server returned incomplete authentication data."
        case .invalidSession:
            return "The saved Apple Account session is incomplete or unsupported."
        case .accountMismatch:
            return "The restored Apple session belongs to a different Apple Account."
        }
    }
}

@MainActor
final class StosSignAuthenticationProvider: AppleAuthenticationProviding {
    private struct SessionRecord: Codable {
        let version: Int
        let dsid: String
        let authToken: String
    }

    func signIn(
        appleID: String,
        password: String,
        anisetteHeaders: [String: String],
        requestVerificationCode: @escaping () async -> String?
    ) async throws -> StoredAppleAccount {
        let anisetteData = try makeAnisetteData(from: anisetteHeaders)
        let (account, session) = try await Authentication.authenticate(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            verificationHandler: { completion in
                completion(await requestVerificationCode())
            }
        )
        let teams = try await AppleAPI.shared.fetchTeamsForAccount(account: account, session: session)
        guard !teams.isEmpty else {
            throw StosSignAuthenticationError.invalidSession
        }
        return try makeStoredAccount(account: account, session: session, teams: teams)
    }

    func restore(
        account: StoredAppleAccount,
        anisetteHeaders: [String: String]
    ) async throws -> StoredAppleAccount {
        let sessionRecord = try JSONDecoder().decode(SessionRecord.self, from: account.sessionData)
        guard sessionRecord.version == 1,
              !sessionRecord.dsid.isEmpty,
              !sessionRecord.authToken.isEmpty else {
            throw StosSignAuthenticationError.invalidSession
        }

        let session = AppleAPISession(
            dsid: sessionRecord.dsid,
            authToken: sessionRecord.authToken,
            anisetteData: try makeAnisetteData(from: anisetteHeaders)
        )
        let appleAccount = try await AppleAPI.shared.fetchAccount(session: session)
        guard appleAccount.appleID.caseInsensitiveCompare(account.appleID) == .orderedSame else {
            throw StosSignAuthenticationError.accountMismatch
        }
        let teams = try await AppleAPI.shared.fetchTeamsForAccount(account: appleAccount, session: session)
        return try makeStoredAccount(
            id: account.id,
            account: appleAccount,
            session: session,
            teams: teams,
            selectedTeamID: account.selectedTeamID,
            storeCountry: account.storeCountry
        )
    }

    private func makeStoredAccount(
        id: UUID = UUID(),
        account: Account,
        session: StosSign_API.AppleAPISession,
        teams: [Team],
        selectedTeamID: String? = nil,
        storeCountry: String? = nil
    ) throws -> StoredAppleAccount {
        let sessionRecord = SessionRecord(version: 1, dsid: session.dsid, authToken: session.authToken)
        let sessionData = try JSONEncoder().encode(sessionRecord)
        let storedTeams = teams.map {
            AppleDeveloperTeam(id: $0.identifier, name: $0.name)
        }
        let storedAccount = StoredAppleAccount(
            id: id,
            appleID: account.appleID,
            sessionData: sessionData,
            teams: storedTeams,
            selectedTeamID: selectedTeamID,
            savedPassword: nil,
            storeCountry: storeCountry
        )
        try storedAccount.validate()
        return storedAccount
    }

    private func makeAnisetteData(from headers: [String: String]) throws -> AnisetteData {
        guard let machineID = headers["X-Apple-I-MD-M"],
              let oneTimePassword = headers["X-Apple-I-MD"],
              let localUserID = headers["X-Apple-I-MD-LU"],
              let routingInfoValue = headers["X-Apple-I-MD-RINFO"],
              let routingInfo = UInt64(routingInfoValue),
              let deviceID = headers["X-Mme-Device-Id"],
              let clientInfo = headers["X-MMe-Client-Info"],
              let serialNumber = headers["X-Apple-I-SRL-NO"] else {
            throw StosSignAuthenticationError.invalidAnisetteData
        }

        return AnisetteData(
            machineID: machineID,
            oneTimePassword: oneTimePassword,
            localUserID: localUserID,
            routingInfo: routingInfo,
            deviceUniqueIdentifier: deviceID,
            deviceSerialNumber: serialNumber,
            deviceDescription: clientInfo,
            date: Date(),
            locale: Locale.current,
            timeZone: TimeZone.current
        )
    }
}
