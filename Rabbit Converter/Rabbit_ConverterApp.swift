//
//  Rabbit_ConverterApp.swift
//  Rabbit Converter
//
//  Created by Bonjoy on 11/17/25.
//

import SwiftUI

@main
struct Rabbit_ConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(action: {
                    // Changed from Cmd+Shift+K to avoid conflict with Xcode's "Clean Build Folder"
                    FileConverter.selectFolderAndConvert()
                }) {
                    Label("Convert Documents...", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
