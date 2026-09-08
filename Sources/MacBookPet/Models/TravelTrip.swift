import Foundation

struct TravelTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let destinationName: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let souvenirs: [TravelSouvenir]

    init(
        id: UUID = UUID(),
        destinationName: String,
        startedAt: Date,
        durationSeconds: TimeInterval,
        souvenirs: [TravelSouvenir]
    ) {
        self.id = id
        self.destinationName = destinationName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.souvenirs = souvenirs
    }
}

enum TravelState: Equatable {
    case home
    case traveling(TravelTrip)

    var isTraveling: Bool {
        if case .traveling = self { return true }
        return false
    }

    var activeTrip: TravelTrip? {
        if case .traveling(let trip) = self { return trip }
        return nil
    }
}