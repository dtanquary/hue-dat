//
//  HighlightedText.swift
//  hue dat iOS
//
//  Text view that highlights matching substrings in bold
//

import SwiftUI

struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)

        guard !highlight.isEmpty else {
            return attributed
        }

        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let range = lowercasedText.range(
            of: lowercasedHighlight,
            range: searchRange
        ) {
            // Convert String.Index to AttributedString.Index
            if let start = AttributedString.Index(range.lowerBound, within: attributed),
               let end = AttributedString.Index(range.upperBound, within: attributed) {
                let attributedRange = start..<end

                // Make this range bold
                attributed[attributedRange].font = .body.bold()
            }

            // Continue searching after this match
            searchRange = range.upperBound..<lowercasedText.endIndex
        }

        return attributed
    }
}

#Preview {
    VStack(spacing: 20) {
        HighlightedText(text: "Bedroom", highlight: "bed")
        HighlightedText(text: "Master Bedroom", highlight: "bed")
        HighlightedText(text: "Living Room", highlight: "living")
        HighlightedText(text: "Kitchen", highlight: "")
    }
    .padding()
}
