//
//  TextExtractionService.swift
//  SmartSpace
//
//  v0.7: Deterministic local text extraction (no AI)
//

import Foundation
import SwiftData
import PDFKit

struct TextExtractionService {
    /// Triggers extraction for a single file if needed. Updates SwiftData fields and persists results.
    @MainActor
    func extractIfNeeded(_ file: SpaceFile, in modelContext: ModelContext) {
        // Pasted text is always considered complete.
        if file.sourceType == .paste {
            if file.extractionStatus != .completed {
                file.extractedText = file.storedText
                file.extractionStatus = .completed
            }
            return
        }

        guard file.sourceType == .fileImport else { return }
        guard file.extractionStatus == .pending else { return }
        guard let url = file.storedFileURL else {
            file.extractionStatus = .failed
            return
        }

        file.extractionStatus = .extracting
        let fileId = file.id

        DispatchQueue.global(qos: .utility).async {
            let result: Result<String, Error> = Result { try TextExtractor.extractPlainText(from: url) }

            DispatchQueue.main.async {
                do {
                    let fetched = try modelContext.fetch(
                        FetchDescriptor<SpaceFile>(
                            predicate: #Predicate { $0.id == fileId }
                        )
                    )
                    guard let current = fetched.first else { return }

                    switch result {
                    case .success(let text):
                        current.extractedText = text
                        current.extractionStatus = .completed
                    case .failure(let error):
                        #if DEBUG
                        print("TextExtractionService: extraction failed for \(url.lastPathComponent): \(error)")
                        #endif
                        current.extractedText = nil
                        current.extractionStatus = .failed
                    }
                } catch {
                    #if DEBUG
                    print("TextExtractionService: failed to refetch SpaceFile for update: \(error)")
                    #endif
                }
            }
        }
    }

    /// Scans the store for pending work. Call on app launch and/or when opening the file manager.
    @MainActor
    func processPending(in modelContext: ModelContext) {
        // Note: SwiftData predicates can be finicky with enum comparisons; keep this simple and robust
        // by fetching and filtering in-memory. (This is early-stage and datasets are small.)
        do {
            let allFiles = try modelContext.fetch(FetchDescriptor<SpaceFile>())
            for file in allFiles {
                if file.sourceType == .paste, file.extractionStatus != .completed {
                    file.extractedText = file.storedText
                    file.extractionStatus = .completed
                    continue
                }
                if file.sourceType == .fileImport, file.extractionStatus == .pending {
                    extractIfNeeded(file, in: modelContext)
                }
            }
        } catch {
            #if DEBUG
            print("TextExtractionService: failed to fetch SpaceFiles: \(error)")
            #endif
        }
    }
}

private enum TextExtractor {
    nonisolated static func extractPlainText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()

        let raw: String
        switch ext {
        case "txt", "md":
            raw = try String(contentsOf: url, encoding: .utf8)
        case "pdf":
            guard let document = PDFDocument(url: url) else {
                throw ExtractionError.unreadablePDF
            }
            raw = document.string ?? ""
        case "docx":
            raw = (try? extractDocxBestEffort(from: url)) ?? ""
        default:
            throw ExtractionError.unsupportedExtension(ext)
        }

        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            throw ExtractionError.emptyResult
        }
        return normalized
    }

    nonisolated static func extractDocxBestEffort(from url: URL) throws -> String {
        // Best-effort only: we avoid third-party parsers. If the system can decode it, great.
        // If not, this will throw and the file will end up as `.failed` (original file preserved).
        let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return attributed.string
    }

    enum ExtractionError: LocalizedError {
        case unsupportedExtension(String)
        case unreadablePDF
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Unsupported file type: .\(ext)"
            case .unreadablePDF:
                return "Could not read PDF."
            case .emptyResult:
                return "Extracted text was empty."
            }
        }
    }
}


