import Foundation

/// Posts the user has saved for later, newest first.
///
/// Whole items are kept, not just ids, so a saved post is readable offline and the
/// list can be drawn without a network round trip. Capped at `limit`: saving one more
/// drops the oldest. Encodes as a plain array of items.
public struct SavedPosts: Codable, Sendable, Equatable {
    /// Plenty for a reading queue, and a few hundred KB at most on disk.
    public static let limit = 100

    /// Newest first, so the list shows what was saved last at the top.
    private var order: [Item]
    private var lookup: Set<String>

    public init(items: [Item] = []) {
        order = []
        lookup = []
        // Appending preserves the given order, including when restoring from disk.
        for item in items where lookup.insert(item.id).inserted {
            order.append(item)
        }
        trim()
    }

    public var items: [Item] { order }
    public var count: Int { order.count }
    public var isEmpty: Bool { order.isEmpty }

    public func contains(_ id: String) -> Bool { lookup.contains(id) }

    /// Saves a post. Saving an already saved post does nothing: it keeps its place.
    public mutating func insert(_ item: Item) {
        guard lookup.insert(item.id).inserted else { return }
        order.insert(item, at: 0)
        trim()
    }

    public mutating func remove(_ id: String) {
        guard lookup.remove(id) != nil else { return }
        order.removeAll { $0.id == id }
    }

    /// Saves or unsaves. Returns whether the post is saved afterwards.
    @discardableResult
    public mutating func toggle(_ item: Item) -> Bool {
        if contains(item.id) {
            remove(item.id)
            return false
        }
        insert(item)
        return true
    }

    /// Drops the oldest items, which sit at the end.
    private mutating func trim() {
        guard order.count > Self.limit else { return }
        for dropped in order.suffix(from: Self.limit) { lookup.remove(dropped.id) }
        order.removeSubrange(Self.limit...)
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let items = try decoder.singleValueContainer().decode([Item].self)
        self.init(items: items)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(order)
    }
}

/// Keeps `SavedPosts` on disk, in Application Support rather than Caches: the system
/// may purge Caches under pressure, and a reading list is not something to lose.
public struct SavedPostsStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                .map { $0.appendingPathComponent("StackerWatch", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("saved-posts.json")
    }

    /// Empty when nothing was saved yet, or when the file cannot be read.
    public func load() -> SavedPosts {
        guard let data = try? Data(contentsOf: fileURL),
              let posts = try? JSONDecoder.sn.decode(SavedPosts.self, from: data) else { return SavedPosts() }
        return posts
    }

    public func save(_ posts: SavedPosts) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(posts).write(to: fileURL, options: .atomic)
    }
}
