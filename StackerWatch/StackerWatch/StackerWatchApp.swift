import SwiftUI

@main
struct StackerWatchApp: App {
    @State private var model: FeedModel
    @State private var sync: WatchSync
    @Environment(\.scenePhase) private var scenePhase

    /// Wired here, not in a view's `.task`: the system launches the app in the
    /// background to deliver WatchConnectivity content, with no view on screen, and
    /// a removal from the phone has to be applied in that launch too.
    init() {
        let model = FeedModel()
        let sync = WatchSync()
        model.savedPostsDidChange = { [weak sync] posts in sync?.push(posts) }
        sync.onRemove = { [weak model] ids in
            for id in ids { model?.removeSaved(id) }
        }
        sync.push(model.savedPosts)
        _model = State(initialValue: model)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environment(model)
                .tint(.snYellow)
                .dynamicTypeSize(model.textSize.dynamicTypeSize)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshIfStale() }
            }
        }
    }
}
