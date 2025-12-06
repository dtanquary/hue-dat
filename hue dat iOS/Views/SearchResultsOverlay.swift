//
//  SearchResultsOverlay.swift
//  hue dat iOS
//
//  Full-screen search results overlay with room, zone, and scene filtering
//

import SwiftUI
import HueDatShared

struct SearchResultsOverlay: View {
    let searchResults: SearchResults
    let searchQuery: String
    let onRoomTap: (HueRoom) -> Void
    let onZoneTap: (HueZone) -> Void
    let onSceneTap: (SceneSearchResult) -> Void

    var body: some View {
        ZStack {
            // Full-screen background to block the content behind
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if searchQuery.isEmpty {
                        emptyQueryView
                    } else if searchResults.isEmpty {
                        noResultsView
                    } else {
                        resultsSections
                    }
                }
                .padding()
                .padding(.bottom, 60) // Extra padding for search bar at bottom
            }
        }
    }

    private var emptyQueryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Search for rooms, zones, or scenes")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No results for '\(searchQuery)'")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    @ViewBuilder
    private var resultsSections: some View {
        if !searchResults.rooms.isEmpty {
            roomsSection
        }

        if !searchResults.zones.isEmpty {
            zonesSection
        }

        if !searchResults.scenes.isEmpty {
            scenesSection
        }
    }

    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROOMS (\(searchResults.rooms.count))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.rooms) { room in
                Button {
                    onRoomTap(room)
                } label: {
                    HStack {
                        Image(systemName: roomIcon(for: room.metadata.archetype))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        HighlightedText(
                            text: room.metadata.name,
                            highlight: searchQuery
                        )
                        .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
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

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ZONES (\(searchResults.zones.count))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.zones) { zone in
                Button {
                    onZoneTap(zone)
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        HighlightedText(
                            text: zone.metadata.name,
                            highlight: searchQuery
                        )
                        .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
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

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCENES (\(searchResults.scenes.count))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.scenes) { sceneResult in
                Button {
                    onSceneTap(sceneResult)
                } label: {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HighlightedText(
                                text: sceneResult.scene.metadata.name,
                                highlight: searchQuery
                            )
                            .foregroundColor(.primary)

                            if let context = sceneResult.contextDescription {
                                Text(context)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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

    private func roomIcon(for archetype: String) -> String {
        switch archetype.lowercased() {
        case "living_room": return "sofa"
        case "bedroom": return "bed.double"
        case "kitchen": return "fork.knife"
        case "bathroom": return "drop"
        case "office": return "desktopcomputer"
        case "dining": return "fork.knife"
        case "hallway": return "door.left.hand.open"
        case "toilet": return "drop"
        case "garage": return "car"
        case "terrace", "balcony": return "sun.max"
        case "garden": return "leaf"
        case "gym": return "figure.run"
        case "recreation": return "gamecontroller"
        default: return "lightbulb.led.fill"
        }
    }
}

#Preview {
    SearchResultsOverlay(
        searchResults: SearchResults(
            rooms: [],
            zones: [],
            scenes: []
        ),
        searchQuery: "",
        onRoomTap: { _ in },
        onZoneTap: { _ in },
        onSceneTap: { _ in }
    )
}
