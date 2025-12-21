//
//  SpaceFile.swift
//  SmartSpace
//
//  v0.6: Space content collection (import & paste) — no extraction, no AI
//

import Foundation
import SwiftData

enum SourceType: String, Codable {
    case fileImport
    case paste
}

enum ExtractionStatus: String, Codable {
    case pending
    case extracting
    case completed
    case failed
}

@Model
final class SpaceFile {
    var id: UUID
    var createdAt: Date

    // Relationship
    @Relationship var space: Space

    // Source
    var sourceType: SourceType
    var displayName: String

    // Storage
    var storedText: String?
    var storedFileURL: URL?

    // Extraction (v0.7)
    var extractedText: String?
    var extractionStatus: ExtractionStatus = ExtractionStatus.pending

    init(
        space: Space,
        sourceType: SourceType,
        displayName: String,
        storedText: String? = nil,
        storedFileURL: URL? = nil
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.space = space
        self.sourceType = sourceType
        self.displayName = displayName
        self.storedText = storedText
        self.storedFileURL = storedFileURL

        switch sourceType {
        case .paste:
            // Do NOT overwrite user-pasted text; mirror it into extractedText for downstream pipelines.
            self.extractedText = storedText
            self.extractionStatus = ExtractionStatus.completed
        case .fileImport:
            self.extractedText = nil
            self.extractionStatus = ExtractionStatus.pending
        }
    }
}


