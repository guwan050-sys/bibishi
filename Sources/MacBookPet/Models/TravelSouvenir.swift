import Foundation

enum TravelRarity: String, Codable, CaseIterable {
    case common
    case uncommon
    case rare

    /// Probability weight used when rolling a random souvenir.
    /// Wider pool or rarer tiers should use smaller weights.
    var weight: Double {
        switch self {
        case .common: 0.6
        case .uncommon: 0.3
        case .rare: 0.1
        }
    }
}

struct TravelSouvenir: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let rarity: TravelRarity

    init(id: String, name: String, symbol: String, rarity: TravelRarity) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.rarity = rarity
    }
}