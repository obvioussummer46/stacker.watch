import Foundation

/// Stores the territory list on disk.
///
/// Territories come and go over weeks, not seconds, so this is cached hard: the
/// picker reads it straight off disk and only hits the network once the entry is a
/// month old. Nothing here is on the path of reading posts.
public struct TerritoryCache: Sendable {
    public struct Entry: Codable, Sendable {
        public let savedAt: Date
        public let territories: [Territory]

        public init(savedAt: Date = Date(), territories: [Territory]) {
            self.savedAt = savedAt
            self.territories = territories
        }
    }

    /// Territories are refetched at most once a month.
    public static let maxAge: TimeInterval = 60 * 60 * 24 * 30
    public static let fileName = "territories.json"

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

    public func load() -> Entry? {
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder.sn.decode(Entry.self, from: data),
              !entry.territories.isEmpty else { return nil }
        return entry
    }

    public func save(_ territories: [Territory], now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Entry(savedAt: now, territories: territories))
        try data.write(to: fileURL, options: .atomic)
    }

    public func isStale(_ entry: Entry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.savedAt) > Self.maxAge
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
}
