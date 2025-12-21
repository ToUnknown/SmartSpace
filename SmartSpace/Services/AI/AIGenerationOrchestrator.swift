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


