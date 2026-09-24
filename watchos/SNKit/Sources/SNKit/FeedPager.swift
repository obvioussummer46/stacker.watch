import Foundation

/// Pure pagination state for a feed. No I/O; the view model drives it.
public struct FeedPager: Codable, Equatable, Sendable {
    public private(set) var items: [Item]
    public private(set) var cursor: String?
    public private(set) var exhausted: Bool

    public init(items: [Item] = [], cursor: String? = nil) {
        self.items = []
        self.cursor = cursor
        self.exhausted = cursor == nil && !items.isEmpty
        appendUnique(items)
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Replace everything with a fresh first page.
    public mutating func reset(with page: ItemsPage) {
        items = []
        cursor = page.cursor
        exhausted = page.cursor == nil
        appendUnique(page.items)
    }

    /// Append a page, dropping items already present (the hot feed reorders between pages).
    public mutating func append(_ page: ItemsPage) {
        cursor = page.cursor
        exhausted = page.cursor == nil
        appendUnique(page.items)
    }

    /// True when the user is near the end and another page could be fetched.
    public func shouldLoadMore(currentIndex: Int, threshold: Int = 5) -> Bool {
        guard !exhausted, cursor != nil, !items.isEmpty else { return false }
        return currentIndex >= items.count - threshold
    }

    public func index(of id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private mutating func appendUnique(_ new: [Item]) {
        var seen = Set(items.map(\.id))
        for item in new where !seen.contains(item.id) {
            seen.insert(item.id)
            items.append(item)
        }
    }
}
