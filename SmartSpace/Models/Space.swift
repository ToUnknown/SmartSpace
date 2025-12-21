//
//  Space.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import Foundation
import SwiftData

@Model
final class Space {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var templateType: TemplateType
    // Default value helps keep existing local stores resilient during early schema changes.
    var aiProvider: AIProvider = AIProvider.appleIntelligence
    var isArchived: Bool

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
    }
}

