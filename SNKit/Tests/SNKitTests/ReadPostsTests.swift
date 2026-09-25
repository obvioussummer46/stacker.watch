import XCTest
@testable import SNKit

/// Read state drives the grey tile headers, and must survive a relaunch.
final class ReadPostsTests: XCTestCase {
    func testStartsEmpty() {
        let read = ReadPosts()
        XCTAssertEqual(read.count, 0)
        XCTAssertFalse(read.contains("1"))
    }

    func testInsertMarksRead() {
        var read = ReadPosts()
        read.insert("1")
        XCTAssertTrue(read.contains("1"))
        XCTAssertFalse(read.contains("2"))
    }

    func testInsertIsIdempotent() {
        var read = ReadPosts()
        read.insert("1")
        read.insert("1")
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.ids, ["1"])
    }

    func testKeepsInsertionOrder() {
        var read = ReadPosts()
        for id in ["c", "a", "b"] { read.insert(id) }
        XCTAssertEqual(read.ids, ["c", "a", "b"])
    }

    func testEvictsOldestPastTheLimit() {
        var read = ReadPosts()
        for index in 0..<(ReadPosts.limit + 10) { read.insert("\(index)") }

        XCTAssertEqual(read.count, ReadPosts.limit)
        XCTAssertFalse(read.contains("0"), "the oldest ids fall off")
        XCTAssertFalse(read.contains("9"))
        XCTAssertTrue(read.contains("10"), "the first surviving id")
        XCTAssertTrue(read.contains("\(ReadPosts.limit + 9)"), "the newest id")
    }

    func testEvictionKeepsLookupAndOrderInStep() {
        var read = ReadPosts()
        for index in 0..<(ReadPosts.limit + 50) { read.insert("\(index)") }
        XCTAssertEqual(read.ids.count, read.count)
        XCTAssertEqual(Set(read.ids).count, read.count, "no duplicates survive eviction")
        for id in read.ids {
            XCTAssertTrue(read.contains(id), "every retained id is still found by contains")
        }
    }

    func testReinsertingAnEvictedIDWorks() {
        var read = ReadPosts()
        for index in 0..<(ReadPosts.limit + 1) { read.insert("\(index)") }
        XCTAssertFalse(read.contains("0"))
        read.insert("0")
        XCTAssertTrue(read.contains("0"))
    }

    func testEncodesAsAPlainArrayOfIDs() throws {
        var read = ReadPosts()
        read.insert("7")
        read.insert("9")
        let data = try JSONEncoder().encode(read)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["7","9"]"#)
    }

    func testSurvivesACodableRoundTrip() throws {
        var read = ReadPosts()
        for id in ["1", "2", "3"] { read.insert(id) }
        let restored = try JSONDecoder().decode(ReadPosts.self, from: try JSONEncoder().encode(read))

        XCTAssertEqual(restored, read)
        XCTAssertEqual(restored.ids, ["1", "2", "3"])
        XCTAssertTrue(restored.contains("2"), "contains works after decoding, not just after insert")
    }

    func testDecodingTrimsAnOversizedStoredList() throws {
        let ids = (0..<(ReadPosts.limit + 20)).map { "\($0)" }
        let data = try JSONEncoder().encode(ids)
        let restored = try JSONDecoder().decode(ReadPosts.self, from: data)
        XCTAssertEqual(restored.count, ReadPosts.limit)
        XCTAssertTrue(restored.contains("\(ReadPosts.limit + 19)"))
    }

    func testDecodingDropsDuplicates() throws {
        let data = try JSONEncoder().encode(["1", "1", "2"])
        let restored = try JSONDecoder().decode(ReadPosts.self, from: data)
        XCTAssertEqual(restored.ids, ["1", "2"])
    }
}
