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
    @EnvironmentObject var bridgeManager: BridgeManager
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pinnedSceneItems.isEmpty {
                emptyStateView
            } else {
                Text("PINNED SCENES (\(pinnedSceneItems.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)

                ForEach(pinnedSceneItems) { item in
                    Button {
                        onSceneTap(item.scene, item.groupId)
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.scene.metadata.name)
                                    .foregroundColor(.primary)

                                Text("in \(item.contextName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "wand.and.stars")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "pin.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No pinned scenes")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Long-press a scene to pin it")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    PinnedScenesListView { scene, groupId in
        print("Tapped scene: \(scene.metadata.name) in group \(groupId)")
    }
    .environmentObject(BridgeManager())
    .padding()
}
