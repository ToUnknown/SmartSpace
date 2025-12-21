//
//  ContentView.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isPresentingCreateSpaceSheet = false
    @State private var isPresentingSettings = false
    @State private var openAIKeyManager = OpenAIKeyManager()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SpacesHomeView(
                    openAIKeyManager: openAIKeyManager,
                    onOpenSettings: { isPresentingSettings = true }
                )
                    .padding(.bottom, 84)

                Button {
                    isPresentingCreateSpaceSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.tint, in: Circle())
                        .shadow(radius: 8, y: 4)
                }
                .padding(.bottom, 16)
                .accessibilityLabel("Create Space")
            }
            .navigationTitle("SmartSpace")
            .toolbar{
            ToolbarItem(placement: .topBarLeading) {
                Button{
                    isPresentingSettings = true
                } label: {
                    Image(systemName: "character")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button{
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        }
        .sheet(isPresented: $isPresentingCreateSpaceSheet) {
            CreateSpaceSheet(openAIKeyManager: openAIKeyManager)
        }
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack {
                SettingsView(openAIKeyManager: openAIKeyManager)
            }
        }
        .task {
            // v0.7: On launch, extract text for any pending imported files (runs once per file via status gating).
            await TextExtractionService().processPending(in: modelContext)
        }
        //Search + Create new buttton
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Space.self, inMemory: true)
}
