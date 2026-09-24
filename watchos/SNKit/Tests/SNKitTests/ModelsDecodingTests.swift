import XCTest
@testable import SNKit

final class ModelsDecodingTests: XCTestCase {
    func testDecodesHotFeed() throws {
        let page = try Fixtures.feed("feed_hot")
        XCTAssertFalse(page.items.isEmpty)
        let first = page.items[0]
        XCTAssertEqual(first.id, "1580650")
        XCTAssertNil(first.url)
        XCTAssertTrue(first.hasText)
        XCTAssertFalse(first.isLink)
        XCTAssertEqual(first.primarySub, "Permaculture")
        XCTAssertEqual(first.user.name, "revhodl21")
        let expected = SNDate.parse("2026-09-23T23:40:09.528Z")
        XCTAssertEqual(first.createdAt, expected)
    }

    func testCursorPresentOnFullPage() throws {
        let page = try Fixtures.feed("feed_hot")
        XCTAssertNotNil(page.cursor)
    }

    func testDecodesLinkPosts() throws {
        let page = try Fixtures.feed("item_link_post")
        let link = page.items[0]
        XCTAssertTrue(link.isLink)
        XCTAssertEqual(link.domain, "wtoc.com")
    }

    func testDecodesItemDetailWithComments() throws {
        let detail = try GraphQLClient.decode(Fixtures.data("item_detail"), as: SNAPI.ItemData.self).item
        let unwrapped = try XCTUnwrap(detail)
        XCTAssertEqual(unwrapped.item.id, "1579742")
        XCTAssertFalse(unwrapped.comments.comments.isEmpty)
        XCTAssertEqual(unwrapped.comments.comments[0].user.name, "martinbarilik")
    }

    func testGraphQLErrorPayloadThrows() throws {
        let data = try Fixtures.data("graphql_error")
        XCTAssertThrowsError(try GraphQLClient.decode(data, as: SNAPI.FeedData.self)) { error in
            guard case SNError.graphQL(let messages) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertFalse(messages.isEmpty)
        }
    }

    func testDateParsingWithAndWithoutFraction() {
        XCTAssertNotNil(SNDate.parse("2021-06-11T19:26:02.662Z"))
        XCTAssertNotNil(SNDate.parse("2021-06-11T19:26:02Z"))
        XCTAssertNil(SNDate.parse("yesterday"))
    }

    func testItemRoundTripsThroughCodable() throws {
        let item = Fixtures.item(id: "1")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        let back = try JSONDecoder.sn.decode(Item.self, from: data)
        XCTAssertEqual(back.id, item.id)
        XCTAssertEqual(back.title, item.title)
    }
}
