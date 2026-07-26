//
//  GroupRowView_iOS.swift
//  hue dat iOS
//
//  Unified row view for rooms and zones in the list.
//  Replaces RoomRowView and ZoneRowView.
//

import SwiftUI
import HueDatShared

struct GroupRowView_iOS<T: GroupedLightContainer>: View {
    let group: T
    var isLoading: Bool = false
    var onTogglePower: (() -> Void)? = nil

    private var lightStatus: (isOn: Bool, brightness: Double?) {
        guard let lights = group.groupedLights, !lights.isEmpty else {
            return (false, nil)
        }

        let anyOn = lights.contains { $0.on?.on == true }
        let averageBrightness = lights.compactMap { $0.dimming?.brightness }.average()

        return (anyOn, averageBrightness)
    }

    /// Live color the group's lights are actually showing right now
    private var liveColor: Color {
        group.groupedLights?.first?.displayColor ?? .orange
    }

    private var icon: String {
        if T.isRoom {
            return iconForArchetype(group.metadata.archetype)
        } else {
            return "square.grid.2x2"
        }
    }

    var body: some View {
        let status = lightStatus  // Compute once and cache

        return HStack(spacing: 8) {
            // Icon doubles as inline power toggle (innermost button wins the
            // tap; the surrounding row button still handles navigation)
            Button {
                onTogglePower?()
            } label: {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(status.isOn ? liveColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.leading, 8)
            .accessibilityLabel("\(group.metadata.name) power")
            .accessibilityValue(status.isOn ? "On" : "Off")
            .accessibilityHint("Double tap to turn \(status.isOn ? "off" : "on")")

            VStack(alignment: .leading, spacing: 4) {
                Text(group.metadata.name)
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

                Text(brightnessText(status.brightness))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .background {
            // Base background with brightness bar tinted by the live light color
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    // Brightness progress bar (only if not loading)
                    if !isLoading, let brightness = status.brightness {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(liveColor.opacity(status.isOn ? 0.22 : 0.08))
                                .frame(width: geometry.size.width * brightness / 100.0)
                                .animation(.easeInOut(duration: 0.4), value: brightness)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .shadow(color: status.isOn ? liveColor.opacity(0.25) : .clear, radius: 8, y: 2)
        }
        .animation(.snappy(duration: 0.3), value: status.isOn)
        .skeletonLoader(isActive: isLoading)
    }

    private func brightnessText(_ brightness: Double?) -> String {
        guard let brightness = brightness else { return "--" }
        if brightness.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(brightness))%"
        }
        return String(format: "%.1f%%", brightness)
    }
}

// MARK: - Array Extension for Average Calculation
extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
