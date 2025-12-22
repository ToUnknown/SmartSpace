import SwiftUI

/// Renders certain text blocks (like Insights / Content Outline) with lightweight formatting.
/// This is presentation-only; it doesn't change any generated payloads.
struct FormattedTextBlockView: View {
    let blockType: BlockType
    let text: String
    var maxItems: Int? = nil

    var body: some View {
        switch blockType {
        case .insights:
            bulletList(items: parseBullets(text), maxItems: maxItems)
        case .contentOutline:
            outlineList(items: parseOutline(text), maxItems: maxItems)
        default:
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension FormattedTextBlockView {
    struct OutlineItem: Identifiable {
        let id = UUID()
        let level: Int
        let text: String
    }

    func normalizeLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
    }

    func parseBullets(_ text: String) -> [String] {
        normalizeLines(text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                var s = line
                if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                if s.hasPrefix("• ") { s = String(s.dropFirst(2)) }
                if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    func parseOutline(_ text: String) -> [OutlineItem] {
        normalizeLines(text).compactMap { raw in
            // Level from leading whitespace (2 spaces = one level).
            let leadingSpaces = raw.prefix { $0 == " " }.count
            let level = max(0, leadingSpaces / 2)
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }

            // Strip common bullets / numbering.
            if line.hasPrefix("- ") { line = String(line.dropFirst(2)) }
            if line.hasPrefix("• ") { line = String(line.dropFirst(2)) }
            if line.hasPrefix("* ") { line = String(line.dropFirst(2)) }

            // "1. Foo" or "1) Foo"
            if let first = line.first, first.isNumber {
                if let dot = line.firstIndex(of: "."), dot < line.index(line.startIndex, offsetBy: min(3, line.count)) {
                    line = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let paren = line.firstIndex(of: ")"), paren < line.index(line.startIndex, offsetBy: min(3, line.count)) {
                    line = String(line[line.index(after: paren)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard !line.isEmpty else { return nil }
            return OutlineItem(level: min(level, 4), text: line)
        }
    }

    @ViewBuilder
    func bulletList(items: [String], maxItems: Int?) -> some View {
        let shown = maxItems.map { Array(items.prefix($0)) } ?? items
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func outlineList(items: [OutlineItem], maxItems: Int?) -> some View {
        let shown = maxItems.map { Array(items.prefix($0)) } ?? items
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shown) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.level == 0 ? "•" : "◦")
                        .foregroundStyle(.secondary)
                    Text(item.text)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .padding(.leading, CGFloat(item.level) * 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


