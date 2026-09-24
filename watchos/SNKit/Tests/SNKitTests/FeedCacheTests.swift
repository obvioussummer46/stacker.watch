import XCTest
@testable import SNKit

final class FeedCacheTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sncache-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTrip() throws {
        let cache = FeedCache(directory: dir)
        let key = FeedKey(kind: .recent, discussionsOnly: true)
        try cache.save(.init(key: key, items: [Fixtures.item(id: "1"), Fixtures.item(id: "2")], cursor: "c"))
        let loaded = try XCTUnwrap(cache.load(key))
        XCTAssertEqual(loaded.items.map(\.id), ["1", "2"])
        XCTAssertEqual(loaded.cursor, "c")
        XCTAssertNil(cache.load(FeedKey(kind: .hot, discussionsOnly: true)))
    }

    func testCapsItems() throws {
        let cache = FeedCache(directory: dir)
        let items = (0..<200).map { Fixtures.item(id: String($0)) }
        try cache.save(.init(key: FeedKey(), items: items, cursor: nil))
        XCTAssertEqual(cache.load(FeedKey())?.items.count, FeedCache.maxItems)
    }

    func testCorruptFileYieldsNil() throws {
        let cache = FeedCache(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: cache.fileURL(for: FeedKey()))
        XCTAssertNil(cache.load(FeedKey()))
    }

    func testStaleness() {
        let cache = FeedCache(directory: dir)
        let old = FeedCache.Entry(key: FeedKey(), savedAt: Date(timeIntervalSinceNow: -3600), items: [], cursor: nil)
        let fresh = FeedCache.Entry(key: FeedKey(), items: [], cursor: nil)
        XCTAssertTrue(cache.isStale(old))
        XCTAssertFalse(cache.isStale(fresh))
    }
}
