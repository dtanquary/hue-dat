//
//  HueDatMacApp.swift
//  hue dat macOS
//
//  macOS MenuBar app entry point
//

import SwiftUI
import HueDatShared

@main
struct HueDatMacApp: App {
    @StateObject private var bridgeManager = BridgeManager()

    var body: some Scene {
        MenuBarExtra("HueDat", systemImage: "lightbulb.fill") {
            MenuBarPanelView()
                .environmentObject(bridgeManager)
        }
        .menuBarExtraStyle(.window)
    }
}
