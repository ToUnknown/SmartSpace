//
//  BlockSeeder.swift
//  SmartSpace
//
//  v0.8: Deterministic seeding of GeneratedBlock records (no AI)
//

import Foundation
import SwiftData

struct BlockSeeder {
    @MainActor
    func seedBlocksIfNeeded(for space: Space, in modelContext: ModelContext) {
        let required = requiredBlockTypes(for: space.templateType)

        // Fetch blocks for this space, then filter in-memory (enum comparisons in SwiftData predicates
        // can be finicky; this keeps seeding reliable and deterministic).
        let spaceId = space.id
        let existing: [GeneratedBlock]
        do {
            existing = try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(
                    predicate: #Predicate { $0.space.id == spaceId }
                )
            )
        } catch {
            #if DEBUG
            print("BlockSeeder: fetch failed: \(error)")
            #endif
            return
        }

        let existingTypes = Set(existing.map { $0.blockType.rawValue })
        for type in required {
            if existingTypes.contains(type.rawValue) { continue }
            modelContext.insert(GeneratedBlock(space: space, blockType: type))
        }
    }

    func requiredBlockTypes(for template: TemplateType) -> [BlockType] {
        switch template {
        case .languageLearning:
            return [.summary, .flashcards, .quiz, .keyTerms]
        case .lectureDebrief:
            return [.summary, .mainQuestion, .keyTerms, .insights]
        case .testPreparation:
            return [.summary, .mainQuestion, .flashcards, .quiz]
        case .researchAnalysis:
            return [.summary, .argumentCounterargument, .contentOutline]
        }
    }
}


