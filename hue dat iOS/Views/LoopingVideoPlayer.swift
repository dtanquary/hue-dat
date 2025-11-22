//
//  LoopingVideoPlayer.swift
//  hue dat iOS
//
//  Looping background video player using AVFoundation
//

import SwiftUI
import AVFoundation

struct LoopingVideoPlayer: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        // Frame updates happen automatically in layoutSubviews
    }

    // Custom UIView that properly manages the player layer
    class PlayerView: UIView {
        override class var layerClass: AnyClass {
            return AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
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
