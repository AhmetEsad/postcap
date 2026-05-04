//
//  postcapApp.swift
//  postcap
//
//  Created by ahmet on 03/05/2026.
//

import SwiftUI

@main
struct PostcapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
