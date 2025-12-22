//
//  TextBlockDetailView.swift
//  SmartSpace
//
//  Full-screen viewer for text-based blocks (Main Question, Insights, etc.)
//

import SwiftUI

struct TextBlockDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let blockType: BlockType
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                FormattedTextBlockView(blockType: blockType, text: text)
                    .padding(16)
            }
            .navigationTitle(blockType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TextBlockDetailView(blockType: .insights, text: "- One\n- Two\n- Three")
}


