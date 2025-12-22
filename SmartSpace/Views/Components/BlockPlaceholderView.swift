//
//  BlockPlaceholderView.swift
//  SmartSpace
//
//  v0.5: Placeholder block component (non-interactive)
//

import SwiftUI
import UIKit

struct BlockPlaceholderView: View {
    let blockType: BlockType
    var block: GeneratedBlock? = nil
    var subtitle: String? = nil
    var forceGeneratingSkeleton: Bool = false

    /// Use for visual consistency between half-width and full-width blocks.
    var minHeight: CGFloat = 96

    @State private var isPresentingDetail = false
    @State private var isSummaryExpanded = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(blockType.title)
                    .font(.headline)

                Spacer(minLength: 0)

                if isInteractive {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            if shouldRenderTextBlock, let textBlockText {
                if blockType == .summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(textBlockText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(isSummaryExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            // Smooth unfold/fold animation for the block height.
                            .animation(.linear(duration: 0.28), value: isSummaryExpanded)

                        if shouldShowSummaryExpand(textBlockText) {
                            Button(isSummaryExpanded ? "Less" : "More") {
                                withAnimation(.linear(duration: 0.28)) {
                                    isSummaryExpanded.toggle()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(isSummaryExpanded ? "Collapse summary" : "Expand summary")
                        }
                    }
                } else if blockType == .insights || blockType == .contentOutline {
                    FormattedTextBlockView(
                        blockType: blockType,
                        text: textBlockText,
                        maxItems: 4
                    )
                } else {
                    Text(textBlockText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(6)
                }
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
            } else if shouldRenderQuizPreview, let info = quizPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(info.count) questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(info.first.question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    ForEach(Array(info.first.options.prefix(5).enumerated()), id: \.offset) { _, option in
                        Text(option)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if shouldRenderKeyTermsPreview, let info = keyTermsPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(info.count) terms")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    ForEach(Array(info.preview.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.term)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(item.definition)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else if effectiveStatus == .generating || (forceGeneratingSkeleton && effectiveStatus == .idle) {
                skeleton
            } else {
                Text(fallbackSubtitle)
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
        .animation(.easeInOut(duration: 0.15), value: effectiveStatus)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(accessibilityHint)

        if isInteractive {
            content
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isPresentingDetail = true
                }
                .fullScreenCover(isPresented: $isPresentingDetail) {
                    detailView
                }
        } else {
            content
        }
    }
}

private extension BlockPlaceholderView {
    func shouldShowSummaryExpand(_ text: String) -> Bool {
        // If it fits within the collapsed display, don’t show an affordance.
        // Heuristic: show expand when the summary is longer than the tile can reasonably display.
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: true).count
        return lineCount > 3 || text.count > 140
    }
}

private extension BlockPlaceholderView {
    @ViewBuilder
    var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            // First line (headline-ish)
            ShimmerBar(height: 12, widthFactor: 0.55)

            switch blockType {
            case .summary:
                ShimmerBar(height: 12, widthFactor: 0.9)
                ShimmerBar(height: 12, widthFactor: 0.7)
            case .flashcards, .quiz, .keyTerms:
                ShimmerBar(height: 10, widthFactor: 0.35)
                ShimmerBar(height: 10, widthFactor: 0.8)
                ShimmerBar(height: 10, widthFactor: 0.6)
            default:
                ShimmerBar(height: 10, widthFactor: 0.9)
                ShimmerBar(height: 10, widthFactor: 0.75)
                ShimmerBar(height: 10, widthFactor: 0.6)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

private extension BlockPlaceholderView {
    var effectiveStatus: BlockStatus {
        block?.status ?? .idle
    }

    var displayStatus: BlockStatus {
        if forceGeneratingSkeleton, effectiveStatus == .idle { return .generating }
        return effectiveStatus
    }

    var fallbackSubtitle: String {
        if let subtitle { return subtitle }
        switch displayStatus {
        case .idle:
            return "Not ready yet"
        case .generating:
            return "Working…"
        case .ready:
            return "Ready"
        case .failed:
            return "Not ready yet"
        }
    }

    var shouldRenderTextBlock: Bool {
        switch blockType {
        case .summary, .mainQuestion, .insights, .argumentCounterargument, .contentOutline:
            return effectiveStatus == .ready
        default:
            return false
        }
    }

    var shouldRenderFlashcardsPreview: Bool {
        blockType == .flashcards && effectiveStatus == .ready
    }

    var shouldRenderQuizPreview: Bool {
        blockType == .quiz && effectiveStatus == .ready
    }

    var shouldRenderKeyTermsPreview: Bool {
        blockType == .keyTerms && effectiveStatus == .ready
    }

    var isInteractive: Bool {
        // Summary is intentionally not tappable.
        if blockType == .summary { return false }

        switch blockType {
        case .flashcards:
            return effectiveStatus == .ready && flashcardsDeck != nil
        case .quiz:
            return effectiveStatus == .ready && quizDeck != nil
        case .keyTerms:
            return effectiveStatus == .ready && keyTermsDeck != nil
        case .mainQuestion, .insights, .argumentCounterargument, .contentOutline:
            return effectiveStatus == .ready && textBlockText != nil
        default:
            return false
        }
    }

    var textBlockText: String? {
        guard shouldRenderTextBlock, let data = block?.payload else { return nil }
        struct TextPayload: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(TextPayload.self, from: data) else {
            return nil
        }
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = stripLeadingTitleIfPresent(trimmed)
        return cleaned.isEmpty ? nil : cleaned
    }

    func stripLeadingTitleIfPresent(_ text: String) -> String {
        let normalizedTitle = blockType.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty else { return text }

        // If the first line repeats the block title (e.g. "Insights"), drop it.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return text }
        let firstLine = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard firstLine == normalizedTitle else { return text }

        let remaining = lines.dropFirst().joined(separator: "\n")
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var flashcardsDeck: [Flashcard]? {
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

        let cards = decoded.cards
            .map { Flashcard(front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                             back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty && !$0.back.isEmpty }

        return cards.isEmpty ? nil : cards
    }

    var quizPreview: (count: Int, first: QuizQuestion)? {
        guard shouldRenderQuizPreview, let data = block?.payload else { return nil }

        struct QuizPayload: Decodable {
            let questions: [QuizQuestion]
        }
        guard let decoded = try? JSONDecoder().decode(QuizPayload.self, from: data) else {
            return nil
        }
        guard let first = decoded.questions.first else { return nil }
        return (count: decoded.questions.count, first: first)
    }

    var quizDeck: [QuizQuestion]? {
        guard shouldRenderQuizPreview, let data = block?.payload else { return nil }

        struct QuizPayload: Decodable {
            let questions: [QuizQuestion]
        }
        guard let decoded = try? JSONDecoder().decode(QuizPayload.self, from: data) else {
            return nil
        }
        let cleaned = decoded.questions.filter { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }

    var keyTermsPreview: (count: Int, preview: [(term: String, definition: String)])? {
        guard shouldRenderKeyTermsPreview, let data = block?.payload else { return nil }

        struct KeyTermsPayload: Decodable {
            struct Term: Decodable {
                let term: String
                let definition: String
            }
            let terms: [Term]
        }

        guard let decoded = try? JSONDecoder().decode(KeyTermsPayload.self, from: data) else {
            return nil
        }

        let pairs = decoded.terms.map { item in
            (
                term: item.term.trimmingCharacters(in: .whitespacesAndNewlines),
                definition: item.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { !$0.term.isEmpty && !$0.definition.isEmpty }

        guard !pairs.isEmpty else { return nil }
        return (count: pairs.count, preview: Array(pairs.prefix(5)))
    }

    var keyTermsDeck: [KeyTermsDetailView.Term]? {
        guard shouldRenderKeyTermsPreview, let data = block?.payload else { return nil }

        struct KeyTermsPayload: Decodable {
            struct Term: Decodable {
                let term: String
                let definition: String
            }
            let terms: [Term]
        }

        guard let decoded = try? JSONDecoder().decode(KeyTermsPayload.self, from: data) else {
            return nil
        }

        let terms = decoded.terms.map { item in
            KeyTermsDetailView.Term(
                term: item.term.trimmingCharacters(in: .whitespacesAndNewlines),
                definition: item.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { !$0.term.isEmpty && !$0.definition.isEmpty }

        return terms.isEmpty ? nil : terms
    }

    var statusLabel: String {
        displayStatus.displayName
    }

    var statusColor: Color {
        switch displayStatus {
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

    var accessibilityTitle: String {
        "\(blockType.title), \(statusLabel)"
    }

    var accessibilityHint: String {
        if isInteractive { return "Double-tap to open." }
        if effectiveStatus == .generating {
            return "This block is being generated."
        }
        return ""
    }

    @ViewBuilder
    var detailView: some View {
        switch blockType {
        case .flashcards:
            FlashcardsStudyView(cards: flashcardsDeck ?? [])
        case .quiz:
            QuizStudyView(questions: quizDeck ?? [])
        case .keyTerms:
            KeyTermsDetailView(terms: keyTermsDeck ?? [])
        case .mainQuestion, .insights, .argumentCounterargument, .contentOutline:
            TextBlockDetailView(blockType: blockType, text: textBlockText ?? "")
        default:
            TextBlockDetailView(blockType: blockType, text: textBlockText ?? "")
        }
    }
}

private extension BlockStatus {
    var displayName: String {
        switch self {
        case .idle: return "Not ready"
        case .generating: return "Working…"
        case .ready: return "Ready"
        case .failed: return "Not ready"
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


