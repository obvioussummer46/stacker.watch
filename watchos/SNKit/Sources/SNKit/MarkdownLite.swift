import Foundation

/// A tiny, dependency-free markdown splitter. It does not render inline
/// markdown; it splits a post into blocks the app can lay out, and produces
/// plain-text excerpts for tiles. Good enough for prose posts on a watch.
public enum MarkdownLite {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case quote(String)
        case code(String)
        case listItem(String)
        case image(alt: String, url: String)
        case rule
    }

    // MARK: Blocks

    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]? = nil

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: " ")))
                quote = []
            }
        }
        func flushAll() { flushParagraph(); flushQuote() }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var current = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(current.joined(separator: "\n")))
                    code = nil
                } else {
                    current.append(line)
                    code = current
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushAll()
                code = []
                continue
            }
            if trimmed.isEmpty {
                flushAll()
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll()
                blocks.append(.rule)
                continue
            }
            if let image = standaloneImage(trimmed) {
                flushAll()
                blocks.append(image)
                continue
            }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6, !text.isEmpty {
                    flushAll()
                    blocks.append(.heading(level: level, text: text))
                    continue
                }
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if let item = listItemText(trimmed) {
                flushAll()
                blocks.append(.listItem(item))
                continue
            }
            flushQuote()
            paragraph.append(trimmed)
        }
        if let current = code { blocks.append(.code(current.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    private static func standaloneImage(_ line: String) -> Block? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let url = String(line[close.upperBound..<line.index(before: line.endIndex)])
        guard !url.contains(" ") else { return nil }
        return .image(alt: alt, url: url)
    }

    private static func listItemText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        var digits = 0
        for ch in line {
            if ch.isNumber { digits += 1 } else { break }
        }
        if digits > 0 {
            let rest = line.dropFirst(digits)
            if rest.hasPrefix(". ") { return String(rest.dropFirst(2)) }
        }
        return nil
    }

    // MARK: Plain text

    /// Strips markdown syntax and image references, leaving readable prose.
    public static func plainText(_ markdown: String?) -> String {
        guard let markdown, !markdown.isEmpty else { return "" }
        var out = ""
        for block in blocks(markdown) {
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text), .listItem(let text):
                let cleaned = stripInline(text)
                if !cleaned.isEmpty { out += cleaned + "\n" }
            case .code(let text):
                out += text + "\n"
            case .image, .rule:
                continue
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First `maxChars` of the plain text, cut on a word boundary.
    public static func excerpt(_ markdown: String?, maxChars: Int = 220) -> String {
        let text = plainText(markdown).replacingOccurrences(of: "\n", with: " ")
        guard text.count > maxChars else { return text }
        let cut = text.index(text.startIndex, offsetBy: maxChars)
        var end = cut
        if let space = text[..<cut].lastIndex(of: " "), text.distance(from: text.startIndex, to: space) > maxChars / 2 {
            end = space
        }
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Removes inline markdown: images, links, emphasis, code spans, html tags.
    public static func stripInline(_ text: String) -> String {
        var s = text
        s = replace(s, pattern: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "")
        s = replace(s, pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1")
        s = replace(s, pattern: "<[^>]+>", with: "")
        s = replace(s, pattern: "`([^`]*)`", with: "$1")
        s = replace(s, pattern: "(\\*\\*|__)(.+?)\\1", with: "$2")
        s = replace(s, pattern: "(?<![\\w])(\\*|_)(?!\\s)(.+?)(?<!\\s)\\1(?![\\w])", with: "$2")
        s = replace(s, pattern: "~~(.+?)~~", with: "$1")
        s = replace(s, pattern: "[ \\t]+", with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ s: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    // MARK: URLs

    /// Host of a URL without a leading "www.", or nil.
    public static func domain(_ url: String) -> String? {
        guard let host = URLComponents(string: url)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
