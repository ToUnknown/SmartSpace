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

    @Environment(\.modelContext) private var modelContext

    private enum SortMode: String {
        case newestFirst
        case alphabetical
    }

    @State private var sortMode: SortMode = .newestFirst

    @Query(
        filter: #Predicate<Space> { $0.isArchived == false },
        sort: [SortDescriptor(\Space.createdAt, order: .reverse)]
    )
    private var spaces: [Space]

    private var sortedSpaces: [Space] {
        switch sortMode {
        case .newestFirst:
            return spaces.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .alphabetical:
            return spaces.sorted { lhs, rhs in
                let c = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if c != .orderedSame { return c == .orderedAscending }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    var body: some View {
        Group {
            if spaces.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sortedSpaces, id: \.id) { space in
                        NavigationLink {
                            SpaceDetailView(
                                space: space,
                                openAIKeyManager: openAIKeyManager,
                                onOpenSettings: onOpenSettings
                            )
                        } label: {
                            SpaceRow(space: space, openAIStatus: openAIKeyManager.status)
                        }
                    }
                    .onDelete(perform: deleteSpaces)
                }
                .listStyle(.plain)
                // Remove default top scroll-content margin so the list starts flush at the top.
                .contentMargins(.top, 0, for: .scrollContent)
                .animation(.easeInOut(duration: 0.2), value: sortMode)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sortMode = (sortMode == .newestFirst) ? .alphabetical : .newestFirst
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel(sortMode == .newestFirst ? "Sort alphabetically" : "Sort by newest")
            }
        }
    }
}

private extension SpacesHomeView {
    func deleteSpaces(at offsets: IndexSet) {
        // Map offsets from the currently displayed order.
        let ids = offsets.compactMap { index in
            sortedSpaces.indices.contains(index) ? sortedSpaces[index].id : nil
        }
        for id in ids {
            ModelMutationCoordinator.deleteSpace(spaceId: id, in: modelContext)
        }
    }

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
    let openAIStatus: OpenAIKeyManager.KeyStatus

    var body: some View {
        HStack(spacing: 12) {
            SpaceCoverImageView(
                space: space,
                size: 44,
                cornerRadius: 12,
                showsBackground: false,
                showsBorder: false
            )

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

#Preview("Empty") {
    SpacesHomeView(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(for: Space.self, inMemory: true)
}

#Preview("Sample (Preview-only)") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, configurations: configuration)

    let context = container.mainContext
    context.insert(Space(name: "Spanish A1", templateType: .languageLearning))
    context.insert(Space(name: "Bio 101 Notes", templateType: .lectureNotes))

    return SpacesHomeView(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(container)
}


