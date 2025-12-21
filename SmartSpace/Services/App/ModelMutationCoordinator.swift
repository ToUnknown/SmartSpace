//
//  ModelMutationCoordinator.swift
//  SmartSpace
//
//  v0.17: Centralize SwiftData writes on the MainActor (Swift 6 safety)
//

import Foundation
import SwiftData

@MainActor
enum ModelMutationCoordinator {
    // MARK: - Generic writes

    static func insert<T: PersistentModel>(_ model: T, in modelContext: ModelContext) {
        modelContext.insert(model)
    }

    static func delete<T: PersistentModel>(_ model: T, in modelContext: ModelContext) {
        modelContext.delete(model)
    }

    // MARK: - SpaceFile extraction updates

    static func updateSpaceFileExtraction(
        spaceFileId: UUID,
        extractedText: String?,
        status: ExtractionStatus,
        in modelContext: ModelContext
    ) {
        guard let file = fetchSpaceFile(id: spaceFileId, in: modelContext) else { return }
        file.extractedText = extractedText
        file.extractionStatus = status
    }

    // MARK: - GeneratedBlock updates

    static func updateGeneratedBlock(
        generatedBlockId: UUID,
        status: BlockStatus,
        payload: Data?,
        errorMessage: String?,
        touchUpdatedAt: Bool = true,
        in modelContext: ModelContext
    ) {
        guard let block = fetchGeneratedBlock(id: generatedBlockId, in: modelContext) else { return }
        block.status = status
        block.payload = payload
        block.errorMessage = errorMessage
        if touchUpdatedAt {
            block.updatedAt = .now
        }
    }

    // MARK: - SpaceQuestion updates

    static func updateSpaceQuestion(
        spaceQuestionId: UUID,
        status: QuestionStatus,
        answer: String?,
        errorMessage: String?,
        in modelContext: ModelContext
    ) {
        guard let q = fetchSpaceQuestion(id: spaceQuestionId, in: modelContext) else { return }
        q.status = status
        q.answer = answer
        q.errorMessage = errorMessage
    }

    // MARK: - Fetch helpers (MainActor only)

    private static func fetchSpaceFile(id: UUID, in modelContext: ModelContext) -> SpaceFile? {
        do {
            return try modelContext.fetch(
                FetchDescriptor<SpaceFile>(predicate: #Predicate { $0.id == id })
            ).first
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: fetchSpaceFile failed: \(error)")
            #endif
            return nil
        }
    }

    private static func fetchGeneratedBlock(id: UUID, in modelContext: ModelContext) -> GeneratedBlock? {
        do {
            return try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(predicate: #Predicate { $0.id == id })
            ).first
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: fetchGeneratedBlock failed: \(error)")
            #endif
            return nil
        }
    }

    private static func fetchSpaceQuestion(id: UUID, in modelContext: ModelContext) -> SpaceQuestion? {
        do {
            return try modelContext.fetch(
                FetchDescriptor<SpaceQuestion>(predicate: #Predicate { $0.id == id })
            ).first
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: fetchSpaceQuestion failed: \(error)")
            #endif
            return nil
        }
    }
}


