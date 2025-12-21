//
//  SmartSpaceApp.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import SwiftUI
import SwiftData

@main
struct SmartSpaceApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Space.self,
            SpaceFile.self,
            GeneratedBlock.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
