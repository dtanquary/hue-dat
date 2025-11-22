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

        return ZStack(alignment: .leading) {
            // Brightness progress bar background
            Rectangle()
                .fill(Color.orange.opacity(0.15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: (status.brightness ?? 0) / 100.0, anchor: .leading)

            // Content
            HStack(spacing: 8) {
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
            }
            .padding(.vertical, 12)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
