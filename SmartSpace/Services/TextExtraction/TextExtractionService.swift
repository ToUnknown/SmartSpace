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
    func extractIfNeeded(_ file: SpaceFile, in modelContext: ModelContext) async {
        // Pasted text is always considered complete.
        if file.sourceType == .paste {
            if file.extractionStatus != .completed {
                ModelMutationCoordinator.updateSpaceFileExtraction(
                    spaceFileId: file.id,
                    extractedText: file.storedText,
                    status: .completed,
                    in: modelContext
                )
            }
            return
        }

        guard file.sourceType == .fileImport else { return }
        guard file.extractionStatus == .pending else { return }
        guard let url = file.storedFileURL else {
            ModelMutationCoordinator.updateSpaceFileExtraction(
                spaceFileId: file.id,
                extractedText: nil,
                status: .failed,
                errorMessage: "File is missing.",
                in: modelContext
            )
            return
        }

        let fileId = file.id
        ModelMutationCoordinator.updateSpaceFileExtraction(
            spaceFileId: fileId,
            extractedText: nil,
            status: .extracting,
            in: modelContext
        )

        // Do parsing off-main. Only apply model updates back on the MainActor.
        let result = await Task.detached(priority: .utility) {
            Result<String, Error> {
                let text = try TextExtractor.extractPlainText(from: url)
                if let message = LanguageGatekeeper.englishOnlyErrorMessage(for: text) {
                    throw TextExtractor.ExtractionError.nonEnglish(message)
                }
                return text
            }
        }.value

        switch result {
        case .success(let text):
            ModelMutationCoordinator.updateSpaceFileExtraction(
                spaceFileId: fileId,
                extractedText: text,
                status: .completed,
                in: modelContext
            )
        case .failure(let error):
            #if DEBUG
            print("TextExtractionService: extraction failed for \(url.lastPathComponent): \(error)")
            #endif
            let message: String
            if let extractionError = error as? TextExtractor.ExtractionError {
                // Convert technical error to calm, user-facing copy.
                switch extractionError {
                case .nonEnglish:
                    message = "Only English language is available right now."
                case .unsupportedExtension:
                    message = "This file type isn’t supported."
                case .unreadablePDF:
                    message = "Couldn’t read this PDF."
                case .emptyResult:
                    message = "This file has no readable text."
                }
            } else {
                message = "Couldn’t read this file."
            }
            ModelMutationCoordinator.updateSpaceFileExtraction(
                spaceFileId: fileId,
                extractedText: nil,
                status: .failed,
                errorMessage: message,
                in: modelContext
            )
        }
    }

    /// Scans the store for pending work. Call on app launch and/or when opening the file manager.
    @MainActor
    func processPending(in modelContext: ModelContext) async {
        // Note: SwiftData predicates can be finicky with enum comparisons; keep this simple and robust
        // by fetching and filtering in-memory. (This is early-stage and datasets are small.)
        do {
            let allFiles = try modelContext.fetch(FetchDescriptor<SpaceFile>())
            for file in allFiles {
                if file.sourceType == .paste, file.extractionStatus != .completed {
                    let text = file.storedText ?? ""
                    let message = LanguageGatekeeper.englishOnlyErrorMessage(for: text)
                    ModelMutationCoordinator.updateSpaceFileExtraction(
                        spaceFileId: file.id,
                        extractedText: message == nil ? file.storedText : nil,
                        status: message == nil ? .completed : .failed,
                        errorMessage: message,
                        in: modelContext
                    )
                    continue
                }
                if file.sourceType == .fileImport, file.extractionStatus == .pending {
                    await extractIfNeeded(file, in: modelContext)
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
        case nonEnglish(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Unsupported file type: .\(ext)"
            case .unreadablePDF:
                return "Could not read PDF."
            case .emptyResult:
                return "Extracted text was empty."
            case .nonEnglish(let message):
                return message
            }
        }
    }
}


