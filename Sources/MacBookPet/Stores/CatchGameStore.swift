import Foundation
import SwiftUI

/// "摇摇乐" — catch the cube mid-air before it hits the floor.
///
/// Game flow:
/// 1. The user starts the game from the status-bar menu (`指挥比比十`
///    submenu → 摇摇乐). The cube gets a small upward kick and the
///    player must click on every bounce to keep it airborne.
/// 2. Each successful click scores 1 point and the cube is given a
///    fresh upward kick.
/// 3. The game ends the instant the cube reaches the catch line (a
///    few pixels above the floor) without a click in time.
///
/// All scoring and phase transitions are kept inside this store so
/// the view layer only has to read `@Published` state and present a
/// HUD. Physics-side integration is one method call each: record a
/// catch, and game-over on floor touch.
@MainActor
final class CatchGameStore: ObservableObject {
    private static let bestScoreKey = "MacBookPet.catchGame.bestScore"

    enum Phase: Equatable {
        case idle
        case playing
        case gameOver
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var score: Int = 0
    @Published private(set) var lastCatchBonus: Int = 0
    @Published private(set) var bestScore: Int = 0

    /// When true, the physics controller is in catch-game mode: the
    /// floor is a game-over trigger instead of a normal bounce, and
    /// mouse clicks on the cube are routed to `attemptCatch(bodyY:)`.
    var isActive: Bool { phase != .idle }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bestScore = defaults.integer(forKey: Self.bestScoreKey)
    }

    // MARK: - Lifecycle

    /// Start a fresh game. Resets score and flips into `.playing`.
    /// The caller (physics controller) is responsible for giving the
    /// cube the opening kick — this store only manages the score /
    /// phase state.
    func startGame() {
        score = 0
        lastCatchBonus = 0
        phase = .playing
    }

    /// Add 1 point to the score for a successful catch — either a
    /// tap on the cube or a drag-release that kept it airborne.
    /// No-op if we are not currently in `.playing`.
    func recordCatch() {
        guard phase == .playing else { return }
        score += 1
        lastCatchBonus = 1
        if score > bestScore {
            bestScore = score
            defaults.set(bestScore, forKey: Self.bestScoreKey)
        }
    }

    /// Triggered by the physics controller when the cube touches
    /// the catch line without a click in time. No-op if we are not
    /// currently in `.playing`.
    func gameOver() {
        guard phase == .playing else { return }
        phase = .gameOver
    }

    /// Cleanly leave the game. Called from the HUD's "返回" button
    /// or automatically after a few seconds in the game-over state.
    func dismiss() {
        phase = .idle
        score = 0
        lastCatchBonus = 0
    }

    /// Re-arm from the game-over screen.
    func restart() {
        startGame()
    }

    // MARK: - Tuning
}
