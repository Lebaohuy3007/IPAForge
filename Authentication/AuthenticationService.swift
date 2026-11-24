import Combine
import Foundation

enum AuthenticationError: LocalizedError, Equatable {
    case loginInProgress
    case verificationUnavailable
    case invalidVerificationCode
    case teamNotFound

    var errorDescription: String? {
        switch self {
        case .loginInProgress:
            return "An Apple Account sign-in is already in progress."
        case .verificationUnavailable:
            return "No two-factor verification request is awaiting a code."
        case .invalidVerificationCode:
            return "Enter the six-digit verification code."
        case .teamNotFound:
            return "The selected Developer Team is no longer available."
        }
    }
}

@MainActor
protocol AppleAuthenticationProviding {
    func signIn(
        appleID: String,
        password: String,
        anisetteHeaders: [String: String],
        requestVerificationCode: @escaping () async -> String?
    ) async throws -> StoredAppleAccount

    func restore(
        account: StoredAppleAccount,
        anisetteHeaders: [String: String]
    ) async throws -> StoredAppleAccount
}

@MainActor
final class AuthenticationService: ObservableObject {
    @Published private(set) var isAwaitingVerification = false
    @Published private(set) var isLoginInProgress = false
    @Published private(set) var currentAccount: StoredAppleAccount?
    var onVerificationStateChanged: (@MainActor (Bool) -> Void)?

    private let provider: AppleAuthenticationProviding
    private let vault: AppleAccountVault
    private var verificationContinuation: CheckedContinuation<String?, Never>?
    private var cancellationRequested = false

    init(
        vault: AppleAccountVault,
        provider: AppleAuthenticationProviding
    ) {
        self.vault = vault
        self.provider = provider
    }

    func startLogin(
        appleID: String,
        password: String,
        anisetteHeaders: [String: String]
    ) async throws -> StoredAppleAccount {
        guard !isLoginInProgress else {
            throw AuthenticationError.loginInProgress
        }

        isLoginInProgress = true
        cancellationRequested = false
        defer {
            isLoginInProgress = false
            if isAwaitingVerification {
                isAwaitingVerification = false
                onVerificationStateChanged?(false)
            }
            verificationContinuation = nil
        }

        do {
            let account = try await provider.signIn(
                appleID: appleID,
                password: password,
                anisetteHeaders: anisetteHeaders,
                requestVerificationCode: { [weak self] in
                    guard let self else { return nil }
                    return await self.waitForVerificationCode()
                }
            )
            guard !cancellationRequested else { throw CancellationError() }

            try vault.save(account)
            try vault.setSelectedAccountID(account.id)
            currentAccount = account
            return account
        } catch {
            if cancellationRequested {
                throw CancellationError()
            }
            throw error
        }
    }

    func restore(
        account: StoredAppleAccount,
        anisetteHeaders: [String: String]
    ) async throws -> StoredAppleAccount {
        currentAccount = nil
        do {
            let restoredAccount = try await provider.restore(
                account: account,
                anisetteHeaders: anisetteHeaders
            )
            try restoredAccount.validate()
            try vault.save(restoredAccount)
            currentAccount = restoredAccount
            return restoredAccount
        } catch {
            currentAccount = nil
            throw error
        }
    }

    func submitVerificationCode(_ code: String) throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.utf8.count == 6,
              trimmedCode.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw AuthenticationError.invalidVerificationCode
        }
        guard isAwaitingVerification, verificationContinuation != nil else {
            throw AuthenticationError.verificationUnavailable
        }
        resolveVerification(with: trimmedCode)
    }

    func cancelLogin() {
        cancellationRequested = true
        resolveVerification(with: nil)
    }

    func signOut() {
        cancelLogin()
        currentAccount = nil
    }

    private func waitForVerificationCode() async -> String? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || cancellationRequested {
                    continuation.resume(returning: nil)
                    return
                }
                verificationContinuation = continuation
                isAwaitingVerification = true
                onVerificationStateChanged?(true)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLogin()
            }
        }
    }

    private func resolveVerification(with code: String?) {
        guard let continuation = verificationContinuation else { return }
        verificationContinuation = nil
        isAwaitingVerification = false
        onVerificationStateChanged?(false)
        continuation.resume(returning: code)
    }
}
