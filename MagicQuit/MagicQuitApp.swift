//
//  MagicQuitApp.swift
//  MagicQuit
//
//  Created by Janis Berneker on 30.06.23.
//

import SwiftUI

let runningAppsManager = RunningAppsManager()

@main
struct MagicQuitApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: runningAppsManager)
        } label: {
            let image: NSImage = {
                $0.size.height = 18
                $0.size.width = 18
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.window)
    }
}
