import XCTest
@testable import SNKit

/// The territory list is cached hard, because territories change over weeks.
final class TerritoryCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: TerritoryCache!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TerritoryCacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = TerritoryCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadOnEmptyDirectoryIsNil() {
        XCTAssertNil(cache.load())
    }

    func testRoundTripsTerritories() throws {
        try cache.save([Territory(name: "bitcoin"), Territory(name: "econ")])
        let entry = try XCTUnwrap(cache.load())
        XCTAssertEqual(entry.territories.map(\.name), ["bitcoin", "econ"])
    }

    func testEmptyListIsTreatedAsNoCache() throws {
        try cache.save([])
        XCTAssertNil(cache.load(), "an empty list must not mask a real fetch")
    }

    func testCorruptFileIsTreatedAsNoCache() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: cache.fileURL)
        XCTAssertNil(cache.load())
    }

    func testFreshEntryIsNotStale() throws {
        try cache.save([Territory(name: "bitcoin")])
        let entry = try XCTUnwrap(cache.load())
        XCTAssertFalse(cache.isStale(entry))
    }

    func testEntryGoesStaleAfterAMonth() throws {
        let saved = Date(timeIntervalSinceNow: -TerritoryCache.maxAge - 60)
        try cache.save([Territory(name: "bitcoin")], now: saved)
        let entry = try XCTUnwrap(cache.load())
        XCTAssertTrue(cache.isStale(entry))
    }

    func testEntryJustUnderAMonthIsStillFresh() throws {
        let saved = Date(timeIntervalSinceNow: -TerritoryCache.maxAge + 3600)
        try cache.save([Territory(name: "bitcoin")], now: saved)
        let entry = try XCTUnwrap(cache.load())
        XCTAssertFalse(cache.isStale(entry), "a 29-day-old list should not trigger a fetch")
    }

    func testSaveOverwritesPreviousList() throws {
        try cache.save([Territory(name: "old")])
        try cache.save([Territory(name: "new")])
        XCTAssertEqual(cache.load()?.territories.map(\.name), ["new"])
    }

    func testRemoveClearsTheEntry() throws {
        try cache.save([Territory(name: "bitcoin")])
        cache.remove()
        XCTAssertNil(cache.load())
    }

    func testMaxAgeIsThirtyDays() {
        XCTAssertEqual(TerritoryCache.maxAge, 60 * 60 * 24 * 30)
    }
}
