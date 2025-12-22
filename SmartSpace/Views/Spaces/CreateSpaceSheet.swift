//
//  CreateSpaceSheet.swift
//  SmartSpace
//
//  v2.0 scaffolding: minimal create flow (v0.4)
//

import SwiftUI
import SwiftData

struct CreateSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var spaces: [Space]

    let openAIKeyManager: OpenAIKeyManager

    @State private var name: String = ""
    @State private var templateType: TemplateType = .languageLearning
    @State private var aiProvider: AIProvider = .appleIntelligence

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Space name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if let message = nameValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Template") {
                    Picker("Template Type", selection: $templateType) {
                        ForEach(TemplateType.allCases) { type in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                Text(type.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(type)
                        }
                    }
                }

                if isOpenAIAvailable {
                    Section("Provider") {
                        Picker("AI Provider", selection: $aiProvider) {
                            Text("Apple Intelligence").tag(AIProvider.appleIntelligence)
                            Text("OpenAI").tag(AIProvider.openAI)
                        }
                        .pickerStyle(.segmented)
                    }
                } else {
                    Section {
                        Text("Add a valid OpenAI API key in Settings to enable OpenAI.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Create Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSpace()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .onChange(of: openAIKeyManager.status) { _, newValue in
            // If OpenAI becomes unavailable, revert to the safe default.
            if newValue != .valid {
                aiProvider = .appleIntelligence
            }
        }
    }
}

private extension CreateSpaceSheet {
    var isOpenAIAvailable: Bool {
        openAIKeyManager.status == .valid
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String {
        trimmedName.lowercased()
    }

    var existingNormalizedNames: Set<String> {
        Set(spaces.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    var nameValidationMessage: String? {
        if trimmedName.isEmpty {
            return "Name can’t be empty."
        }
        if existingNormalizedNames.contains(normalizedName) {
            return "A Space with this name already exists."
        }
        return nil
    }

    var isFormValid: Bool {
        nameValidationMessage == nil
    }

    func createSpace() {
        guard isFormValid else { return }

        let providerToPersist: AIProvider = isOpenAIAvailable ? aiProvider : .appleIntelligence
        let newSpace = Space(
            name: trimmedName,
            templateType: templateType,
            aiProvider: providerToPersist
        )
        ModelMutationCoordinator.insert(newSpace, in: modelContext)
        dismiss()
    }
}

#Preview("Empty") {
    CreateSpaceSheet(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(for: Space.self, inMemory: true)
}

#Preview("Duplicate name validation") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, configurations: configuration)

    let context = container.mainContext
    context.insert(Space(name: "Spanish A1", templateType: .languageLearning))

    return CreateSpaceSheet(openAIKeyManager: OpenAIKeyManager())
        .modelContainer(container)
}

