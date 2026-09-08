import AppKit

enum MenuStyle: String, CaseIterable, Hashable {
    case `default`
    case liquidGlass
    case dark
    case light

    static let selectableCases: [MenuStyle] = [.default, .dark, .light]

    var menuAppearance: NSAppearance? {
        switch self {
        case .default:
            nil
        case .liquidGlass:
            NSAppearance(named: .vibrantLight)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .light:
            NSAppearance(named: .aqua)
        }
    }
}
