//
//  ScenePickerView.swift
//  hue dat Watch App
//
//  Scene picker dialog for selecting and activating scenes
//

import SwiftUI
import HueDatShared

struct ScenePickerView: View {
    let scenes: [HueScene]
    let activeSceneId: String?
    let onSceneSelected: (HueScene) -> Void
    @Environment(\.dismiss) var dismiss
    var bridgeManager: BridgeManager

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
                    .padding(14)
                    .glassEffect(.regular.interactive())
                    .listRowBackground(Color.clear)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .navigationTitle("Scenes (\(scenes.count))")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
    }
}

struct SceneRowView: View {
    let scene: HueScene
    let isActive: Bool
    var bridgeManager: BridgeManager

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Scene name
                Text(scene.metadata.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
    }
}
