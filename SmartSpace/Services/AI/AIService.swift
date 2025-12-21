//
//  AIService.swift
//  SmartSpace
//
//  v0.9: Provider-agnostic AI abstraction
//

import Foundation

protocol AIService {
    func generateSummary(context: String) async throws -> String

    func generateFlashcards(
        context: String
    ) async throws -> [(front: String, back: String)]

    func generateQuiz(
        context: String
    ) async throws -> [QuizQuestion]
}


