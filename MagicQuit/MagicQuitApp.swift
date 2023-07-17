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
        MenuBarExtra {
            ContentView()
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 18
                $0.size.width = 18 / ratio
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.window)
    }
}
