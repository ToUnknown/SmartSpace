//
//  AIGenerationOrchestrator.swift
//  SmartSpace
//
//  v0.9: Orchestrate deterministic generation (Summary only)
//

import Foundation
import SwiftData
#if canImport(ImagePlayground)
import ImagePlayground
#endif

struct AIGenerationOrchestrator {
    struct SummaryPayload: Codable {
        let text: String
    }

    struct TextPayload: Codable {
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

    // MARK: - Apple Intelligence file summarization

    /// For Apple Intelligence spaces, summarize each extracted file and persist the summary on `SpaceFile`.
    /// This makes downstream block generation deterministic and ensures the model "sees" all files.
    @MainActor
    func summarizeAppleFilesIfNeeded(for space: Space, in modelContext: ModelContext) async {
        let spaceId = space.id
        let files: [SpaceFile]
        do {
            files = try modelContext.fetch(
                FetchDescriptor<SpaceFile>(
                    predicate: #Predicate { $0.space.id == spaceId },
                    sortBy: [SortDescriptor(\SpaceFile.createdAt, order: .forward)]
                )
            )
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: summarizeAppleFilesIfNeeded fetch failed: \(error)")
            #endif
            return
        }

        for file in files {
            guard file.extractionStatus == .completed else { continue }
            if file.aiSummaryStatus == .ready, file.aiSummaryText != nil { continue }
            if file.aiSummaryStatus == .summarizing { continue }

            let fileId = file.id
            let name = file.displayName
            let extracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !extracted.isEmpty else { continue }

            ModelMutationCoordinator.updateSpaceFileSummary(
                spaceFileId: fileId,
                summaryText: file.aiSummaryText,
                status: .summarizing,
                errorMessage: nil,
                in: modelContext
            )

            let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let summary = try await AppleIntelligenceService().summarizeFileForBlocks(fileName: name, text: extracted)
                    return .success(summary)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let summary):
                let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    ModelMutationCoordinator.updateSpaceFileSummary(
                        spaceFileId: fileId,
                        summaryText: nil,
                        status: .failed,
                        errorMessage: "Summary was empty.",
                        in: modelContext
                    )
                } else {
                    ModelMutationCoordinator.updateSpaceFileSummary(
                        spaceFileId: fileId,
                        summaryText: cleaned,
                        status: .ready,
                        errorMessage: nil,
                        in: modelContext
                    )
                }
            case .failure(let error):
                #if DEBUG
                print("AIGenerationOrchestrator: file summary failed (\(name)): \(error)")
                #endif
                ModelMutationCoordinator.updateSpaceFileSummary(
                    spaceFileId: fileId,
                    summaryText: nil,
                    status: .failed,
                    errorMessage: error.localizedDescription,
                    in: modelContext
                )
            }
        }
    }

    @MainActor
    private func buildContextForProvider(
        _ provider: AIProvider,
        space: Space,
        in modelContext: ModelContext
    ) async -> String {
        switch provider {
        case .appleIntelligence:
            // Apple Intelligence uses per-file summaries only (generated and persisted first),
            // plus the Space Summary block (if already generated).
            let spaceId = space.id
            let files: [SpaceFile]
            do {
                files = try modelContext.fetch(
                    FetchDescriptor<SpaceFile>(
                        predicate: #Predicate { $0.space.id == spaceId },
                        sortBy: [SortDescriptor(\SpaceFile.createdAt, order: .forward)]
                    )
                )
            } catch {
                #if DEBUG
                print("AIGenerationOrchestrator: buildContextForProvider(.appleIntelligence) fetch failed: \(error)")
                #endif
                return ""
            }

            // If Summary block is already available, prepend it as a compact “global” guide.
            let spaceSummaryText: String? = {
                guard let summaryBlock = fetchSummaryBlock(for: space, in: modelContext),
                      summaryBlock.status == .ready,
                      let data = summaryBlock.payload
                else { return nil }
                if let decoded = try? JSONDecoder().decode(SummaryPayload.self, from: data) {
                    let t = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
                return nil
            }()

            let summaries: [(name: String, text: String)] = files.compactMap { f in
                guard f.extractionStatus == .completed else { return nil }
                guard f.aiSummaryStatus == .ready else { return nil }
                let s = f.aiSummaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !s.isEmpty else { return nil }
                // Include the file name as a lightweight header, but avoid "FILE:".
                let combined = "Document: \(f.displayName)\n\n\(s)"
                return (name: f.displayName, text: combined)
            }

            let (filesContext, _) = contextBuilder.buildContext(
                from: summaries,
                mode: .full,
                maxCharacters: Int.max,
                includeFileHeaders: false
            )
            if let spaceSummaryText {
                let combined = "Space summary:\n\(spaceSummaryText)\n\n\(filesContext)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return combined
            } else {
                return filesContext
            }

        case .openAI:
            let cap = 200_000
            let files = contextBuilder.fetchCompletedFiles(for: space, in: modelContext)
            let (fullContext, didTruncate) = contextBuilder.buildContext(
                from: files,
                mode: .full,
                maxCharacters: cap,
                includeFileHeaders: true
            )
            guard didTruncate else { return fullContext }

            // Context is too large: summarize each file using Apple Intelligence on-device Foundation Models,
            // then use the summaries as the OpenAI context.
            let summaries: [(name: String, text: String)] = await Task.detached(priority: .userInitiated) {
                let summarizer = AppleIntelligenceService()
                var out: [(name: String, text: String)] = []
                out.reserveCapacity(files.count)
                for item in files {
                    do {
                        let summary = try await summarizer.summarizeForContext(item.text)
                        let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        out.append((name: item.name, text: cleaned.isEmpty ? String(item.text.prefix(2_000)) : cleaned))
                    } catch {
                        out.append((name: item.name, text: String(item.text.prefix(2_000))))
                    }
                }
                return out
            }.value

            let (summaryContext, _) = contextBuilder.buildContext(
                from: summaries,
                mode: .full,
                maxCharacters: cap,
                includeFileHeaders: true
            )
            return summaryContext.isEmpty ? fullContext : summaryContext
        }
    }

    @MainActor
    func generateSummaryIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let summaryBlock = fetchSummaryBlock(for: space, in: modelContext) else { return }
        guard summaryBlock.status == .idle else { return }

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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
            #if DEBUG
            print("AIGenerationOrchestrator: summary generation failed: \(error)")
            #endif
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

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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
            #if DEBUG
            print("AIGenerationOrchestrator: flashcards generation failed: \(error)")
            #endif
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

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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
            #if DEBUG
            print("AIGenerationOrchestrator: quiz generation failed: \(error)")
            #endif
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

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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
            #if DEBUG
            print("AIGenerationOrchestrator: key terms generation failed: \(error)")
            #endif
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
    func generateMainQuestionIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        await generateTextBlockIfNeeded(
            for: space,
            blockType: .mainQuestion,
            openAIStatus: openAIStatus,
            in: modelContext
        )
    }

    @MainActor
    func generateInsightsIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        await generateTextBlockIfNeeded(
            for: space,
            blockType: .insights,
            openAIStatus: openAIStatus,
            in: modelContext
        )
    }

    @MainActor
    func generateArgumentCounterargumentIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        await generateTextBlockIfNeeded(
            for: space,
            blockType: .argumentCounterargument,
            openAIStatus: openAIStatus,
            in: modelContext
        )
    }

    @MainActor
    func generateContentOutlineIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        await generateTextBlockIfNeeded(
            for: space,
            blockType: .contentOutline,
            openAIStatus: openAIStatus,
            in: modelContext
        )
    }

    @MainActor
    private func generateTextBlockIfNeeded(
        for space: Space,
        blockType: BlockType,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard let block = fetchBlock(for: space, blockType: blockType, in: modelContext) else { return }
        guard block.status == .idle else { return }

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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

        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let text: String
                switch (provider, blockType) {
                case (.appleIntelligence, .mainQuestion):
                    text = try await AppleIntelligenceService().generateMainQuestion(context: context)
                case (.openAI, .mainQuestion):
                    text = try await OpenAIService().generateMainQuestion(context: context)

                case (.appleIntelligence, .insights):
                    text = try await AppleIntelligenceService().generateInsights(context: context)
                case (.openAI, .insights):
                    text = try await OpenAIService().generateInsights(context: context)

                case (.appleIntelligence, .argumentCounterargument):
                    text = try await AppleIntelligenceService().generateArgumentCounterargument(context: context)
                case (.openAI, .argumentCounterargument):
                    text = try await OpenAIService().generateArgumentCounterargument(context: context)

                case (.appleIntelligence, .contentOutline):
                    text = try await AppleIntelligenceService().generateContentOutline(context: context)
                case (.openAI, .contentOutline):
                    text = try await OpenAIService().generateContentOutline(context: context)

                default:
                    return .failure(NSError(domain: "SmartSpace", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported block type."]))
                }
                return .success(text)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: blockId,
                    status: .failed,
                    payload: nil,
                    errorMessage: "Empty result.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
                return
            }

            do {
                let payload = TextPayload(text: trimmed)
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
                    errorMessage: "Couldn’t save result.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
        case .failure(let error):
            #if DEBUG
            print("AIGenerationOrchestrator: \(blockType.rawValue) generation failed: \(error)")
            #endif
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
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        let context = await buildContextForProvider(provider, space: space, in: modelContext)
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
            #if DEBUG
            print("AIGenerationOrchestrator: Q&A failed: \(error)")
            #endif
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

    // MARK: - Space cover image (Apple Intelligence + Image Playground)

    @MainActor
    func generateSpaceCoverIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let spaceId = space.id
        let spaceName = space.name
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)

        // Avoid duplicate work.
        switch space.coverStatus {
        case .generatingPrompt, .generatingImage, .ready, .none:
            return
        case .pending, .failed:
            break
        }

        // Build a compact context from extracted text / summaries.
        let context = buildCoverContext(spaceId: spaceId, in: modelContext)
        if context.isEmpty {
            // No extracted content yet; keep pending.
            return
        }

        ModelMutationCoordinator.updateSpaceCover(
            spaceId: spaceId,
            status: .generatingPrompt,
            prompt: nil,
            imageData: nil,
            errorMessage: nil,
            in: modelContext
        )

        let promptResult: Result<String?, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let prompt: String?
                switch provider {
                case .appleIntelligence:
                    prompt = try await AppleIntelligenceService()
                        .suggestSpaceCoverPrompt(spaceName: spaceName, context: context)
                case .openAI:
                    // User request: even in GPT Spaces, generate the cover prompt on-device.
                    // (Image generation is on-device via Image Playground; prompt selection should match.)
                    prompt = try await AppleIntelligenceService()
                        .suggestSpaceCoverPrompt(spaceName: spaceName, context: context)
                }
                return .success(prompt)
            } catch {
                return .failure(error)
            }
        }.value

        switch promptResult {
        case .success(let prompt):
            // If the model returns NONE/empty, don't give up — generate a safe fallback prompt.
            let finalPrompt: String = {
                let trimmed = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                return fallbackCoverPrompt(spaceName: spaceName, context: context)
            }()

            ModelMutationCoordinator.updateSpaceCover(
                spaceId: spaceId,
                status: .generatingImage,
                prompt: finalPrompt,
                imageData: nil,
                errorMessage: nil,
                in: modelContext
            )

            // IMPORTANT: Image Playground creation must happen while the app is in the foreground.
            // Running this in a detached task can trigger `backgroundCreationForbidden`.
            let imageResult: Result<Data, Error>
            do {
                let data = try await AppleIntelligenceService().generateCoverImagePNG(prompt: finalPrompt)
                imageResult = .success(data)
            } catch {
                imageResult = .failure(error)
            }

            switch imageResult {
            case .success(let data):
                ModelMutationCoordinator.updateSpaceCover(
                    spaceId: spaceId,
                    status: .ready,
                    prompt: finalPrompt,
                    imageData: data,
                    errorMessage: nil,
                    in: modelContext
                )
            case .failure(let error):
                #if DEBUG
                print("AIGenerationOrchestrator: cover image generation failed: \(error)")
                #endif
                #if canImport(ImagePlayground)
                if let e = error as? ImageCreator.Error {
                    switch e {
                    case .notSupported, .unavailable:
                        // Clean fallback to the default logo.
                        ModelMutationCoordinator.updateSpaceCover(
                            spaceId: spaceId,
                            status: .none,
                            prompt: finalPrompt,
                            imageData: nil,
                            errorMessage: nil,
                            in: modelContext
                        )
                    case .unsupportedLanguage:
                        ModelMutationCoordinator.updateSpaceCover(
                            spaceId: spaceId,
                            status: .failed,
                            prompt: finalPrompt,
                            imageData: nil,
                            errorMessage: "Image generation isn’t available for the current device language.",
                            in: modelContext
                        )
                    case .backgroundCreationForbidden:
                        ModelMutationCoordinator.updateSpaceCover(
                            spaceId: spaceId,
                            status: .failed,
                            prompt: finalPrompt,
                            imageData: nil,
                            errorMessage: "Open SmartSpace in the foreground to generate the cover image.",
                            in: modelContext
                        )
                    default:
                        ModelMutationCoordinator.updateSpaceCover(
                            spaceId: spaceId,
                            status: .failed,
                            prompt: finalPrompt,
                            imageData: nil,
                            errorMessage: "Couldn’t generate a cover image.",
                            in: modelContext
                        )
                    }
                } else {
                    ModelMutationCoordinator.updateSpaceCover(
                        spaceId: spaceId,
                        status: .failed,
                        prompt: finalPrompt,
                        imageData: nil,
                        errorMessage: "Couldn’t generate a cover image.",
                        in: modelContext
                    )
                }
                #else
                ModelMutationCoordinator.updateSpaceCover(
                    spaceId: spaceId,
                    status: .none,
                    prompt: finalPrompt,
                    imageData: nil,
                    errorMessage: nil,
                    in: modelContext
                )
                #endif
            }

        case .failure(let error):
            #if DEBUG
            print("AIGenerationOrchestrator: cover prompt failed: \(error)")
            #endif
            ModelMutationCoordinator.updateSpaceCover(
                spaceId: spaceId,
                status: .failed,
                prompt: nil,
                imageData: nil,
                errorMessage: "Couldn’t generate a cover image.",
                in: modelContext
            )
        }
    }

    /// Deterministic fallback prompt to avoid "NONE => give up".
    /// Keeps prompts icon-like, simple, and generally relevant to the content/name.
    @MainActor
    private func fallbackCoverPrompt(spaceName: String, context: String) -> String {
        let haystack = (spaceName + "\n" + context).lowercased()

        func hasAny(_ terms: [String]) -> Bool { terms.contains { haystack.contains($0) } }

        let subject: String = {
            if hasAny(["cat", "kitten", "feline"]) { return "orange cat" }
            if hasAny(["dog", "puppy", "canine"]) { return "dog paw print" }
            if hasAny(["space", "rocket", "planet", "saturn", "astronomy"]) { return "rocket" }
            if hasAny(["biology", "cell", "dna", "genetics"]) { return "microscope" }
            if hasAny(["chemistry", "molecule", "reaction", "lab"]) { return "lab flask" }
            if hasAny(["math", "algebra", "calculus", "equation"]) { return "calculator" }
            if hasAny(["music", "guitar", "piano", "melody"]) { return "musical note" }
            if hasAny(["history", "ancient", "empire", "war"]) { return "ancient scroll" }
            if hasAny(["language", "vocabulary", "grammar", "spanish", "english", "french"]) { return "speech bubble" }
            if hasAny(["finance", "money", "budget", "invest"]) { return "coin" }
            if hasAny(["programming", "code", "swift", "python", "javascript"]) { return "laptop" }
            if hasAny(["ai", "machine learning", "neural"]) { return "robot head" }
            return "book"
        }()

        // <= 18 words, one-line, icon-like.
        return "\(subject), centered, clean background, high contrast, no text"
    }

    @MainActor
    private func buildCoverContext(spaceId: UUID, in modelContext: ModelContext) -> String {
        let files: [SpaceFile]
        do {
            files = try modelContext.fetch(
                FetchDescriptor<SpaceFile>(predicate: #Predicate { $0.space.id == spaceId })
            )
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: buildCoverContext failed to fetch files: \(error)")
            #endif
            return ""
        }

        // Prefer Apple file summaries when present; otherwise use extracted text.
        let parts: [(String, String)] = files.compactMap { f in
            let name = f.displayName
            if let s = f.aiSummaryText, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (name, s)
            }
            if let t = f.extractedText, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (name, t)
            }
            return nil
        }

        guard !parts.isEmpty else { return "" }

        var out = ""
        out.reserveCapacity(8_000)

        let perFileCap = 2_000
        let totalCap = 12_000

        for (name, text) in parts {
            if out.count >= totalCap { break }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let clipped = String(trimmed.prefix(perFileCap))
            out += "Document: \(name)\n\(clipped)\n\n"
        }

        return String(out.prefix(totalCap)).trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Regeneration (manual)

    /// Resets all generated blocks for a Space back to `.idle` and clears payload/errors.
    /// Intended for a user-initiated "Regenerate" action. Does not seed missing blocks.
    @MainActor
    func resetAllBlocks(for space: Space, in modelContext: ModelContext) {
        let spaceId = space.id
        let blocks: [GeneratedBlock]
        do {
            blocks = try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(
                    predicate: #Predicate { $0.space.id == spaceId }
                )
            )
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: resetAllBlocks fetch failed: \(error)")
            #endif
            return
        }

        for block in blocks {
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: block.id,
                status: .idle,
                payload: nil,
                errorMessage: nil,
                touchUpdatedAt: true,
                in: modelContext
            )
        }
    }

    // MARK: - Concurrent generation (OpenAI only)

    /// Kicks off generation for all `.idle` blocks for the Space concurrently **when the effective provider is OpenAI**.
    /// - Note: Uses a single context build and a single block fetch for performance. All SwiftData writes remain on MainActor.
    @MainActor
    func generateAllBlocksConcurrentlyIfNeeded(
        for space: Space,
        openAIStatus: OpenAIKeyManager.KeyStatus,
        in modelContext: ModelContext
    ) async {
        let provider = effectiveProvider(for: space, openAIStatus: openAIStatus)
        guard provider == .openAI else { return }

        let spaceId = space.id
        var blocks: [GeneratedBlock]
        do {
            blocks = try modelContext.fetch(
                FetchDescriptor<GeneratedBlock>(
                    predicate: #Predicate { $0.space.id == spaceId }
                )
            )
        } catch {
            #if DEBUG
            print("AIGenerationOrchestrator: concurrent fetch failed: \(error)")
            #endif
            // Fallback: fetch and filter in-memory for robustness.
            let fetched = (try? modelContext.fetch(FetchDescriptor<GeneratedBlock>())) ?? []
            blocks = fetched.filter { $0.space.id == spaceId }
        }

        // Preserve generation trigger order based on the template map.
        let orderedTypes = TemplateBlockMap.blockTypes(for: space.templateType)
        let byTypeRaw = Dictionary(uniqueKeysWithValues: blocks.map { ($0.blockType.rawValue, $0) })

        let idleBlocks: [GeneratedBlock] = orderedTypes.compactMap { type in
            guard let block = byTypeRaw[type.rawValue] else { return nil }
            return block.status == .idle ? block : nil
        }
        guard !idleBlocks.isEmpty else { return }

        let context = await buildContextForProvider(provider, space: space, in: modelContext)
        guard !context.isEmpty else {
            // Surface a calm failure if there is no extracted content context yet.
            for block in idleBlocks {
                ModelMutationCoordinator.updateGeneratedBlock(
                    generatedBlockId: block.id,
                    status: .failed,
                    payload: nil,
                    errorMessage: "No extracted content available yet.",
                    touchUpdatedAt: true,
                    in: modelContext
                )
            }
            return
        }

        // Mark all as generating up-front.
        for block in idleBlocks {
            ModelMutationCoordinator.updateGeneratedBlock(
                generatedBlockId: block.id,
                status: .generating,
                payload: block.payload,
                errorMessage: nil,
                touchUpdatedAt: true,
                in: modelContext
            )
        }

        struct TaskResult: Sendable {
            let blockId: UUID
            let result: Result<Data, Error>
        }

        await withTaskGroup(of: TaskResult.self) { group in
            for block in idleBlocks {
                let blockId = block.id
                let raw = block.blockType.rawValue
                let ctx = context
                group.addTask {
                    do {
                        let service = OpenAIService()
                        let data: Data

                        // Local payload types (avoid MainActor-isolated nested types under default isolation).
                        struct SummaryPayload: Encodable { let text: String }
                        struct TextPayload: Encodable { let text: String }
                        struct FlashcardsPayload: Encodable {
                            struct Card: Encodable { let front: String; let back: String }
                            let cards: [Card]
                        }
                        struct KeyTermsPayload: Encodable {
                            struct Term: Encodable { let term: String; let definition: String }
                            let terms: [Term]
                        }
                        struct QuizPayload: Encodable { let questions: [QuizQuestion] }

                        switch raw {
                        case BlockType.summary.rawValue:
                            let text = try await service.generateSummary(context: ctx)
                            data = try JSONEncoder().encode(SummaryPayload(text: text))
                        case BlockType.flashcards.rawValue:
                            let cards = try await service.generateFlashcards(context: ctx)
                            let payload = FlashcardsPayload(cards: cards.map { .init(front: $0.front, back: $0.back) })
                            data = try JSONEncoder().encode(payload)
                        case BlockType.quiz.rawValue:
                            let questions = try await service.generateQuiz(context: ctx)
                            data = try JSONEncoder().encode(QuizPayload(questions: questions))
                        case BlockType.keyTerms.rawValue:
                            let terms = try await service.generateKeyTerms(context: ctx)
                            let payload = KeyTermsPayload(terms: terms.map { .init(term: $0.term, definition: $0.definition) })
                            data = try JSONEncoder().encode(payload)
                        case BlockType.mainQuestion.rawValue:
                            let text = try await service.generateMainQuestion(context: ctx)
                            data = try JSONEncoder().encode(TextPayload(text: text))
                        case BlockType.insights.rawValue:
                            let text = try await service.generateInsights(context: ctx)
                            data = try JSONEncoder().encode(TextPayload(text: text))
                        case BlockType.argumentCounterargument.rawValue:
                            let text = try await service.generateArgumentCounterargument(context: ctx)
                            data = try JSONEncoder().encode(TextPayload(text: text))
                        case BlockType.contentOutline.rawValue:
                            let text = try await service.generateContentOutline(context: ctx)
                            data = try JSONEncoder().encode(TextPayload(text: text))
                        default:
                            throw NSError(
                                domain: "SmartSpace",
                                code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "Unsupported block type: \(raw)"]
                            )
                        }

                        return TaskResult(blockId: blockId, result: .success(data))
                    } catch {
                        return TaskResult(blockId: blockId, result: .failure(error))
                    }
                }
            }

            for await item in group {
                switch item.result {
                case .success(let data):
                    ModelMutationCoordinator.updateGeneratedBlock(
                        generatedBlockId: item.blockId,
                        status: .ready,
                        payload: data,
                        errorMessage: nil,
                        touchUpdatedAt: true,
                        in: modelContext
                    )
                case .failure(let error):
                    #if DEBUG
                    print("AIGenerationOrchestrator: concurrent block generation failed: \(error)")
                    #endif
                    ModelMutationCoordinator.updateGeneratedBlock(
                        generatedBlockId: item.blockId,
                        status: .failed,
                        payload: nil,
                        errorMessage: error.localizedDescription,
                        touchUpdatedAt: true,
                        in: modelContext
                    )
                }
            }
        }
    }
}


