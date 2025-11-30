//
//  ZoneRowView.swift
//  hue dat iOS
//
//  Created by Claude Code
//

import SwiftUI
import HueDatShared

struct ZoneRowView: View {
    let zone: HueZone
    var isLoading: Bool = false

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = zone.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    var body: some View {
        let status = lightStatus  // Compute once and cache

        return HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.headline)
                .foregroundStyle(status.isOn ? .yellow : .secondary)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(zone.metadata.name)
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
        .background(
            ZStack {
                // Brightness progress bar background
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: geometry.size.width * (status.brightness ?? 0) / 100.0)

                        Spacer(minLength: 0)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: status.brightness)

                // Base background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .skeletonLoader(isActive: isLoading)
    }
}
