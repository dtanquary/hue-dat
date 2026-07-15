//
//  PanelHeader.swift
//  hue dat macOS
//
//  Shared glass header bar for panel views. NavigationStack toolbars do not
//  render inside an NSPopover-hosted hierarchy, so each destination view
//  provides this header via .safeAreaInset(edge: .top) (scroll content slides
//  under the glass) or as the first row of a fixed layout.
//

import SwiftUI

struct PanelHeader<Accessories: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsBack: Bool = false
    var searchText: Binding<String>? = nil
    @ViewBuilder var accessories: () -> Accessories

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if showsBack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .headerButtonHover()
                    .help("Back")
                    .accessibilityLabel("Back")
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                accessories()
            }

            if let searchText {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Search rooms, zones & scenes", text: searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)

                    if !searchText.wrappedValue.isEmpty {
                        Button {
                            searchText.wrappedValue = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(in: .rect)
    }
}

// MARK: - Header Button Hover

/// Shared hover highlight for borderless icon buttons in panel headers.
/// (.accessoryBar and toolbar styles don't receive clicks inside an NSPopover.)
struct HeaderButtonHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(5)
            .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0)))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func headerButtonHover() -> some View {
        modifier(HeaderButtonHover())
    }
}

extension PanelHeader where Accessories == EmptyView {
    init(title: String, subtitle: String? = nil, showsBack: Bool = false, searchText: Binding<String>? = nil) {
        self.init(title: title, subtitle: subtitle, showsBack: showsBack, searchText: searchText) {
            EmptyView()
        }
    }
}
