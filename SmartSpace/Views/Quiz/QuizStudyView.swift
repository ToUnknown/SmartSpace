//
//  QuizStudyView.swift
//  SmartSpace
//
//  v0.15: Interactive quiz mode (local-only scoring, no persistence)
//

import SwiftUI

struct QuizStudyView: View {
    @Environment(\.dismiss) private var dismiss

    let questions: [QuizQuestion]

    @State private var index: Int = 0
    @State private var selectedIndex: Int? = nil
    @State private var correctCount: Int = 0
    @State private var isFinished: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if questions.isEmpty {
                    errorState
                } else if isFinished {
                    resultsView
                } else {
                    questionView
                }
            }
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension QuizStudyView {
    var currentQuestion: QuizQuestion? {
        guard !questions.isEmpty else { return nil }
        return questions[min(max(index, 0), questions.count - 1)]
    }

    var questionView: some View {
        guard let q = currentQuestion else { return AnyView(errorState) }

        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                Text("Question \(index + 1) of \(questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Text(q.question)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 16)

                VStack(spacing: 10) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { optionIndex, option in
                        optionRow(
                            option: option,
                            optionIndex: optionIndex,
                            correctIndex: q.correctIndex
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                if selectedIndex != nil {
                    Button {
                        goNextOrFinish()
                    } label: {
                        Text(index == questions.count - 1 ? "Finish" : "Next")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        )
    }

    func optionRow(option: String, optionIndex: Int, correctIndex: Int) -> some View {
        let locked = selectedIndex != nil
        let isSelected = selectedIndex == optionIndex
        let isCorrect = optionIndex == correctIndex

        let showFeedback = locked
        let background: Color = {
            guard showFeedback else {
                return isSelected ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.10)
            }
            if isCorrect { return Color.green.opacity(0.20) }
            if isSelected && !isCorrect { return Color.red.opacity(0.20) }
            return Color.secondary.opacity(0.08)
        }()

        let border: Color = {
            guard showFeedback else {
                return isSelected ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.18)
            }
            if isCorrect { return Color.green.opacity(0.55) }
            if isSelected && !isCorrect { return Color.red.opacity(0.55) }
            return Color.secondary.opacity(0.14)
        }()

        return Button {
            selectOption(optionIndex, correctIndex: correctIndex)
        } label: {
            HStack(spacing: 10) {
                Text(option)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showFeedback {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isSelected && !isCorrect {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(14)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(locked) // lock after selection
    }

    func selectOption(_ optionIndex: Int, correctIndex: Int) {
        guard selectedIndex == nil else { return }
        selectedIndex = optionIndex
        if optionIndex == correctIndex {
            correctCount += 1
        }
    }

    func goNextOrFinish() {
        guard selectedIndex != nil else { return }

        if index >= questions.count - 1 {
            isFinished = true
            return
        }

        index += 1
        selectedIndex = nil
    }

    var resultsView: some View {
        VStack(spacing: 10) {
            Text("Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You scored \(correctCount) / \(questions.count)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Nice work—keep going.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Button("Done") { dismiss() }
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var errorState: some View {
        VStack(spacing: 10) {
            Text("Quiz unavailable")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This Space has no valid quiz payload yet.")
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
    QuizStudyView(questions: [
        QuizQuestion(question: "What is 2 + 2?", options: ["3", "4", "5"], correctIndex: 1),
        QuizQuestion(question: "Capital of France?", options: ["Berlin", "Paris", "Rome", "Madrid"], correctIndex: 1)
    ])
}


