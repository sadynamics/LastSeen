//
//  APIClient.swift
//

import Foundation

nonisolated enum APIError: LocalizedError, Sendable {
    case invalidURL
    case transport(URLError)
    case decode(String)
    case server(status: Int, code: String?, message: String?)
    case unauthorized
    case subscriptionRequired
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .transport(let e): e.localizedDescription
        case .decode: "Couldn't read the server's response."
        case .server(_, _, let m): m ?? "Server error"
        case .unauthorized: "Please sign in again."
        case .subscriptionRequired: "Subscription required to continue."
        case .offline: "You appear to be offline."
        }
    }

    var isAuthError: Bool { if case .unauthorized = self { return true } else { return false } }
}

private nonisolated struct APIErrorBody: Decodable, Sendable {
    let code: String?
    let message: String?
}

private nonisolated struct EmptyBody: Encodable, Sendable {}
private nonisolated struct EmptyResponse: Decodable, Sendable {}

@MainActor
final class APIClient {
    let baseURL: URL
    var tokenProvider: (@MainActor () -> String?)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "LastSeen/iOS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "1.0")"
        ]
        self.session = URLSession(configuration: cfg)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        dec.keyDecodingStrategy = .useDefaultKeys
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: - Public requests

    @discardableResult
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], as: T.Type = T.self) async throws -> T {
        try await request(method: "GET", path: path, query: query, body: Optional<EmptyBody>.none)
    }

    @discardableResult
    func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as: T.Type = T.self) async throws -> T {
        try await request(method: "POST", path: path, query: [], body: body)
    }

    @discardableResult
    func put<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as: T.Type = T.self) async throws -> T {
        try await request(method: "PUT", path: path, query: [], body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE",
                                                 path: path,
                                                 query: [],
                                                 body: Optional<EmptyBody>.none,
                                                 allowEmpty: true)
    }

    // MARK: - Internals

    private func request<B: Encodable & Sendable, T: Decodable & Sendable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: B?,
        allowEmpty: Bool = false
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider?() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try encoder.encode(body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let err as URLError where err.code == .notConnectedToInternet || err.code == .dataNotAllowed {
            throw APIError.offline
        } catch let err as URLError {
            throw APIError.transport(err)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, code: nil, message: "Unexpected response")
        }
        switch http.statusCode {
        case 200..<300:
            if data.isEmpty || allowEmpty {
                if let empty = EmptyResponse() as? T { return empty }
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decode("\(error)")
            }
        case 401:
            throw APIError.unauthorized
        case 402:
            throw APIError.subscriptionRequired
        default:
            let parsed = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.server(status: http.statusCode, code: parsed?.code, message: parsed?.message)
        }
    }
}
