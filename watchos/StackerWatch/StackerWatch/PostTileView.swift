import SwiftUI
import SNKit

/// One full-screen tile. Fixed layout, no inner scrolling, so the crown pages tiles.
struct PostTileView: View {
    let item: Item

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 5) {
                MetaLine(item: item)
                Text(item.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                if let domain = item.domain {
                    Label(domain, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.snLink)
                        .lineLimit(1)
                }
                if item.hasText {
                    Text(MarkdownLite.excerpt(item.text))
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(item.isLink ? 4 : 6)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

/// `~sub · @user · ⚡ 9.4k · 12 comments · 3h`
struct MetaLine: View {
    let item: Item

    var body: some View {
        HStack(spacing: 4) {
            if let sub = item.primarySub {
                Text("~\(sub)")
                    .foregroundStyle(.snYellow)
            }
            Text("@\(item.user.name)")
            Spacer(minLength: 0)
            Text("⚡\(Format.sats(item.sats))")
            Text(Format.age(item.createdAt))
        }
        .font(.caption2)
        .foregroundStyle(.snGrey)
        .lineLimit(1)
    }
}
