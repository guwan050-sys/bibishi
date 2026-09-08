import SwiftUI

/// Transient popup shown briefly after the pet returns from a trip. Lists
/// the souvenirs the pet brought home and the total count. Mirrors the
/// lifecycle of `PetSpeechBubbleView`: scale-in / fade-in spring, fade-out
/// after a fixed duration.
struct TravelReturnPopupView: View {
    let souvenirs: [TravelSouvenir]

    @State private var opacity: Double = 0
    @State private var verticalOffset: CGFloat = 8
    @State private var scale: CGFloat = 0.85

    var body: some View {
        VStack(spacing: 8) {
            if !souvenirs.isEmpty {
                HStack(spacing: 10) {
                    ForEach(souvenirs) { souvenir in
                        VStack(spacing: 4) {
                            Image(systemName: souvenir.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(rarityColor(souvenir.rarity))
                            Text(souvenir.name)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.black.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
            }
            Text("带回了 \(souvenirs.count) 件宝贝！")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        .opacity(opacity)
        .offset(y: verticalOffset)
        .scaleEffect(scale, anchor: .bottom)
        .onAppear(perform: animateIn)
    }

    private func rarityColor(_ rarity: TravelRarity) -> Color {
        switch rarity {
        case .common:   return Color(red: 0.35, green: 0.50, blue: 0.70)
        case .uncommon: return Color(red: 0.20, green: 0.55, blue: 0.40)
        case .rare:     return Color(red: 0.78, green: 0.50, blue: 0.15)
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
            opacity = 1
            verticalOffset = 0
            scale = 1
        }
    }
}