import SwiftUI
import WatchKit
import SNKit

/// One full-screen tile. Fixed layout, no inner scrolling, so the crown pages tiles.
struct PostTileView: View {
    @Environment(FeedModel.self) private var model
    let item: Item
    /// Off on a territory screen, where every post is from the same territory.
    var showsTerritory = true
    /// Long-press action. watchOS reserves a downward swipe for Notification Center,
    /// and `refreshable` needs a scroll view, so a hold is the gesture left for this.
    var onRefresh: () -> Void = {}

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 4) {
                ByLine(item: item, showsTerritory: showsTerritory)
                Text(item.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(3)
                    // Grey once opened, so a glance says what is still unread.
                    .foregroundStyle(model.isRead(item.id) ? Color.snGrey : Color.primary)
                if let domain = item.domain {
                    Text(domain)
                        .font(.caption2)
                        .foregroundStyle(.snLink)
                        .lineLimit(1)
                }
                if item.hasText {
                    Text(MarkdownLite.excerpt(item.text))
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(item.isLink ? 6 : 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scenePadding(.horizontal)
        .onLongPressGesture {
            WKInterfaceDevice.current().play(.click)
            onRefresh()
        }
    }
}

/// ```
/// ~territory
/// @user                    3h
/// ```
///
/// Two lines rather than one: on a site-wide feed the territory changes from post to
/// post and is worth its own line, and splitting them means a long territory name can
/// no longer squeeze the poster off the screen.
struct ByLine: View {
    let item: Item
    var showsTerritory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTerritory, let sub = item.primarySub {
                Text("~\(sub)")
                    .foregroundStyle(.snYellow)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 4) {
                Text("@\(item.user.name)")
                    .foregroundStyle(.snGrey)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text(Format.age(item.createdAt))
                    .foregroundStyle(.snGrey)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.caption2)
    }
}
