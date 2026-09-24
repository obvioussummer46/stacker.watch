import Foundation

/// GraphQL documents used by the watch app. Kept minimal on purpose:
/// no client-only fields and no `me*` fields, since the app is anonymous.
public enum Queries {
    public static let itemFragment = """
    fragment WatchItem on Item {
      id title url text sats boost ncomments createdAt subNames user { name }
    }
    """

    public static let feed = """
    \(itemFragment)
    query WatchFeed($sub: String, $sort: String, $type: String, $when: String, $cursor: String, $limit: Limit) {
      items(sub: $sub, sort: $sort, type: $type, when: $when, cursor: $cursor, limit: $limit) {
        cursor
        items { ...WatchItem }
      }
    }
    """

    /// Territories ranked by recent activity; the source for the territory picker.
    public static let topTerritories = """
    query WatchTopSubs($when: String, $limit: Limit) {
      topSubs(when: $when, limit: $limit) {
        cursor
        subs { name }
      }
    }
    """

    public static let item = """
    \(itemFragment)
    query WatchItem($id: ID!) {
      item(id: $id) {
        ...WatchItem
        comments(sort: "lit") {
          cursor
          comments { id text createdAt sats ncomments user { name } }
        }
      }
    }
    """

    public static let defaultLimit = 21
}

public extension FeedKey {
    /// Variables for `Queries.feed`. `nil` values are dropped before sending.
    func variables(cursor: String?, limit: Int = Queries.defaultLimit) -> [String: Any?] {
        [
            "sub": sub,
            "sort": kind.sort,
            "when": kind.when,
            "type": discussionsOnly ? "discussions" : nil,
            "cursor": cursor,
            "limit": limit
        ]
    }

    /// Pool that "surprise me" draws from: the year's top discussions.
    static func shuffleVariables(cursor: String?, limit: Int = Queries.defaultLimit) -> [String: Any?] {
        ["sort": "top", "when": "year", "type": "discussions", "cursor": cursor, "limit": limit]
    }
}
