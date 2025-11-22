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

        return ZStack(alignment: .leading) {
            // Brightness progress bar background
            Rectangle()
                .fill(Color.orange.opacity(0.15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: (status.brightness ?? 0) / 100.0, anchor: .leading)

            // Content
            HStack(spacing: 8) {
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
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
