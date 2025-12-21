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

    @MainActor
    func generateSummaryIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let summaryBlock = fetchSummaryBlock(for: space, in: modelContext) else { return }
        guard summaryBlock.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        let blockId = summaryBlock.id
        ModelMutationCoordinator.updateGeneratedBlock(
            generatedBlockId: blockId,
            status: .generating,
            payload: summaryBlock.payload,
            errorMessage: nil,
            touchUpdatedAt: true,
            in: modelContext
        )

        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do {
                switch provider {
                case .appleIntelligence:
                    let text = try await AppleIntelligenceService().generateSummary(context: context)
                    return .success(text)
                case .openAI:
                    let text = try await OpenAIService().generateSummary(context: context)
                    return .success(text)
                }
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let summaryText):
            do {
                let payload = SummaryPayload(text: summaryText)
                let data = try JSONEncoder().encode(payload)
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .ready,
                    payload: data,
                    errorMessage: nil,
                    touchUpdatedAt: true,
                    in: modelContext
                )
            } catch {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .failed,
                    payload: nil,
                    errorMessage: "Couldn’t save summary.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
        case .failure(let error):
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: blockId,
                status: .failed,
                payload: nil,
                errorMessage: error.localizedDescription,
                touchUpdatedAt: true,
                in: modelContext
            )
        }
    }

    @MainActor
    func generateFlashcardsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let block = fetchBlock(for: space, blockType: .flashcards, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        let blockId = block.id
        ModelMutationCoordinator.updateGeneratedBlock(
            generatedBlockId: blockId,
            status: .generating,
            payload: block.payload,
            errorMessage: nil,
            touchUpdatedAt: true,
            in: modelContext
        )

        let result: Result<[(front: String, back: String)], Error> = await Task.detached(priority: .userInitiated) {
            do {
                switch provider {
                case .appleIntelligence:
                    let cards = try await AppleIntelligenceService().generateFlashcards(context: context)
                    return .success(cards)
                case .openAI:
                    let cards = try await OpenAIService().generateFlashcards(context: context)
                    return .success(cards)
                }
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let cards):
            do {
                let payload = FlashcardsPayload(
                    cards: cards.map { FlashcardsPayload.Card(front: $0.front, back: $0.back) }
                )
                let data = try JSONEncoder().encode(payload)
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .ready,
                    payload: data,
                    errorMessage: nil,
                    touchUpdatedAt: true,
                    in: modelContext
                )
            } catch {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .failed,
                    payload: nil,
                    errorMessage: "Couldn’t save flashcards.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
        case .failure(let error):
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: blockId,
                status: .failed,
                payload: nil,
                errorMessage: error.localizedDescription,
                touchUpdatedAt: true,
                in: modelContext
            )
        }
    }

    @MainActor
    func generateQuizIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let block = fetchBlock(for: space, blockType: .quiz, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        let blockId = block.id
        ModelMutationCoordinator.updateGeneratedBlock(
            generatedBlockId: blockId,
            status: .generating,
            payload: block.payload,
            errorMessage: nil,
            touchUpdatedAt: true,
            in: modelContext
        )

        let result: Result<[QuizQuestion], Error> = await Task.detached(priority: .userInitiated) {
            do {
                switch provider {
                case .appleIntelligence:
                    let questions = try await AppleIntelligenceService().generateQuiz(context: context)
                    return .success(questions)
                case .openAI:
                    let questions = try await OpenAIService().generateQuiz(context: context)
                    return .success(questions)
                }
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let questions):
            do {
                let payload = QuizPayload(questions: questions)
                let data = try JSONEncoder().encode(payload)
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .ready,
                    payload: data,
                    errorMessage: nil,
                    touchUpdatedAt: true,
                    in: modelContext
                )
            } catch {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .failed,
                    payload: nil,
                    errorMessage: "Couldn’t save quiz.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
        case .failure(let error):
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: blockId,
                status: .failed,
                payload: nil,
                errorMessage: error.localizedDescription,
                touchUpdatedAt: true,
                in: modelContext
            )
        }
    }

    @MainActor
    func generateKeyTermsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let block = fetchBlock(for: space, blockType: .keyTerms, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else { return }

        let blockId = block.id
        ModelMutationCoordinator.updateGeneratedBlock(
            generatedBlockId: blockId,
            status: .generating,
            payload: block.payload,
            errorMessage: nil,
            touchUpdatedAt: true,
            in: modelContext
        )

        let result: Result<[(term: String, definition: String)], Error> = await Task.detached(priority: .userInitiated) {
            do {
                switch provider {
                case .appleIntelligence:
                    let terms = try await AppleIntelligenceService().generateKeyTerms(context: context)
                    return .success(terms)
                case .openAI:
                    let terms = try await OpenAIService().generateKeyTerms(context: context)
                    return .success(terms)
                }
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let terms):
            do {
                let payload = KeyTermsPayload(
                    terms: terms.map { KeyTermsPayload.Term(term: $0.term, definition: $0.definition) }
                )
                let data = try JSONEncoder().encode(payload)
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .ready,
                    payload: data,
                    errorMessage: nil,
                    touchUpdatedAt: true,
                    in: modelContext
                )
            } catch {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .failed,
                    payload: nil,
                    errorMessage: "Couldn’t save key terms.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
        case .failure(let error):
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: blockId,
                status: .failed,
                payload: nil,
                errorMessage: error.localizedDescription,
                touchUpdatedAt: true,
                in: modelContext
            )
        }
    }

    // MARK: - Q&A (v0.13)

    @MainActor
    func answerIfNeeded(
        question: SpaceQuestion,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let qId = question.id
        // Do not re-answer.
        if question.status == .answered { return }
        if question.status == .failed { return }

        // If we crashed mid-flight, allow continuing.
        if question.status == .answering, question.answer != nil {
            ModelMutationCoordinator.updateSpaceQuestion(
                spaceQuestionId: qId,
                status: .answered,
                answer: question.answer,
                errorMessage: nil,
                in: modelContext
            )
            return
        }

        guard question.status == .pending || question.status == .answering else { return }

        let trimmedQ = question.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQ.isEmpty else {
            ModelMutationCoordinator.updateSpaceQuestion(
                spaceQuestionId: qId,
                status: .failed,
                answer: nil,
                errorMessage: "Question is empty.",
                in: modelContext
            )
            return
        }

        // Build context from Space files (and keep it deterministic).
        let space = question.space
        let context = contextBuilder.buildContext(for: space, in: modelContext)
        guard !context.isEmpty else {
            ModelMutationCoordinator.updateSpaceQuestion(
                spaceQuestionId: qId,
                status: .failed,
                answer: nil,
                errorMessage: "No extracted content available for this Space yet.",
                in: modelContext
            )
            return
        }

        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        ModelMutationCoordinator.updateSpaceQuestion(
            spaceQuestionId: qId,
            status: .answering,
            answer: nil,
            errorMessage: nil,
            in: modelContext
        )

        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do {
                switch provider {
                case .appleIntelligence:
                    let answer = try await AppleIntelligenceService().answerQuestion(context: context, question: trimmedQ)
                    return .success(answer)
                case .openAI:
                    let answer = try await OpenAIService().answerQuestion(context: context, question: trimmedQ)
                    return .success(answer)
                }
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let answer):
            let trimmedA = answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedA.isEmpty else {
                ModelMutationCoordinator.updateSpaceQuestion(
                    spaceQuestionId: qId,
                    status: .failed,
                    answer: nil,
                    errorMessage: "Answer was empty.",
                    in: modelContext
                )
                return
            }

            ModelMutationCoordinator.updateSpaceQuestion(
                spaceQuestionId: qId,
                status: .answered,
                answer: trimmedA,
                errorMessage: nil,
                in: modelContext
            )
        case .failure(let error):
            ModelMutationCoordinator.updateSpaceQuestion(
                spaceQuestionId: qId,
                status: .failed,
                answer: nil,
                errorMessage: error.localizedDescription,
                in: modelContext
            )
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


