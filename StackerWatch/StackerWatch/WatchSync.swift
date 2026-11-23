import Foundation
import WatchConnectivity
import SNKit

/// Sends the reading list to the iPhone and takes removals back.
///
/// The whole list goes out as the application context every time it changes, and
/// once at launch. The system delivers the latest context when the phone app next
/// runs, so nothing here waits for the phone to be reachable. Sending fails while
/// the phone app is not installed or the session is still activating, so the last
/// list is kept and sent again when the session reports a change.
///
/// Removals come the other way as the phone's application context, read at
/// activation and whenever it changes, and as a live message when the phone is
/// reachable at the time. Applying one twice is harmless.
@MainActor
final class WatchSync: NSObject {
    /// Called with the ids of posts the phone removed. Removals that arrive before
    /// this is set are held and delivered as soon as it is.
    var onRemove: (([String]) -> Void)? {
        didSet {
            guard onRemove != nil, !held.isEmpty else { return }
            let ids = held
            held = []
            apply(removals: ids)
        }
    }

    /// The most recent list handed over; re-sent after a failed or early push.
    private var latest: SavedPosts?
    /// Removals received while `onRemove` was still nil.
    private var held: [String] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func push(_ posts: SavedPosts) {
        latest = posts
        resend()
    }

    private func resend() {
        guard let latest, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Throws when the phone app is not installed or the list is unchanged.
        // `latest` is kept, so an install or the next change tries again.
        try? session.updateApplicationContext(SavedSync.context(for: latest))
    }

    private func apply(removals ids: [String]) {
        guard !ids.isEmpty else { return }
        guard let onRemove else {
            held.append(contentsOf: ids)
            return
        }
        onRemove(ids)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // The phone's last removals, kept by the system across launches.
        let ids = SavedSync.removedIDs(from: session.receivedApplicationContext)
        Task { @MainActor in
            apply(removals: ids)
            resend()
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in resend() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in resend() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let ids = SavedSync.removedIDs(from: applicationContext)
        Task { @MainActor in apply(removals: ids) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let ids = SavedSync.removedIDs(from: message)
        Task { @MainActor in apply(removals: ids) }
    }
}
