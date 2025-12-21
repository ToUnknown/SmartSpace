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

    @Query private var generatedBlocks: [GeneratedBlock]
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
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.secondary)

                Text("Ask about this Space")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.secondary.opacity(0.12), in: Capsule())

            Button {
                // TODO v0.5: search behavior
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(.secondary.opacity(0.12), in: Circle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
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


