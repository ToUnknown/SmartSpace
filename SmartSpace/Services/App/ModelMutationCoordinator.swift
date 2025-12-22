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

    // MARK: - Space deletion (manual cascade)

    static func deleteSpace(spaceId: UUID, in modelContext: ModelContext) {
        // Delete dependents first (no relationship cascade configured).
        do {
            let files = try modelContext.fetch(
                FetchDescriptor<SpaceFile>(predicate: #Predicate { $0.space.id == spaceId })
            )
            for f in files { modelContext.delete(f) }
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: deleteSpace failed to fetch SpaceFile: \(error)")
            #endif
        }

        do {
            let blocks = try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(predicate: #Predicate { $0.space.id == spaceId })
            )
            for b in blocks { modelContext.delete(b) }
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: deleteSpace failed to fetch GeneratedBlock: \(error)")
            #endif
        }

        do {
            let questions = try modelContext.fetch(
                FetchDescriptor<SpaceQuestion>(predicate: #Predicate { $0.space.id == spaceId })
            )
            for q in questions { modelContext.delete(q) }
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: deleteSpace failed to fetch SpaceQuestion: \(error)")
            #endif
        }

        do {
            if let space = try modelContext.fetch(
                FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
            ).first {
                modelContext.delete(space)
            }
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: deleteSpace failed to fetch Space: \(error)")
            #endif
        }
    }

    // MARK: - SpaceFile extraction updates

    static func updateSpaceFileExtraction(
        spaceFileId: UUID,
        extractedText: String?,
        status: ExtractionStatus,
        errorMessage: String? = nil,
        in modelContext: ModelContext
    ) {
        guard let file = fetchSpaceFile(id: spaceFileId, in: modelContext) else { return }
        file.extractedText = extractedText
        file.extractionStatus = status
        file.extractionErrorMessage = errorMessage

        // If extraction changed, invalidate any existing Apple summary so it can be regenerated.
        if status == .completed {
            file.extractionErrorMessage = nil
            file.aiSummaryText = nil
            file.aiSummaryStatus = .pending
            file.aiSummaryErrorMessage = nil
        }
    }

    // MARK: - SpaceFile summary updates (Apple Intelligence)

    static func updateSpaceFileSummary(
        spaceFileId: UUID,
        summaryText: String?,
        status: FileSummaryStatus,
        errorMessage: String?,
        in modelContext: ModelContext
    ) {
        guard let file = fetchSpaceFile(id: spaceFileId, in: modelContext) else { return }
        file.aiSummaryText = summaryText
        file.aiSummaryStatus = status
        file.aiSummaryErrorMessage = errorMessage
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

    // MARK: - Space cover image updates

    static func updateSpaceCover(
        spaceId: UUID,
        status: SpaceCoverStatus,
        prompt: String?,
        imageData: Data?,
        errorMessage: String?,
        in modelContext: ModelContext
    ) {
        guard let space = fetchSpace(id: spaceId, in: modelContext) else { return }
        space.coverStatus = status
        space.coverPrompt = prompt
        space.coverImageData = imageData
        space.coverErrorMessage = errorMessage

        // When asked to regenerate (pending), bump a token so list rows re-run their task even if
        // the status stays `.pending` due to empty context.
        if status == .pending {
            space.coverGenerationTokenRaw = UUID().uuidString
        }
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

    private static func fetchSpace(id: UUID, in modelContext: ModelContext) -> Space? {
        do {
            return try modelContext.fetch(
                FetchDescriptor<Space>(predicate: #Predicate { $0.id == id })
            ).first
        } catch {
            #if DEBUG
            print("ModelMutationCoordinator: fetchSpace failed: \(error)")
            #endif
            return nil
        }
    }
}


