//
//  OpenAIService.swift
//  SmartSpace
//
//  v0.9: OpenAI summary generation (model: gpt-5-mini)
//  Note: model name is centralized below for easy temporary switching.
//

import Foundation

struct OpenAIService: AIService {
    enum OpenAIServiceError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key is not set."
            case .invalidResponse:
                return "OpenAI returned an invalid response."
            case .apiError(let message):
                return message
            }
        }
    }

    private let session: URLSession
    private let keyStore: OpenAIKeyStore
    private let modelName: String = "gpt-5-nano"
    // User-requested: use a large output budget for all OpenAI calls.
    // Prompts still constrain length for UI; this prevents truncation.
    private let maxTokensSummary: Int = 16_384
    private let maxTokensStructured: Int = 16_384
    private let maxTokensText: Int = 16_384
    private let maxTokensQA: Int = 16_384

    nonisolated init(session: URLSession = .shared, keyStore: OpenAIKeyStore = OpenAIKeyStore()) {
        self.session = session
        self.keyStore = keyStore
    }

    nonisolated func generateSummary(context: String) async throws -> String {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
Write a concise summary based only on the provided content.

Output rules:
- Plain text only (no markdown)
- Exactly 2 or 3 lines
- About 18–28 words total
- No headings, no bullets, no quotes
- No extra commentary
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            // Provide a large budget to avoid server-default truncation; prompt controls final length.
            "max_output_tokens": maxTokensSummary
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let summary = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func generateTextBlock(
        systemPrompt: String,
        context: String
    ) async throws -> String {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": context]
            ],
            // Provide a generous budget; prompt controls final length.
            "max_output_tokens": maxTokensText
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        return trimmed
    }

    nonisolated func generateFlashcards(context: String) async throws -> [(front: String, back: String)] {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Ask for strict JSON to keep parsing deterministic and UI-friendly.
        let systemPrompt = """
Create study flashcards from the content.
Return ONLY valid JSON with the exact shape:
{ "cards": [ { "front": "...", "back": "..." } ] }

Rules:
- 10 to 20 cards
- front: a single question or prompt, max 80 characters, no newlines
- back: a short answer, max 160 characters, no newlines
- Prefer concrete facts/definitions; avoid fluff
- No markdown, no extra keys, no surrounding text
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            // Prevent truncated JSON on the server-default budget.
            "max_output_tokens": maxTokensStructured
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }

        let cards = try decodeFlashcardsJSON(from: text)
        return cards
    }

    nonisolated func generateQuiz(context: String) async throws -> [QuizQuestion] {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
Create a multiple-choice quiz from the content.
Return ONLY valid JSON with the exact shape:
{
  "questions": [
    { "question": "...", "options": ["..."], "correctIndex": 0 }
  ]
}

Rules:
- 6 to 12 questions
- Each question max 120 characters, no newlines
- options length must be 3 to 5
- each option max 60 characters
- correctIndex must be a valid index into options
- No markdown, no extra keys, no surrounding text
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            // Prevent truncated JSON on the server-default budget.
            "max_output_tokens": maxTokensStructured
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }

        let questions = try decodeQuizJSON(from: text)
        return questions
    }

    nonisolated func generateKeyTerms(context: String) async throws -> [(term: String, definition: String)] {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
Extract key terms and definitions from the content.
Return ONLY valid JSON with the exact shape:
{
  "terms": [
    { "term": "…", "definition": "…" }
  ]
}

Rules:
- 10 to 20 terms
- term max 32 characters, no newlines
- definition: 1–2 short sentences, max 160 characters, no newlines
- No markdown, no extra keys, no surrounding text
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            // Prevent truncated JSON on the server-default budget.
            "max_output_tokens": maxTokensStructured
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }

        let terms = try decodeKeyTermsJSON(from: text)
        return terms
    }

    nonisolated func generateMainQuestion(context: String) async throws -> String {
        let prompt = """
Create ONE strong, specific main question that the user should be able to answer after studying the content.

Rules:
- Plain text only (no markdown)
- One line only
- Max 120 characters
- Do not include a label like "Main Question:" (the UI already shows it)
"""
        return try await generateTextBlock(systemPrompt: prompt, context: context)
    }

    nonisolated func generateInsights(context: String) async throws -> String {
        let prompt = """
Extract insights from the content.

Rules:
- 4 to 8 bullets
- Each bullet max 110 characters
- Each bullet must start with "- "
- Do not include a title like "Insights" (the UI already shows it)
- No extra sections
"""
        return try await generateTextBlock(systemPrompt: prompt, context: context)
    }

    nonisolated func generateArgumentCounterargument(context: String) async throws -> String {
        let prompt = """
Based on the content, write:
Argument: (2–4 short sentences)
Counterargument: (2–4 short sentences)

Rules:
- Plain text only (no markdown)
- Keep total under ~900 characters
"""
        return try await generateTextBlock(systemPrompt: prompt, context: context)
    }

    nonisolated func generateContentOutline(context: String) async throws -> String {
        let prompt = """
Create a structured outline of the content.

Rules:
- 6 to 14 bullets total (including sub-bullets)
- Short phrases, no long paragraphs
- Use "- " for bullets and "  - " for sub-bullets
- Do not include a title like "Outline" (the UI already shows it)
"""
        return try await generateTextBlock(systemPrompt: prompt, context: context)
    }

    nonisolated func answerQuestion(context: String, question: String) async throws -> String {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
Answer the user’s question using the provided content first.

Output rules (plain text, no markdown):
- Be direct and specific
- 1–3 short paragraphs OR up to 6 bullets (only if it helps clarity)
- If the content does not contain enough information, give a best-effort general answer BUT start with: "Not in files:" (keep it brief).
- Do NOT add extra sections, titles, benchmarks, or “Please let me know…” style lines
- Keep the entire answer under ~600 characters
"""

        let userContent = """
CONTENT:
\(context)

QUESTION:
\(question)
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            // Provide a generous budget; prompt controls final length.
            "max_output_tokens": maxTokensQA
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        return trimmed
    }

    private nonisolated func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }

    private nonisolated func decodeSummaryText(from data: Data) -> String? {
        // Responses API can return text in `output[].content[].text`.
        struct ResponseEnvelope: Decodable {
            struct Output: Decodable {
                struct Content: Decodable {
                    let type: String?
                    let text: String?
                }
                let content: [Content]?
            }
            let output: [Output]?
        }

        guard let decoded = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            return nil
        }
        guard let outputs = decoded.output else { return nil }

        // Prefer explicit output_text content if present.
        for output in outputs {
            guard let contents = output.content else { continue }
            for content in contents {
                if content.type == "output_text", let text = content.text, !text.isEmpty {
                    return text
                }
            }
        }

        // Fallback: first non-empty text.
        for output in outputs {
            guard let contents = output.content else { continue }
            for content in contents {
                if let text = content.text, !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    private nonisolated func decodeFlashcardsJSON(from text: String) throws -> [(front: String, back: String)] {
        struct FlashcardsPayload: Decodable {
            struct Card: Decodable {
                let front: String
                let back: String
            }
            let cards: [Card]
        }

        let jsonString = extractFirstJSONObjectString(from: text)
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(FlashcardsPayload.self, from: data)

        let pairs = decoded.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty && !$0.back.isEmpty }

        guard !pairs.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        return pairs
    }

    private nonisolated func decodeQuizJSON(from text: String) throws -> [QuizQuestion] {
        struct QuizPayload: Decodable {
            let questions: [QuizQuestion]
        }

        let jsonString = extractFirstJSONObjectString(from: text)
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(QuizPayload.self, from: data)

        let cleaned: [QuizQuestion] = decoded.questions.map { q in
            QuizQuestion(
                question: q.question.trimmingCharacters(in: .whitespacesAndNewlines),
                options: q.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                correctIndex: q.correctIndex
            )
        }.filter { !$0.question.isEmpty }

        guard !cleaned.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }

        for q in cleaned {
            if q.options.count < 3 || q.options.count > 5 {
                throw OpenAIServiceError.invalidResponse
            }
            if q.correctIndex < 0 || q.correctIndex >= q.options.count {
                throw OpenAIServiceError.invalidResponse
            }
        }

        return cleaned
    }

    private nonisolated func decodeKeyTermsJSON(from text: String) throws -> [(term: String, definition: String)] {
        struct KeyTermsPayload: Decodable {
            struct Term: Decodable {
                let term: String
                let definition: String
            }
            let terms: [Term]
        }

        let jsonString = extractFirstJSONObjectString(from: text)
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonString.data(using: .utf8) else {
            throw OpenAIServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(KeyTermsPayload.self, from: data)

        let pairs = decoded.terms.map { item in
            (
                term: item.term.trimmingCharacters(in: .whitespacesAndNewlines),
                definition: item.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { !$0.term.isEmpty && !$0.definition.isEmpty }

        guard !pairs.isEmpty else {
            throw OpenAIServiceError.invalidResponse
        }
        return pairs
    }

    /// Best-effort: extract the first JSON object from model output (handles code fences / extra text).
    private nonisolated func extractFirstJSONObjectString(from text: String) -> String? {
        let cleaned = unwrapCodeFencesIfPresent(text)

        let chars = Array(cleaned)
        var start: Int? = nil
        var depth = 0
        var inString = false
        var escape = false

        for i in chars.indices {
            let c = chars[i]

            if start == nil {
                if c == "{" {
                    start = i
                    depth = 1
                }
                continue
            }

            if inString {
                if escape {
                    escape = false
                } else if c == "\\" {
                    escape = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            } else {
                if c == "\"" {
                    inString = true
                    continue
                }
                if c == "{" {
                    depth += 1
                } else if c == "}" {
                    depth -= 1
                    if depth == 0, let s = start {
                        return String(chars[s...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        return nil
    }

    private nonisolated func unwrapCodeFencesIfPresent(_ text: String) -> String {
        guard let first = text.range(of: "```"),
              let last = text.range(of: "```", options: .backwards),
              first.lowerBound != last.lowerBound
        else {
            return text
        }

        var inner = String(text[first.upperBound..<last.lowerBound])
        inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the first line is a language tag (e.g. "json"), drop it.
        if let newline = inner.firstIndex(of: "\n") {
            let firstLine = inner[..<newline].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstLine.count <= 12, firstLine.allSatisfy({ $0.isLetter }) {
                inner = String(inner[inner.index(after: newline)...])
            }
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Space cover prompt (OpenAI)

    /// Returns a short prompt for an icon-like cover image, or nil if the model explicitly returns "NONE".
    nonisolated func suggestSpaceCoverPrompt(spaceName: String, context: String) async throws -> String? {
        let key = try keyStore.readKey()
        guard let apiKey = key, !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
You write a SHORT image prompt for a small cover icon.
Default behavior: ALWAYS return a prompt. If unsure, be generic rather than giving up.

Output rules:
- Return ONE line prompt (<= 18 words)
- Plain text only (no markdown), English, no quotes
- Use simple words (no jargon/acronyms)
- One concrete subject (animal/object/symbol), centered, clean background, high contrast
- No text in the image, no logos/brands, no real people
"""

        let input = """
Space name: \(spaceName)

Content:
\(context)
"""

        let body: [String: Any] = [
            "model": modelName,
            "input": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": input]
            ],
            "max_output_tokens": 256
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        guard let text = decodeSummaryText(from: data) else {
            throw OpenAIServiceError.invalidResponse
        }
        let out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.uppercased() == "NONE" { return nil }
        let oneLine = out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first ?? out
        let cleaned = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}


