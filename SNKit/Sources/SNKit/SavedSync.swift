import Foundation

/// The wire format between the watch and the iPhone, carried by WatchConnectivity.
///
/// Each side publishes its state as the session's application context, which the
/// system keeps and delivers whenever the other app next runs: the watch publishes
/// the whole reading list, the phone publishes the ids it has removed that the watch
/// has not yet dropped. Latest wins on both, which is right for whole-state snapshots.
/// The same dictionaries double as live messages when the other device is reachable.
///
/// Post bodies are stripped before sending: the phone opens posts on stacker.news,
/// and the application context has a size limit that a hundred full posts would hit.
/// The list is one JSON blob under one key, so the dictionary stays property-list
/// safe and the schema lives in `Item`, not in dictionary keys.
public enum SavedSync {
    public static let listKey = "savedPosts"
    public static let removedKey = "removedPosts"

    // MARK: Watch to phone

    public static func context(for posts: SavedPosts) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(posts.items.map(withoutText))) ?? Data()
        return [listKey: data]
    }

    /// The list carried by a received context, or `nil` when it is not one of ours.
    public static func posts(from context: [String: Any]) -> SavedPosts? {
        guard let data = context[listKey] as? Data,
              let items = try? JSONDecoder.sn.decode([Item].self, from: data) else { return nil }
        return SavedPosts(items: items)
    }

    // MARK: Phone to watch

    /// Every id the phone removed and still waits for the watch to drop.
    public static func removalsContext(_ ids: some Sequence<String>) -> [String: Any] {
        [removedKey: Array(ids).sorted()]
    }

    /// Empty when the dictionary carries no removals.
    public static func removedIDs(from context: [String: Any]) -> [String] {
        context[removedKey] as? [String] ?? []
    }

    static func withoutText(_ item: Item) -> Item {
        Item(id: item.id, title: item.title, url: item.url, text: nil, sats: item.sats,
             boost: item.boost, ncomments: item.ncomments, createdAt: item.createdAt,
             subNames: item.subNames, user: item.user)
    }
}
