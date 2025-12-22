//
//  AppleIntelligenceService.swift
//  SmartSpace
//
//  v0.9: Apple Intelligence summary generation
//  NOTE: Safe stub implementation (no unstable APIs yet).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import UIKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

struct AppleIntelligenceService: AIService {
    enum AppleIntelligenceServiceError: Error {
        case unavailable
        case emptyOutput
        case parseFailed
    }

    private func fallbackText(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if canImport(FoundationModels)
    private func respond(
        instructions: String,
        prompt: String,
        input: String,
        inputCap: Int = 40_000
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AppleIntelligenceServiceError.unavailable
        }

        // No local input caps. Let the system model handle its own context window limits.
        // (Callers still pass `inputCap` for legacy reasons; it's intentionally ignored.)
        let safeInput = input

        let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
        let response = try await session.respond(
            to: Prompt("""
\(prompt)

\(safeInput)
""")
        )

        let out = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if out.isEmpty { throw AppleIntelligenceServiceError.emptyOutput }
        return out
    }

    private func respondBestEffort(
        instructions: String,
        prompt: String,
        input: String
    ) async throws -> String {
        do {
            return try await respond(instructions: instructions, prompt: prompt, input: input)
        } catch {
            // If we exceeded the on-device context window (or any other generation error),
            // fall back to generating from a compact summary of the input and retry once.
            let compact = (try? await summarizeForContext(input)) ?? fallbackText(input, max: 2_000)
            return try await respond(instructions: instructions, prompt: prompt, input: compact)
        }
    }
    #endif

    private func parseFlashcards(from text: String) -> [(front: String, back: String)] {
        // Expected repeated blocks:
        // Front: ...
        // Back: ...
        // ---
        var results: [(front: String, back: String)] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var currentFront: String?
        var currentBack: String?

        func flush() {
            if let f = currentFront?.trimmingCharacters(in: .whitespacesAndNewlines),
               let b = currentBack?.trimmingCharacters(in: .whitespacesAndNewlines),
               !f.isEmpty, !b.isEmpty {
                results.append((front: f, back: b))
            }
            currentFront = nil
            currentBack = nil
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                flush()
                continue
            }
            if line.lowercased().hasPrefix("front:") {
                currentFront = line.dropFirst("front:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if line.lowercased().hasPrefix("back:") {
                currentBack = line.dropFirst("back:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
        }
        flush()
        return results
    }

    private func parseKeyTerms(from text: String) -> [(term: String, definition: String)] {
        // Expected: "Term: Definition" per line
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let pairs: [(String, String)] = lines.compactMap { line in
            guard !line.isEmpty else { return nil }
            // Allow either "Term: Def" or "- Term: Def"
            let cleaned = line.hasPrefix("- ") ? String(line.dropFirst(2)) : String(line)
            guard let idx = cleaned.firstIndex(of: ":") else { return nil }
            let term = cleaned[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
            let def = cleaned[cleaned.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !def.isEmpty else { return nil }
            return (String(term), String(def))
        }
        return pairs
    }

    private func sanitizeKeyTerms(_ items: [(term: String, definition: String)]) -> [(term: String, definition: String)] {
        // Repair common small-model failure mode where it outputs:
        // "Term: <actual term>" then "Definition: <actual definition>"
        // which our parser reads as (term:"Term", def:"<actual term>") etc.
        var repaired: [(term: String, definition: String)] = []
        repaired.reserveCapacity(items.count)

        var i = 0
        while i < items.count {
            let t = items[i].term.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = items[i].definition.trimmingCharacters(in: .whitespacesAndNewlines)

            if t.lowercased() == "term", i + 1 < items.count {
                let nextT = items[i + 1].term.trimmingCharacters(in: .whitespacesAndNewlines)
                let nextD = items[i + 1].definition.trimmingCharacters(in: .whitespacesAndNewlines)
                if nextT.lowercased() == "definition", !d.isEmpty, !nextD.isEmpty {
                    repaired.append((term: d, definition: nextD))
                    i += 2
                    continue
                }
            }

            // Also handle "Definition: ..." line without preceding Term line by skipping it.
            if t.lowercased() == "definition" {
                i += 1
                continue
            }

            repaired.append((term: t, definition: d))
            i += 1
        }

        return repaired.map { item in
            let term = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
            var def = item.definition.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove common “benchmark / comparison” phrasing that often sneaks into definitions.
            // Keep this conservative to avoid deleting meaningful content.
            let lower = def.lowercased()
            if lower.contains("outperforms") || lower.contains("matches") || lower.contains("accuracy") || lower.contains("%") {
                // Keep only the first clause/sentence before heavy comparison language.
                if let cut = def.firstIndex(of: ",") {
                    def = String(def[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let dot = def.firstIndex(of: ".") {
                    def = String(def[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Hard cap for UI friendliness.
            if def.count > 160 {
                def = String(def.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return (term: term, definition: def)
        }
        .filter { !$0.term.isEmpty && !$0.definition.isEmpty }
    }

    private func parseQuiz(from text: String) -> [QuizQuestion] {
        // Expected blocks:
        // Q: ...
        // A) ...
        // B) ...
        // C) ...
        // D) ...
        // Correct: B
        // ---
        var results: [QuizQuestion] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var q: String?
        var options: [String] = []
        var correctLetter: String?

        func flush() {
            guard let question = q?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !question.isEmpty,
                  options.count >= 2,
                  let letter = correctLetter?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  ["A", "B", "C", "D"].contains(letter)
            else {
                q = nil; options = []; correctLetter = nil
                return
            }

            let indexMap: [String: Int] = ["A": 0, "B": 1, "C": 2, "D": 3]
            guard let correctIndex = indexMap[letter], correctIndex < options.count else {
                q = nil; options = []; correctLetter = nil
                return
            }

            results.append(QuizQuestion(question: question, options: options, correctIndex: correctIndex))
            q = nil; options = []; correctLetter = nil
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                flush()
                continue
            }
            if line.lowercased().hasPrefix("q:") {
                q = line.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if line.count >= 3, line[ line.startIndex ] == "A" || line[ line.startIndex ] == "B" || line[ line.startIndex ] == "C" || line[ line.startIndex ] == "D" {
                // "A) option"
                if line.dropFirst(1).hasPrefix(")") {
                    let opt = line.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !opt.isEmpty { options.append(opt) }
                    continue
                }
            }
            if line.lowercased().hasPrefix("correct:") {
                correctLetter = line.dropFirst("correct:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
        }
        flush()
        return results
    }

    /// Summarize a single file's extracted text into a compact, high-signal summary suitable for downstream generation.
    /// This is used as a fallback when OpenAI context would otherwise truncate.
    func summarizeForContext(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // No local input caps.
        let input = trimmed

        #if canImport(FoundationModels)
        do {
            let instructions = """
You summarize documents for study.
Return only the summary text (no title, no markdown).
Use 8–14 short bullets. Each bullet must start with "- ".
Focus on key concepts, entities, definitions, and important lists.
"""
            return try await respond(
                instructions: instructions,
                prompt: "Summarize this document into bullets:",
                input: input
            )
        } catch {
            return fallbackText(input, max: 2_000)
        }
        #else
        return fallbackText(input, max: 2_000)
        #endif
    }

    /// Detailed per-file summary used for Apple Intelligence Spaces.
    /// This summary is persisted on `SpaceFile` and then used as the only context for block generation.
    func summarizeFileForBlocks(fileName: String, text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        #if canImport(FoundationModels)
        let instructions = """
You create study-ready file summaries for a learning app.
Return plain text only (no markdown). No title.
Do NOT include the file name.

Format (exact):
Key points:
- ...
- ...
Definitions (if present):
- Term — short definition
Claims / Results (if present):
- ...
Open questions (optional):
- ...

Rules:
- Prefer short bullets.
- Keep each bullet <= 140 characters.
- 10–18 key points.
"""

        let raw = try await respondBestEffort(
            instructions: instructions,
            prompt: "Summarize the document for study:",
            input: trimmed
        )
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return fallbackText(trimmed, max: 2_000)
        #endif
    }

    func generateSummary(context: String) async throws -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        #if canImport(FoundationModels)
        do {
            let instructions = """
You write concise summaries for a learning app UI.
Return plain text only. No markdown. No title.
Write exactly 2 or 3 short lines total (about 18–28 words total).
Do NOT include file names or lines that start with "FILE:".
"""
            let raw = try await respondBestEffort(
                instructions: instructions,
                prompt: "Write a concise 2–3 line summary:",
                input: trimmed
            )
            return normalizeSummary(raw)
        } catch {
            // Fallback: first ~180 chars split into up to 2 lines.
            let s = fallbackText(trimmed, max: 180)
            return s
        }
        #else
        return fallbackText(trimmed, max: 180)
        #endif
    }

    private func normalizeSummary(_ text: String) -> String {
        // Remove "FILE:" lines if any slip through. Do not clip length.
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.uppercased().hasPrefix("FILE:") }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateFlashcards(context: String) async throws -> [(front: String, back: String)] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        #if canImport(FoundationModels)
        do {
            let instructions = """
You create flashcards for study.
Return ONLY flashcards in this exact repeated format:
Front: <short question or term>
Back: <short answer>
---
No title. No markdown. No extra text.
Make 8–14 cards.
Keep Front <= 80 chars, Back <= 160 chars.
"""
            let raw = try await respondBestEffort(
                instructions: instructions,
                prompt: "Create flashcards from the content:",
                input: trimmed
            )
            var cards = parseFlashcards(from: raw)
            if cards.count < 4 {
                // One repair attempt: ask the model to reformat its output.
                let repairInstructions = """
Reformat the text into flashcards ONLY in this exact repeated format:
Front: <text>
Back: <text>
---
No title. No markdown. No extra text.
"""
                let repaired = try await respondBestEffort(
                    instructions: repairInstructions,
                    prompt: "Reformat to flashcards:",
                    input: raw
                )
                cards = parseFlashcards(from: repaired)
            }
            // Best-effort: return whatever we got (avoid failing the whole block).
            return Array(cards.prefix(16))
        } catch {
            // Best-effort fallback: no flashcards if the system model is unavailable.
            return []
        }
        #else
        return []
        #endif
    }

    func generateQuiz(context: String) async throws -> [QuizQuestion] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        #if canImport(FoundationModels)
        let instructions = """
You create multiple choice quiz questions for study.
Return ONLY questions in this exact repeated format:
Q: <question>
A) <option>
B) <option>
C) <option>
D) <option>
Correct: <A/B/C/D>
---
No title. No markdown. No extra text.
Make 5–10 questions.
Keep question <= 140 chars. Options <= 70 chars.
"""
        let raw = try await respondBestEffort(
            instructions: instructions,
            prompt: "Create a quiz from the content:",
            input: trimmed
        )
        var questions = parseQuiz(from: raw)
        if questions.count < 3 {
            let repairInstructions = """
Reformat the text into quiz questions ONLY in this exact repeated format:
Q: <question>
A) <option>
B) <option>
C) <option>
D) <option>
Correct: <A/B/C/D>
---
No title. No markdown. No extra text.
"""
            let repaired = try await respondBestEffort(
                instructions: repairInstructions,
                prompt: "Reformat to quiz questions:",
                input: raw
            )
            questions = parseQuiz(from: repaired)
        }
        return Array(questions.prefix(12))
        #else
        return []
        #endif
    }

    func generateKeyTerms(context: String) async throws -> [(term: String, definition: String)] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        #if canImport(FoundationModels)
        let instructions = """
You extract key terms and write clear definitions for study.

Return ONLY lines in this exact format:
Term: Definition

Rules:
- No title. No markdown. No extra text.
- Make 8–16 terms.
- Term: 1–4 words (<= 40 chars).
- Definition: what it IS (not what it achieves), <= 120 chars.
- Each line MUST start with the actual term (for example: "Reinforcement Learning: ..."), not the word "Term".
- Do NOT output separate lines like "Term: ..." and "Definition: ...".
- Do NOT include benchmarks, percentages, “outperforms”, “matches”, or comparisons to other models.
- Prefer concepts/methods/entities; avoid listing many model names unless they are central.
"""
        let raw = try await respondBestEffort(
            instructions: instructions,
            prompt: "Extract key terms from the content:",
            input: trimmed
        )
        var terms = sanitizeKeyTerms(parseKeyTerms(from: raw))
        if terms.count < 4 {
            let repairInstructions = """
Reformat the text into ONLY lines in this exact format:
Term: Definition
No title. No markdown. No extra text.
"""
            let repaired = try await respondBestEffort(
                instructions: repairInstructions,
                prompt: "Reformat to key terms:",
                input: raw
            )
            terms = sanitizeKeyTerms(parseKeyTerms(from: repaired))
        }
        return Array(terms.prefix(20))
        #else
        return []
        #endif
    }

    func generateMainQuestion(context: String) async throws -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        #if canImport(FoundationModels)
        let instructions = """
You write a single strong main question for study.
Return ONE line only. Plain text only. No label like "Main Question:".
Max 120 characters.
"""
        return try await respondBestEffort(
            instructions: instructions,
            prompt: "Write the main question:",
            input: trimmed
        )
        #else
        return ""
        #endif
    }

    func generateInsights(context: String) async throws -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        #if canImport(FoundationModels)
        let instructions = """
You extract insights for a learning app.
Return ONLY 4–8 bullets. Each bullet must start with "- ".
No title. No markdown. No extra sections.
Each bullet <= 110 characters.
"""
        return try await respondBestEffort(
            instructions: instructions,
            prompt: "Extract insights from the content:",
            input: trimmed
        )
        #else
        return ""
        #endif
    }

    func generateArgumentCounterargument(context: String) async throws -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        #if canImport(FoundationModels)
        let instructions = """
You write a short argument and counterargument based only on the content.
Return ONLY:
Argument: <2–4 short sentences>
Counterargument: <2–4 short sentences>
Plain text only. No markdown. No extra sections.
Keep total under ~900 characters.
"""
        return try await respondBestEffort(
            instructions: instructions,
            prompt: "Write argument and counterargument:",
            input: trimmed
        )
        #else
        return ""
        #endif
    }

    func generateContentOutline(context: String) async throws -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        #if canImport(FoundationModels)
        let instructions = """
You create a structured outline for study.
Return ONLY bullets. No title. No markdown.
Use "- " for bullets and "  - " for sub-bullets.
6–14 bullets total (including sub-bullets). Short phrases only.
"""
        return try await respondBestEffort(
            instructions: instructions,
            prompt: "Create an outline from the content:",
            input: trimmed
        )
        #else
        return ""
        #endif
    }

    func answerQuestion(context: String, question: String) async throws -> String {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return "" }
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else { return "" }

        #if canImport(FoundationModels)
        let instructions = """
You answer the user's question using the provided content first.
Return plain text only. No markdown.
Be direct and specific.

Output rules:
- 1–3 short paragraphs OR up to 6 bullets (only if it helps clarity)
- Do NOT add extra sections, titles, benchmarks, or “Please let me know…” style lines
- If the content is insufficient, give a best-effort general answer BUT start with: "Not in files:" (keep it brief).
- Keep under ~600 characters.
"""
        let prompt = """
CONTENT:
\(trimmedContext)

QUESTION:
\(trimmedQuestion)
"""
        return try await respondBestEffort(
            instructions: instructions,
            prompt: "Answer the question using the content below:",
            input: prompt
        )
        #else
        return ""
        #endif
    }

    // MARK: - Space cover prompt + image generation (Apple Intelligence)

    /// Returns a short prompt for an icon-like cover image, or nil if there is no good visual subject.
    func suggestSpaceCoverPrompt(spaceName: String, context: String) async throws -> String? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        let instructions = """
You create short prompts for generating an icon-like cover image for a learning space.
Your job is to pick ONE simple, concrete visual subject from the content that would look good as a small cover image.

Default behavior: ALWAYS return a prompt.
NEVER return NONE unless the input is truly empty (this should be extremely rare).
If unsure, pick a generic learning icon (book, light bulb, brain) rather than giving up.

Output rules:
- Return ONE line prompt (<= 18 words), plain text, no quotes, in English
- Prefer a single object/animal/symbol from the content (not a paragraph summary).
- Avoid text in the image. Avoid logos/brands. Avoid real people.
- Make it “icon-like”: centered subject, clean background, high contrast.

Selection rules:
- Prefer tangible subjects: animal, object, place, tool, food, plant, planet, simple diagram icon.
- If the content is technical, pick the most repeated concrete noun.
- If the content is abstract but the space name suggests a thing, use the space name to choose a subject.
- If still abstract: choose a universal learning icon (book, light bulb, brain).

Language rules (keep it simple):
- Use simple, common words a child would understand.
- Avoid jargon and acronyms (no "MoE", "MLA", "RL", etc.).
- Avoid proper names.
- Prefer: "orange cat", "cat paw print", "saturn planet", "brain", "book", "microscope", "rocket".
- Keep it short: mostly nouns + 1–2 adjectives (example: "orange cat on clean background").
"""
        let raw = try await respondBestEffort(
            instructions: instructions,
            prompt: "Pick a cover subject and write the image prompt:",
            input: """
Space name: \(spaceName)

Content:
\(trimmed)
"""
        )
        let out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("AppleIntelligenceService: cover prompt decision for '\(spaceName)': \(out)")
        #endif
        if out.uppercased() == "NONE" { return nil }
        if out.isEmpty { return nil }
        // Best-effort: keep it short and single-line.
        let oneLine = out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first ?? out
        return oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// Generates a single image (PNG data) using on-device Image Playground.
    func generateCoverImagePNG(prompt: String) async throws -> Data {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw AppleIntelligenceServiceError.emptyOutput }

        #if canImport(ImagePlayground)
        do {
            let creator = try await ImageCreator()
            // User request: always use the Animation style.
            guard creator.availableStyles.contains(.animation) else {
                throw AppleIntelligenceServiceError.unavailable
            }
            let style: ImagePlaygroundStyle = .animation

            let stream = creator.images(for: [.text(p)], style: style, limit: 1)
            for try await item in stream {
                let uiImage = UIImage(cgImage: item.cgImage)
                if let data = uiImage.pngData() {
                    return data
                }
                break
            }
            throw AppleIntelligenceServiceError.emptyOutput
        } catch let e as ImageCreator.Error {
            #if DEBUG
            print("AppleIntelligenceService: cover image generation ImageCreator.Error: \(e)")
            #endif
            throw e
        } catch {
            #if DEBUG
            print("AppleIntelligenceService: cover image generation unknown error: \(error)")
            #endif
            throw AppleIntelligenceServiceError.unavailable
        }
        #else
        throw AppleIntelligenceServiceError.unavailable
        #endif
    }
}


