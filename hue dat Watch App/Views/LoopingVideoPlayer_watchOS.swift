//
//  LoopingVideoPlayer_watchOS.swift
//  hue dat Watch App
//
//  Looping background video player for watchOS using AVFoundation
//

import SwiftUI
import AVFoundation
import AVKit

struct LoopingVideoPlayer_watchOS: View {
    let player: AVPlayer

    // Detect if running in Xcode preview mode
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        if isPreview {
            // Preview fallback - simple gradient to avoid preview crashes
            LinearGradient(
                colors: [Color.primary, Color.blue.opacity(0.3), Color.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        } else {
            // Real device/simulator - use actual video player
            GeometryReader { geometry in
                VideoPlayer(player: player)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .aspectRatio(contentMode: .fill)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .allowsHitTesting(false) // Disable user interaction with video controls
                    .onAppear {
                        // Ensure video plays when view appears
                        if player.rate == 0 {
                            player.play()
                            print("🎬 VideoPlayer appeared - starting playback")
                        }
                    }
            }
            .clipped()
            .ignoresSafeArea()
        }
    }

    // Static helper to load video from asset catalog
    static func loadVideoURL(named name: String) -> URL? {
        guard let asset = NSDataAsset(name: name) else {
            print("Error: Could not find video asset '\(name)' in asset catalog")
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).mp4")

        do {
            try asset.data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error: Could not write video data to temporary file: \(error)")
            return nil
        }
    }
}
