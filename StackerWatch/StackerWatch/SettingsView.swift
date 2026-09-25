import SwiftUI
import SNKit

/// The leftmost horizontal page, one swipe right from the first feed.
///
/// Reordering only: long-press a screen and drag it up or down. There is no
/// swipe-to-delete, because a horizontal swipe here belongs to the pager — it would
/// flick you to the next page instead of revealing a delete button. Adding and
/// removing lives in `ModifyScreensView`.
struct SettingsView: View {
    @Environment(FeedModel.self) private var model
    @State private var showModifyScreens = false

    var body: some View {
        List {
            Section("Text size") {
                Picker("Text size", selection: Binding(
                    get: { model.textSize },
                    set: { model.setTextSize($0) }
                )) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
            }

            Section {
                ForEach(model.screens) { source in
                    ScreenRow(source: source)
                }
                .onMove { offsets, destination in
                    model.moveScreens(from: offsets, to: destination)
                }

                Button {
                    showModifyScreens = true
                } label: {
                    Label("Modify screens", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("Screens")
            } footer: {
                Text("Hold a screen and drag to reorder.")
            }

            Section {
                Toggle("Text posts only", isOn: Binding(
                    get: { model.discussionsOnly },
                    set: { on in Task { await model.setDiscussionsOnly(on) } }
                ))
            } footer: {
                Text("Off shows link posts too. They have a title and a domain, little to read.")
            }
        }
        .sheet(isPresented: $showModifyScreens) {
            ModifyScreensView()
        }
    }
}

private struct ScreenRow: View {
    let source: FeedSource

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .lineLimit(1)
                    .foregroundStyle(source.isTerritory ? .snYellow : .primary)
                Text(source.sortTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Screen editor

/// Add and remove screens with check marks. Site-wide feeds are toggled directly;
/// a territory opens its own sorts, so `~bitcoin · Hot` and `~bitcoin · Recent` can
/// both exist as separate screens.
private struct ModifyScreensView: View {
    @Environment(FeedModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FeedKind.allCases, id: \.self) { kind in
                        CheckRow(source: FeedSource(kind: kind))
                    }
                } header: {
                    Text("Site-wide")
                } footer: {
                    Text("\(model.screens.count) of \(FeedSource.maxScreens) screens used.")
                }

                Section("Territories") {
                    territories
                }
            }
            .navigationTitle("Screens")
        }
        .task { await model.loadTerritories() }
    }

    @ViewBuilder
    private var territories: some View {
        switch model.territoriesPhase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.loadTerritories(force: true) } }
        case .idle, .loaded:
            if ordered.isEmpty {
                Text("No territories found")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(ordered, id: \.self) { name in
                NavigationLink {
                    TerritorySortsView(territory: name)
                } label: {
                    TerritoryRow(name: name, chosen: model.chosenSorts(for: name))
                }
            }
        }
    }

    /// Chosen territories first, then the rest. Both groups alphabetical, ignoring
    /// case, since territory names mix `bitcoin` with `AskSN` and `Stacker_Sports`.
    private var ordered: [String] {
        let chosen = Set(model.chosenTerritories)
        let all = Set(model.territories.map(\.name)).union(chosen)
        return all.sorted { left, right in
            let leftChosen = chosen.contains(left)
            if leftChosen != chosen.contains(right) { return leftChosen }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }
}

private struct TerritoryRow: View {
    let name: String
    let chosen: Set<FeedKind>

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // No tilde here: the list reads as plain alphabetical names.
            Text(name)
                .lineLimit(1)
                .foregroundStyle(chosen.isEmpty ? Color.primary : Color.snYellow)
            if !chosen.isEmpty {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Lists the chosen sorts in the order they appear in `FeedKind`.
    private var summary: String {
        FeedKind.allCases.filter { chosen.contains($0) }.map(\.title).joined(separator: ", ")
    }
}

/// The three sorts of one territory, each a check row.
private struct TerritorySortsView: View {
    @Environment(FeedModel.self) private var model
    let territory: String

    var body: some View {
        List {
            Section {
                ForEach(FeedKind.allCases, id: \.self) { kind in
                    CheckRow(source: FeedSource(kind: kind, sub: territory), showsSortOnly: true)
                }
            } footer: {
                Text("Each checked sort is its own screen.")
            }
        }
        .navigationTitle(territory)
    }
}

/// A row that toggles one screen on or off.
private struct CheckRow: View {
    @Environment(FeedModel.self) private var model
    let source: FeedSource
    var showsSortOnly = false

    var body: some View {
        let isOn = model.contains(source)
        Button {
            model.toggleScreen(source)
        } label: {
            HStack {
                Text(showsSortOnly ? source.sortTitle : source.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.snYellow : Color.snGrey)
            }
        }
        // Blocked when the list is full, or when this is the last screen left.
        .disabled(isOn ? model.screens.count == 1 : !model.canAddScreen)
    }
}
