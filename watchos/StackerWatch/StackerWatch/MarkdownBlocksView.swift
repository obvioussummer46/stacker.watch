import SwiftUI
import SNKit

/// Lays out the blocks SNKit split a post into. Inline markdown is rendered
/// by Foundation; anything it cannot parse falls back to plain text.
struct MarkdownBlocksView: View {
    let markdown: String

    private var blocks: [MarkdownLite.Block] { MarkdownLite.blocks(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownLite.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level <= 2 ? .title3.weight(.semibold) : .headline)
        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.body)
        case .listItem(let text):
            HStack(alignment: .top, spacing: 4) {
                Text("•")
                Text(Self.inline(text))
            }
            .font(.body)
        case .quote(let text):
            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .fill(Color.snYellow)
                    .frame(width: 3)
                Text(Self.inline(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .code(let text):
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .image(let alt, _):
            Label(alt.isEmpty ? "image" : alt, systemImage: "photo")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .rule:
            Divider()
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(MarkdownLite.stripInline(text))
    }
}
