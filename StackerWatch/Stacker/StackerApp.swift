import SwiftUI

/// The iPhone companion. It exists to show what was saved on the watch; reading
/// itself happens on stacker.news in the browser.
@main
struct StackerApp: App {
    @State private var sync = PhoneSync()

    var body: some Scene {
        WindowGroup {
            SavedListView()
                .environment(sync)
                .tint(.snYellow)
        }
    }
}
