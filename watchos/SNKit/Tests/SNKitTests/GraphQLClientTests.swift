import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SNKit

final class StubTransport: HTTPTransport, @unchecked Sendable {
    var response: (Data, Int)
    var lastRequest: URLRequest?
    init(_ data: Data, status: Int = 200) { response = (data, status) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lastRequest = request
        return response
    }
}

final class GraphQLClientTests: XCTestCase {
    func testRequestShape() async throws {
        let stub = StubTransport(try Fixtures.data("feed_hot"))
        let api = SNAPI(client: GraphQLClient(transport: stub))
        _ = try await api.fetchFeed(FeedKey(kind: .topWeek, discussionsOnly: true))

        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GraphQLClient.defaultEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let vars = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(vars["sort"] as? String, "top")
        XCTAssertEqual(vars["when"] as? String, "week")
        XCTAssertEqual(vars["type"] as? String, "discussions")
        XCTAssertEqual(vars["limit"] as? Int, 21)
        XCTAssertNil(vars["cursor"])
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.contains("query WatchFeed"))
    }

    func testHotFeedSendsNoSort() throws {
        let vars = FeedKey(kind: .hot, discussionsOnly: false).variables(cursor: "abc")
        XCTAssertNil(vars["sort"] ?? nil)
        XCTAssertNil(vars["type"] ?? nil)
        XCTAssertEqual(vars["cursor"] as? String, "abc")
        let body = try GraphQLClient.body(query: "q", variables: vars)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let sent = try XCTUnwrap(json?["variables"] as? [String: Any])
        XCTAssertEqual(Set(sent.keys), ["cursor", "limit"])
    }

    func testHTTPErrorSurfaces() async throws {
        let stub = StubTransport(Data(), status: 503)
        let api = SNAPI(client: GraphQLClient(transport: stub))
        do {
            _ = try await api.fetchFeed(FeedKey())
            XCTFail("expected throw")
        } catch let error as SNError {
            XCTAssertEqual(error, .http(503))
        }
    }

    func testMalformedJSONIsDecodingError() async throws {
        let stub = StubTransport(Data("not json".utf8))
        let api = SNAPI(client: GraphQLClient(transport: stub))
        do {
            _ = try await api.fetchFeed(FeedKey())
            XCTFail("expected throw")
        } catch let error as SNError {
            guard case .decoding = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testMissingItemThrows() async throws {
        let stub = StubTransport(Data(#"{"data":{"item":null}}"#.utf8))
        let api = SNAPI(client: GraphQLClient(transport: stub))
        do {
            _ = try await api.fetchItem(id: "0")
            XCTFail("expected throw")
        } catch let error as SNError {
            XCTAssertEqual(error, .graphQL(["Post not found"]))
        }
    }
}
