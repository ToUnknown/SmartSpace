//
//  SpaceDetailView.swift
//  SmartSpace
//
//  v0.5: Space detail shell + template dashboards (placeholders only)
//

import SwiftUI
import SwiftData
import UIKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

struct SpaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let space: Space
    let openAIKeyManager: OpenAIKeyManager
    var onOpenSettings: (() -> Void)? = nil

    @State private var isPresentingFileManager = false
    @State private var isPresentingImagePlayground = false
    @State private var imagePlaygroundPrompt: String = ""
    @State private var isPresentingRegenerateAfterUploadDialog = false
    @State private var isAwaitingPostUploadChoice = false
    @State private var pendingManualBlocksRegeneration = false
    @State private var pendingManualCoverRegeneration = false
    @State private var questionInput: String = ""
    @FocusState private var isAskFieldFocused: Bool
    @State private var isRunningPipelines = false
    @State private var isOptimisticallyShimmeringBlocks = false
    @State private var fileManagerFileIdsSnapshot: Set<UUID> = []
    @State private var lastKnownFileIds: Set<UUID> = []
    @State private var shouldStartFilePicker = false
    @Namespace private var askGlassNamespace

    @Query private var generatedBlocks: [GeneratedBlock]
    @Query private var questions: [SpaceQuestion]
    @Query private var files: [SpaceFile]
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

        _files = Query(
            filter: #Predicate<SpaceFile> { $0.space.id == spaceId },
            sort: []
        )
    }

    var body: some View {
        Group {
            if files.isEmpty {
                emptySpaceState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if shouldShowOpenAIFallbackBanner {
                            fallbackBanner
                        }

                        Text("Using \(effective.displayName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        dashboard
                            // While the Q&A field is focused, prevent accidental taps on blocks.
                            // (Use hit-testing instead of `.disabled` because blocks use `onTapGesture`.)
                            .allowsHitTesting(!isAskFieldFocused)

                        // User questions should appear under the blocks.
                        if !questions.isEmpty {
                            questionsList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 24)
                }
                // Remove default top scroll-content margin so content starts flush under the nav bar.
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isAskFieldFocused = false
                    },
                    including: .gesture
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    SpaceCoverImageView(space: space, size: 22, cornerRadius: 7)
                    Text(space.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingFileManager = true
                } label: {
                    Image(systemName: "archivebox")
                }
                .accessibilityLabel("Space Files")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await regenerateAllBlocks() }
                    } label: {
                        Label("Blocks", systemImage: "text.rectangle")
                    }
                    .disabled(isRunningPipelines)

                    Button {
                        Task { await regenerateCoverImage() }
                    } label: {
                        Label("Cover image", systemImage: "photo")
                    }
                    .disabled(isCoverGenerating)

                    Divider()

                    Button {
                        // Open Image Playground with no prefilled prompt so the user can freely create a cover.
                        imagePlaygroundPrompt = ""
                        isPresentingImagePlayground = true
                    } label: {
                        Label("Custom cover", systemImage: "apple.image.playground")
                    }
                    .disabled(isCoverGenerating || !isImagePlaygroundAvailable)
                } label: {
                    if isRunningPipelines || isCoverGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "repeat.circle")
                    }
                }
                .accessibilityLabel("Regenerate")
            }
        }
        // Force inline title mode to avoid the large-title top inset when using a custom principal toolbar title.
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingFileManager) {
            SpaceFileManagerView(space: space, startWithFilePicker: shouldStartFilePicker)
        }
        .sheet(isPresented: $isPresentingImagePlayground) {
            SystemImagePlaygroundCoverPicker(
                isPresented: $isPresentingImagePlayground,
                prompt: imagePlaygroundPrompt
            ) { data in
                let trimmed = imagePlaygroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                ModelMutationCoordinator.updateSpaceCover(
                    spaceId: space.id,
                    status: .ready,
                    prompt: trimmed.isEmpty ? nil : trimmed,
                    imageData: data,
                    errorMessage: nil,
                    in: modelContext
                )
            }
        }
        .onChange(of: isPresentingFileManager) { _, newValue in
            if newValue {
                // Snapshot current file IDs when opening the file manager.
                fileManagerFileIdsSnapshot = Set(files.map(\.id))
                // Consume the one-shot request for auto-opening the picker.
                // (We only want this behavior when launched from the empty state button.)
                // Keep it true while the sheet is presented; clear on dismissal.
            } else {
                shouldStartFilePicker = false
                // When the user taps Done, if new files were added, regenerate all blocks.
                // Otherwise, just run the idempotent pipelines.
                let wasEmptyBefore = fileManagerFileIdsSnapshot.isEmpty
                let currentIds = Set(files.map(\.id))
                let added = currentIds.subtracting(fileManagerFileIdsSnapshot)
                if !added.isEmpty {
                    if wasEmptyBefore {
                        // First upload: don't ask. Just run the normal pipelines to populate the initial blocks.
                        isAwaitingPostUploadChoice = false
                        Task { await runPipelinesIfNeeded() }
                    } else {
                        // Subsequent uploads: ask the user what they want to regenerate.
                        isAwaitingPostUploadChoice = true
                        isPresentingRegenerateAfterUploadDialog = true
                    }
                } else {
                    Task { await runPipelinesIfNeeded() }
                }
            }
        }
        .alert("New files added", isPresented: $isPresentingRegenerateAfterUploadDialog) {
            Button("Regenerate Space") {
                Task {
                    isAwaitingPostUploadChoice = false
                    await regenerateAllBlocks()
                    await regenerateCoverImage()
                }
            }
            Button("Regenerate blocks") {
                Task {
                    isAwaitingPostUploadChoice = false
                    await regenerateAllBlocks()
                }
            }
            Button("Regenerate cover image") {
                Task {
                    isAwaitingPostUploadChoice = false
                    await regenerateCoverImage()
                }
            }
            Button("Cancel", role: .cancel) {
                // User explicitly opted out of regeneration.
                isAwaitingPostUploadChoice = false
            }
        } message: {
            Text("What do you want to regenerate with the new content?")
        }
        .safeAreaInset(edge: .bottom) {
            if !files.isEmpty {
                footer
            }
        }
        .onAppear {
            // Track file IDs so we can detect additions and refresh the space cover image.
            lastKnownFileIds = Set(files.map(\.id))
        }
        .onChange(of: files.map(\.id)) { _, newIdsArray in
            let current = Set(newIdsArray)
            let added = current.subtracting(lastKnownFileIds)
            if !added.isEmpty {
                // New content: reset the space cover so it can be regenerated from updated files.
                ModelMutationCoordinator.updateSpaceCover(
                    spaceId: space.id,
                    status: .pending,
                    prompt: nil,
                    imageData: nil,
                    errorMessage: nil,
                    in: modelContext
                )
            }
            lastKnownFileIds = current
        }
        .task {
            if !isAwaitingPostUploadChoice {
                await runPipelinesIfNeeded()
            }
        }
        .task(id: filesPipelineToken) {
            if !isAwaitingPostUploadChoice {
                await runPipelinesIfNeeded()
            }
        }
    }
}

private extension SpaceDetailView {
    var isImagePlaygroundAvailable: Bool {
        #if canImport(ImagePlayground)
        return ImagePlaygroundViewController.isAvailable
        #else
        return false
        #endif
    }

    var emptySpaceState: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.folder.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Add content to make this Space smarter")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Upload files to generate blocks and answers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                shouldStartFilePicker = true
                isPresentingFileManager = true
            } label: {
                Label("Add files", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add files")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var filesPipelineToken: String {
        // If extraction completes after the first appearance, re-run the pipelines.
        // Keep it small and deterministic; idempotence prevents duplicate work.
        files.map { "\($0.id.uuidString)-\($0.extractionStatus.rawValue)" }
            .joined(separator: "|")
    }

    @MainActor
    func runPipelinesIfNeeded() async {
        // Avoid overlapping runs (e.g., rapid extraction status changes).
        if isAwaitingPostUploadChoice { return }
        if isRunningPipelines { return }
        isRunningPipelines = true
        defer {
            isRunningPipelines = false
            // If a user tapped Regenerate while we were busy, run it now.
            if pendingManualBlocksRegeneration {
                pendingManualBlocksRegeneration = false
                Task { await regenerateAllBlocks() }
            } else if pendingManualCoverRegeneration {
                pendingManualCoverRegeneration = false
                Task { await regenerateCoverImage() }
            }
        }

        // v0.8: Deterministically ensure blocks exist (create missing only).
        blockSeeder.seedBlocksIfNeeded(for: space, in: modelContext)

        // v0.9+: Generate blocks if needed (idempotent; does not overwrite ready blocks).
        if effective == .openAI {
            // OpenAI: start all blocks concurrently.
            await orchestrator.generateAllBlocksConcurrentlyIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )
        } else {
            // Apple Intelligence: summarize each file first, then generate blocks from summaries.
            await orchestrator.summarizeAppleFilesIfNeeded(for: space, in: modelContext)

            // Apple Intelligence: generate one-by-one (sequential).
            for type in TemplateBlockMap.blockTypes(for: space.templateType) {
                switch type {
                case .summary:
                    await orchestrator.generateSummaryIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .flashcards:
                    await orchestrator.generateFlashcardsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .quiz:
                    await orchestrator.generateQuizIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .keyTerms:
                    await orchestrator.generateKeyTermsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .mainQuestion:
                    await orchestrator.generateMainQuestionIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .insights:
                    await orchestrator.generateInsightsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .argumentCounterargument:
                    await orchestrator.generateArgumentCounterargumentIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .contentOutline:
                    await orchestrator.generateContentOutlineIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                }
            }
        }

        // v0.13: Answer any pending questions (idempotent).
        await orchestrator.answerPendingQuestionsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
    }

    var isCoverGenerating: Bool {
        space.coverStatus == .generatingPrompt || space.coverStatus == .generatingImage
    }

    @MainActor
    func regenerateCoverImage() async {
        if isCoverGenerating { return }
        if isRunningPipelines {
            pendingManualCoverRegeneration = true
            return
        }
        ModelMutationCoordinator.updateSpaceCover(
            spaceId: space.id,
            status: .pending,
            prompt: nil,
            imageData: nil,
            errorMessage: nil,
            in: modelContext
        )
        await orchestrator.generateSpaceCoverIfNeeded(
            for: space,
            openAIStatus: openAIKeyManager.status,
            in: modelContext
        )
    }

    @MainActor
    func regenerateAllBlocks() async {
        if isRunningPipelines {
            // Queue the action; avoid "nothing happens" when the auto pipeline is running.
            pendingManualBlocksRegeneration = true
            isOptimisticallyShimmeringBlocks = true
            return
        }

        // Reset all blocks to idle, then run generation again.
        isRunningPipelines = true
        isOptimisticallyShimmeringBlocks = true
        defer {
            isRunningPipelines = false
            isOptimisticallyShimmeringBlocks = false
        }

        orchestrator.resetAllBlocks(for: space, in: modelContext)
        // Re-run the standard pipeline (idempotent).
        blockSeeder.seedBlocksIfNeeded(for: space, in: modelContext)

        if effective == .openAI {
            await orchestrator.generateAllBlocksConcurrentlyIfNeeded(
                for: space,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )
        } else {
            await orchestrator.summarizeAppleFilesIfNeeded(for: space, in: modelContext)
            for type in TemplateBlockMap.blockTypes(for: space.templateType) {
                switch type {
                case .summary:
                    await orchestrator.generateSummaryIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .flashcards:
                    await orchestrator.generateFlashcardsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .quiz:
                    await orchestrator.generateQuizIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .keyTerms:
                    await orchestrator.generateKeyTermsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .mainQuestion:
                    await orchestrator.generateMainQuestionIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .insights:
                    await orchestrator.generateInsightsIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .argumentCounterargument:
                    await orchestrator.generateArgumentCounterargumentIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                case .contentOutline:
                    await orchestrator.generateContentOutlineIfNeeded(for: space, openAIStatus: openAIKeyManager.status, in: modelContext)
                }
            }
        }
    }

    var effective: AIProvider {
        effectiveProvider(for: space, openAIStatus: openAIKeyManager.status)
    }

    var shouldShowOpenAIFallbackBanner: Bool {
        // Only show the banner when OpenAI is unavailable, not while validating.
        if space.aiProvider != .openAI { return false }
        switch openAIKeyManager.status {
        case .notSet, .invalid:
            return true
        case .checking, .valid:
            return false
        }
    }

    var dashboard: some View {
        Group {
            if visibleDashboardBlocks.isEmpty {
                VStack(spacing: 8) {
                    if isRunningPipelines || isOptimisticallyShimmeringBlocks {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRunningPipelines || isOptimisticallyShimmeringBlocks ? "Generating blocks…" : "No blocks yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !isRunningPipelines, !isOptimisticallyShimmeringBlocks {
                        Text("Tap Regenerate to create blocks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleDashboardBlocks) { item in
                        BlockPlaceholderView(
                            blockType: item.blockType,
                            block: generatedBlock(for: item.blockType),
                            // Only force shimmer for an explicit user action (Regenerate).
                            // Otherwise, show shimmer only when the block's persisted status is actually `.generating`.
                            forceGeneratingSkeleton: isOptimisticallyShimmeringBlocks,
                            minHeight: item.minHeight
                        )
                    }
                }
            }
        }
    }

    var footer: some View {
        // Use a slightly larger container spacing than the inner HStack spacing so glass shapes
        // can blend and "flow" into each other during transitions.
        let trimmedQuestion = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldShowSend = isAskFieldFocused || !trimmedQuestion.isEmpty
        let inactiveForeground: AnyShapeStyle = colorScheme == .dark
            ? AnyShapeStyle(Color.white)
            : AnyShapeStyle(.primary)
        let inactivePlaceholder: AnyShapeStyle = colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.9))
            : AnyShapeStyle(.primary)

        return GlassEffectContainer(spacing: 18) {
            HStack(spacing: 16) {
                // Search-like field (native TextField + icon + clear)
                HStack(spacing: 8) {
                    providerAskIcon
                        // Keep the icon high-contrast even when focused (no "active gray").
                        .foregroundStyle(inactiveForeground)

                    TextField(
                        "",
                        text: $questionInput,
                        prompt: Text("Ask about this Space…")
                            .foregroundStyle(
                                isAskFieldFocused
                                ? AnyShapeStyle(.secondary)
                                : inactivePlaceholder
                            )
                    )
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .focused($isAskFieldFocused)
                    .foregroundStyle(
                        isAskFieldFocused
                        ? AnyShapeStyle(.primary)
                        : inactiveForeground
                    )
                    .submitLabel(.send)
                    .onSubmit { sendQuestion() }
                    .accessibilityLabel("Ask about this Space")

                    if isAskFieldFocused, !questionInput.isEmpty {
                        Button {
                            questionInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear question")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                // Make the whole pill tappable (not just the TextField’s text rect),
                // and ensure this wins vs the ScrollView's tap-to-dismiss gesture.
                .contentShape(Capsule())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        isAskFieldFocused = true
                    }
                )
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("askField", in: askGlassNamespace)

                // Send appears only when the field is active and morphs in with the native glass transition.
                if shouldShowSend {
                    Button {
                        sendQuestion()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(
                                isAskFieldFocused
                                ? AnyShapeStyle(.primary)
                                : inactiveForeground
                            )
                    }
                    .contentShape(Circle())
                    .disabled(trimmedQuestion.isEmpty)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send question")
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID("send", in: askGlassNamespace)
                    .glassEffectTransition(.matchedGeometry)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 4)
        // Keep the input capsule as Liquid Glass; avoid an extra bar background behind it.
        .animation(.bouncy, value: shouldShowSend)
    }

    @ViewBuilder
    var providerAskIcon: some View {
        switch effective {
        case .appleIntelligence:
            Image(systemName: "apple.intelligence")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        case .openAI:
            // Use template rendering so the logo automatically adapts (white in dark mode, black in light mode).
            // Also guard against missing assets to prevent runtime crashes when entering a Space.
            if let uiImage = UIImage(named: "openai_logo") {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "sparkle.magnifyingglass")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
    }

    var questionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Q&A")
                .font(.headline)

            ForEach(questions, id: \.id) { q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(q.question)
                            .font(.subheadline.weight(.semibold))

                        Spacer(minLength: 0)

                        Button(role: .destructive) {
                            deleteQuestion(q)
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete question")
                    }

                    switch q.status {
                    case .pending:
                        qaGeneratingSkeleton
                    case .answering:
                        qaGeneratingSkeleton
                    case .answered:
                        if let answer = q.answer {
                            FormattedMarkdownTextView(text: answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    case .failed:
                        Text("Couldn’t answer right now.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteQuestion(q)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        deleteQuestion(q)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    var qaGeneratingSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShimmerBar(height: 10, widthFactor: 0.9)
            ShimmerBar(height: 10, widthFactor: 0.75)
            ShimmerBar(height: 10, widthFactor: 0.6)
        }
        .accessibilityLabel("Answering")
    }

    func deleteQuestion(_ q: SpaceQuestion) {
        ModelMutationCoordinator.delete(q, in: modelContext)
    }

    func sendQuestion() {
        let trimmed = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let q = SpaceQuestion(space: space, question: trimmed)
        ModelMutationCoordinator.insert(q, in: modelContext)
        questionInput = ""
        isAskFieldFocused = false

        Task {
            await orchestrator.answerIfNeeded(
                question: q,
                openAIStatus: openAIKeyManager.status,
                in: modelContext
            )
        }
    }

    var noContentYetBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No content yet")
                .font(.headline)

            Text("Add files or paste text in Space Files to generate learning blocks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var dashboardBlocks: [DashboardBlock] {
        let types = TemplateBlockMap.blockTypes(for: space.templateType)

        return types.map { type in
            // List-style: every block is full width.
            return DashboardBlock(
                blockType: type,
                gridColumns: 1,
                minHeight: type == .summary ? 120 : 96
            )
        }
    }

    /// Only show blocks when they are actually generating/ready (or optimistically shimmering after an explicit regenerate).
    var visibleDashboardBlocks: [DashboardBlock] {
        dashboardBlocks.filter { item in
            guard let block = generatedBlock(for: item.blockType) else { return false }
            switch block.status {
            case .generating, .ready:
                return true
            case .idle:
                // User-initiated regenerate: show the skeleton immediately even before persisted status flips.
                return isOptimisticallyShimmeringBlocks
            case .failed:
                return false
            }
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

    // Legacy helpers left intentionally unused (layout is now single-column).
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


