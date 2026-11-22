import SwiftUI
import WatchKit
import SNKit

/// Full post text, then the top-level comments. The crown scrolls.
struct PostDetailView: View {
    @Environment(FeedModel.self) private var model
    let item: Item
    @State private var comments: CommentsState = .idle
    @State private var showOpenOnPhone = false
    private let api = SNAPI()

    enum CommentsState: Equatable {
        case idle, loading
        case loaded([Comment])
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title ?? "Untitled")
                    .font(.headline)
                ByLine(item: item)
                PostStats(item: item)
                if let urlString = item.url, let url = URL(string: urlString), let domain = item.domain {
                    Link(destination: url) {
                        Label(domain, systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.snLink)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                actions
                if item.hasText {
                    MarkdownBlocksView(markdown: item.text ?? "")
                }
                Divider()
                    .padding(.vertical, 4)
                commentsSection
            }
            .scenePadding(.horizontal)
        }
        .navigationTitle(item.primarySub.map { "~\($0)" } ?? "Post")
        .navigationBarTitleDisplayMode(.inline)
        .handoff(item)
        .sheet(isPresented: $showOpenOnPhone) {
            OpenOnPhoneView(item: item)
        }
        .task(id: item.id) {
            model.markRead(item.id)
            await loadComments()
        }
    }

    /// `Save` and `iPhone`, above the text: whoever wants the post on a bigger
    /// screen decides that before reading, not after.
    private var actions: some View {
        let isSaved = model.isSaved(item.id)
        return HStack(spacing: 6) {
            Button {
                let saved = model.toggleSaved(item)
                WKInterfaceDevice.current().play(saved ? .success : .click)
            } label: {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(isSaved ? Color.snYellow : Color.primary)
            Button {
                showOpenOnPhone = true
            } label: {
                Label("iPhone", systemImage: "iphone")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption2)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var commentsSection: some View {
        if item.ncomments == 0 {
            Text("No comments yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("\(item.ncomments) comments")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.snYellow)
            switch comments {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .failed(let message):
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await loadComments() } }
            case .loaded(let list):
                if list.isEmpty {
                    Text("No comments to show")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { comment in
                    CommentRow(comment: comment)
                }
            }
        }
    }

    private func loadComments() async {
        guard item.ncomments > 0, comments == .idle || isFailed else { return }
        comments = .loading
        do {
            let detail = try await api.fetchItem(id: item.id)
            comments = .loaded(Array(detail.comments.comments.prefix(10)))
        } catch {
            comments = .failed((error as? SNError)?.message ?? error.localizedDescription)
        }
    }

    private var isFailed: Bool {
        if case .failed = comments { return true }
        return false
    }
}

extension View {
    /// Advertises the post for Handoff while this view is on screen.
    ///
    /// The paired iPhone then shows a Safari icon at the bottom of the Lock Screen and
    /// in the App Switcher; tapping it opens the post's page on stacker.news. No app on
    /// the phone claims the activity, so the `webpageURL` is what gets continued.
    func handoff(_ item: Item) -> some View {
        userActivity(NSUserActivityTypeBrowsingWeb) { activity in
            activity.title = item.title ?? "stacker.news"
            activity.webpageURL = item.webURL
            activity.isEligibleForHandoff = true
        }
    }
}

/// What the `iPhone` button shows. Handoff needs no tap on the watch, the post is
/// advertised the whole time it is open; this sheet exists because that is invisible,
/// and to offer the share sheet for a phone Handoff cannot reach.
private struct OpenOnPhoneView: View {
    let item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Handoff is on", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.snYellow)
                Text("On your iPhone, tap the Safari icon at the bottom of the Lock Screen, or at the bottom of the App Switcher, to open this post.")
                    .font(.footnote)
                Text("Both devices need the same Apple Account with Handoff, Bluetooth and Wi‑Fi on.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ShareLink(item: item.webURL) {
                    Label("Send link…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .font(.footnote)
            }
            .scenePadding(.horizontal)
        }
        // Keep advertising while the sheet covers the reader.
        .handoff(item)
    }
}

/// `⚡ 9.4k sats` — zaps show here, once the post is open, not on the tile.
///
/// Age is already in `ByLine` above and the comment count heads the comments
/// section below, so neither is repeated here.
struct PostStats: View {
    let item: Item

    var body: some View {
        Label("\(Format.sats(item.sats)) sats", systemImage: "bolt.fill")
            .font(.caption2)
            .foregroundStyle(.snYellow)
            .lineLimit(1)
    }
}

struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("@\(comment.user.name)")
                Spacer(minLength: 0)
                Text("⚡\(Format.sats(comment.sats))")
                Text(Format.age(comment.createdAt))
            }
            .font(.caption2)
            .foregroundStyle(.snGrey)
            .lineLimit(1)
            Text(MarkdownLite.plainText(comment.text))
                .font(.footnote)
            if comment.ncomments > 0 {
                Text("\(comment.ncomments) replies")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
