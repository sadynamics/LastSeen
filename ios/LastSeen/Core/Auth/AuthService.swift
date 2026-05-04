//
//  AuthService.swift
//

import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthService {
    enum SessionState: Sendable {
        case unknown
        case signedOut
        case signedIn(User)
    }

    private(set) var state: SessionState = .unknown
    private(set) var token: String?
    private(set) var lastError: String?

    var isAuthenticated: Bool {
        if case .signedIn = state { return true }
        return false
    }

    private let api: APIClient
    private let tokenKey = "jwt"
    private let userKey = "user"

    init(api: APIClient) {
        self.api = api
    }

    func restoreSessionIfAny() async {
        if let token = KeychainStore.get(tokenKey) {
            self.token = token
            if let userJSON = KeychainStore.get(userKey),
               let data = userJSON.data(using: .utf8),
               let user = try? makeDecoder().decode(User.self, from: data) {
                state = .signedIn(user)
                return
            }
        }
        state = .signedOut
    }

    func signIn(with credential: ASAuthorizationAppleIDCredential) async throws {
        LSAnalytics.shared.log(.signInStarted(method: "apple"))
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            let err = NSError(domain: "AuthService", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing identity token"])
            LSAnalytics.shared.log(.signInFailed(method: "apple", reason: "missing_identity_token"))
            LSAnalytics.shared.logError(err, context: ["operation": "sign_in_apple"])
            throw err
        }
        let req = AppleSignInRequest(
            identityToken: identityToken,
            email: credential.email,
            locale: Locale.current.identifier
        )
        do {
            let resp: AppleSignInResponse = try await api.post("/v1/auth/apple", body: req)
            token = resp.token
            KeychainStore.set(resp.token, for: tokenKey)
            if let json = try? makeEncoder().encode(resp.user),
               let s = String(data: json, encoding: .utf8) {
                KeychainStore.set(s, for: userKey)
            }
            state = .signedIn(resp.user)
            lastError = nil

            LSAnalytics.shared.setUser(id: resp.user.id, email: resp.user.email)
            LSAnalytics.shared.log(.signInSucceeded(method: "apple", userId: resp.user.id))
        } catch {
            LSAnalytics.shared.log(.signInFailed(method: "apple",
                                                 reason: shortReason(for: error)))
            LSAnalytics.shared.logError(error, context: ["operation": "sign_in_apple"])
            throw error
        }
    }

    func signOut() async {
        token = nil
        KeychainStore.delete(tokenKey)
        KeychainStore.delete(userKey)
        state = .signedOut
        LSAnalytics.shared.log(.signOut)
        LSAnalytics.shared.clearUser()
    }

    func deleteAccount() async throws {
        do {
            try await api.delete("/v1/me")
            LSAnalytics.shared.log(.accountDeleted)
            await signOut()
        } catch {
            LSAnalytics.shared.logError(error, context: ["operation": "delete_account"])
            throw error
        }
    }

    /// Map an arbitrary error to a short, low-cardinality reason string suitable
    /// for an analytics parameter. Avoids leaking PII or per-request details.
    private func shortReason(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .invalidURL: return "invalid_url"
            case .transport: return "transport"
            case .decode: return "decode"
            case .server(let status, let code, _): return "server_\(status)_\(code ?? "unknown")"
            case .unauthorized: return "unauthorized"
            case .subscriptionRequired: return "subscription_required"
            case .offline: return "offline"
            }
        }
        return "unknown"
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}
