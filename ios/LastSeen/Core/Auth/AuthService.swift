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
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw NSError(domain: "AuthService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing identity token"])
        }
        let req = AppleSignInRequest(
            identityToken: identityToken,
            email: credential.email,
            locale: Locale.current.identifier
        )
        let resp: AppleSignInResponse = try await api.post("/v1/auth/apple", body: req)
        token = resp.token
        KeychainStore.set(resp.token, for: tokenKey)
        if let json = try? makeEncoder().encode(resp.user),
           let s = String(data: json, encoding: .utf8) {
            KeychainStore.set(s, for: userKey)
        }
        state = .signedIn(resp.user)
        lastError = nil
    }

    func signOut() async {
        token = nil
        KeychainStore.delete(tokenKey)
        KeychainStore.delete(userKey)
        state = .signedOut
    }

    func deleteAccount() async throws {
        try await api.delete("/v1/me")
        await signOut()
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}
