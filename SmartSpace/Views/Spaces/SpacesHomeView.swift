//
//  SpacesHomeView.swift
//  SmartSpace
//
//  v2.0 scaffolding (v0.1): placeholder view (non-functional)
//

import SwiftUI
import SwiftData

struct SpacesHomeView: View {
    let openAIKeyManager: OpenAIKeyManager
    var onOpenSettings: (() -> Void)? = nil

    @Query(
        filter: #Predicate<Space> { $0.isArchived == false },
        sort: [SortDescriptor(\Space.createdAt, order: .reverse)]
    )
    private var spaces: [Space]

    var body: some View {
        Group {
            if spaces.isEmpty {
                emptyState
            } else {
                List(spaces, id: \.id) { space in
                    NavigationLink {
                        SpaceDetailView(
                            space: space,
                            openAIKeyManager: openAIKeyManager,
                            onOpenSettings: onOpenSettings
                        )
                    } label: {
                        SpaceRow(space: space)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private extension SpacesHomeView {
    var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Spaces yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Create your first Space to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct SpaceRow: View {
    let space: Space

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.title3)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.headline)

                Text(space.templateType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private extension TemplateType {
    var displayName: String {
        switch self {
        case .languageLearning: return "Language Learning"
        case .lectureDebrief: return "Lecture Debrief"
        case .testPreparation: return "Test Preparation"
        case .researchAnalysis: return "Research Analysis"
        }
    }
}

#Preview("Empty") {
    SpacesHomeView(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(for: Space.self, inMemory: true)
}

#Preview("Sample (Preview-only)") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, configurations: configuration)

    let context = container.mainContext
    context.insert(Space(name: "Spanish A1", templateType: .languageLearning))
    context.insert(Space(name: "Bio 101 Debrief", templateType: .lectureDebrief))

    return SpacesHomeView(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(container)
}


