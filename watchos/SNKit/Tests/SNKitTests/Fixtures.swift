import Foundation
import XCTest
@testable import SNKit

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    static func feed(_ name: String) throws -> ItemsPage {
        try GraphQLClient.decode(data(name), as: SNAPI.FeedData.self).items
    }

    static func item(id: String, text: String? = "hello", url: String? = nil) -> Item {
        Item(id: id, title: "Post \(id)", url: url, text: text, user: User(name: "k00b"))
    }
}
