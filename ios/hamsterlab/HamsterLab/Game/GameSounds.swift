import Foundation

enum HamsterSound: String, CaseIterable {
    case loss = "loose"
    case minusPoint = "minus_point"
    case plusPoint = "plus_point"
    case turnaround = "return"
    case win
    case oops

    var isResult: Bool { self == .win || self == .loss }

    func files(in bundle: Bundle = .main) -> [URL] {
        (bundle.urls(forResourcesWithExtension:"mp3",subdirectory:"sound") ?? [])
            .filter { url in
                let name=url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix(rawValue + "_") else { return false }
                return Int(name.dropFirst(rawValue.count+1)) != nil
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func result(own: Int, opponent: Int) -> Self? {
        own == opponent ? nil : own > opponent ? .win : .loss
    }

    static func deliveries(_ turn: Turn, side: Side) -> [Self] {
        // One cue per receiver, even if several hamsters arrive together.
        [side,side.opposite].compactMap { receiver in
            turn.delivered.contains { $0.1 == receiver } ? (receiver == side ? .plusPoint : .minusPoint) : nil
        }
    }

    static func hasTurnaround(before: BoardState, after: BoardState, turn: Turn) -> Bool {
        var rotated=before
        rotated.balls.append(contentsOf:turn.spawned)
        for (platform,quarters) in turn.rotations {
            Rules.rotate(&rotated,platform:platform,quarters:quarters)
        }
        return after.balls.contains { ball in
            rotated.balls.contains { $0.id == ball.id && $0.row == ball.row && $0.col == ball.col && $0.exit != ball.exit }
        }
    }
}

/// At most one interjection in a selected thinking round. Repeated online
/// timer/active messages and app resumes must not schedule it a second time.
struct ThinkingSoundSchedule {
    private(set) var nextRound=Int.random(in:7...15)
    private(set) var round: Int?
    private(set) var remainingAtCue: Double?

    mutating func begin(round: Int, remaining: Double) {
        guard self.round != round else { return }
        self.round=round; remainingAtCue=nil
        guard round >= nextRound, remaining > 6 else { return }
        remainingAtCue=Double.random(in:3...min(25,remaining-2))
        nextRound=round+Int.random(in:7...15)
    }

    mutating func takeCue(remaining: Double) -> Bool {
        guard let threshold=remainingAtCue, remaining > 0, remaining <= threshold else { return false }
        remainingAtCue=nil
        return true
    }
}
