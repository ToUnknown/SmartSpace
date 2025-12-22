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
    guard space.aiProvider == .openAI else { return .appleIntelligence }

    switch openAIStatus {
    case .valid, .checking:
        // While checking, prefer OpenAI so generation can start immediately.
        // If the key turns out invalid, the app will fall back on the next run.
        return .openAI
    case .notSet, .invalid:
        return .appleIntelligence
    }
}


