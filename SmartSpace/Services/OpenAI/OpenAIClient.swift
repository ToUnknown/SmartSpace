//
//  OpenAIClient.swift
//  SmartSpace
//
//  v0.4.2: Minimal OpenAI key validation (no streaming, no retries)
//

import Foundation

struct OpenAIClient {
    enum ValidationResult: Equatable {
        case valid
        case invalid(message: String)
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validateKey(_ apiKey: String) async -> ValidationResult {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            return .invalid(message: "Invalid OpenAI URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-5-nano",
            "input": "ping",
            // OpenAI Responses API requires a minimum output token budget.
            // Keep this small but valid for a cheap connectivity check.
            "max_output_tokens": 16
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .invalid(message: "Failed to encode request.")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .invalid(message: "No HTTP response.")
            }

            if (200...299).contains(http.statusCode) {
                return .valid
            }

            let message = decodeOpenAIErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            return .invalid(message: message)
        } catch {
            return .invalid(message: error.localizedDescription)
        }
    }

    private func decodeOpenAIErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable {
                let message: String?
            }
            let error: APIError?
        }

        guard let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        return decoded.error?.message
    }
}


