//
//  BlockPlaceholderView.swift
//  SmartSpace
//
//  v0.5: Placeholder block component (non-interactive)
//

import SwiftUI

struct BlockPlaceholderView: View {
    let blockType: BlockType
    var subtitle: String? = "Placeholder"

    /// Use for visual consistency between half-width and full-width blocks.
    var minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(blockType.title)
                .font(.headline)

            if let subtitle {
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


