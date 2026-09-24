import Foundation

/// A post or comment on stacker.news, trimmed to what the watch needs.
public struct Item: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let url: String?
    /// Raw markdown body. `nil` for link posts without a description.
    public let text: String?
    public let sats: Int
    public let boost: Int
    public let ncomments: Int
    public let createdAt: Date
    public let subNames: [String]?
    public let user: User

    public init(id: String, title: String?, url: String? = nil, text: String?, sats: Int = 0,
                boost: Int = 0, ncomments: Int = 0, createdAt: Date = Date(),
                subNames: [String]? = nil, user: User) {
        self.id = id
        self.title = title
        self.url = url
        self.text = text
        self.sats = sats
        self.boost = boost
        self.ncomments = ncomments
        self.createdAt = createdAt
        self.subNames = subNames
        self.user = user
    }

    /// True when the post points at an external URL.
    public var isLink: Bool { url != nil }
    public var hasText: Bool { !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    public var primarySub: String? { subNames?.first }
    /// Host of `url` without a leading "www.".
    public var domain: String? { url.flatMap(MarkdownLite.domain) }
}

public struct User: Codable, Hashable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

/// One page of the `items` query.
public struct ItemsPage: Decodable, Sendable {
    public let cursor: String?
    public let items: [Item]
    public init(cursor: String?, items: [Item]) {
        self.cursor = cursor
        self.items = items
    }
}

public struct Comment: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let text: String?
    public let createdAt: Date
    public let sats: Int
    public let ncomments: Int
    public let user: User
}

public struct CommentsPage: Decodable, Sendable {
    public let cursor: String?
    public let comments: [Comment]
}

/// The `item(id:)` query result: the item plus its top-level comments.
public struct ItemDetail: Decodable, Sendable {
    public let item: Item
    public let comments: CommentsPage

    private enum CodingKeys: String, CodingKey { case comments }

    public init(from decoder: Decoder) throws {
        item = try Item(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comments = try container.decode(CommentsPage.self, forKey: .comments)
    }
}

/// Which feed the user is reading.
public enum FeedKind: String, CaseIterable, Codable, Sendable {
    case hot, recent, topWeek

    public var title: String {
        switch self {
        case .hot: return "Hot"
        case .recent: return "Recent"
        case .topWeek: return "Top this week"
        }
    }

    var sort: String? {
        switch self {
        case .hot: return nil
        case .recent: return "new"
        case .topWeek: return "top"
        }
    }

    var when: String? { self == .topWeek ? "week" : nil }
}

/// Feed kind plus filters; also the cache key.
public struct FeedKey: Hashable, Codable, Sendable {
    public var kind: FeedKind
    public var discussionsOnly: Bool

    public init(kind: FeedKind = .hot, discussionsOnly: Bool = true) {
        self.kind = kind
        self.discussionsOnly = discussionsOnly
    }

    public var cacheFileName: String {
        "feed-\(kind.rawValue)-\(discussionsOnly ? "discussions" : "all").json"
    }
}

public extension JSONDecoder {
    /// Decoder configured for stacker.news dates (`2021-06-11T19:26:02.662Z`, fractional seconds optional).
    static let sn: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = SNDate.parse(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unrecognized date \(raw)"))
        }
        return decoder
    }()
}

public enum SNDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ raw: String) -> Date? {
        withFraction.date(from: raw) ?? plain.date(from: raw)
    }
}
