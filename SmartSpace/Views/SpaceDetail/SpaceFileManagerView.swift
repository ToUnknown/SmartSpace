//
//  SpaceFileManagerView.swift
//  SmartSpace
//
//  v0.6: Space content collection UI (import & paste) — persistence only
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SpaceFileManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let space: Space

    @State private var isPresentingFileImporter = false
    @State private var isPresentingPasteText = false

    @Query private var files: [SpaceFile]
    private let extractionService = TextExtractionService()

    init(space: Space) {
        self.space = space
        let spaceId = space.id
        _files = Query(
            filter: #Predicate<SpaceFile> { $0.space.id == spaceId },
            sort: [SortDescriptor(\SpaceFile.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(files, id: \.id) { file in
                            row(file)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Space Files")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add File") {
                            isPresentingFileImporter = true
                        }
                        Button("Paste Text") {
                            isPresentingPasteText = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            // Trigger pending extraction when opening the file manager (runs once per file via status gating).
            extractionService.processPending(in: modelContext)
        }
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $isPresentingPasteText) {
            PasteTextView { text in
                addPastedText(text)
            }
        }
    }
}

private extension SpaceFileManagerView {
    var allowedImportTypes: [UTType] {
        var types: [UTType] = [
            .pdf,
            .plainText
        ]

        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Text("No content yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add files or paste text to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func row(_ file: SpaceFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.sourceType == .fileImport ? "doc" : "text.alignleft")
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(file.sourceType.label)
                    if file.sourceType == .fileImport {
                        Text("• \(file.extractionStatus.label)")
                            .foregroundStyle(file.extractionStatus.color)
                    }
                }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(file.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let file = files[index]
            deleteFileAndCleanup(file)
        }
    }

    func deleteFileAndCleanup(_ file: SpaceFile) {
        if let url = file.storedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(file)
    }

    func addPastedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newFile = SpaceFile(
            space: space,
            sourceType: .paste,
            displayName: "Pasted Text",
            storedText: trimmed,
            storedFileURL: nil
        )
        modelContext.insert(newFile)
    }

    func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            importFile(url)
        }
    }

    func importFile(_ sourceURL: URL) {
        let displayName = sourceURL.lastPathComponent

        // Strategy: copy into app container (Documents/SpaceFiles/<spaceId>/...)
        let destinationURL = fileDestinationURL(
            spaceId: space.id,
            originalFilename: displayName
        )

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // `fileImporter` URLs may be security-scoped. Best-effort access.
            let didStart = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStart { sourceURL.stopAccessingSecurityScopedResource() }
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            let newFile = SpaceFile(
                space: space,
                sourceType: .fileImport,
                displayName: displayName,
                storedText: nil,
                storedFileURL: destinationURL
            )
            modelContext.insert(newFile)

            // Trigger extraction immediately for newly imported files.
            extractionService.extractIfNeeded(newFile, in: modelContext)
        } catch {
            // Intentionally no alerts/logging in v0.6. (Collection-only, keep UX simple.)
        }
    }

    func fileDestinationURL(spaceId: UUID, originalFilename: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = documents
            .appendingPathComponent("SpaceFiles", isDirectory: true)
            .appendingPathComponent(spaceId.uuidString, isDirectory: true)

        // Avoid collisions.
        let sanitized = originalFilename.isEmpty ? "ImportedFile" : originalFilename
        let uniqueName = "\(UUID().uuidString)-\(sanitized)"
        return folder.appendingPathComponent(uniqueName, isDirectory: false)
    }
}

private extension SourceType {
    var label: String {
        switch self {
        case .fileImport: return "File"
        case .paste: return "Text"
        }
    }
}

private extension ExtractionStatus {
    var label: String {
        switch self {
        case .pending: return "Not ready"
        case .extracting: return "Working…"
        case .completed: return "Ready"
        case .failed: return "Couldn’t extract"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .extracting: return .secondary
        case .completed: return .secondary
        case .failed: return .red
        }
    }
}

private struct PasteTextView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .padding(12)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .padding()
                    .focused($isFocused)
                    .accessibilityLabel("Pasted text")
            }
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isFocused = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        isFocused = false
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
        }
        .onAppear {
            // Best-effort focus for a smoother paste flow.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

#Preview("Empty (preview-only)") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, SpaceFile.self, configurations: configuration)
    let context = container.mainContext
    let space = Space(name: "Spanish A1", templateType: .languageLearning)
    context.insert(space)

    return SpaceFileManagerView(space: space)
        .modelContainer(container)
}


