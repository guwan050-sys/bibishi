import Combine
import Foundation

/// Per-pet speech line configuration. Lines pool is what the user filled in.
struct PetSpeechConfig: Codable, Equatable {
    var lines: [String]
    var enabled: Bool

    init(lines: [String] = [], enabled: Bool = true) {
        self.lines = lines
        self.enabled = enabled
    }
}

/// A single line currently being shown above the pet. `id` is fresh per show
/// so SwiftUI views can use `.id(line.id)` to restart their entry animation.
struct DisplayedSpeechLine: Equatable, Identifiable {
    let id: UUID
    let text: String

    init(text: String) {
        self.id = UUID()
        self.text = text
    }
}

/// Owns per-pet speech line pools (persisted to Application Support JSON) and
/// exposes the currently-displayed line for `PetView` to render.
///
/// One store doubles as both the data layer and the view-model so callers
/// (the click handler) only need to talk to a single object.
@MainActor
final class PetSpeechLineStore: ObservableObject {
    @Published private(set) var configs: [String: PetSpeechConfig] = [:]

    /// `nil` means "nothing is being shown right now". The view layer binds to
    /// this and shows the bubble whenever it becomes non-nil.
    @Published private(set) var displayedLine: DisplayedSpeechLine?

    private let fileURL: URL?
    private let fileManager: FileManager
    private var hideTask: Task<Void, Never>?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("CubePet", isDirectory: true)
        self.fileURL = appSupport?.appendingPathComponent("speech_lines.json")
        load()
    }

    // MARK: - Configuration API

    func setLines(_ lines: [String], for petID: String) {
        configs[petID] = PetSpeechConfig(lines: lines)
        save()
    }

    func setEnabled(_ enabled: Bool, for petID: String) {
        var cfg = configs[petID] ?? PetSpeechConfig()
        cfg.enabled = enabled
        configs[petID] = cfg
        save()
    }

    /// Seeds defaults the first time we see a pet. Later edits are respected.
    func ensureDefaults(for petID: String, defaults: [String]) {
        guard configs[petID] == nil else { return }
        setLines(defaults, for: petID)
    }

    // MARK: - Display API

    /// Picks a random line from the pool for `petID` and publishes it for the
    /// view layer. Calling again while a bubble is still visible replaces it
    /// (and resets the auto-hide timer).
    func showRandomLine(for petID: String, duration: TimeInterval = 2.5) {
        guard let cfg = configs[petID], cfg.enabled, !cfg.lines.isEmpty,
              let line = cfg.lines.randomElement() else {
            return
        }
        displayedLine = DisplayedSpeechLine(text: line)
        scheduleHide(after: duration)
    }

    func dismissImmediately() {
        hideTask?.cancel()
        hideTask = nil
        displayedLine = nil
    }

    // MARK: - Internals

    private func scheduleHide(after duration: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.displayedLine = nil
            }
        }
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: PetSpeechConfig].self, from: data)
        else { return }
        configs = decoded
    }

    private func save() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(configs) else { return }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    deinit {
        hideTask?.cancel()
    }
}
