import Foundation

enum SouvenirCatalog {
    /// All possible souvenirs. Displayed (greyed when uncollected) in the
    /// "收集品" tab of MyPetsView.
    static let all: [TravelSouvenir] = [
        // common (6)
        TravelSouvenir(id: "leaf",      name: "幸运叶",     symbol: "leaf.fill",          rarity: .common),
        TravelSouvenir(id: "fish",      name: "小鱼",       symbol: "fish.fill",          rarity: .common),
        TravelSouvenir(id: "ladybug",   name: "小瓢虫",     symbol: "ladybug.fill",       rarity: .common),
        TravelSouvenir(id: "drop",      name: "露珠",       symbol: "drop.fill",          rarity: .common),
        TravelSouvenir(id: "flame",     name: "萤火",       symbol: "flame.fill",         rarity: .common),
        TravelSouvenir(id: "sparkles",  name: "碎星",       symbol: "sparkles",           rarity: .common),
        // uncommon (4)
        TravelSouvenir(id: "mountain",  name: "山纹石",      symbol: "mountain.2.fill",     rarity: .uncommon),
        TravelSouvenir(id: "globe",     name: "微缩地球",    symbol: "globe.americas.fill", rarity: .uncommon),
        TravelSouvenir(id: "moon",      name: "月光碎片",    symbol: "moon.stars.fill",     rarity: .uncommon),
        TravelSouvenir(id: "snowflake", name: "六角雪晶",    symbol: "snowflake",           rarity: .uncommon),
        // rare (2)
        TravelSouvenir(id: "tornado",   name: "风暴之眼",    symbol: "tornado",             rarity: .rare),
        TravelSouvenir(id: "crown",     name: "王冠贝壳",    symbol: "crown.fill",          rarity: .rare)
    ]

    static func souvenir(id: String) -> TravelSouvenir? {
        all.first(where: { $0.id == id })
    }
}