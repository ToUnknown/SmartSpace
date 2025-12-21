//
//  AIGenerationOrchestrator.swift
//  SmartSpace
//
//  v0.9: Orchestrate deterministic generation (Summary only)
//

import Foundation
import SwiftData

struct AIGenerationOrchestrator {
    struct SummaryPayload: Codable {
        let text: String
    }

    struct FlashcardsPayload: Codable {
        struct Card: Codable {
            let front: String
            let back: String
        }
        let cards: [Card]
    }

    struct QuizPayload: Codable {
        let questions: [QuizQuestion]
    }

    struct KeyTermsPayload: Codable {
        struct Term: Codable {
            let term: String
            let definition: String
        }
        let terms: [Term]
    }

    var contextBuilder = SpaceContextBuilder()
    var appleService: AIService = AppleIntelligenceService()
    var openAIService: AIService = OpenAIService()

    @MainActor
    func generateSummaryIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        // Find the Summary block for this space
        guard let summaryBlock = fetchSummaryBlock(for: space, in: modelContext) else { return }

        // Never generate twice; never overwrite.
        guard summaryBlock.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        summaryBlock.status = .generating
        summaryBlock.errorMessage = nil

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        do {
            let summaryText: String
            switch provider {
            case .appleIntelligence:
                summaryText = try await appleService.generateSummary(context: context)
            case .openAI:
                summaryText = try await openAIService.generateSummary(context: context)
            }

            let payload = SummaryPayload(text: summaryText)
            summaryBlock.payload = try JSONEncoder().encode(payload)
            summaryBlock.status = .ready
            summaryBlock.updatedAt = .now
            summaryBlock.errorMessage = nil
        } catch {
            summaryBlock.status = .failed
            summaryBlock.updatedAt = .now
            summaryBlock.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func generateFlashcardsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        guard let block = fetchBlock(for: space, blockType: .flashcards, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        block.status = .generating
        block.errorMessage = nil

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        do {
            let cards: [(front: String, back: String)]
            switch provider {
            case .appleIntelligence:
                cards = try await appleService.generateFlashcards(context: context)
            case .openAI:
                cards = try await openAIService.generateFlashcards(context: context)
            }

            let payload = FlashcardsPayload(
                cards: cards.map { FlashcardsPayload.Card(front: $0.front, back: $0.back) }
            )
            block.payload = try JSONEncoder().encode(payload)
            block.status = .ready
            block.updatedAt = .now
            block.errorMessage = nil
        } catch {
            block.status = .failed
            block.updatedAt = .now
            block.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func generateQuizIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        guard let block = fetchBlock(for: space, blockType: .quiz, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        block.status = .generating
        block.errorMessage = nil

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        do {
            let questions: [QuizQuestion]
            switch provider {
            case .appleIntelligence:
                questions = try await appleService.generateQuiz(context: context)
            case .openAI:
                questions = try await openAIService.generateQuiz(context: context)
            }

            let payload = QuizPayload(questions: questions)
            block.payload = try JSONEncoder().encode(payload)
            block.status = .ready
            block.updatedAt = .now
            block.errorMessage = nil
        } catch {
            block.status = .failed
            block.updatedAt = .now
            block.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func generateKeyTermsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        guard let block = fetchBlock(for: space, blockType: .keyTerms, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        block.status = .generating
        block.errorMessage = nil

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        do {
            let terms: [(term: String, definition: String)]
            switch provider {
            case .appleIntelligence:
                terms = try await appleService.generateKeyTerms(context: context)
            case .openAI:
                terms = try await openAIService.generateKeyTerms(context: context)
            }

            let payload = KeyTermsPayload(
                terms: terms.map { KeyTermsPayload.Term(term: $0.term, definition: $0.definition) }
            )
            block.payload = try JSONEncoder().encode(payload)
            block.status = .ready
            block.updatedAt = .now
            block.errorMessage = nil
        } catch {
            block.status = .failed
            block.updatedAt = .now
            block.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Q&A (v0.13)

    @MainActor
    func answerIfNeeded(
        question: SpaceQuestion,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        // Do not re-answer.
        if question.status == .answered { return }
        if question.status == .failed { return }

        // If we crashed mid-flight, allow continuing.
        if question.status == .answering, question.answer != nil {
            question.status = .answered
            return
        }

        guard question.status == .pending || question.status == .answering else { return }

        let trimmedQ = question.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQ.isEmpty else {
            question.status = .failed
            question.errorMessage = "Question is empty."
            return
        }

        // Build context from Space files (and keep it deterministic).
        let space = question.space
        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else {
            question.status = .failed
            question.errorMessage = "No extracted content available for this Space yet."
            return
        }

        question.status = .answering
        question.errorMessage = nil

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        do {
            let answer: String
            switch provider {
            case .appleIntelligence:
                answer = try await appleService.answerQuestion(context: context, question: trimmedQ)
            case .openAI:
                answer = try await openAIService.answerQuestion(context: context, question: trimmedQ)
            }

            let trimmedA = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedA.isEmpty else {
                question.status = .failed
                question.errorMessage = "Answer was empty."
                return
            }

            question.answer = trimmedA
            question.status = .answered
            question.errorMessage = nil
        } catch {
            question.status = .failed
            question.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func answerPendingQuestionsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let spaceId = space.id
        let all: [SpaceQuestion]
        do {
            all = try modelContext.fetch(
                FetchDescriptor<SpaceQuestion>(
                    predicate: #Predicate { $0.space.id == spaceId },
                    sortBy: [SortDescriptor(\SpaceQuestion.createdAt, order: .forward)]
                )
            )
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: failed to fetch SpaceQuestion: \(error)")
            #endif
            return
        }

        for q in all {
            if q.status == .pending || (q.status == .answering && q.answer == nil) {
                await answerIfNeeded(question: q, openAIStatus: openAIStatus, in: modelContext)
            }
        }
    }

    @MainActor
    private func fetchSummaryBlock(for space: Space, in modelContext: ModelContext) -> GeneratedBlock? {
        fetchBlock(for: space, blockType: .summary, in: modelContext)
    }

    @MainActor
    private func fetchBlock(for space: Space, blockType: BlockType, in modelContext: ModelContext) -> GeneratedBlock? {
        let spaceId = space.id
        do {
            let blocks = try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(
                    predicate: #Predicate { $0.space.id == spaceId }
                )
            )
            // Compare by rawValue to avoid enum predicate quirks.
            return blocks.first { $0.blockType.rawValue == blockType.rawValue }
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: fetchBlock failed: \(error)")
            #endif
            return nil
        }
    }
}


