import SwiftUI
import SNKit

/// Root screen: one post per page, Digital Crown moves between posts.
struct FeedView: View {
    @Environment(FeedModel.self) private var model
    @State private var showPicker = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            content
                .navigationDestination(for: Item.self) { item in
                    PostDetailView(item: item)
                }
                .navigationTitle(model.feedKey.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showPicker = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Choose feed")
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task { await model.surpriseMe() }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .accessibilityLabel("Surprise me")
                        Spacer()
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
                .sheet(isPresented: $showPicker) {
                    FeedPickerView()
                }
        }
        .task { await model.start() }
        .onChange(of: model.selectedID) { _, id in
            Task { await model.loadMoreIfNeeded(around: id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        if model.items.isEmpty {
            switch model.phase {
            case .failed(let message):
                ErrorView(message: message) { Task { await model.refresh() } }
            case .loaded:
                EmptyFeedView()
            case .idle, .loading:
                LoadingView()
            }
        } else {
            TabView(selection: $model.selectedID) {
                ForEach(model.items) { item in
                    PostTileView(item: item)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.verticalPage)
            .overlay(alignment: .top) {
                if let banner = model.banner {
                    BannerView(text: banner)
                }
            }
        }
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
        .padding(.horizontal, 8)
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
