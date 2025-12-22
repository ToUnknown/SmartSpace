//
//  KeyTermsDetailView.swift
//  SmartSpace
//
//  Full-screen viewer for Key Terms (read-only)
//

import SwiftUI

struct KeyTermsDetailView: View {
    @Environment(\.dismiss) private var dismiss

    struct Term: Identifiable, Equatable {
        let id = UUID()
        let term: String
        let definition: String
    }

    let terms: [Term]

    var body: some View {
        NavigationStack {
            Group {
                if terms.isEmpty {
                    emptyState
                } else {
                    List(terms) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.term)
                                .font(.headline)
                            Text(item.definition)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Key Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 10) {
            Text("Not ready yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("There are no key terms available for this Space yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    KeyTermsDetailView(terms: [
        .init(term: "Term", definition: "Definition"),
        .init(term: "Another", definition: "Another definition")
    ])
}


