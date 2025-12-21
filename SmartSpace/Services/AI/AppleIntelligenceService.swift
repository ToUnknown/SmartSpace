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
}


