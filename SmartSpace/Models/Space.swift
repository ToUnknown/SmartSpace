//
//  Space.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import Foundation
import SwiftData

enum SpaceCoverStatus: String, Codable {
    case pending
    case generatingPrompt
    case generatingImage
    case ready
    case none
    case failed
}

@Model
final class Space {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var templateType: TemplateType
    // Default value helps keep existing local stores resilient during early schema changes.
    var aiProvider: AIProvider = AIProvider.appleIntelligence
    var isArchived: Bool

    // MARK: - Cover Image (Apple Intelligence / Image Playground)
    // Store raw value for migration safety.
    /// Changes whenever the Space content changes in a way that should re-trigger cover generation.
    /// We store as optional raw string for migration safety.
    var coverGenerationTokenRaw: String?
    var coverStatusRaw: String?
    var coverPrompt: String?
    var coverImageData: Data?
    var coverErrorMessage: String?

    var coverStatus: SpaceCoverStatus {
        get {
            guard let raw = coverStatusRaw, let status = SpaceCoverStatus(rawValue: raw) else {
                return .pending
            }
            return status
        }
        set {
            coverStatusRaw = newValue.rawValue
        }
    }

    init(
        name: String,
        templateType: TemplateType,
        aiProvider: AIProvider = .appleIntelligence
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.templateType = templateType
        self.aiProvider = aiProvider
        self.isArchived = false

        self.coverGenerationTokenRaw = UUID().uuidString
        self.coverStatusRaw = SpaceCoverStatus.pending.rawValue
        self.coverPrompt = nil
        self.coverImageData = nil
        self.coverErrorMessage = nil
    }
}

