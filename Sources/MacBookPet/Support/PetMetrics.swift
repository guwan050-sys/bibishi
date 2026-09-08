import Foundation

enum PetMetrics {
    static let bodySize: CGFloat = 76
    // Pet body is centered inside the canvas. (canvasWidth − bodySize) / 2
    // for X and (canvasHeight − bodySize) / 2 for Y, so the pet sits in the
    // geometric center regardless of canvas size.
    static let bodyInsetX: CGFloat = (canvasWidth - bodySize) / 2
    static let bodyInsetY: CGFloat = (canvasHeight - bodySize) / 2
    static let canvasWidth: CGFloat = 230
    static let canvasHeight: CGFloat = 250
    static let bodyPadding: CGFloat = 5
    static let bodyContentSize: CGFloat = bodySize - bodyPadding * 2
    static let cornerRadius: CGFloat = 11
    static let fileDropMargin: CGFloat = 26

    static var bodyBoundsInWindow: CGRect {
        CGRect(x: bodyInsetX, y: bodyInsetY, width: bodySize, height: bodySize)
    }
}
