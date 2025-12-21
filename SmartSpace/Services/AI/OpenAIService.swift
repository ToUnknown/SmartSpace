//
//  OpenAIService.swift
//  SmartSpace
//
//  v0.9: OpenAI summary generation (model: gpt-5-mini)
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

    init(session: URLSession = .shared, keyStore: OpenAIKeyStore = OpenAIKeyStore()) {
        self.session = session
        self.keyStore = keyStore
    }

    func generateSummary(context: String) async throws -> String {
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
            "model": "gpt-5-mini",
            "input": [
                [
                    "role": "system",
                    "content": "Summarize the following content clearly and concisely."
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            "max_output_tokens": 300
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

    func generateFlashcards(context: String) async throws -> [(front: String, back: String)] {
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

        // Ask for strict JSON to keep parsing deterministic.
        let systemPrompt = """
Create concise study flashcards from the following content.
Return ONLY valid JSON with the shape:
{ "cards": [ { "front": "...", "back": "..." } ] }
"""

        let body: [String: Any] = [
            "model": "gpt-5-mini",
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
            "max_output_tokens": 600
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

    private func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }

    private func decodeSummaryText(from data: Data) -> String? {
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

    private func decodeFlashcardsJSON(from text: String) throws -> [(front: String, back: String)] {
        struct FlashcardsPayload: Decodable {
            struct Card: Decodable {
                let front: String
                let back: String
            }
            let cards: [Card]
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
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
}


