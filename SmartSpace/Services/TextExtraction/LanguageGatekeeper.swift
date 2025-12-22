import Foundation
import NaturalLanguage

enum LanguageGatekeeper {
    /// Returns nil if the text is acceptable (English-only policy).
    /// Returns a human-readable error message if the text appears to be non-English.
    nonisolated static func englishOnlyErrorMessage(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Use a prefix for speed and to avoid huge memory use.
        let sample = String(trimmed.prefix(6_000))

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)

        // If the recognizer can't decide, allow it (better UX for short texts).
        guard let lang = recognizer.dominantLanguage else { return nil }
        if lang == .english { return nil }

        return "Only English language is available right now."
    }
}


