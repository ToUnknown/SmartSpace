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

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: 8) {
                    Button("Save key") {
                        openAIKeyManager.saveKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove key", role: .destructive) {
                        openAIKeyManager.removeKey()
                        apiKeyInput = ""
                    }
                    .disabled(!openAIKeyManager.hasStoredKey)

                    Button("Test connection") {
                        Task { await openAIKeyManager.testKey() }
                    }
                    .disabled(!openAIKeyManager.hasStoredKey || openAIKeyManager.status == .checking)
                }

                statusRow
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            openAIKeyManager.loadKeyStatus()
        }
    }
}

private extension SettingsView {
    var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            if case .invalid(let error) = openAIKeyManager.status {
                Text("Invalid (\(error))")
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
}

#Preview {
    SettingsView(openAIKeyManager: OpenAIKeyManager())
}


