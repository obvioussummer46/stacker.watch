import XCTest
@testable import SNKit

final class FeedPagerTests: XCTestCase {
    private func page(_ ids: [String], cursor: String?) -> ItemsPage {
        ItemsPage(cursor: cursor, items: ids.map { Fixtures.item(id: $0) })
    }

    func testResetThenAppendDedupes() {
        var pager = FeedPager()
        pager.reset(with: page(["1", "2", "3"], cursor: "c1"))
        pager.append(page(["3", "4"], cursor: "c2"))
        XCTAssertEqual(pager.items.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(pager.cursor, "c2")
        XCTAssertFalse(pager.exhausted)
    }

    func testExhaustedWhenCursorNil() {
        var pager = FeedPager()
        pager.reset(with: page(["1"], cursor: nil))
        XCTAssertTrue(pager.exhausted)
        XCTAssertFalse(pager.shouldLoadMore(currentIndex: 0))
    }

    func testShouldLoadMoreThreshold() {
        var pager = FeedPager()
        pager.reset(with: page((1...10).map(String.init), cursor: "c"))
        XCTAssertFalse(pager.shouldLoadMore(currentIndex: 0, threshold: 5))
        XCTAssertFalse(pager.shouldLoadMore(currentIndex: 4, threshold: 5))
        XCTAssertTrue(pager.shouldLoadMore(currentIndex: 5, threshold: 5))
        XCTAssertTrue(pager.shouldLoadMore(currentIndex: 9, threshold: 5))
    }

    func testEmptyPagerNeverLoadsMore() {
        XCTAssertFalse(FeedPager().shouldLoadMore(currentIndex: 0))
    }

    func testInitFromCachedItems() {
        let pager = FeedPager(items: [Fixtures.item(id: "1"), Fixtures.item(id: "1")], cursor: "c")
        XCTAssertEqual(pager.items.count, 1)
        XCTAssertEqual(pager.index(of: "1"), 0)
        XCTAssertNil(pager.index(of: "9"))
    }

    func testResetReplacesItems() {
        var pager = FeedPager()
        pager.reset(with: page(["1", "2"], cursor: "a"))
        pager.reset(with: page(["9"], cursor: nil))
        XCTAssertEqual(pager.items.map(\.id), ["9"])
        XCTAssertTrue(pager.exhausted)
    }
}
