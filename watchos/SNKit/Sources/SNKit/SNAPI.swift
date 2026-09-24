import Foundation

/// High-level, anonymous read API for stacker.news.
public struct SNAPI: Sendable {
    private let client: GraphQLClient

    public init(client: GraphQLClient = GraphQLClient()) {
        self.client = client
    }

    public func fetchFeed(_ key: FeedKey, cursor: String? = nil, limit: Int = Queries.defaultLimit) async throws -> ItemsPage {
        let result = try await client.execute(Queries.feed, variables: key.variables(cursor: cursor, limit: limit), as: FeedData.self)
        return result.items
    }

    public func fetchShufflePage(cursor: String? = nil) async throws -> ItemsPage {
        let result = try await client.execute(Queries.feed, variables: FeedKey.shuffleVariables(cursor: cursor), as: FeedData.self)
        return result.items
    }

    /// A territory feed, read from the site-wide feed and filtered client-side.
    ///
    /// `items(sub:)` looks like the obvious call but withholds posts: a territory can
    /// set `postsSatsFilter` (`~bitcoin` uses 300), and stacker.news applies it to
    /// anonymous callers. A post sits invisible on its own territory feed until it has
    /// earned that many sats, while showing up site-wide the whole time — so the
    /// territory screen looked hours behind the Recent screen. Reading the site-wide
    /// feed and matching on `subNames` shows everything, zapped or not.
    ///
    /// Costs more requests, so it stops as soon as it has `limit` matches and never
    /// reads more than `maxPages`. A quiet territory can return a short page.
    public func fetchTerritoryFeed(_ key: FeedKey,
                                   cursor: String? = nil,
                                   limit: Int = Queries.defaultLimit,
                                   pageLimit: Int = 100,
                                   maxPages: Int = 3) async throws -> ItemsPage {
        guard let sub = key.sub else { return try await fetchFeed(key, cursor: cursor, limit: limit) }
        let siteWide = FeedKey(kind: key.kind, discussionsOnly: key.discussionsOnly)
        var matched: [Item] = []
        var next = cursor
        var pages = 0
        while matched.count < limit, pages < maxPages {
            let variables = siteWide.variables(cursor: next, limit: pageLimit)
            let page = try await client.execute(Queries.feed, variables: variables, as: FeedData.self).items
            pages += 1
            matched += page.items.filter { $0.belongs(to: sub) }
            next = page.cursor
            // No cursor means the site-wide feed is exhausted, so there is no more to find.
            if next == nil { break }
        }
        return ItemsPage(cursor: next, items: matched)
    }

    /// Territories ranked by activity, for choosing a screen in settings.
    public func fetchTopTerritories(when: String = "month", limit: Int = 30) async throws -> [Territory] {
        let result = try await client.execute(Queries.topTerritories,
                                              variables: ["when": when, "limit": limit],
                                              as: TopSubsData.self)
        return result.topSubs.subs
    }

    public func fetchItem(id: String) async throws -> ItemDetail {
        let result = try await client.execute(Queries.item, variables: ["id": id], as: ItemData.self)
        guard let item = result.item else { throw SNError.graphQL(["Post not found"]) }
        return item
    }

    struct FeedData: Decodable { let items: ItemsPage }
    struct ItemData: Decodable { let item: ItemDetail? }
    struct TopSubsData: Decodable { let topSubs: TerritoriesPage }
}
