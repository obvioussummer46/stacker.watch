import XCTest
@testable import SNKit

/// The reading list: newest first, no duplicates, capped, and it survives a relaunch.
final class SavedPostsTests: XCTestCase {
    func testStartsEmpty() {
        let saved = SavedPosts()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertFalse(saved.contains("1"))
    }

    func testInsertPutsTheNewestFirst() {
        var saved = SavedPosts()
        saved.insert(Fixtures.item(id: "1"))
        saved.insert(Fixtures.item(id: "2"))
        XCTAssertEqual(saved.items.map(\.id), ["2", "1"])
        XCTAssertTrue(saved.contains("1"))
    }

    func testInsertingTwiceKeepsThePlace() {
        var saved = SavedPosts()
        saved.insert(Fixtures.item(id: "1"))
        saved.insert(Fixtures.item(id: "2"))
        saved.insert(Fixtures.item(id: "1"))
        XCTAssertEqual(saved.items.map(\.id), ["2", "1"])
    }

    func testRemove() {
        var saved = SavedPosts()
        saved.insert(Fixtures.item(id: "1"))
        saved.insert(Fixtures.item(id: "2"))
        saved.remove("1")
        XCTAssertEqual(saved.items.map(\.id), ["2"])
        XCTAssertFalse(saved.contains("1"))
        saved.remove("missing")
        XCTAssertEqual(saved.count, 1)
    }

    func testToggleReportsTheNewState() {
        var saved = SavedPosts()
        let item = Fixtures.item(id: "1")
        XCTAssertTrue(saved.toggle(item))
        XCTAssertTrue(saved.contains("1"))
        XCTAssertFalse(saved.toggle(item))
        XCTAssertFalse(saved.contains("1"))
        XCTAssertTrue(saved.isEmpty)
    }

    func testDropsTheOldestPastTheLimit() {
        var saved = SavedPosts()
        for index in 0..<(SavedPosts.limit + 5) { saved.insert(Fixtures.item(id: "\(index)")) }

        XCTAssertEqual(saved.count, SavedPosts.limit)
        XCTAssertEqual(saved.items.first?.id, "\(SavedPosts.limit + 4)", "the newest stays on top")
        XCTAssertFalse(saved.contains("0"), "the oldest falls off")
        XCTAssertFalse(saved.contains("4"))
        XCTAssertTrue(saved.contains("5"), "the first survivor")
        XCTAssertEqual(Set(saved.items.map(\.id)).count, saved.count)
        for item in saved.items { XCTAssertTrue(saved.contains(item.id)) }
    }

    func testEncodesAsAnArrayOfItems() throws {
        var saved = SavedPosts()
        saved.insert(Fixtures.item(id: "7"))
        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?["id"] as? String, "7")
    }

    func testSurvivesACodableRoundTrip() throws {
        var saved = SavedPosts()
        for id in ["1", "2", "3"] { saved.insert(Fixtures.item(id: id)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let restored = try JSONDecoder.sn.decode(SavedPosts.self, from: try encoder.encode(saved))

        XCTAssertEqual(restored.items.map(\.id), ["3", "2", "1"], "order is kept, not reversed again")
        XCTAssertTrue(restored.contains("2"), "contains works after decoding")
    }

    func testDecodingDropsDuplicatesAndTrims() throws {
        let items = [Fixtures.item(id: "1"), Fixtures.item(id: "1")]
            + (2..<(SavedPosts.limit + 10)).map { Fixtures.item(id: "\($0)") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let restored = try JSONDecoder.sn.decode(SavedPosts.self, from: try encoder.encode(items))
        XCTAssertEqual(restored.count, SavedPosts.limit)
        XCTAssertEqual(restored.items.first?.id, "1")
        XCTAssertEqual(restored.items.filter { $0.id == "1" }.count, 1)
    }
}

final class SavedPostsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedPostsStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadsEmptyWhenNothingWasSaved() {
        let store = SavedPostsStore(directory: directory)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testRoundTrip() throws {
        let store = SavedPostsStore(directory: directory)
        var saved = SavedPosts()
        saved.insert(Fixtures.item(id: "1"))
        saved.insert(Fixtures.item(id: "2", text: nil, url: "https://example.com/a"))
        try store.save(saved)

        let restored = store.load()
        // Ids rather than whole items: ISO 8601 drops sub-second precision from dates.
        XCTAssertEqual(restored.items.map(\.id), ["2", "1"])
        XCTAssertEqual(restored.items.first?.url, "https://example.com/a")
        XCTAssertEqual(restored.items.last?.text, "hello")
    }

    func testCreatesTheDirectory() throws {
        let nested = directory.appendingPathComponent("a/b", isDirectory: true)
        let store = SavedPostsStore(directory: nested)
        try store.save(SavedPosts(items: [Fixtures.item(id: "1")]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testCorruptFileLoadsEmpty() throws {
        let store = SavedPostsStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertTrue(store.load().isEmpty)
    }
}
