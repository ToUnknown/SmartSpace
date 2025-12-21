//
//  BlockPlaceholderView.swift
//  SmartSpace
//
//  v0.5: Placeholder block component (non-interactive)
//

import SwiftUI

struct BlockPlaceholderView: View {
    let blockType: BlockType
    var block: GeneratedBlock? = nil
    var subtitle: String? = "Placeholder"

    /// Use for visual consistency between half-width and full-width blocks.
    var minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(blockType.title)
                    .font(.headline)

                Spacer(minLength: 0)

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            if shouldRenderSummaryText, let summaryText {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
            } else if shouldRenderFlashcardsPreview, let info = flashcardsPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(info.count) cards")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    ForEach(Array(info.preview.enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.front)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(card.back)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

private extension BlockPlaceholderView {
    var effectiveStatus: BlockStatus {
        block?.status ?? .idle
    }

    var shouldRenderSummaryText: Bool {
        blockType == .summary && effectiveStatus == .ready
    }

    var shouldRenderFlashcardsPreview: Bool {
        blockType == .flashcards && effectiveStatus == .ready
    }

    var summaryText: String? {
        guard shouldRenderSummaryText, let data = block?.payload else { return nil }
        struct SummaryPayload: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(SummaryPayload.self, from: data) else {
            return nil
        }
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var flashcardsPreview: (count: Int, preview: [(front: String, back: String)])? {
        guard shouldRenderFlashcardsPreview, let data = block?.payload else { return nil }

        struct FlashcardsPayload: Decodable {
            struct Card: Decodable {
                let front: String
                let back: String
            }
            let cards: [Card]
        }

        guard let decoded = try? JSONDecoder().decode(FlashcardsPayload.self, from: data) else {
            return nil
        }
        let pairs = decoded.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty && !$0.back.isEmpty }

        guard !pairs.isEmpty else { return nil }
        return (count: pairs.count, preview: Array(pairs.prefix(2)))
    }

    var statusLabel: String {
        effectiveStatus.displayName
    }

    var statusColor: Color {
        switch effectiveStatus {
        case .idle:
            return .secondary
        case .generating:
            return .secondary
        case .ready:
            return .secondary
        case .failed:
            return .red
        }
    }
}

private extension BlockType {
    var title: String {
        switch self {
        case .summary: return "Summary"
        case .flashcards: return "Flashcards"
        case .quiz: return "Quiz"
        case .keyTerms: return "Key Terms"
        case .mainQuestion: return "Main Question"
        case .insights: return "Insights"
        case .argumentCounterargument: return "Argument & Counterargument"
        case .contentOutline: return "Content Outline"
        }
    }
}

private extension BlockStatus {
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .generating: return "Generating"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        BlockPlaceholderView(blockType: .summary, minHeight: 120)
        HStack(spacing: 12) {
            BlockPlaceholderView(blockType: .flashcards)
            BlockPlaceholderView(blockType: .quiz)
        }
    }
    .padding()
}


