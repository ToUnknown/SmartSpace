import SwiftUI

/// Renders plain text that may include simple markdown and bullet lists.
/// - Supports: paragraphs, "- " bullets (with indentation), and inline markdown like **bold**.
/// - Presentation-only: does not mutate stored content.
struct FormattedMarkdownTextView: View {
    let text: String

    var body: some View {
        let parts = parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parts) { part in
                switch part.kind {
                case .paragraph:
                    attributedText(part.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let level):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(level == 0 ? "•" : "◦")
                            .foregroundStyle(.tertiary)
                        attributedText(part.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(min(level, 4)) * 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension FormattedMarkdownTextView {
    struct Part: Identifiable {
        enum Kind {
            case paragraph
            case bullet(level: Int)
        }

        let id = UUID()
        let kind: Kind
        let text: String
    }

    func attributedText(_ s: String) -> Text {
        // Use markdown parsing for bold/italic; fall back to plain text if parsing fails.
        if let attributed = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(s)
    }

    func parse(_ text: String) -> [Part] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var out: [Part] = []
        out.reserveCapacity(lines.count)

        for raw in lines {
            // Preserve intentional blank lines as spacing (by skipping; VStack spacing handles it).
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            let leadingSpaces = raw.prefix { $0 == " " }.count
            let level = max(0, leadingSpaces / 2)
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // Bullets: "- " or "• " or "* "
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    out.append(Part(kind: .bullet(level: level), text: line))
                }
                continue
            }

            out.append(Part(kind: .paragraph, text: line))
        }

        return out
    }
}


