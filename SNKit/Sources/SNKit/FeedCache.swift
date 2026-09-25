import Foundation

/// Stores the last loaded page(s) of each feed on disk so the app can show
/// a post before the network answers.
public struct FeedCache: Sendable {
    public struct Entry: Codable, Sendable {
        public let key: FeedKey
        public let savedAt: Date
        public let items: [Item]
        public let cursor: String?

        public init(key: FeedKey, savedAt: Date = Date(), items: [Item], cursor: String?) {
            self.key = key
            self.savedAt = savedAt
            self.items = items
            self.cursor = cursor
        }
    }

    public static let maxItems = 105
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("StackerWatch", isDirectory: true)
        }
    }

    public func load(_ key: FeedKey) -> Entry? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder.sn.decode(Entry.self, from: data), entry.key == key else { return nil }
        return entry
    }

    public func save(_ entry: Entry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let trimmed = Entry(key: entry.key, savedAt: entry.savedAt,
                            items: Array(entry.items.prefix(Self.maxItems)), cursor: entry.cursor)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(trimmed)
        try data.write(to: fileURL(for: entry.key), options: .atomic)
    }

    public func isStale(_ entry: Entry, maxAge: TimeInterval = 600, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) > maxAge
    }

    public func remove(_ key: FeedKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func fileURL(for key: FeedKey) -> URL {
        directory.appendingPathComponent(key.cacheFileName)
    }
}
