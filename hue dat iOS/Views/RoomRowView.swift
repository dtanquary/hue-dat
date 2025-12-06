//
//  RoomRowView.swift
//  hue dat iOS
//
//  Created by Claude Code
//

import SwiftUI
import HueDatShared

struct RoomRowView: View {
    let room: HueRoom
    var isLoading: Bool = false

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = room.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        let status = lightStatus  // Compute once and cache

        return HStack(spacing: 8) {
            Image(systemName: iconForArchetype(room.metadata.archetype))
                .font(.headline)
                .foregroundStyle(status.isOn ? .yellow : .secondary)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.metadata.name)
                    .font(.subheadline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.isOn ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(status.isOn ? "On" : "Off")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }

                if let brightness = status.brightness {
                    Text("\(Int(brightness))%")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 12)
        .background {
            // Base background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    // Brightness progress bar (only if not loading)
                    if !isLoading, let brightness = status.brightness {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: geometry.size.width * brightness / 100.0)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
        }
        .skeletonLoader(isActive: isLoading)
    }

    private func iconForArchetype(_ archetype: String) -> String {
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

// MARK: - Array Extension for Average Calculation
extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
