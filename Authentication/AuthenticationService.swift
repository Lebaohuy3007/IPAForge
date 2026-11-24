import Foundation

enum AuthenticationError: LocalizedError, Equatable {
    case unsupported
    case twoFactorRequired
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Apple Account sign-in is not implemented. No credentials were sent or stored."
        case .twoFactorRequired:
            return "Two-factor verification is not available until Apple Account sign-in is implemented."
        case .invalidCredentials:
            return "The sign-in response could not be validated."
        }
    }
}

final class AuthenticationService {
    func startLogin(appleID: String, password: String) async throws {
        _ = appleID
        _ = password
        throw AuthenticationError.unsupported
    }

    func verify2FA(code: String) async throws {
        _ = code
        throw AuthenticationError.unsupported
    }

    func cancelLogin() {}
}
