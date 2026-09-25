import SwiftUI
import SNKit

/// Root screen. Swipe sideways to change screen, turn the crown to move between posts.
///
/// Settings is the leftmost page, so it is one swipe right from the first feed. No
/// toolbar buttons: on watchOS they render as tinted circles over the text.
struct FeedView: View {
    @Environment(FeedModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            TabView(selection: $model.page) {
                SettingsView()
                    .tag(FeedModel.Page.settings)
                ForEach(model.screens) { source in
                    FeedPageView(source: source)
                        .tag(FeedModel.Page.feed(source))
                }
            }
            .tabViewStyle(.page)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Item.self) { item in
                PostDetailView(item: item)
            }
        }
        // Every screen loads up front, so a swipe lands on posts rather than a spinner.
        .task { model.preloadAll() }
        .onChange(of: model.screens) { _, _ in model.preloadAll() }
        // Landing on a screen tops it up; a no-op when it is already fresh.
        .onChange(of: model.page) { _, _ in model.preloadAll() }
    }

    private var title: String {
        switch model.page {
        case .settings: return "Settings"
        case .feed(let source): return source.fullTitle
        }
    }
}

/// One screen: a vertical pager of tiles, so the crown moves between posts.
private struct FeedPageView: View {
    @Environment(FeedModel.self) private var model
    let source: FeedSource

    var body: some View {
        let state = model.state(for: source)
        content(state)
            .overlay(alignment: .top) {
                if let banner = state.banner {
                    BannerView(text: banner)
                }
            }
            .onChange(of: state.selectedID) { _, id in
                Task { await model.loadMoreIfNeeded(source: source, around: id) }
            }
    }

    @ViewBuilder
    private func content(_ state: FeedModel.FeedState) -> some View {
        if state.pager.isEmpty {
            switch state.phase {
            case .failed(let message):
                ErrorView(message: message) { Task { await model.refresh(source) } }
            case .loaded:
                EmptyFeedView()
            case .idle, .loading:
                LoadingView()
            }
        } else {
            TabView(selection: selection) {
                ForEach(state.pager.items) { item in
                    PostTileView(item: item, showsTerritory: !source.isTerritory) {
                        Task { await model.refresh(source) }
                    }
                    .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.verticalPage)
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.state(for: source).selectedID },
                set: { model.setSelectedID($0, for: source) })
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading posts…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(.snYellow)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
        }
        .scenePadding(.horizontal)
    }
}

struct EmptyFeedView: View {
    var body: some View {
        Text("Nothing here yet.")
            .foregroundStyle(.secondary)
    }
}

struct BannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 2)
    }
}
