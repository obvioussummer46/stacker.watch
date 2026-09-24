import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SNError: Error, Equatable, Sendable {
    case http(Int)
    case graphQL([String])
    case decoding(String)
    case transport(String)

    public var message: String {
        switch self {
        case .http(let code): return "Server returned \(code)"
        case .graphQL(let messages): return messages.first ?? "GraphQL error"
        case .decoding(let detail): return "Bad response: \(detail)"
        case .transport(let detail): return detail
        }
    }
}

/// Abstracts the network so tests can stub it.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: SNError.transport(error.localizedDescription))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), status))
            }
            task.resume()
        }
    }
}

public struct GraphQLClient: Sendable {
    public static let defaultEndpoint = URL(string: "https://stacker.news/api/graphql")!

    public let endpoint: URL
    private let transport: HTTPTransport

    public init(endpoint: URL = GraphQLClient.defaultEndpoint, transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// Builds the JSON request body. Exposed for tests.
    public static func body(query: String, variables: [String: Any?]) throws -> Data {
        var cleaned: [String: Any] = [:]
        for (key, value) in variables {
            if let value { cleaned[key] = value }
        }
        return try JSONSerialization.data(withJSONObject: ["query": query, "variables": cleaned])
    }

    public func request(query: String, variables: [String: Any?]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StackerWatch/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try Self.body(query: query, variables: variables)
        return request
    }

    public func execute<T: Decodable>(_ query: String, variables: [String: Any?], as type: T.Type) async throws -> T {
        let request = try self.request(query: query, variables: variables)
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw SNError.http(status) }
        return try Self.decode(data, as: type)
    }

    /// Unwraps the `{ data, errors }` envelope. Exposed for tests.
    /// Errors win: the server sends `data: { items: null }` alongside `errors`.
    public static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        if let errors = try? JSONDecoder.sn.decode(ErrorsOnly.self, from: data).errors, !errors.isEmpty {
            throw SNError.graphQL(errors.map(\.message))
        }
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder.sn.decode(Envelope<T>.self, from: data)
        } catch {
            throw SNError.decoding(String(describing: error))
        }
        guard let payload = envelope.data else { throw SNError.graphQL(["Empty response"]) }
        return payload
    }

    struct ErrorsOnly: Decodable {
        let errors: [GQLError]?
    }

    struct Envelope<T: Decodable>: Decodable {
        let data: T?
    }

    struct GQLError: Decodable {
        let message: String
    }
}
