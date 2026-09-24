import Foundation
import Observation
import SNKit

/// Drives the feed: cache-first load, background refresh, paging and the configurable screens.
///
/// Every screen keeps its own state and is refreshed in the background, so swiping
/// sideways lands on posts that are already there instead of a spinner.
@Observable
@MainActor
final class FeedModel {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// A horizontal page. Settings sits to the left of every feed screen.
    enum Page: Hashable {
        case settings
        case feed(FeedSource)
    }

    /// Everything belonging to one screen.
    struct FeedState {
        var pager = FeedPager()
        var phase: Phase = .idle
        var selectedID: String?
        /// Non-blocking error shown over a cached feed.
        var banner: String?
        var lastRefresh: Date?
        var isLoadingMore = false

        var isStale: Bool {
            guard let lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) > FeedModel.staleAfter
        }
    }

    enum TerritoriesPhase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// The page on screen; bound to the outer `TabView`.
    var page: Page {
        didSet {
            guard case .feed(let source) = page else { return }
            lastSource = source
        }
    }

    /// Navigation path; a pushed `Item` is being read.
    var path: [Item] = []

    /// The screens the user has configured, in page order.
    private(set) var screens: [FeedSource]
    /// The most recent feed page, so settings can still act on a feed.
    private(set) var lastSource: FeedSource
    private(set) var discussionsOnly: Bool
    private(set) var textSize: TextSize
    private(set) var states: [FeedSource: FeedState] = [:]
    private(set) var territories: [Territory] = []
    private(set) var territoriesPhase: TerritoriesPhase = .idle
    private(set) var readPosts = ReadPosts()

    /// Screens with a refresh in flight, so preloading never doubles up.
    private var inFlight: Set<FeedSource> = []

    private let api: SNAPI
    private let cache: FeedCache
    private let territoryCache: TerritoryCache
    private let defaults: UserDefaults

    private static let screensKey = "screens"
    private static let discussionsKey = "discussionsOnly"
    private static let textSizeKey = "textSize"
    private static let readPostsKey = "readPosts"
    /// Short on purpose: a feed you swipe back to should not be minutes behind.
    static let staleAfter: TimeInterval = 120

    init(api: SNAPI = SNAPI(),
         cache: FeedCache = FeedCache(),
         territoryCache: TerritoryCache = TerritoryCache(),
         defaults: UserDefaults = .standard) {
        self.api = api
        self.cache = cache
        self.territoryCache = territoryCache
        self.defaults = defaults
        discussionsOnly = defaults.object(forKey: Self.discussionsKey) as? Bool ?? true
        textSize = TextSize(rawValue: defaults.object(forKey: Self.textSizeKey) as? Int ?? -1) ?? .default
        let stored = Self.storedScreens(defaults)
        screens = stored
        lastSource = stored[0]
        // Start on the first feed, not on settings, even though settings is to its left.
        page = .feed(stored[0])
        loadAllCaches()
        if let entry = territoryCache.load() {
            territories = entry.territories
            territoriesPhase = .loaded
        }
        if let data = defaults.data(forKey: Self.readPostsKey),
           let stored = try? JSONDecoder().decode(ReadPosts.self, from: data) {
            readPosts = stored
        }
    }

    // MARK: Read state

    func isRead(_ id: String) -> Bool { readPosts.contains(id) }

    /// Called when a post is opened.
    func markRead(_ id: String) {
        guard !readPosts.contains(id) else { return }
        readPosts.insert(id)
        guard let data = try? JSONEncoder().encode(readPosts) else { return }
        defaults.set(data, forKey: Self.readPostsKey)
    }

    // MARK: Reading state

    func state(for source: FeedSource) -> FeedState { states[source] ?? FeedState() }

    func items(for source: FeedSource) -> [Item] { state(for: source).pager.items }

    /// The screen on screen, or `nil` while settings is showing.
    var currentSource: FeedSource? {
        if case .feed(let source) = page { return source }
        return nil
    }

    func setSelectedID(_ id: String?, for source: FeedSource) {
        mutate(source) { $0.selectedID = id }
    }

    // MARK: Screens

    var canAddScreen: Bool { screens.count < FeedSource.maxScreens }

    /// Territory names with at least one screen, in screen order. Drives the
    /// "chosen first" ordering in the screen editor.
    var chosenTerritories: [String] {
        var seen = Set<String>()
        return screens.compactMap { source in
            guard let sub = source.sub, seen.insert(sub).inserted else { return nil }
            return sub
        }
    }

    /// Which sorts of a territory already have a screen.
    func chosenSorts(for territory: String) -> Set<FeedKind> {
        Set(screens.filter { $0.sub == territory }.map(\.kind))
    }

    func contains(_ source: FeedSource) -> Bool { screens.contains(source) }

    /// Adds or removes a screen. Keeps at least one so the pager is never empty.
    func toggleScreen(_ source: FeedSource) {
        if screens.contains(source) {
            removeScreen(source)
        } else {
            addScreen(source)
        }
    }

    func addScreen(_ source: FeedSource) {
        guard canAddScreen, !screens.contains(source) else { return }
        screens.append(source)
        states[source] = cachedState(for: source)
        persistScreens()
        preload(source)
    }

    func removeScreen(_ source: FeedSource) {
        guard screens.count > 1, let index = screens.firstIndex(of: source) else { return }
        screens.remove(at: index)
        states[source] = nil
        if currentSource == source { page = .feed(screens[min(index, screens.count - 1)]) }
        if lastSource == source { lastSource = screens[0] }
        persistScreens()
    }

    /// Drag-to-reorder from the settings page.
    func moveScreens(from offsets: IndexSet, to destination: Int) {
        screens.move(fromOffsets: offsets, toOffset: destination)
        persistScreens()
    }

    func setTextSize(_ size: TextSize) {
        guard size != textSize else { return }
        textSize = size
        defaults.set(size.rawValue, forKey: Self.textSizeKey)
    }

    // MARK: Loading

    /// Starts a refresh for every screen that needs one, without waiting for any.
    ///
    /// This is what keeps swiping instant: by the time a page scrolls into view its
    /// posts have usually already arrived.
    func preloadAll() {
        for source in screens { preload(source) }
    }

    /// Fire-and-forget refresh of one screen, skipped when it is fresh or already loading.
    func preload(_ source: FeedSource) {
        let current = state(for: source)
        guard !inFlight.contains(source), current.phase == .idle || current.isStale else { return }
        Task { await performRefresh(source) }
    }

    /// Called when the app returns to the foreground.
    func refreshIfStale() async {
        guard path.isEmpty else { return }
        preloadAll()
    }

    /// Awaited only by the explicit Retry button.
    func refresh(_ source: FeedSource) async {
        guard !inFlight.contains(source) else { return }
        await performRefresh(source)
    }

    private func performRefresh(_ source: FeedSource) async {
        inFlight.insert(source)
        defer { inFlight.remove(source) }
        let key = source.key(discussionsOnly: discussionsOnly)
        mutate(source) { state in
            if state.pager.isEmpty { state.phase = .loading }
            state.banner = nil
        }
        do {
            let page = try await api.fetchFeed(key)
            guard isCurrent(source, key) else { return }
            mutate(source) { state in
                let previous = state.selectedID
                // Someone parked on the newest post wants to *stay* on the newest
                // post, otherwise a refresh silently buries new arrivals above them.
                let wasAtTop = previous == nil || previous == state.pager.items.first?.id
                state.pager.reset(with: page)
                if !wasAtTop, let previous, state.pager.index(of: previous) != nil {
                    state.selectedID = previous
                } else {
                    state.selectedID = state.pager.items.first?.id
                }
                state.phase = .loaded
                state.lastRefresh = Date()
            }
            persist(source)
        } catch {
            guard isCurrent(source, key) else { return }
            let message = Self.message(for: error)
            mutate(source) { state in
                if state.pager.isEmpty { state.phase = .failed(message) } else { state.banner = message }
            }
        }
    }

    /// Drops results for a screen the user deleted, or for a superseded filter.
    private func isCurrent(_ source: FeedSource, _ key: FeedKey) -> Bool {
        key.discussionsOnly == discussionsOnly && screens.contains(source)
    }

    /// Fetches the next page when the visible tile is near the end.
    func loadMoreIfNeeded(source: FeedSource, around id: String?) async {
        guard let id else { return }
        let current = state(for: source)
        guard let index = current.pager.index(of: id),
              current.pager.shouldLoadMore(currentIndex: index),
              !current.isLoadingMore else { return }
        mutate(source) { $0.isLoadingMore = true }
        defer { mutate(source) { $0.isLoadingMore = false } }
        let key = source.key(discussionsOnly: discussionsOnly)
        do {
            let page = try await api.fetchFeed(key, cursor: current.pager.cursor)
            guard isCurrent(source, key) else { return }
            mutate(source) { $0.pager.append(page) }
            persist(source)
        } catch {
            mutate(source) { $0.banner = Self.message(for: error) }
        }
    }

    // MARK: Filter

    /// Applies to every screen, so they are all reloaded and preloaded again.
    func setDiscussionsOnly(_ on: Bool) async {
        guard on != discussionsOnly else { return }
        discussionsOnly = on
        defaults.set(on, forKey: Self.discussionsKey)
        path = []
        loadAllCaches()
        preloadAll()
    }

    // MARK: Territories

    /// Reads the cached list and only hits the network when it is a month old.
    func loadTerritories(force: Bool = false) async {
        let entry = territoryCache.load()
        if let entry {
            territories = entry.territories
            territoriesPhase = .loaded
            if !force, !territoryCache.isStale(entry) { return }
        }
        if territories.isEmpty { territoriesPhase = .loading }
        do {
            let fetched = try await api.fetchTopTerritories()
            guard !fetched.isEmpty else { territoriesPhase = .loaded; return }
            territories = fetched
            territoriesPhase = .loaded
            try? territoryCache.save(fetched)
        } catch {
            // A stale list is more useful than an error, so keep showing it.
            if territories.isEmpty {
                territoriesPhase = .failed(Self.message(for: error))
            } else {
                territoriesPhase = .loaded
            }
        }
    }

    // MARK: Persistence

    private static func storedScreens(_ defaults: UserDefaults) -> [FeedSource] {
        guard let data = defaults.data(forKey: Self.screensKey),
              let stored = try? JSONDecoder().decode([FeedSource].self, from: data),
              !stored.isEmpty else { return FeedSource.defaults }
        return Array(stored.prefix(FeedSource.maxScreens))
    }

    private func persistScreens() {
        guard let data = try? JSONEncoder().encode(screens) else { return }
        defaults.set(data, forKey: Self.screensKey)
    }

    private func loadAllCaches() {
        states = [:]
        for source in screens {
            states[source] = cachedState(for: source)
        }
    }

    private func cachedState(for source: FeedSource) -> FeedState {
        let key = source.key(discussionsOnly: discussionsOnly)
        guard let entry = cache.load(key), !entry.items.isEmpty else { return FeedState() }
        var state = FeedState()
        state.pager = FeedPager(items: entry.items, cursor: entry.cursor)
        state.selectedID = entry.items.first?.id
        state.lastRefresh = entry.savedAt
        state.phase = .loaded
        return state
    }

    private func persist(_ source: FeedSource) {
        let current = state(for: source)
        let entry = FeedCache.Entry(key: source.key(discussionsOnly: discussionsOnly),
                                    savedAt: current.lastRefresh ?? Date(),
                                    items: current.pager.items,
                                    cursor: current.pager.cursor)
        try? cache.save(entry)
    }

    private func mutate(_ source: FeedSource, _ body: (inout FeedState) -> Void) {
        var state = states[source] ?? FeedState()
        body(&state)
        states[source] = state
    }

    private static func message(for error: Error) -> String {
        (error as? SNError)?.message ?? error.localizedDescription
    }
}
