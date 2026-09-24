import SwiftUI
import SNKit

/// Full post text, then the top-level comments. The crown scrolls.
struct PostDetailView: View {
    let item: Item
    @State private var comments: CommentsState = .idle
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
                MetaLine(item: item)
                if let urlString = item.url, let url = URL(string: urlString), let domain = item.domain {
                    Link(destination: url) {
                        Label(domain, systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.snLink)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                if item.hasText {
                    MarkdownBlocksView(markdown: item.text ?? "")
                }
                Divider()
                    .padding(.vertical, 4)
                commentsSection
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(item.primarySub.map { "~\($0)" } ?? "Post")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) { await loadComments() }
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
