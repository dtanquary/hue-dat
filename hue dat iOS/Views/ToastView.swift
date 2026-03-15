//
//  ToastView.swift
//  hue dat iOS
//
//  Toast notification modifier for success messages
//

import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isShowing {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .font(.body)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .onChange(of: isShowing) { _, newValue in
            if newValue {
                // Auto-dismiss after 2 seconds
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}

#Preview {
    struct ToastPreview: View {
        @State private var showToast = false

        var body: some View {
            VStack {
                Button("Show Toast") {
                    withAnimation {
                        showToast = true
                    }
                }
            }
            .toast(isShowing: $showToast, message: "Scene 'Bright' applied")
        }
    }

    return ToastPreview()
}
