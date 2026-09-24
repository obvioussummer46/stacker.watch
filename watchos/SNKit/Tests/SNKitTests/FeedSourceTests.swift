import XCTest
@testable import SNKit

/// Covers the configurable screens and territory-scoped feeds.
final class FeedSourceTests: XCTestCase {
    func testSiteWideSourceUsesKindTitle() {
        let source = FeedSource(kind: .topWeek)
        XCTAssertEqual(source.title, "Top this week")
        XCTAssertEqual(source.sortTitle, "Top this week")
        XCTAssertFalse(source.isTerritory)
        XCTAssertNil(source.key(discussionsOnly: true).sub)
    }

    func testTerritorySourceUsesTildeName() {
        let source = FeedSource(kind: .hot, sub: "bitcoin")
        XCTAssertEqual(source.title, "~bitcoin")
        XCTAssertEqual(source.sortTitle, "Hot")
        XCTAssertTrue(source.isTerritory)
        XCTAssertEqual(source.key(discussionsOnly: false).sub, "bitcoin")
    }

    func testNextSortCyclesAndKeepsTerritory() {
        let hot = FeedSource(kind: .hot, sub: "econ")
        let recent = hot.nextSort
        let top = recent.nextSort
        XCTAssertEqual(recent.kind, .recent)
        XCTAssertEqual(top.kind, .topWeek)
        XCTAssertEqual(top.nextSort.kind, .hot, "cycles back round")
        XCTAssertEqual(recent.sub, "econ", "territory survives a sort change")
    }

    func testFullTitleTellsTwoSortsOfOneTerritoryApart() {
        let hot = FeedSource(kind: .hot, sub: "bitcoin")
        let recent = FeedSource(kind: .recent, sub: "bitcoin")
        XCTAssertEqual(hot.title, recent.title, "the short title alone is ambiguous")
        XCTAssertEqual(hot.fullTitle, "~bitcoin · Hot")
        XCTAssertEqual(recent.fullTitle, "~bitcoin · Recent")
        XCTAssertNotEqual(hot.fullTitle, recent.fullTitle)
    }

    func testFullTitleOfSiteWideFeedIsJustTheSort() {
        XCTAssertEqual(FeedSource(kind: .topWeek).fullTitle, "Top this week")
    }

    func testIDSeparatesTerritoryFromSiteWide() {
        XCTAssertNotEqual(FeedSource(kind: .hot).id, FeedSource(kind: .hot, sub: "hot").id)
        XCTAssertNotEqual(FeedSource(kind: .hot, sub: "a").id, FeedSource(kind: .recent, sub: "a").id)
    }

    func testDefaultsAreTheThreeSiteWideFeeds() {
        XCTAssertEqual(FeedSource.defaults.count, 3)
        XCTAssertTrue(FeedSource.defaults.allSatisfy { !$0.isTerritory })
        XCTAssertLessThanOrEqual(FeedSource.defaults.count, FeedSource.maxScreens)
    }

    func testScreensSurviveACodableRoundTrip() throws {
        let screens = [FeedSource(kind: .hot), FeedSource(kind: .topWeek, sub: "bitcoin")]
        let data = try JSONEncoder().encode(screens)
        XCTAssertEqual(try JSONDecoder().decode([FeedSource].self, from: data), screens)
    }

    // MARK: FeedKey

    func testTerritoryFeedSendsSubVariable() {
        let vars = FeedKey(kind: .hot, discussionsOnly: true, sub: "bitcoin").variables(cursor: nil)
        XCTAssertEqual(vars["sub"] as? String, "bitcoin")
    }

    func testSiteWideFeedDropsSubVariable() throws {
        let vars = FeedKey(kind: .hot, discussionsOnly: false).variables(cursor: nil)
        XCTAssertNil(vars["sub"] ?? nil)
        let body = try GraphQLClient.body(query: "q", variables: vars)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let sent = try XCTUnwrap(json?["variables"] as? [String: Any])
        XCTAssertFalse(sent.keys.contains("sub"))
    }

    func testCacheFileNamesDoNotCollide() {
        let names = [
            FeedKey(kind: .hot, discussionsOnly: true).cacheFileName,
            FeedKey(kind: .hot, discussionsOnly: true, sub: "bitcoin").cacheFileName,
            FeedKey(kind: .hot, discussionsOnly: false, sub: "bitcoin").cacheFileName,
            FeedKey(kind: .recent, discussionsOnly: true, sub: "bitcoin").cacheFileName
        ]
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testCacheFileNameStripsPathCharactersFromTerritory() {
        let name = FeedKey(kind: .hot, sub: "../../etc/passwd").cacheFileName
        XCTAssertFalse(name.contains("/"), "a territory name must not escape the cache directory")
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(name.filter { $0 == "." }.count, 1, "the .json suffix is the only dot")
    }

    func testCachedTerritoryFeedIsReadBackUnderItsOwnKey() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeedSourceTests-\(UUID().uuidString)", isDirectory: true)
        let cache = FeedCache(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = FeedKey(kind: .hot, discussionsOnly: true, sub: "bitcoin")
        try cache.save(.init(key: key, items: [Fixtures.item(id: "1")], cursor: "c"))

        XCTAssertEqual(cache.load(key)?.items.count, 1)
        XCTAssertNil(cache.load(FeedKey(kind: .hot, discussionsOnly: true)),
                     "the site-wide feed must not read the territory's cache")
    }

    // MARK: Territories

    func testDecodesTopTerritories() throws {
        let data = try Fixtures.data("top_subs")
        let page = try GraphQLClient.decode(data, as: SNAPI.TopSubsData.self).topSubs
        XCTAssertEqual(page.subs.first?.name, "bitcoin")
        XCTAssertEqual(page.subs.count, 8)
        XCTAssertNotNil(page.cursor)
    }

    func testTerritoryIsIdentifiedByName() {
        XCTAssertEqual(Territory(name: "bitcoin").id, "bitcoin")
    }

    func testTopTerritoriesRequestShape() async throws {
        let stub = StubTransport(try Fixtures.data("top_subs"))
        let api = SNAPI(client: GraphQLClient(transport: stub))
        let territories = try await api.fetchTopTerritories(when: "week", limit: 8)

        XCTAssertEqual(territories.count, 8)
        let request = try XCTUnwrap(stub.lastRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let vars = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(vars["when"] as? String, "week")
        XCTAssertEqual(vars["limit"] as? Int, 8)
        XCTAssertTrue(try XCTUnwrap(body["query"] as? String).contains("topSubs"))
    }
}
