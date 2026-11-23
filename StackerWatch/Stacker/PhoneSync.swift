import Foundation
import Observation
import WatchConnectivity
import SNKit

/// The phone's copy of the watch's reading list.
///
/// The watch owns the list and sends it whole as its application context. The system
/// keeps the last context delivered, so the list is here even when this app was never
/// running while posts were saved.
///
/// Removals made here apply locally at once and are published as this side's
/// application context: the set of ids the watch has not yet dropped. The watch reads
/// that at launch or on change, removes the posts, and sends a list without them,
/// which is when the ids leave the set. Until then a stale list from the watch cannot
/// bring a removed post back. When the watch is reachable the same removals also go
/// out as a message, so the watch catches up while it is on screen.
@MainActor
@Observable
final class PhoneSync: NSObject {
    private(set) var saved: SavedPosts
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    private let store: SavedPostsStore
    private let defaults: UserDefaults
    /// Ids removed here that the watch has not yet dropped from its list.
    private var pendingRemovals: Set<String>

    private static let pendingKey = "pendingRemovals"

    init(store: SavedPostsStore = SavedPostsStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        saved = store.load()
        pendingRemovals = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func remove(_ id: String) {
        guard saved.contains(id) else { return }
        saved.remove(id)
        try? store.save(saved)
        pendingRemovals.insert(id)
        defaults.set(Array(pendingRemovals), forKey: Self.pendingKey)
        publishRemovals()
    }

    /// Takes the watch's list as the truth, minus removals it has not caught up with.
    private func apply(_ posts: SavedPosts) {
        var incoming = posts
        var caughtUp = false
        for id in pendingRemovals {
            if incoming.contains(id) {
                incoming.remove(id)
            } else {
                pendingRemovals.remove(id)
                caughtUp = true
            }
        }
        saved = incoming
        try? store.save(saved)
        if caughtUp {
            defaults.set(Array(pendingRemovals), forKey: Self.pendingKey)
            publishRemovals()
        }
    }

    private func publishRemovals() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let context = SavedSync.removalsContext(pendingRemovals)
        // Throws only when the set is unchanged, which needs no handling.
        try? session.updateApplicationContext(context)
        if session.isReachable, !pendingRemovals.isEmpty {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
    }

    private func updateWatchState(paired: Bool, installed: Bool) {
        isPaired = paired
        isWatchAppInstalled = installed
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        // The last list the watch sent, kept by the system across launches.
        let posts = SavedSync.posts(from: session.receivedApplicationContext)
        Task { @MainActor in
            updateWatchState(paired: paired, installed: installed)
            if let posts { apply(posts) }
            // Anything removed before activation finished goes out now.
            publishRemovals()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let posts = SavedSync.posts(from: applicationContext) else { return }
        Task { @MainActor in apply(posts) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in updateWatchState(paired: paired, installed: installed) }
    }

    /// The watch app came within reach; hand it any removals it has not seen, live.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in publishRemovals() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch; the session has to be activated again.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
