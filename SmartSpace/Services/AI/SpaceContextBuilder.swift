//
//  SpaceContextBuilder.swift
//  SmartSpace
//
//  v0.9: Build deterministic text context for AI input (no AI side effects)
//

import Foundation
import SwiftData

struct SpaceContextBuilder {
    enum ContextMode {
        /// Default: fair per-file contribution under a character cap.
        case balanced
        /// OpenAI mode: include full extracted text from all files (still subject to an overall cap).
        case full
    }

    /// Conservative cap to avoid huge prompts. Deterministic truncation with fair per-file contribution.
    var maxCharacters: Int = 20_000

    @MainActor
    func buildContext(
        for space: Space,
        in modelContext: ModelContext,
        mode: ContextMode = .balanced,
        maxCharactersOverride: Int? = nil
    ) -> String {
        let completedFiles = fetchCompletedFiles(for: space, in: modelContext)
        let (context, _) = buildContext(
            from: completedFiles,
            mode: mode,
            maxCharacters: maxCharactersOverride,
            includeFileHeaders: true
        )
        return context
    }

    @MainActor
    func fetchCompletedFiles(for space: Space, in modelContext: ModelContext) -> [(name: String, text: String)] {
        let spaceId = space.id

        let allFiles: [SpaceFile]
        do {
            // SwiftData relationship predicates can be brittle across schema changes.
            // Fetch and filter in-memory for robustness (datasets are small).
            let fetched = try modelContext.fetch(FetchDescriptor<SpaceFile>())
            allFiles = fetched
                .filter { $0.space.id == spaceId }
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            #if DEBUG
            print("SpaceContextBuilder: fetch failed: \(error)")
            #endif
            return []
        }

        return allFiles.compactMap { file in
            guard file.extractionStatus == .completed else { return nil }
            let text = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return (name: file.displayName, text: trimmed)
        }
    }

    func buildContext(
        from completedFiles: [(name: String, text: String)],
        mode: ContextMode,
        maxCharacters: Int?,
        includeFileHeaders: Bool = true
    ) -> (context: String, didTruncate: Bool) {
        guard !completedFiles.isEmpty else { return ("", false) }

        let maxChars = maxCharacters ?? self.maxCharacters

        // Ensure every file contributes by allocating a per-file budget.
        let fileCount = completedFiles.count
        let separator = "\n\n---\n\n"
        let headerPrefix = "FILE: "
        let headerSuffix = "\n\n"

        var parts: [String] = []
        parts.reserveCapacity(fileCount)
        var didTruncate = false

        func currentLength() -> Int {
            // Avoid repeated O(n) joins in non-huge scenarios; fine for small file counts.
            parts.joined(separator: separator).count
        }

        switch mode {
        case .balanced:
            // Budget per file (deterministic). If many files, each gets a smaller slice.
            let perFileBudget = max(1_000, maxChars / fileCount)

            for item in completedFiles {
                if currentLength() >= maxChars {
                    didTruncate = true
                    break
                }

                let header = includeFileHeaders ? "\(headerPrefix)\(item.name)\(headerSuffix)" : ""
                let remainingForThis = max(0, perFileBudget - header.count)
                let textSlice: String
                if item.text.count <= remainingForThis {
                    textSlice = item.text
                } else {
                    didTruncate = true
                    let cutoff = item.text.index(item.text.startIndex, offsetBy: remainingForThis)
                    textSlice = String(item.text[..<cutoff])
                }

                let combined = (header + textSlice).trimmingCharacters(in: .whitespacesAndNewlines)
                if !combined.isEmpty {
                    parts.append(combined)
                }
            }

        case .full:
            // Include full text from each file (subject only to overall maxChars).
            for item in completedFiles {
                if currentLength() >= maxChars {
                    didTruncate = true
                    break
                }
                let header = includeFileHeaders ? "\(headerPrefix)\(item.name)\(headerSuffix)" : ""
                let combined = (header + item.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !combined.isEmpty {
                    parts.append(combined)
                }
            }
        }

        let result = parts.joined(separator: separator)
        let final = String(result.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxChars {
            didTruncate = true
        }

        #if DEBUG
        let includedNames = completedFiles.map(\.name).joined(separator: ", ")
        print("SpaceContextBuilder: included \(parts.count)/\(completedFiles.count) files: \(includedNames)")
        #endif

        return (final, didTruncate)
    }
}


