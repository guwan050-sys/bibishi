import SwiftUI

/// Warehouse section that lists every collectable souvenir the pet
/// can bring back from trips. Used as a sub-page in the warehouse
/// (alongside decoration / food), not as a stand-alone page any more.
struct SouvenirsGridView: View {
    @ObservedObject var travelStore: TravelStore

    static let cardSize: CGFloat = 150

    private let columns = [
        GridItem(.adaptive(minimum: Self.cardSize, maximum: Self.cardSize + 30), spacing: 18)
    ]

    var body: some View {
        let totalCollected = SouvenirCatalog.all.reduce(0) { acc, s in
            acc + (travelStore.count(of: s.id) > 0 ? 1 : 0)
        }

        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.brown.opacity(0.7))
                    Text("已收集：\(totalCollected) / \(SouvenirCatalog.all.count)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.brown)
                }
                .padding(.top, 6)

                if totalCollected == 0 {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(SouvenirCatalog.all) { souvenir in
                            SouvenirCard(
                                souvenir: souvenir,
                                count: travelStore.count(of: souvenir.id)
                            )
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.brown.opacity(0.35))
            Text("还没有宝贝")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.brown.opacity(0.7))
            Text("右键宠物 → 去旅行，带些宝贝回来")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.brown.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct SouvenirCard: View {
    let souvenir: TravelSouvenir
    let count: Int
    @State private var isHovering = false

    private var isCollected: Bool { count > 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.96, blue: 0.89))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.brown.opacity(0.30), lineWidth: 1)
                    )
                Image(systemName: souvenir.symbol)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(isCollected ? rarityColor : Color.brown.opacity(0.25))
            }
            .frame(width: SouvenirsGridView.cardSize * 0.85, height: SouvenirsGridView.cardSize * 0.85)
            .shadow(color: .black.opacity(isHovering && isCollected ? 0.18 : 0.08), radius: isHovering ? 8 : 4, x: 0, y: isHovering ? 4 : 2)

            Text(souvenir.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isCollected ? Color.primary : Color.secondary.opacity(0.6))

            Text(isCollected ? "× \(count)" : rarityName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isCollected ? .brown.opacity(0.65) : .brown.opacity(0.35))
        }
        .opacity(isCollected ? 1.0 : 0.55)
        .scaleEffect(isHovering ? 1.04 : 1)
        .onHover { hovering in
            if isCollected { isHovering = hovering }
        }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    private var rarityName: String {
        switch souvenir.rarity {
        case .common:   return "未发现"
        case .uncommon: return "稀有"
        case .rare:     return "传说"
        }
    }

    private var rarityColor: Color {
        switch souvenir.rarity {
        case .common:   return Color(red: 0.35, green: 0.50, blue: 0.70)
        case .uncommon: return Color(red: 0.20, green: 0.55, blue: 0.40)
        case .rare:     return Color(red: 0.78, green: 0.50, blue: 0.15)
        }
    }
}
