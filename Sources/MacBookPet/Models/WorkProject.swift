import Foundation

enum WorkProjectID: String, Codable, CaseIterable {
    case softwareCopyright
    case prototypeDesign
    case coding
    case videoEditing

    var displayName: String {
        switch self {
        case .softwareCopyright: "写软著"
        case .prototypeDesign: "画原型"
        case .coding: "写代码"
        case .videoEditing: "剪视频"
        }
    }

    var iconSystemSymbol: String {
        switch self {
        case .softwareCopyright: "doc.text.fill"
        case .prototypeDesign: "scribble.variable"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .videoEditing: "scissors"
        }
    }
}

struct WorkProject: Identifiable, Hashable {
    let id: WorkProjectID
    let displayName: String
    let iconSystemSymbol: String
    let requiredLevel: Int
    let coinMultiplier: Double
    let hungerMultiplier: Double

    var multiplierSummary: String {
        let coinText = String(format: "%.1f×", coinMultiplier)
        let hungerText = String(format: "%.1f×", hungerMultiplier)
        return "金币 \(coinText) · 饱腹 \(hungerText)"
    }
}

enum WorkCatalog {
    static let projects: [WorkProject] = [
        WorkProject(
            id: .softwareCopyright,
            displayName: WorkProjectID.softwareCopyright.displayName,
            iconSystemSymbol: WorkProjectID.softwareCopyright.iconSystemSymbol,
            requiredLevel: 1,
            coinMultiplier: 1.5,
            hungerMultiplier: 1.5
        ),
        WorkProject(
            id: .prototypeDesign,
            displayName: WorkProjectID.prototypeDesign.displayName,
            iconSystemSymbol: WorkProjectID.prototypeDesign.iconSystemSymbol,
            requiredLevel: 5,
            coinMultiplier: 2.0,
            hungerMultiplier: 2.0
        ),
        WorkProject(
            id: .coding,
            displayName: WorkProjectID.coding.displayName,
            iconSystemSymbol: WorkProjectID.coding.iconSystemSymbol,
            requiredLevel: 15,
            coinMultiplier: 3.0,
            hungerMultiplier: 2.5
        ),
        WorkProject(
            id: .videoEditing,
            displayName: WorkProjectID.videoEditing.displayName,
            iconSystemSymbol: WorkProjectID.videoEditing.iconSystemSymbol,
            requiredLevel: 20,
            coinMultiplier: 4.5,
            hungerMultiplier: 3.0
        )
    ]

    static func project(id: WorkProjectID) -> WorkProject? {
        projects.first { $0.id == id }
    }
}