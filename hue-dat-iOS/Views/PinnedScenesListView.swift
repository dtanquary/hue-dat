//
//  PinnedScenesListView.swift
//  hue dat iOS
//
//  List view displaying all pinned scenes across rooms and zones
//

import SwiftUI
import HueDatShared

struct PinnedSceneItem: Identifiable {
    let id: String
    let scene: HueScene
    let groupId: String
    let contextName: String
}

struct PinnedScenesListView: View {
    @Environment(BridgeManager.self) var bridgeManager
    let onSceneTap: (HueScene, String) -> Void

    private var pinnedSceneItems: [PinnedSceneItem] {
        var items: [PinnedSceneItem] = []

        // Collect pinned scenes from rooms
        for room in bridgeManager.rooms {
            let pinnedScenes = bridgeManager.getPinnedScenes(forRoomId: room.id)
            for scene in pinnedScenes {
                items.append(PinnedSceneItem(
                    id: "\(room.id)-\(scene.id)",
                    scene: scene,
                    groupId: room.id,
                    contextName: room.metadata.name
                ))
            }
        }

        // Collect pinned scenes from zones
        for zone in bridgeManager.zones {
            let pinnedScenes = bridgeManager.getPinnedScenes(forZoneId: zone.id)
            for scene in pinnedScenes {
                items.append(PinnedSceneItem(
                    id: "\(zone.id)-\(scene.id)",
                    scene: scene,
                    groupId: zone.id,
                    contextName: zone.metadata.name
                ))
            }
        }

        return items
    }

    // Rendered inside a toolbar Menu, which flattens custom styling —
    // rows must be plain menu items (Button + Label/Text only).
    var body: some View {
        if pinnedSceneItems.isEmpty {
            Text("No pinned scenes — long-press a scene to pin it")
        } else {
            Text("Pinned Scenes (\(pinnedSceneItems.count))")

            ForEach(pinnedSceneItems) { item in
                Button {
                    onSceneTap(item.scene, item.groupId)
                } label: {
                    Label {
                        Text(item.scene.metadata.name)
                        Text("in \(item.contextName)")
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                    }
                }
            }
        }
    }
}

#Preview {
    PinnedScenesListView { scene, groupId in
        debugLog("Tapped scene: \(scene.metadata.name) in group \(groupId)")
    }
    .environment(BridgeManager())
    .padding()
}
