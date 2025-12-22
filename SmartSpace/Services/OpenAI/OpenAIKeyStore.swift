//
//  OpenAIKeyStore.swift
//  SmartSpace
//
//  v0.4.2: Keychain storage for OpenAI API key (no logging)
//

import Foundation
import Security

enum OpenAIKeyStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned unexpected data."
        case .unhandledStatus(let status):
            return "Keychain error (\(status))."
        }
    }
}

struct OpenAIKeyStore {
    private let service = "SmartSpace"
    private let account = "openai_api_key"

    nonisolated func readKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OpenAIKeyStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw OpenAIKeyStoreError.unexpectedData
        }
        return key
    }

    nonisolated func saveKey(_ key: String) throws {
        let data = Data(key.utf8)

        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw OpenAIKeyStoreError.unhandledStatus(updateStatus)
        }

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIKeyStoreError.unhandledStatus(addStatus)
        }
    }

    nonisolated func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw OpenAIKeyStoreError.unhandledStatus(status)
    }
}


