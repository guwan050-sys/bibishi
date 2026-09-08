import SwiftUI

/// 桌宠工作时的可爱表情气泡：圆角图标 + 可选文字。
/// 比 PetSpeechBubbleView 更"道具感"——显示在 Cube 头顶，用于表达专注、喝咖啡、记笔记、想到主意、完成庆祝。
///
/// 简化：之前尝试在气泡上加 ✓ / × 按钮（SwiftUI Button / onTapGesture / NSPanel+NSButton
/// 三套方案），全部命中 NSHostingView 的 hit test 硬伤。改成最朴素的方案：
/// 气泡整个可点 → onTap 由调用方决定（待办气泡时 = 弹开待办窗口）。
/// 用户在待办窗口里点 ✓ 或 删除 → MacBookPetApp 监听 tasks 变化清气泡。
struct PetWorkingBubbleView: View {
    let bubble: PetWorkingBubble
    var onTap: (() -> Void)? = nil

    @State private var opacity: Double = 0
    @State private var verticalOffset: CGFloat = 10
    @State private var scale: CGFloat = 0.7

    var body: some View {
        bubbleBody
            .opacity(opacity)
            .offset(y: verticalOffset)
            .scaleEffect(scale)
            .onAppear(perform: animateIn)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        HStack(spacing: 6) {
            Image(systemName: bubble.mood.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PetMenuCardPalette.cocoa)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(moodBackground)
                )
            if let text = bubble.text {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PetMenuCardPalette.cocoa)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PetMenuCardPalette.blush.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PetMenuCardPalette.cocoa.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: PetMenuCardPalette.cocoa.opacity(0.18), radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var moodBackground: Color {
        switch bubble.mood {
        case .focusing:
            return PetMenuCardPalette.softCoral.opacity(0.5)
        case .sipping:
            return PetMenuCardPalette.bisque
        case .note:
            return PetMenuCardPalette.blush
        case .idea:
            return Color.yellow.opacity(0.4)
        case .celebrating:
            return Color.pink.opacity(0.35)
        case .reminder:
            return Color.orange.opacity(0.35)
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            opacity = 1
            verticalOffset = 0
            scale = 1
        }
    }
}
