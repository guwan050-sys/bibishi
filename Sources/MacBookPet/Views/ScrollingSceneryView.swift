import SwiftUI

/// Minimalist scrolling ground shown behind the pet during travel.
/// Driven by an external TimelineView so we don't add a second 60Hz
/// timer to the app.
///
/// The scene is intentionally pared down to a thin grass strip at the
/// bottom of the canvas. No sky, no scenery — just a short ground
/// band with blades and pebbles that scroll horizontally to convey
/// motion. The static grass gradient stays put; only the foreground
/// details sweep past under the pet's feet.
struct ScrollingSceneryView: View {
    let date: Date
    let startedAt: Date

    /// Speed of the foreground grass details. 90pt/s → one full tile
    /// (230pt) per ~2.6s — slow enough that the loop is clearly
    /// readable as a loop, not a blur.
    private static let grassDetailSpeed: CGFloat = 90

    /// Tile width = canvas width. Same content is rendered in two
    /// adjacent tiles and `moduloNegative(_:)` keeps the offset in
    /// `(-tileWidth, 0]` so a single cycle from `0` to `-tileWidth`
    /// is pixel-identical to the next.
    private static let tileWidth: CGFloat = PetMetrics.canvasWidth

    /// Height of the ground strip. The strip's top edge sits flush
    /// against the bottom of the pet body, so the pet appears to
    /// stand on the grass rather than float above an empty canvas.
    private static let groundHeight: CGFloat = 22

    /// Y position of the ground strip's top edge. = bodyInsetY +
    /// bodySize, i.e. exactly the bottom of the centered pet body.
    private static var groundTopY: CGFloat {
        PetMetrics.bodyInsetY + PetMetrics.bodySize
    }

    /// Y position (center) of the ground strip, used by `.position`.
    private static var groundCenterY: CGFloat {
        groundTopY + groundHeight / 2
    }

    /// Blade geometry: 9 triangles per tile, period 28pt, width 6pt.
    /// Last blade starts at x=224 and ends at x=230 — exactly the
    /// tile boundary — so two adjacent tiles match pixel-perfect.
    private static let bladeCount = 9
    private static let bladePeriod: CGFloat = 28

    /// Pebble geometry: 10 per tile, period 23pt, width 4pt, offset
    /// 19pt so the first pebble lands mid-gap between blades 0 and 1.
    /// Last pebble ends at x=230 — same boundary guarantee.
    private static let pebbleCount = 10
    private static let pebblePeriod: CGFloat = 23
    private static let pebbleOffset: CGFloat = 19

    var body: some View {
        let elapsed = CGFloat(max(0, date.timeIntervalSince(startedAt)))

        ZStack(alignment: .bottom) {
            // Static grass gradient — does NOT move. Forms the
            // visible ground the pet stands on. Top edge sits flush
            // against the bottom of the centered pet body.
            grassBase
                .frame(width: PetMetrics.canvasWidth, height: Self.groundHeight)
                .position(
                    x: Self.tileWidth / 2,
                    y: Self.groundCenterY
                )

            grassDetails(offset: moduloNegative(elapsed * Self.grassDetailSpeed))
                .frame(width: Self.tileWidth, height: Self.groundHeight)
                .position(
                    x: Self.tileWidth / 2,
                    y: Self.groundCenterY
                )
        }
        .frame(width: PetMetrics.canvasWidth, height: PetMetrics.canvasHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Grass base (static gradient)

    private var grassBase: some View {
        LinearGradient(
            colors: [
                Color(red: 0.45, green: 0.72, blue: 0.38),
                Color(red: 0.32, green: 0.58, blue: 0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Grass details (near) — blades and pebbles

    private func grassDetails(offset: CGFloat) -> some View {
        Canvas { context, size in
            // Blades: small triangles rooted at the bottom of the
            // strip. Two adjacent tiles share the same coordinate
            // list so the offset loop is seamless.
            for tileIndex in 0...1 {
                let tileOffsetX = CGFloat(tileIndex) * size.width
                for i in 0..<Self.bladeCount {
                    let x = CGFloat(i) * Self.bladePeriod + tileOffsetX
                    var blade = Path()
                    blade.move(to: CGPoint(x: x, y: size.height))
                    blade.addLine(to: CGPoint(x: x + 3, y: size.height - 6))
                    blade.addLine(to: CGPoint(x: x + 6, y: size.height))
                    blade.closeSubpath()
                    let color = i.isMultiple(of: 2)
                        ? Color(red: 0.42, green: 0.68, blue: 0.34).opacity(0.95)
                        : Color(red: 0.34, green: 0.58, blue: 0.28).opacity(0.95)
                    context.fill(blade, with: .color(color))
                }
            }

            // Pebbles: small ellipses, one per ~2 blade slots.
            for tileIndex in 0...1 {
                let tileOffsetX = CGFloat(tileIndex) * size.width
                for i in 0..<Self.pebbleCount {
                    let x = CGFloat(i) * Self.pebblePeriod + Self.pebbleOffset + tileOffsetX
                    let pebble = Path(
                        ellipseIn: CGRect(x: x, y: size.height - 5, width: 4, height: 2)
                    )
                    context.fill(pebble, with: .color(Color(red: 0.55, green: 0.50, blue: 0.40).opacity(0.85)))
                }
            }
        }
        .offset(x: offset)
    }

    // MARK: - Helpers

    /// Wraps `value` into the range `(-tileWidth, 0]` so the layer
    /// appears to scroll forever when paired with 2×-wide rendering.
    /// A single cycle from `0` to `-tileWidth` is the loop unit.
    private func moduloNegative(_ value: CGFloat) -> CGFloat {
        let w = Self.tileWidth
        let remainder = value.truncatingRemainder(dividingBy: w)
        return remainder > 0 ? remainder - w : remainder
    }
}
