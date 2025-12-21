//
//  SpaceDetailView.swift
//  SmartSpace
//
//  v0.5: Space detail shell + template dashboards (placeholders only)
//

import SwiftUI
import SwiftData

struct SpaceDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let space: Space
    let openAIKeyManager: OpenAIKeyManager
    var onOpenSettings: (() -> Void)? = nil

    @State private var isPresentingFileManager = false
    @State private var questionInput: String = ""

    @Query private var generatedBlocks: [GeneratedBlock]
    @Query private var questions: [SpaceQuestion]
    private let blockSeeder = BlockSeeder()
    private let orchestrator = AIGenerationOrchestrator()

    init(
        space: Space,
        openAIKeyManager: OpenAIKeyManager,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.space = space
        self.openAIKeyManager = openAIKeyManager
        self.onOpenSettings = onOpenSettings

        let spaceId = space.id
        _generatedBlocks = Query(
            filter: #Predicate<GeneratedBlock> { $0.space.id == spaceId },
            sort: []
        )

        _questions = Query(
            filter: #Predicate<SpaceQuestion> { $0.space.id == spaceId },
            sort: [SortDescriptor(\SpaceQuestion.createdAt, order: .forward)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if shouldShowOpenAIFallbackBanner {
                    fallbackBanner
                }

                Text("Using \(effective.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !questions.isEmpty {
                    questionsList
                }

                dashboard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle(space.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingFileManager = true
                } label: {
                    Image(systemName: "archivebox")
                }
            }
        }
        .sheet(isPresented: $isPresentingFileManager) {
            SpaceFileManagerView(space: space)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .task {
            // v0.8: Deterministically ensure blocks exist (create missing only).
            blockSeeder.seedBlocksIfNeeded(for: space, in: modelContext)

            // v0.9: Generate Summary if needed (idempotent; does not overwrite ready blocks).
            await orchestrator.generateSummaryIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )

            // v0.10: Generate Flashcards if needed (independent of Summary result).
            await orchestrator.generateFlashcardsIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )

            // v0.11: Generate Quiz if needed (independent lifecycle).
            await orchestrator.generateQuizIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )

            // v0.12: Generate Key Terms if needed (independent lifecycle).
            await orchestrator.generateKeyTermsIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )

            // v0.13: Answer any pending questions (idempotent).
            await orchestrator.answerPendingQuestionsIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )
        }
    }
}

private extension SpaceDetailView {
    var effective: AIProvider {
        effectiveProvider(for: space, openAIStatus: openAIKeyManager.status)
    }

    var shouldShowOpenAIFallbackBanner: Bool {
        space.aiProvider == .openAI && openAIKeyManager.status != .valid
    }

    var dashboard: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(dashboardBlocks) { item in
                BlockPlaceholderView(
                    blockType: item.blockType,
                    block: generatedBlock(for: item.blockType),
                    minHeight: item.minHeight
                )
                    .gridCellColumns(item.gridColumns)
            }
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Ask about this Space…", text: $questionInput)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.secondary.opacity(0.12), in: Capsule())

            Button {
                sendQuestion()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }

    var questionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Q&A")
                .font(.headline)

            ForEach(questions, id: \.id) { q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q.question)
                        .font(.subheadline.weight(.semibold))

                    switch q.status {
                    case .pending:
                        Text("Pending…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .answering:
                        Text("Answering…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .answered:
                        if let answer = q.answer {
                            Text(answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    case .failed:
                        let suffix = q.errorMessage.map { ": \($0)" } ?? ""
                        Text("Failed\(suffix)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    func sendQuestion() {
        let trimmed = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let q = SpaceQuestion(space: space, question: trimmed)
        modelContext.insert(q)
        questionInput = ""

        Task {
            await orchestrator.answerIfNeeded(
                question: q,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )
        }
    }

    var fallbackBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI API key is not available. This Space is temporarily using Apple Intelligence.")
                .font(.subheadline)

            if let onOpenSettings {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var dashboardBlocks: [DashboardBlock] {
        switch space.templateType {
        case .languageLearning:
            return [
                .full(.summary),
                .half(.flashcards),
                .half(.quiz),
                .full(.keyTerms)
            ]
        case .lectureDebrief:
            return [
                .full(.summary),
                .full(.mainQuestion),
                .half(.keyTerms),
                .half(.insights)
            ]
        case .testPreparation:
            return [
                .full(.summary),
                .full(.mainQuestion),
                .half(.flashcards),
                .half(.quiz)
            ]
        case .researchAnalysis:
            return [
                .full(.summary),
                .full(.argumentCounterargument),
                .full(.contentOutline)
            ]
        }
    }

    func generatedBlock(for type: BlockType) -> GeneratedBlock? {
        // Compare by rawValue for stability across SwiftData enum backing.
        generatedBlocks.first { $0.blockType.rawValue == type.rawValue }
    }
}

private struct DashboardBlock: Identifiable {
    let blockType: BlockType
    let gridColumns: Int
    let minHeight: CGFloat

    var id: String { blockType.rawValue }

    static func full(_ type: BlockType) -> Self {
        DashboardBlock(blockType: type, gridColumns: 2, minHeight: 120)
    }

    static func half(_ type: BlockType) -> Self {
        DashboardBlock(blockType: type, gridColumns: 1, minHeight: 96)
    }
}

#Preview("Language Learning (preview-only)") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, SpaceFile.self, GeneratedBlock.self, configurations: configuration)
    let context = container.mainContext

    let space = Space(name: "Spanish A1", templateType: .languageLearning, aiProvider: .openAI)
    context.insert(space)

    return NavigationStack {
        SpaceDetailView(space: space, openAIKeyManager: OpenAIKeyManager())
    }
    .modelContainer(container)
}


