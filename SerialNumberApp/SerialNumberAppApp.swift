//
//  SerialNumberAppApp.swift
//  SerialNumberApp
//
//  Created by Bastian Gardel on 07.11.2024.
//

import SwiftUI

@main
struct SerialNumberAppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
