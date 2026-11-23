import SwiftUI
import SNKit

/// The one screen of the iPhone app: what was saved on the watch, newest first.
///
/// Tap a post to read it on stacker.news in the browser. Link posts can also open
/// the link itself from a leading swipe. Swipe the other way to remove a post; the
/// watch follows along.
struct SavedListView: View {
    @Environment(PhoneSync.self) private var sync
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if sync.saved.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Saved")
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(sync.saved.items) { item in
                    Button {
                        openURL(item.webURL)
                    } label: {
                        SavedPostRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        if let urlString = item.url, let url = URL(string: urlString) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open link", systemImage: "link")
                            }
                            .tint(.snLink)
                        }
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ sync.saved.items[$0].id }) {
                        sync.remove(id)
                    }
                }
            } footer: {
                Text("Saved in Stacker on your Apple Watch. Tap to read on stacker.news, swipe to remove.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "bookmark")
        } description: {
            Text(sync.isWatchAppInstalled
                 ? "Open a post in Stacker on your Apple Watch and tap Save. It shows up here."
                 : "Install Stacker on your Apple Watch, save posts there, and read them here.")
        }
    }
}

private struct SavedPostRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? "Untitled")
                .font(.headline)
                .lineLimit(3)
            HStack(spacing: 4) {
                if let sub = item.primarySub {
                    Text("~\(sub)")
                        .foregroundStyle(.snYellow)
                }
                Text("@\(item.user.name)")
                Text("·")
                Text(Format.age(item.createdAt))
                Spacer(minLength: 0)
                Label("\(Format.sats(item.sats))", systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if let domain = item.domain {
                Label(domain, systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.snLink)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
