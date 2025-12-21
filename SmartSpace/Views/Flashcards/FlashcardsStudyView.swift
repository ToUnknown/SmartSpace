//
//  FlashcardsStudyView.swift
//  SmartSpace
//
//  v0.14: Interactive flashcards study mode (no persistence, no scoring)
//

import SwiftUI

struct FlashcardsStudyView: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [Flashcard]

    @State private var index: Int = 0
    @State private var isShowingBack: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    errorState
                } else {
                    VStack(spacing: 16) {
                        Text("Card \(index + 1) of \(cards.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        cardView

                        HStack(spacing: 12) {
                            Button("Previous") {
                                goPrevious()
                            }
                            .disabled(index == 0)

                            Spacer(minLength: 0)

                            Button("Next") {
                                goNext()
                            }
                            .disabled(index >= cards.count - 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension FlashcardsStudyView {
    var currentCard: Flashcard? {
        guard !cards.isEmpty else { return nil }
        return cards[min(max(index, 0), cards.count - 1)]
    }

    var cardView: some View {
        let text = isShowingBack ? (currentCard?.back ?? "") : (currentCard?.front ?? "")
        let sideLabel = isShowingBack ? "Back" : "Front"

        return VStack(alignment: .leading, spacing: 10) {
            Text(sideLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingBack.toggle()
            }
        }
    }

    var errorState: some View {
        VStack(spacing: 10) {
            Text("Flashcards unavailable")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This Space has no valid flashcards payload yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func goNext() {
        guard index < cards.count - 1 else { return }
        index += 1
        isShowingBack = false
    }

    func goPrevious() {
        guard index > 0 else { return }
        index -= 1
        isShowingBack = false
    }
}

struct Flashcard: Equatable {
    let front: String
    let back: String
}

#Preview {
    FlashcardsStudyView(cards: [
        Flashcard(front: "Front 1", back: "Back 1"),
        Flashcard(front: "Front 2", back: "Back 2")
    ])
}


