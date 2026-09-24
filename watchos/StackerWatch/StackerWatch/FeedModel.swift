import Foundation
import Observation
import SNKit

/// Drives the feed: cache-first load, refresh, paging, feed switching and "surprise me".
@Observable
@MainActor
final class FeedModel {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var pager = FeedPager()
    private(set) var phase: Phase = .idle
    private(set) var feedKey: FeedKey
    /// Non-blocking error shown over a cached feed.
    private(set) var banner: String?
    private(set) var isLoadingMore = false

    /// Id of the tile currently on screen.
    var selectedID: String?
    /// Navigation path; a pushed `Item` is being read.
    var path: [Item] = []

    var items: [Item] { pager.items }

    private var lastRefresh: Date?
    private var shufflePool = FeedPager()
    private var refreshTask: Task<Void, Never>?

    private let api: SNAPI
    private let cache: FeedCache
    private let defaults: UserDefaults

    private static let kindKey = "feedKind"
    private static let discussionsKey = "discussionsOnly"
    private static let staleAfter: TimeInterval = 600

    init(api: SNAPI = SNAPI(), cache: FeedCache = FeedCache(), defaults: UserDefaults = .standard) {
        self.api = api
        self.cache = cache
        self.defaults = defaults
        let kind = FeedKind(rawValue: defaults.string(forKey: Self.kindKey) ?? "") ?? .hot
        let discussions = defaults.object(forKey: Self.discussionsKey) as? Bool ?? true
        feedKey = FeedKey(kind: kind, discussionsOnly: discussions)
        loadCache()
    }

    // MARK: Loading

    /// Called once when the feed appears.
    func start() async {
        if phase == .idle || isStale { await refresh() }
    }

    /// Called when the app returns to the foreground.
    func refreshIfStale() async {
        if isStale, path.isEmpty { await refresh() }
    }

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > Self.staleAfter
    }

    func refresh() async {
        refreshTask?.cancel()
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        if items.isEmpty { phase = .loading }
        banner = nil
        let key = feedKey
        do {
            let page = try await api.fetchFeed(key)
            guard !Task.isCancelled, key == feedKey else { return }
            let previous = selectedID
            pager.reset(with: page)
            if let previous, pager.index(of: previous) != nil {
                selectedID = previous
            } else {
                selectedID = items.first?.id
            }
            phase = .loaded
            lastRefresh = Date()
            persist()
        } catch {
            guard !Task.isCancelled, key == feedKey else { return }
            let message = Self.message(for: error)
            if items.isEmpty { phase = .failed(message) } else { banner = message }
        }
    }

    /// Fetches the next page when the visible tile is near the end.
    func loadMoreIfNeeded(around id: String?) async {
        guard let id, let index = pager.index(of: id),
              pager.shouldLoadMore(currentIndex: index), !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let key = feedKey
        do {
            let page = try await api.fetchFeed(key, cursor: pager.cursor)
            guard key == feedKey else { return }
            pager.append(page)
            persist()
        } catch {
            banner = Self.message(for: error)
        }
    }

    // MARK: Feed selection

    func setKind(_ kind: FeedKind) async {
        await setFeedKey(FeedKey(kind: kind, discussionsOnly: feedKey.discussionsOnly))
    }

    func setDiscussionsOnly(_ on: Bool) async {
        await setFeedKey(FeedKey(kind: feedKey.kind, discussionsOnly: on))
    }

    private func setFeedKey(_ key: FeedKey) async {
        guard key != feedKey else { return }
        refreshTask?.cancel()
        feedKey = key
        defaults.set(key.kind.rawValue, forKey: Self.kindKey)
        defaults.set(key.discussionsOnly, forKey: Self.discussionsKey)
        path = []
        selectedID = nil
        banner = nil
        loadCache()
        await start()
    }

    // MARK: Surprise me

    /// Opens a random post from the year's top discussions (or the loaded feed when offline).
    func surpriseMe() async {
        if shufflePool.items.count < 60, !shufflePool.exhausted {
            if let page = try? await api.fetchShufflePage(cursor: shufflePool.cursor) {
                shufflePool.append(page)
            }
        }
        let pool = shufflePool.items.isEmpty ? items : shufflePool.items
        let current = path.last?.id ?? selectedID
        guard let pick = pool.filter({ $0.id != current }).randomElement() else { return }
        path = [pick]
    }

    // MARK: Cache

    private func loadCache() {
        if let entry = cache.load(feedKey), !entry.items.isEmpty {
            pager = FeedPager(items: entry.items, cursor: entry.cursor)
            selectedID = items.first?.id
            lastRefresh = entry.savedAt
            phase = .loaded
        } else {
            pager = FeedPager()
            selectedID = nil
            lastRefresh = nil
            phase = .idle
        }
    }

    private func persist() {
        let entry = FeedCache.Entry(key: feedKey, savedAt: lastRefresh ?? Date(), items: items, cursor: pager.cursor)
        try? cache.save(entry)
    }

    private static func message(for error: Error) -> String {
        (error as? SNError)?.message ?? error.localizedDescription
    }
}
