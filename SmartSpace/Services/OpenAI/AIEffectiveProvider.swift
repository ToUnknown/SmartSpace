//
//  AIEffectiveProvider.swift
//  SmartSpace
//
//  v0.4.4: Runtime-only provider resolution (no persistence, no mutation)
//

import Foundation

func effectiveProvider(
    for space: Space,
    openAIStatus: OpenAIKeyManager.KeyStatus
) -> AIProvider {
    if space.aiProvider == .openAI, openAIStatus == .valid {
        return .openAI
    } else {
        return .appleIntelligence
    }
}


