//
//  AIProvider.swift
//  SmartSpace
//
//  v2.0 data layer (v0.4.1): provider enum (no logic beyond display naming)
//

import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case appleIntelligence = "appleIntelligence"
    case openAI = "openAI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI: return "OpenAI"
        }
    }
}


