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

    func generateKeyTerms(
        context: String
    ) async throws -> [(term: String, definition: String)]

    func generateMainQuestion(context: String) async throws -> String
    func generateInsights(context: String) async throws -> String
    func generateArgumentCounterargument(context: String) async throws -> String
    func generateContentOutline(context: String) async throws -> String

    func answerQuestion(
        context: String,
        question: String
    ) async throws -> String
}


