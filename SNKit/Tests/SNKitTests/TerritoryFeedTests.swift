import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SNKit

/// Returns a queued response per request, so multi-page paths can be exercised.
final class SequenceTransport: HTTPTransport, @unchecked Sendable {
    private var pages: [Data]
    var requests: [URLRequest] = []

    init(_ pages: [Data]) { self.pages = pages }

    var requestCount: Int { requests.count }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !pages.isEmpty else { throw SNError.transport("no more stubbed pages") }
        return (pages.removeFirst(), 200)
    }

    /// The `variables` dictionary of the nth request.
    func variables(at index: Int) throws -> [String: Any] {
        let body = try XCTUnwrap(requests[index].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(json["variables"] as? [String: Any])
    }
}

/// A territory feed is assembled from the site-wide feed, because `items(sub:)`
/// withholds posts under the territory's sats filter.
final class TerritoryFeedTests: XCTestCase {
    /// Builds one page of the `items` query with the given `(id, subNames)` items.
    private func page(_ items: [(String, [String])], cursor: String?) throws -> Data {
        let entries = items.map { id, subs in
            let names = subs.map { "\"\($0)\"" }.joined(separator: ",")
            return """
            {"id":"\(id)","title":"Post \(id)","url":null,"text":"body","sats":0,"boost":0,
             "ncomments":0,"createdAt":"2026-09-24T10:00:00.000Z","subNames":[\(names)],
             "user":{"name":"k00b"}}
            """
        }.joined(separator: ",")
        let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"data":{"items":{"cursor":\(cursorJSON),"items":[\(entries)]}}}
        """.utf8)
    }

    private func api(_ pages: [Data]) -> (SNAPI, SequenceTransport) {
        let transport = SequenceTransport(pages)
        return (SNAPI(client: GraphQLClient(transport: transport)), transport)
    }

    // MARK: Filtering

    func testKeepsOnlyPostsInTheTerritory() async throws {
        let (api, _) = api([try page([("1", ["bitcoin"]), ("2", ["econ"]), ("3", ["bitcoin"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"))
        XCTAssertEqual(result.items.map(\.id), ["1", "3"])
    }

    func testKeepsCrossPosts() async throws {
        let (api, _) = api([try page([("1", ["econ", "bitcoin"]), ("2", ["econ"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"))
        XCTAssertEqual(result.items.map(\.id), ["1"], "a cross-post counts as being in the territory")
    }

    func testMatchesTerritoryNameCaseInsensitively() async throws {
        let (api, _) = api([try page([("1", ["Stacker_Sports"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "stacker_sports"))
        XCTAssertEqual(result.items.map(\.id), ["1"])
    }

    func testIncludesZeroSatPosts() async throws {
        // The whole point: these are exactly what items(sub:) hides.
        let (api, _) = api([try page([("1", ["bitcoin"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"))
        XCTAssertEqual(result.items.first?.sats, 0)
        XCTAssertEqual(result.items.count, 1)
    }

    // MARK: Requests

    func testDoesNotSendSubToTheServer() async throws {
        let (api, transport) = api([try page([("1", ["bitcoin"])], cursor: nil)])
        _ = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, discussionsOnly: true, sub: "bitcoin"))

        let vars = try transport.variables(at: 0)
        XCTAssertNil(vars["sub"], "sending sub would re-apply the territory's sats filter")
        XCTAssertEqual(vars["sort"] as? String, "new", "the screen's sort is preserved")
        XCTAssertEqual(vars["type"] as? String, "discussions", "the text-posts filter is preserved")
    }

    func testTopWeekTerritoryKeepsTheWhenWindow() async throws {
        let (api, transport) = api([try page([("1", ["bitcoin"])], cursor: nil)])
        _ = try await api.fetchTerritoryFeed(FeedKey(kind: .topWeek, sub: "bitcoin"))
        let vars = try transport.variables(at: 0)
        XCTAssertEqual(vars["sort"] as? String, "top")
        XCTAssertEqual(vars["when"] as? String, "week")
    }

    // MARK: Paging

    func testPagesUntilItHasEnoughMatches() async throws {
        let sparse = (0..<20).map { ("a\($0)", ["econ"]) } + [("hit1", ["bitcoin"])]
        let (api, transport) = api([
            try page(sparse, cursor: "c1"),
            try page([("hit2", ["bitcoin"]), ("hit3", ["bitcoin"])], cursor: "c2")
        ])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"), limit: 3)

        XCTAssertEqual(result.items.map(\.id), ["hit1", "hit2", "hit3"])
        XCTAssertEqual(transport.requestCount, 2, "stops as soon as it has enough")
        XCTAssertEqual(result.cursor, "c2", "hands back the site-wide cursor so paging continues")
    }

    func testStopsAtTheEndOfTheSiteWideFeed() async throws {
        let (api, transport) = api([try page([("1", ["econ"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"), limit: 21)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.cursor, "a nil cursor marks the feed exhausted")
        XCTAssertEqual(transport.requestCount, 1, "no cursor means nothing left to page through")
    }

    func testHonoursTheMaxPagesCap() async throws {
        let pages = (0..<5).map { i in try! page([("x\(i)", ["econ"])], cursor: "c\(i)") }
        let (api, transport) = api(pages)
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"),
                                                      limit: 21, maxPages: 3)

        XCTAssertEqual(transport.requestCount, 3, "a quiet territory must not page forever")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.cursor, "c2", "resumable: the next fetch carries on from here")
    }

    func testForwardsTheIncomingCursor() async throws {
        let (api, transport) = api([try page([("1", ["bitcoin"])], cursor: nil)])
        _ = try await api.fetchTerritoryFeed(FeedKey(kind: .recent, sub: "bitcoin"), cursor: "resume")
        XCTAssertEqual(try transport.variables(at: 0)["cursor"] as? String, "resume")
    }

    func testSiteWideKeyFallsBackToThePlainFeed() async throws {
        let (api, transport) = api([try page([("1", ["econ"]), ("2", ["bitcoin"])], cursor: nil)])
        let result = try await api.fetchTerritoryFeed(FeedKey(kind: .hot))

        XCTAssertEqual(result.items.map(\.id), ["1", "2"], "no territory means no filtering")
        XCTAssertEqual(transport.requestCount, 1)
    }

    // MARK: Item

    func testBelongsTo() {
        let item = Item(id: "1", title: "t", text: nil, subNames: ["econ", "Bitcoin"], user: User(name: "k00b"))
        XCTAssertTrue(item.belongs(to: "bitcoin"))
        XCTAssertTrue(item.belongs(to: "econ"))
        XCTAssertFalse(item.belongs(to: "meta"))
    }

    func testBelongsToWithNoSubNames() {
        let item = Item(id: "1", title: "t", text: nil, subNames: nil, user: User(name: "k00b"))
        XCTAssertFalse(item.belongs(to: "bitcoin"))
    }
}
