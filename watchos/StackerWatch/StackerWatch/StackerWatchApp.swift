import SwiftUI

@main
struct StackerWatchApp: App {
    @State private var model = FeedModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environment(model)
                .tint(.snYellow)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshIfStale() }
            }
        }
    }
}
