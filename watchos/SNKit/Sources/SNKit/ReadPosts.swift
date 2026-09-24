import Foundation

/// The ids of posts already opened, so tiles can show a read state.
///
/// Insertion-ordered and capped: the oldest ids fall off once `limit` is reached, so
/// this never grows without bound on a watch. Encodes as a plain array of ids.
public struct ReadPosts: Codable, Sendable, Equatable {
    /// Roughly a year of casual reading, and a few KB on disk.
    public static let limit = 500

    /// Oldest first, so eviction takes from the front.
    private var order: [String]
    private var lookup: Set<String>

    public init(ids: [String] = []) {
        order = []
        lookup = []
        for id in ids { insert(id) }
    }

    public var ids: [String] { order }
    public var count: Int { order.count }

    public func contains(_ id: String) -> Bool { lookup.contains(id) }

    /// Marks a post read. Re-reading an old post does not move it back up the queue;
    /// what matters is only whether it has been seen.
    public mutating func insert(_ id: String) {
        guard lookup.insert(id).inserted else { return }
        order.append(id)
        guard order.count > Self.limit else { return }
        let overflow = order.count - Self.limit
        for dropped in order.prefix(overflow) { lookup.remove(dropped) }
        order.removeFirst(overflow)
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let ids = try decoder.singleValueContainer().decode([String].self)
        self.init(ids: ids)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(order)
    }
}
