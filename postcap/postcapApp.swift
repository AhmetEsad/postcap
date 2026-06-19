//
//  postcapApp.swift
//  postcap
//
//  Created by ahmet on 03/05/2026.
//

import SwiftUI

@main
struct PostcapApp: App {
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateManager.checkForUpdates()
                }
                .disabled(!updateManager.canCheckForUpdates)
            }
        }
    }
}
