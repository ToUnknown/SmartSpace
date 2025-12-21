//
//  AppleIntelligenceService.swift
//  SmartSpace
//
//  v0.9: Apple Intelligence summary generation
//  NOTE: Safe stub implementation (no unstable APIs yet).
//

import Foundation

struct AppleIntelligenceService: AIService {
    func generateSummary(context: String) async throws -> String {
        // TODO v0.9: Replace stub with real Apple Intelligence API call when stable/available.
        // Keep deterministic behavior in the stub.
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }

        let max = 480
        if trimmed.count <= max {
            return "Summary (stub): \(trimmed)"
        }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: max)
        return "Summary (stub): \(trimmed[..<cutoff])…"
    }

    func generateFlashcards(context: String) async throws -> [(front: String, back: String)] {
        // TODO v0.10: Replace stub with real Apple Intelligence API call when stable/available.
        // Deterministic sample flashcards.
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return [
            (front: "Key idea (stub)?", back: "This is a placeholder flashcard generated locally."),
            (front: "What is SmartSpace (stub)?", back: "A study space that collects content and prepares structured outputs.")
        ]
    }

    func generateQuiz(context: String) async throws -> [QuizQuestion] {
        // TODO v0.11: Replace stub with real Apple Intelligence API call when stable/available.
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return [
            QuizQuestion(
                question: "What is the primary purpose of SmartSpace (stub)?",
                options: ["Cooking", "Studying", "Travel", "Shopping"],
                correctIndex: 1
            ),
            QuizQuestion(
                question: "Which type of content can SmartSpace collect (stub)?",
                options: ["Only PDFs", "Only text", "Files and pasted text", "Only images"],
                correctIndex: 2
            )
        ]
    }

    func generateKeyTerms(context: String) async throws -> [(term: String, definition: String)] {
        // TODO v0.12: Replace stub with real Apple Intelligence API call when stable/available.
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return [
            (term: "SmartSpace", definition: "An app that collects learning content and generates structured study outputs."),
            (term: "Space", definition: "A container for content and generated blocks tied to a specific learning template.")
        ]
    }

    func answerQuestion(context: String, question: String) async throws -> String {
        // TODO v0.13: Replace stub with real Apple Intelligence API call when stable/available.
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return "" }
        return "(Stub) Answer based on the Space content: \(trimmedQuestion)"
    }
}


