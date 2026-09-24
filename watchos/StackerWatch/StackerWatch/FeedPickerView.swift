import SwiftUI
import SNKit

/// Sheet for choosing the feed. Kept to one list so it is a single tap away.
struct FeedPickerView: View {
    @Environment(FeedModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Feed") {
                ForEach(FeedKind.allCases, id: \.self) { kind in
                    Button {
                        Task { await model.setKind(kind) }
                        dismiss()
                    } label: {
                        HStack {
                            Text(kind.title)
                            Spacer()
                            if kind == model.feedKey.kind {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.snYellow)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Text posts only", isOn: Binding(
                    get: { model.feedKey.discussionsOnly },
                    set: { on in Task { await model.setDiscussionsOnly(on) } }
                ))
            } footer: {
                Text("Off shows link posts too. They have a title and a domain, little to read.")
            }
        }
        .navigationTitle("Feeds")
    }
}
