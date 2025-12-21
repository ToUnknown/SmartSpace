//
//  GeneratedBlock.swift
//  SmartSpace
//
//  v0.8: Persistent block storage (no AI generation yet)
//

import Foundation
import SwiftData

enum BlockStatus: String, Codable {
    case idle
    case generating
    case ready
    case failed
}

@Model
final class GeneratedBlock {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Relationship
    @Relationship var space: Space

    // Identity
    var blockType: BlockType

    // Lifecycle
    var status: BlockStatus
    var errorMessage: String?

    // Payload (JSON-encoded later)
    var payload: Data?

    init(
        space: Space,
        blockType: BlockType
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.space = space
        self.blockType = blockType
        self.status = .idle
        self.errorMessage = nil
        self.payload = nil
    }
}


