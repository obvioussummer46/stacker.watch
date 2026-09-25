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

    /// True when the post was posted to `sub`, including cross-posts.
    /// Case-insensitive, because territory names mix `bitcoin` with `AskSN`.
    public func belongs(to sub: String) -> Bool {
        subNames?.contains { $0.caseInsensitiveCompare(sub) == .orderedSame } ?? false
    }
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
    /// Territory to scope the feed to. `nil` reads the whole site.
    public var sub: String?

    public init(kind: FeedKind = .hot, discussionsOnly: Bool = true, sub: String? = nil) {
        self.kind = kind
        self.discussionsOnly = discussionsOnly
        self.sub = sub
    }

    public var cacheFileName: String {
        let scope = sub.map { "sub-" + Self.slug($0) } ?? "site"
        return "feed-\(kind.rawValue)-\(discussionsOnly ? "discussions" : "all")-\(scope).json"
    }

    /// Keeps territory names safe to use as a file name.
    private static func slug(_ name: String) -> String {
        let allowed = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return String(allowed)
    }
}

/// One configurable screen: a site-wide feed, or a feed scoped to one territory.
///
/// The user arranges up to `maxScreens` of these; each becomes a horizontal page.
public struct FeedSource: Hashable, Codable, Sendable, Identifiable {
    public var kind: FeedKind
    /// `nil` for the site-wide feed, otherwise a territory name.
    public var sub: String?

    public init(kind: FeedKind = .hot, sub: String? = nil) {
        self.kind = kind
        self.sub = sub
    }

    public var id: String { "\(sub ?? "")|\(kind.rawValue)" }

    /// `Hot` for a site-wide feed, `~bitcoin` for a territory.
    public var title: String { sub.map { "~\($0)" } ?? kind.title }
    /// Which sort the screen uses, shown under the title in settings.
    public var sortTitle: String { kind.title }
    /// `~bitcoin · Hot`. Tells two screens for the same territory apart.
    public var fullTitle: String { sub == nil ? kind.title : "\(title) · \(kind.title)" }
    public var isTerritory: Bool { sub != nil }

    public func key(discussionsOnly: Bool) -> FeedKey {
        FeedKey(kind: kind, discussionsOnly: discussionsOnly, sub: sub)
    }

    /// Next sort in the cycle, for tapping a row in settings.
    public var nextSort: FeedSource {
        let all = FeedKind.allCases
        let index = all.firstIndex(of: kind) ?? 0
        return FeedSource(kind: all[(index + 1) % all.count], sub: sub)
    }

    public static let maxScreens = 6
    /// What a fresh install starts with: the three site-wide feeds.
    public static let defaults: [FeedSource] = FeedKind.allCases.map { FeedSource(kind: $0) }
}

/// A territory (a "sub" in the API).
public struct Territory: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public var id: String { name }

    public init(name: String) { self.name = name }
}

/// One page of the `topSubs` query.
public struct TerritoriesPage: Decodable, Sendable {
    public let cursor: String?
    public let subs: [Territory]
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
