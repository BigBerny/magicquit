//
//  MagicQuitApp.swift
//  MagicQuit
//
//  Created by Janis Berneker on 30.06.23.
//

import SwiftUI

@main
struct MagicQuitApp: App {
    var body: some Scene {
        MenuBarExtra("MagicQuit", systemImage: "xmark.square.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
