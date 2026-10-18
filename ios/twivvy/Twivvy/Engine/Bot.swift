import Foundation

enum Difficulty: String, CaseIterable, Codable, Sendable { case easy, medium, hard }
enum Bot {
    static func moves(_ state: BoardState) -> [Command?] {
        [nil] + (0..<9).flatMap { p in [-1, 1].map { Command(platform: p, dir: $0) } }.filter { Rules.valid($0, in: state) }.map(Optional.some)
    }
    static func evaluate(_ state: BoardState) -> Double {
        Double(state.score.top-state.score.bottom)*100 + state.balls.reduce(0) { $0 + Double(5-2*$1.row)*0.6 }
    }
    static func forecast(_ state: BoardState, _ top: Command?, _ bottom: Command?, depth: Int) -> Double {
        var future = state
        Rules.resolve(&future, top: top, bottom: bottom)
        var score = evaluate(future)
        for i in 1..<depth where !future.finished {
            Rules.resolve(&future, top: nil, bottom: nil)
            score += evaluate(future)*pow(0.8, Double(i))
        }
        return score
    }
    static func choose(_ state: BoardState, difficulty: Difficulty) -> Command? {
        let legal = moves(state)
        if difficulty == .easy { return legal.randomElement() ?? nil }
        var best = -Double.infinity, chosen: Command?
        for move in legal {
            let value: Double
            if difficulty == .hard {
                let outcomes = legal.map { forecast(state, move, $0, depth: 4) }
                value = outcomes.min()! * 0.65 + outcomes.reduce(0,+)/Double(outcomes.count)*0.35
            } else { value = forecast(state, move, nil, depth: 3) }
            if value > best { best = value; chosen = move }
        }
        return chosen
    }
}
