import Foundation

/// Client for the community suggestions board on the proxy server: everyone
/// sees every suggestion, votes rank them (one per person, tap to toggle),
/// and near-duplicate submissions come back as a nudge toward the existing
/// entry — with an explicit "post anyway" override so similar-but-different
/// ideas are never blocked.
struct SuggestionsService {
    var session: URLSession = .shared

    struct Suggestion: Identifiable, Decodable, Equatable, Hashable {
        let id: Int
        let text: String
        let author: String
        let votes: Int
        let comments: Int
        let created_at: Double

        var createdDate: Date { Date(timeIntervalSince1970: created_at / 1000) }
    }

    struct Comment: Identifiable, Decodable {
        let author: String
        let text: String
        let created_at: Double
        var id: Double { created_at }
        var createdDate: Date { Date(timeIntervalSince1970: created_at / 1000) }
    }

    enum SubmitResult {
        case created
        /// Near-duplicates found — show them and offer vote/comment or force.
        case similar([Suggestion])
    }

    enum ServiceError: LocalizedError {
        case notConfigured, http(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Suggestions need an invite code (Settings → API keys)."
            case .http(let status):
                return "The server returned HTTP \(status)."
            }
        }
    }

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil) throws -> URLRequest {
        guard let (base, code) = ClaudeEndpoint.proxyConfig else {
            throw ServiceError.notConfigured
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(code, forHTTPHeaderField: "x-foob-user")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    func list() async throws -> (items: [Suggestion], votedIDs: Set<Int>) {
        struct Response: Decodable { let items: [Suggestion]; let voted: [Int] }
        let (data, response) = try await session.data(for: request("suggestions"))
        try Self.check(response)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.items, Set(decoded.voted))
    }

    func submit(_ text: String, force: Bool) async throws -> SubmitResult {
        struct Body: Encodable { let text: String; let force: Bool }
        struct SimilarResponse: Decodable { let similar: [Suggestion] }
        let (data, response) = try await session.data(
            for: request("suggestions", method: "POST", body: Body(text: text, force: force))
        )
        if let http = response as? HTTPURLResponse, http.statusCode == 409,
           let decoded = try? JSONDecoder().decode(SimilarResponse.self, from: data) {
            return .similar(decoded.similar)
        }
        try Self.check(response)
        return .created
    }

    /// Toggles this user's vote; returns the new state and count.
    func vote(_ id: Int) async throws -> (voted: Bool, votes: Int) {
        struct Response: Decodable { let voted: Bool; let votes: Int }
        let (data, response) = try await session.data(
            for: request("suggestions/\(id)/vote", method: "POST")
        )
        try Self.check(response)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.voted, decoded.votes)
    }

    func comments(for id: Int) async throws -> [Comment] {
        struct Response: Decodable { let items: [Comment] }
        let (data, response) = try await session.data(for: request("suggestions/\(id)/comments"))
        try Self.check(response)
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    func addComment(_ text: String, to id: Int) async throws {
        struct Body: Encodable { let text: String }
        let (_, response) = try await session.data(
            for: request("suggestions/\(id)/comments", method: "POST", body: Body(text: text))
        )
        try Self.check(response)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.http(http.statusCode)
        }
    }
}
