//
//  OpenAIKeyManager.swift
//  SmartSpace
//
//  v0.4.2: OpenAI key status manager (stores status only; key stays in Keychain)
//

import Foundation
import Observation

@MainActor
@Observable
final class OpenAIKeyManager {
    enum KeyStatus: Equatable {
        case notSet
        case checking
        case valid
        case invalid(error: String)
    }

    private let keyStore: OpenAIKeyStore
    private let client: OpenAIClient

    private(set) var status: KeyStatus = .notSet
    private(set) var hasStoredKey: Bool = false

    init(
        keyStore: OpenAIKeyStore = OpenAIKeyStore(),
        client: OpenAIClient = OpenAIClient()
    ) {
        self.keyStore = keyStore
        self.client = client
        loadKeyStatus()
    }

    func loadKeyStatus() {
        do {
            let raw = try keyStore.readKey()
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            hasStoredKey = !trimmed.isEmpty
        } catch {
            hasStoredKey = false
        }

        // If a key is stored, reflect that immediately so the rest of the app can use OpenAI
        // without forcing the user to re-enter the key after relaunch.
        // We still validate in the background and will flip to `.invalid(...)` if needed.
        if hasStoredKey {
            status = .valid
            Task { await testKey() }
        } else {
            status = .notSet
        }
    }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try keyStore.saveKey(trimmed)
            hasStoredKey = true
            // Immediately kick off validation so Settings reflects a useful status.
            status = .checking
            Task { await testKey() }
        } catch {
            hasStoredKey = false
            status = .invalid(error: error.localizedDescription)
        }
    }

    func removeKey() {
        do {
            try keyStore.deleteKey()
            hasStoredKey = false
            status = .notSet
        } catch {
            // If deletion fails, reflect the error. (Do not pretend the key is removed.)
            hasStoredKey = (try? keyStore.readKey()) != nil
            status = .invalid(error: error.localizedDescription)
        }
    }

    func testKey() async {
        do {
            guard let key = try keyStore.readKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty
            else {
                hasStoredKey = false
                status = .notSet
                return
            }

            hasStoredKey = true
            status = .checking

            let result = await client.validateKey(key)
            switch result {
            case .valid:
                status = .valid
            case .invalid(let message):
                status = .invalid(error: message)
            }
        } catch {
            hasStoredKey = false
            status = .invalid(error: error.localizedDescription)
        }
    }
}


