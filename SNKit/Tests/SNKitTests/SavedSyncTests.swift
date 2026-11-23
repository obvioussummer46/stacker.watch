import XCTest
@testable import SNKit

/// What crosses from the watch to the phone and back.
final class SavedSyncTests: XCTestCase {
    func testContextRoundTripKeepsOrderAndDropsText() throws {
        var saved = SavedPosts()
        saved.insert(Item(id: "1", title: "First", url: "https://example.com/a", text: "long body",
                          sats: 12, ncomments: 3, subNames: ["bitcoin"], user: User(name: "k00b")))
        saved.insert(Fixtures.item(id: "2"))

        let context = SavedSync.context(for: saved)
        XCTAssertTrue(context[SavedSync.listKey] is Data, "property-list safe payload")

        let restored = try XCTUnwrap(SavedSync.posts(from: context))
        XCTAssertEqual(restored.items.map(\.id), ["2", "1"])
        let first = try XCTUnwrap(restored.items.last)
        XCTAssertEqual(first.title, "First")
        XCTAssertEqual(first.url, "https://example.com/a")
        XCTAssertEqual(first.sats, 12)
        XCTAssertEqual(first.ncomments, 3)
        XCTAssertEqual(first.primarySub, "bitcoin")
        XCTAssertEqual(first.user.name, "k00b")
        XCTAssertNil(first.text, "bodies stay on the watch")
    }

    func testEmptyListRoundTrips() throws {
        let restored = try XCTUnwrap(SavedSync.posts(from: SavedSync.context(for: SavedPosts())))
        XCTAssertTrue(restored.isEmpty)
    }

    func testForeignContextIsIgnored() {
        XCTAssertNil(SavedSync.posts(from: [:]))
        XCTAssertNil(SavedSync.posts(from: ["other": "thing"]))
        XCTAssertNil(SavedSync.posts(from: [SavedSync.listKey: Data("junk".utf8)]))
    }

    func testPayloadStaysSmall() {
        var saved = SavedPosts()
        let body = String(repeating: "words ", count: 2000)
        for index in 0..<SavedPosts.limit {
            saved.insert(Item(id: "\(index)", title: "A fairly long post title number \(index)",
                              url: "https://example.com/some/long/path/\(index)", text: body,
                              subNames: ["bitcoin_beginners"], user: User(name: "someone_long")))
        }
        let data = SavedSync.context(for: saved)[SavedSync.listKey] as? Data
        XCTAssertLessThan(data?.count ?? .max, 40_000, "well under the application context limit")
    }

    func testRemovals() {
        let context = SavedSync.removalsContext(Set(["9", "42"]))
        XCTAssertEqual(SavedSync.removedIDs(from: context), ["42", "9"], "sorted, so equal sets give equal contexts")
        XCTAssertTrue(context[SavedSync.removedKey] is [String], "property-list safe payload")
        XCTAssertEqual(SavedSync.removedIDs(from: SavedSync.removalsContext([])), [])
        XCTAssertEqual(SavedSync.removedIDs(from: [:]), [])
        XCTAssertEqual(SavedSync.removedIDs(from: [SavedSync.removedKey: 42]), [])
    }
}
