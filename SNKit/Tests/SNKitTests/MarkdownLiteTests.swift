import XCTest
@testable import SNKit

final class MarkdownLiteTests: XCTestCase {
    func testExcerptStripsImagesLinksAndEmphasis() {
        let md = "We heat **900sqft** with *wood*. See [the note](https://x.y/z).\n![](https://i.imgur.com/a.jpeg)\n![](https://i.imgur.com/b.jpeg)\nMore text."
        let excerpt = MarkdownLite.excerpt(md, maxChars: 500)
        XCTAssertEqual(excerpt, "We heat 900sqft with wood. See the note. More text.")
        XCTAssertFalse(excerpt.contains("!["))
    }

    func testExcerptCutsOnWordBoundary() {
        let md = String(repeating: "word ", count: 100)
        let excerpt = MarkdownLite.excerpt(md, maxChars: 23)
        XCTAssertTrue(excerpt.hasSuffix("…"))
        XCTAssertLessThanOrEqual(excerpt.count, 24)
        XCTAssertFalse(excerpt.contains("wor…"))
    }

    func testExcerptOfShortTextIsUnchanged() {
        XCTAssertEqual(MarkdownLite.excerpt("short"), "short")
        XCTAssertEqual(MarkdownLite.excerpt(nil), "")
        XCTAssertEqual(MarkdownLite.excerpt(""), "")
    }

    func testBlocksSplitParagraphsQuotesHeadingsLists() {
        let md = """
        # Title

        First line
        second line

        > quoted
        > more

        - one
        2. two

        ---
        """
        XCTAssertEqual(MarkdownLite.blocks(md), [
            .heading(level: 1, text: "Title"),
            .paragraph("First line second line"),
            .quote("quoted more"),
            .listItem("one"),
            .listItem("two"),
            .rule
        ])
    }

    func testFencedCodeKeepsBlankLines() {
        let md = "before\n```\nlet a = 1\n\nlet b = 2\n```\nafter"
        XCTAssertEqual(MarkdownLite.blocks(md), [
            .paragraph("before"),
            .code("let a = 1\n\nlet b = 2"),
            .paragraph("after")
        ])
    }

    func testConsecutiveImagesBecomeImageBlocks() {
        let md = "text\n![](https://a/1.jpg)\n![alt](https://a/2.jpg)\nmore"
        XCTAssertEqual(MarkdownLite.blocks(md), [
            .paragraph("text"),
            .image(alt: "", url: "https://a/1.jpg"),
            .image(alt: "alt", url: "https://a/2.jpg"),
            .paragraph("more")
        ])
    }

    func testPlainTextHandlesUnicodeAndCodeSpans() {
        XCTAssertEqual(MarkdownLite.plainText("65-70°f and `code` 🔥 <b>bold</b>"), "65-70°f and code 🔥 bold")
    }

    func testUnderscoresInsideWordsSurvive() {
        XCTAssertEqual(MarkdownLite.stripInline("snake_case_name and _em_"), "snake_case_name and em")
    }

    func testDomain() {
        XCTAssertEqual(MarkdownLite.domain("https://www.wtoc.com/2026/x"), "wtoc.com")
        XCTAssertEqual(MarkdownLite.domain("https://ericyakes.substack.com/p/a"), "ericyakes.substack.com")
        XCTAssertNil(MarkdownLite.domain("not a url"))
    }
}
