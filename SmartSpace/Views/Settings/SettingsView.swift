//
//  SettingsView.swift
//  SmartSpace
//
//  v0.4.2: Settings (OpenAI API key management)
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let openAIKeyManager: OpenAIKeyManager

    @State private var apiKeyInput: String = ""
    @State private var isPresentingRemoveKeyConfirmation = false
    @FocusState private var isKeyFieldFocused: Bool

    private let maskedKeyPlaceholder = "••••••••••••"

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                SecureField("API key", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isKeyFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveKey()
                    }
                    .onTapGesture {
                        // If a key exists, show a masked placeholder. Clear it on tap so the user can paste a new key.
                        if apiKeyInput == maskedKeyPlaceholder {
                            apiKeyInput = ""
                        }
                    }

                statusRow
            }

            Section("Connection") {
                Button("Test connection") {
                    Task { await openAIKeyManager.testKey() }
                }
                .disabled(!openAIKeyManager.hasStoredKey || openAIKeyManager.status == .checking)
            }

            Section {
                Button("Remove key", role: .destructive) {
                    isPresentingRemoveKeyConfirmation = true
                }
                .disabled(!openAIKeyManager.hasStoredKey)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Removing the key will cause Spaces using OpenAI to fall back to Apple Intelligence.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Cloud models")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveKey()
                    dismiss()
                }
                .disabled(
                    apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiKeyInput == maskedKeyPlaceholder
                    || openAIKeyManager.status == .checking
                )
            }
        }
        .alert(
            "Remove OpenAI key?",
            isPresented: $isPresentingRemoveKeyConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                openAIKeyManager.removeKey()
                apiKeyInput = ""
            }
        }
        .onAppear {
            openAIKeyManager.loadKeyStatus()
            // If a key is already stored, show a masked placeholder in the field.
            if openAIKeyManager.hasStoredKey, apiKeyInput.isEmpty {
                apiKeyInput = maskedKeyPlaceholder
            }
        }
        .onChange(of: openAIKeyManager.hasStoredKey) { _, hasKey in
            if hasKey {
                if apiKeyInput.isEmpty {
                    apiKeyInput = maskedKeyPlaceholder
                }
            } else {
                if apiKeyInput == maskedKeyPlaceholder {
                    apiKeyInput = ""
                }
            }
        }
    }
}

private extension SettingsView {
    func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != maskedKeyPlaceholder else { return }
        openAIKeyManager.saveKey(trimmed)
        apiKeyInput = ""
        isKeyFieldFocused = false
    }

    var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)

                if openAIKeyManager.status == .checking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if case .invalid(let error) = openAIKeyManager.status {
                Text(invalidKeyMessage(for: error))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    var statusTitle: String {
        switch openAIKeyManager.status {
        case .notSet:
            return "Not set"
        case .checking:
            return "Checking…"
        case .valid:
            return "Valid"
        case .invalid:
            return "Invalid"
        }
    }

    var statusColor: Color {
        switch openAIKeyManager.status {
        case .notSet:
            return .secondary
        case .checking:
            return .secondary
        case .valid:
            return .green
        case .invalid:
            return .red
        }
    }

    func invalidKeyMessage(for error: String) -> String {
        // Keep this human-readable. Avoid dumping raw technical errors into the UI.
        let lower = error.lowercased()
        if lower.contains("incorrect") && lower.contains("api key") {
            return "Couldn’t validate key. Please check it and try again."
        }
        if lower.contains("network") || lower.contains("offline") {
            return "Couldn’t validate key. Check your connection and try again."
        }
        return "Couldn’t validate key. Please try again."
    }
}

#Preview {
    SettingsView(openAIKeyManager: OpenAIKeyManager())
}


