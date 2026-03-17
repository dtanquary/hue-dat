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
                .foregroundStyle(.secondary)
            Text("Search for rooms, zones, or scenes")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No results for '\(searchQuery)'")
                .font(.headline)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.rooms) { room in
                Button {
                    onRoomTap(room)
                } label: {
                    HStack {
                        Image(systemName: iconForArchetype(room.metadata.archetype))
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        HighlightedText(
                            text: room.metadata.name,
                            highlight: searchQuery
                        )
                        .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
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

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ZONES (\(searchResults.zones.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.zones) { zone in
                Button {
                    onZoneTap(zone)
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.purple)
                            .frame(width: 24)

                        HighlightedText(
                            text: zone.metadata.name,
                            highlight: searchQuery
                        )
                        .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
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

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCENES (\(searchResults.scenes.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(searchResults.scenes) { sceneResult in
                Button {
                    onSceneTap(sceneResult)
                } label: {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HighlightedText(
                                text: sceneResult.scene.metadata.name,
                                highlight: searchQuery
                            )
                            .foregroundStyle(.primary)

                            if let context = sceneResult.contextDescription {
                                Text(context)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
