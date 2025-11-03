//
//  ScenePickerView.swift
//  hue dat Watch App
//
//  Scene picker dialog for selecting and activating scenes
//

import SwiftUI

struct ScenePickerView: View {
    let scenes: [HueScene]
    let activeSceneId: String?
    let onSceneSelected: (HueScene) -> Void
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bridgeManager: BridgeManager

    var body: some View {
        NavigationView {
            List {
                ForEach(scenes) { scene in
                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        onSceneSelected(scene)
                        dismiss()
                    }) {
                        SceneRowView(
                            scene: scene,
                            isActive: scene.id == activeSceneId,
                            bridgeManager: bridgeManager
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SceneRowView: View {
    let scene: HueScene
    let isActive: Bool
    @ObservedObject var bridgeManager: BridgeManager

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Scene name
                Text(scene.metadata.name)
                    .font(.headline)
                    .foregroundColor(.white)

                // Color preview using mini orbs
                let colors = bridgeManager.extractColorsFromScene(scene)
                if !colors.isEmpty {
                    ColorOrbsBackground(colors: colors, size: .compact)
                        .frame(height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Spacer()

            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 2)
    }
}
