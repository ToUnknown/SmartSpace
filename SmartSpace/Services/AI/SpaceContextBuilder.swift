//
//  SpaceContextBuilder.swift
//  SmartSpace
//
//  v0.9: Build deterministic text context for AI input (no AI side effects)
//

import Foundation
import SwiftData

struct SpaceContextBuilder {
    /// Conservative cap to avoid huge prompts. Deterministic truncation (oldest-first).
    var maxCharacters: Int = 20_000

    @MainActor
    func buildContext(for space: Space, in modelContext: ModelContext) -> String {
        let spaceId = space.id

        let allFiles: [SpaceFile]
        do {
            allFiles = try modelContext.fetch(
                FetchDescriptor<SpaceFile>(
                    predicate: #Predicate { $0.space.id == spaceId },
                    sortBy: [SortDescriptor(\SpaceFile.createdAt, order: .forward)]
                )
            )
        } catch {
            #if DEBUG
            print("SpaceContextBuilder: fetch failed: \(error)")
            #endif
            return ""
        }

        let completedTexts: [String] = allFiles.compactMap { file in
            guard file.extractionStatus == .completed else { return nil }
            let text = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }

        guard !completedTexts.isEmpty else { return "" }

        var result = ""
        result.reserveCapacity(min(maxCharacters, 4096))

        for (index, text) in completedTexts.enumerated() {
            if result.count >= maxCharacters { break }

            if index > 0 {
                result.append("\n\n---\n\n")
            }

            let remaining = maxCharacters - result.count
            if text.count <= remaining {
                result.append(text)
            } else {
                // Deterministic truncation: cut off the tail.
                let cutoffIndex = text.index(text.startIndex, offsetBy: max(0, remaining))
                result.append(String(text[..<cutoffIndex]))
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


