import SwiftUI
import SNKit

/// The rightmost page: posts saved from the reader, newest first. Tap one to read it,
/// offline too, since whole posts are stored.
///
/// No swipe-to-delete, for the same reason as in settings: a horizontal swipe here
/// belongs to the pager. Unsaving is the `Saved` button inside the post.
struct SavedPostsView: View {
    @Environment(FeedModel.self) private var model

    var body: some View {
        if model.savedPosts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.title3)
                    .foregroundStyle(.snYellow)
                Text("Nothing saved yet.")
                    .foregroundStyle(.secondary)
                Text("Open a post and tap Save for later. Saved posts also show up in Stacker on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .scenePadding(.horizontal)
        } else {
            List {
                Section {
                    ForEach(model.savedPosts.items) { item in
                        NavigationLink(value: item) {
                            SavedRow(item: item)
                        }
                    }
                } footer: {
                    Text("Also in Stacker on your iPhone. Open a post and tap Saved to remove it.")
                }
            }
        }
    }
}

private struct SavedRow: View {
    @Environment(FeedModel.self) private var model
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title ?? "Untitled")
                .lineLimit(2)
                .foregroundStyle(model.isRead(item.id) ? Color.snGrey : Color.primary)
            // One run of text rather than an HStack, so a long territory name only
            // loses its tail instead of both halves being squeezed to "~bitcoin_be…".
            caption
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var caption: Text {
        let user = Text("@\(item.user.name)").foregroundStyle(.snGrey)
        guard let sub = item.primarySub else { return user }
        return Text("~\(sub) ").foregroundStyle(.snYellow) + user
    }
}
