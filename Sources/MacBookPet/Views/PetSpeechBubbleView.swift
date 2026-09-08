import SwiftUI

/// Speech bubble shown above the pet when a line is displayed.
/// Animates in (scale + fade + rise), holds, then animates out.
///
/// The view re-runs its `onAppear` animation whenever its `id` changes, so
/// callers should attach a fresh `.id(...)` per show to restart the entry
/// animation when the same bubble is replaced with a new one.
struct PetSpeechBubbleView: View {
    let text: String
    var tailAlignment: Alignment = .bottom

    @State private var opacity: Double = 0
    @State private var verticalOffset: CGFloat = 6
    @State private var scale: CGFloat = 0.85
    @State private var dismissWorkItem: DispatchWorkItem?

    var body: some View {
        bubbleBody
            .frame(maxWidth: 220, alignment: .center)
            .opacity(opacity)
            .offset(y: verticalOffset)
            .scaleEffect(scale, anchor: tailAlignment == .top ? .top : .bottom)
            .onAppear(perform: animateIn)
            .onDisappear(perform: cancelScheduledDismiss)
    }

    private var bubbleBody: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
            opacity = 1
            verticalOffset = 0
            scale = 1
        }
        let work = DispatchWorkItem { animateOut() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func animateOut() {
        withAnimation(.easeOut(duration: 0.35)) {
            opacity = 0
            verticalOffset = -8
            scale = 0.95
        }
    }

    private func cancelScheduledDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}
