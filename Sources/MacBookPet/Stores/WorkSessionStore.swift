import Combine
import Foundation

@MainActor
final class WorkSessionStore: ObservableObject {
    @Published private(set) var activeProject: WorkProject?

    var isWorking: Bool { activeProject != nil }

    /// Returns the multiplier the coin loop should apply for the currently
    /// selected pet. 1.0 when idle so the rest of the app doesn't have to
    /// branch on `isWorking`.
    var currentCoinMultiplier: Double {
        activeProject?.coinMultiplier ?? 1.0
    }

    /// Same idea for hunger decay.
    var currentHungerMultiplier: Double {
        activeProject?.hungerMultiplier ?? 1.0
    }

    func canStart(_ project: WorkProject, currentLevel: Int) -> Bool {
        guard !isWorking else { return false }
        return currentLevel >= project.requiredLevel
    }

    func start(_ project: WorkProject, currentLevel: Int) -> Bool {
        guard canStart(project, currentLevel: currentLevel) else { return false }
        activeProject = project
        return true
    }

    func stop() {
        activeProject = nil
    }
}