import Foundation

@MainActor
final class TravelStore: ObservableObject {
    private static let historyKey = "MacBookPet.travelHistory"
    private static let collectedCountsKey = "MacBookPet.travelCollectedCounts"
    private static let maxHistoryEntries = 20

    /// Min/max trip duration in seconds. Matches plan: 3-8 minutes.
    private static let minDuration: TimeInterval = 180
    private static let maxDuration: TimeInterval = 480

    /// Minimum actual elapsed time before the trip counts as a real
    /// excursion and the pet is allowed to bring back souvenirs.
    /// Trips shorter than this (typically because the user ended them
    /// early) get no souvenirs and no "brought back" popup.
    private static let minDurationForSouvenir: TimeInterval = 300

    /// Auto-dismiss delay for the "brought back" popup.
    private static let returnPopupDuration: TimeInterval = 4.0

    private static let destinations = [
        "月光森林",
        "云海草原",
        "贝壳海湾",
        "樱花山谷",
        "极光雪原"
    ]

    @Published private(set) var state: TravelState = .home
    @Published private(set) var lastReturnSouvenirs: [TravelSouvenir]?
    @Published private(set) var tripHistory: [TravelTrip]
    @Published private(set) var collectedCounts: [String: Int]

    private let defaults: UserDefaults
    private var completionTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.tripHistory = Self.decode(defaults.data(forKey: Self.historyKey), as: [TravelTrip].self) ?? []
        self.collectedCounts = Self.decode(defaults.data(forKey: Self.collectedCountsKey), as: [String: Int].self) ?? [:]
    }

    deinit {
        completionTimer?.invalidate()
    }

    /// Begin a new trip. No-op when already traveling.
    func startTrip(now: Date = Date()) {
        guard !state.isTraveling else { return }

        let duration = TimeInterval.random(in: Self.minDuration...Self.maxDuration)
        let destination = Self.destinations.randomElement() ?? "远方"
        let trip = TravelTrip(
            destinationName: destination,
            startedAt: now,
            durationSeconds: duration,
            souvenirs: []
        )
        state = .traveling(trip)

        completionTimer?.invalidate()
        completionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.completeTrip()
            }
        }
    }

    /// Manually end the current trip early (e.g. for testing). No-op when not
    /// traveling.
    func endTripEarly() {
        guard state.isTraveling else { return }
        completionTimer?.invalidate()
        completionTimer = nil
        completeTrip()
    }

    /// Clears `lastReturnSouvenirs` so SwiftUI views stop rendering the popup.
    /// Called automatically after the popup duration; safe to call manually.
    func consumeReturnPopup() {
        lastReturnSouvenirs = nil
    }

    /// Number of times a souvenir has been collected across all trips.
    func count(of souvenirID: String) -> Int {
        collectedCounts[souvenirID] ?? 0
    }

    private func completeTrip(now: Date = Date()) {
        guard let activeTrip = state.activeTrip else { return }
        completionTimer?.invalidate()
        completionTimer = nil

        let elapsed = now.timeIntervalSince(activeTrip.startedAt)
        // Only hand out souvenirs if the pet actually traveled long
        // enough. End-trip-early within `minDurationForSouvenir` is
        // treated as a quick detour that produced nothing.
        let gotSouvenirs = elapsed >= Self.minDurationForSouvenir

        let souvenirs: [TravelSouvenir] = gotSouvenirs ? Self.rollSouvenirs() : []
        let finishedTrip = TravelTrip(
            id: activeTrip.id,
            destinationName: activeTrip.destinationName,
            startedAt: activeTrip.startedAt,
            durationSeconds: elapsed,
            souvenirs: souvenirs
        )

        tripHistory.insert(finishedTrip, at: 0)
        if tripHistory.count > Self.maxHistoryEntries {
            tripHistory = Array(tripHistory.prefix(Self.maxHistoryEntries))
        }
        if gotSouvenirs {
            for souvenir in souvenirs {
                collectedCounts[souvenir.id, default: 0] += 1
            }
        }

        state = .home
        lastReturnSouvenirs = gotSouvenirs ? souvenirs : nil
        persist()

        if gotSouvenirs {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnPopupDuration) { [weak self] in
                self?.consumeReturnPopup()
            }
        }
    }

    private func persist() {
        if let historyData = try? JSONEncoder().encode(tripHistory) {
            defaults.set(historyData, forKey: Self.historyKey)
        }
        if let countsData = try? JSONEncoder().encode(collectedCounts) {
            defaults.set(countsData, forKey: Self.collectedCountsKey)
        }
    }

    // MARK: - Souvenir rolling

    /// Weighted pick 1-3 souvenirs. Duplicates are allowed within one trip
    /// but rarity weights mean stacking rares is very unlikely.
    private static func rollSouvenirs() -> [TravelSouvenir] {
        let count = Int.random(in: 1...3)
        var picks: [TravelSouvenir] = []
        picks.reserveCapacity(count)
        for _ in 0..<count {
            picks.append(weightedRandomPick())
        }
        return picks
    }

    private static func weightedRandomPick() -> TravelSouvenir {
        let totalWeight = SouvenirCatalog.all.reduce(0.0) { $0 + $1.rarity.weight }
        var roll = Double.random(in: 0..<totalWeight)
        for souvenir in SouvenirCatalog.all {
            roll -= souvenir.rarity.weight
            if roll <= 0 { return souvenir }
        }
        return SouvenirCatalog.all.last!
    }

    private static func decode<T: Decodable>(_ data: Data?, as type: T.Type) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}