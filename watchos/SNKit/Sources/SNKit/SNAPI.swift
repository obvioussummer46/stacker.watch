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
