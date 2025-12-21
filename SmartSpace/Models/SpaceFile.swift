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
    }
}


