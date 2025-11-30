//
//  AboutView_iOS.swift
//  Modern About Page - iOS 26+ / macOS Tahoe
//
//  Follows Apple's Liquid Glass design system and WWDC25 guidelines
//

import SwiftUI

// MARK: - About View

struct AboutView_iOS: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .background(backgroundGradient)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem() {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .glassEffect(.clear)
                }
                
            }
        }
    }
    
    // MARK: - Compact Layout (iPhone)
    
    private var compactLayout: some View {
        VStack(spacing: 32) {
            appIconSection
            appInfoSection
            featuresSection
            limitationsSection
            // footerSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
    
    // MARK: - Regular Layout (iPad)
    
    private var regularLayout: some View {
        VStack(spacing: 40) {
            HStack(alignment: .top, spacing: 48) {
                VStack(spacing: 24) {
                    appIconSection
                    footerSection
                }
                .frame(maxWidth: 280)
                
                VStack(alignment: .leading, spacing: 32) {
                    appInfoSection
                    
                    HStack(alignment: .top, spacing: 32) {
                        featuresSection
                        limitationsSection
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
        }
        .frame(maxWidth: 900)
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - App Icon Section

private extension AboutView_iOS {
    var appIconSection: some View {
        VStack(spacing: 16) {
            // App Icon Placeholder
            // Replace with your actual app icon asset
            appIconPlaceholder
            
            VStack(spacing: 4) {
                Text("Hue Dat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0 (Build 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    var appIconPlaceholder: some View {
        // Replace "AppIcon" with your actual app icon asset name
        // Or use Image("AppIcon") for a custom image asset
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.secondary, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ).opacity(0.5)
            
            Image("hueDatLight")
                .opacity(0.5)
                .font(.system(size: 44, weight: .medium))
                .offset(y: 50)
            
            Image("hueDatLight")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
        }
        .frame(width: 100, height: 100)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        // iOS 26+ Liquid Glass effect (commented for backward compatibility)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

// MARK: - App Info Section

private extension AboutView_iOS {
    var appInfoSection: some View {
        VStack(alignment: isCompact ? .leading : .leading, spacing: 12) {
            Label("What is this?", systemImage: "questionmark.circle.fill")
                .font(.headline)
            
            Text("A minimalistic way to access basic room, zone, and scene functionalities for Philips Hue lights.\n\nThis application also includes versions for WatchOS and MacOS which were my original primary focus.\n\nThe iPhone and iPad versions are relatively pointless. They were more an exercise in 'can I make a cool iOS app'.")
                .font(.body)
                .multilineTextAlignment(isCompact ? .leading : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .padding()
        .glassEffect(in: .rect(cornerRadius: 24))
    }
}

// MARK: - Features Section

private extension AboutView_iOS {
    var featuresSection: some View {
        AboutCardViewLiquidGlass(
            title: "What Does This App Do?",
            systemImage: "checkmark.circle.fill",
            tint: .green
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "lightbulb.fill",
                    text: "Basic light functionality (On/Off, brightness adjustments, applying scenes) to rooms or zones."
                )
                FeatureRow(
                    icon: "sparkles",
                    text: "Gives you a MacOS, WatchOS, and iOS app all in one."
                )
//                FeatureRow(
//                    icon: "apple.logo",
//                    text: "Native versions of this application are also available for WatchOS and MacOS"
//                )
            }
        }
    }
}

// MARK: - Limitations Section

private extension AboutView_iOS {
    var limitationsSection: some View {
        AboutCardViewLiquidGlass(
            title: "What This App Doesn't Do:",
            systemImage: "xmark.circle.fill",
            tint: .orange
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "lightbulb.slash.fill",
                    text: "Cannot configure your Philips Hue lights. Use the official app for any adjustments to lights, rooms, or zones."
                )
//                FeatureRow(
//                    icon: "applewatch",
//                    text: "Apple watch version is not just a companion app, its a stand alone version that does not require an iPhone nearby to function."
//                )
                FeatureRow(
                    icon: "person.2.slash.fill",
                    text: "Does not share data with third parties"
                )
                FeatureRow(
                    icon: "bell.slash.fill",
                    text: "Does not send unsolicited notifications"
                )
                FeatureRow(
                    icon: "location.slash.fill",
                    text: "Does not track your location in the background"
                )
            }
        }
    }
}

// MARK: - Footer Section

private extension AboutView_iOS {
    var footerSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, isCompact ? 0 : 20)
            
            VStack(spacing: 8) {
                Link(destination: URL(string: "https://example.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                        .font(.subheadline)
                }
                
                Link(destination: URL(string: "https://example.com/terms")!) {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                        .font(.subheadline)
                }
                
                Link(destination: URL(string: "https://example.com/support")!) {
                    Label("Support & Feedback", systemImage: "questionmark.circle.fill")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            
            Text("© 2025 Your Company Name")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Supporting Views

struct AboutCardView<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        // iOS 26+ Liquid Glass alternative:
//        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - iOS 26+ Liquid Glass Version

/// Use this version when targeting iOS 26+ / macOS Tahoe exclusively
/// Uncomment and replace the standard AboutCardView
@available(iOS 26.0, macOS 26.0, *)
struct AboutCardViewLiquidGlass<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview("iPhone") {
    AboutView_iOS()
}

#Preview("iPad") {
    AboutView_iOS()
        .previewDevice("iPad Pro 11-inch")
}
