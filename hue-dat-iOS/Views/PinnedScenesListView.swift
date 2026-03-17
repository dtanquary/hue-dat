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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pinnedSceneItems.isEmpty {
                emptyStateView
            } else {
                Text("PINNED SCENES (\(pinnedSceneItems.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(pinnedSceneItems) { item in
                    Button {
                        onSceneTap(item.scene, item.groupId)
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.scene.metadata.name)
                                    .foregroundStyle(.primary)

                                Text("in \(item.contextName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "wand.and.stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Text("No pinned scenes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Long-press a scene to pin it")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    PinnedScenesListView { scene, groupId in
        debugLog("Tapped scene: \(scene.metadata.name) in group \(groupId)")
    }
    .environment(BridgeManager())
    .padding()
}
