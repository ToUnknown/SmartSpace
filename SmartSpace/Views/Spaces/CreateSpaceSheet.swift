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

    @State private var name: String = ""
    @State private var templateType: TemplateType = .languageLearning

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
                            Text(type.displayName).tag(type)
                        }
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
    }
}

private extension CreateSpaceSheet {
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

        let newSpace = Space(
            name: trimmedName,
            templateType: templateType
        )
        modelContext.insert(newSpace)
        dismiss()
    }
}

private extension TemplateType {
    var displayName: String {
        switch self {
        case .languageLearning: return "Language Learning"
        case .lectureDebrief: return "Lecture Debrief"
        case .testPreparation: return "Test Preparation"
        case .researchAnalysis: return "Research Analysis"
        }
    }
}

#Preview("Empty") {
    CreateSpaceSheet()
        .modelContainer(for: Space.self, inMemory: true)
}

#Preview("Duplicate name validation") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Space.self, configurations: configuration)

    let context = container.mainContext
    context.insert(Space(name: "Spanish A1", templateType: .languageLearning))

    return CreateSpaceSheet()
        .modelContainer(container)
}

