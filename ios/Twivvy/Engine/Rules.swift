import Foundation

enum Side: String, Codable, Sendable { case top, bottom
    var opposite: Side { self == .top ? .bottom : .top }
}
struct Command: Codable, Equatable, Sendable {
    let platform: Int
    let dir: Int
}
struct Ball: Codable, Equatable, Sendable {
    var id: Int
    var row: Int
    var col: Int
    var exit: Int
}
struct Score: Codable, Equatable, Sendable {
    var top = 0
    var bottom = 0
    subscript(_ side: Side) -> Int {
        get { side == .top ? top : bottom }
        set { if side == .top { top = newValue } else { bottom = newValue } }
    }
}
struct BoardState: Codable, Equatable, Sendable {
    var rulesVersion = 6
    var map: Int
    var tick = 0
    var cells: [[Int]]
    var balls: [Ball] = []
    var nextBallId = 1
    var score = Score()
    var cooldown: [Int] = []
    var finished = false
    init(map: Int = 0) {
        self.map = ((map % Rules.maps.count) + Rules.maps.count) % Rules.maps.count
        cells = Rules.maps[self.map]
    }
}
struct Turn: Sendable {
    var rotations: [Int: Int] = [:]
    var spawned: [Ball] = []
    var delivered: [(Ball, Side)] = []
}

/// Integer-only rules v6. The browser fixture suite verifies every round of
/// seeded games against js/rules.js, including 32-bit spawn mixing.
enum Rules {
    static let rounds = 30
    static let decideSeconds: Double = 30
    static let spawnTicks = [1, 5, 9, 13, 17, 21]
    static let maps = [
        [[3,6,10,12,9,3],[9,3,12,3,10,10],[0,5,9,3,5,9],[6,5,12,6,5,0],[10,10,12,3,12,6],[12,6,3,10,9,12]],
        [[3,12,6,9,0,3],[6,10,5,0,12,6],[0,3,9,10,9,9],[6,6,10,6,12,0],[9,3,0,5,10,9],[12,0,6,9,3,12]],
        [[10,10,5,5,3,9],[12,5,5,3,12,0],[5,12,5,10,12,10],[10,3,10,5,3,5],[0,3,12,5,5,3],[6,12,5,5,10,10]]
    ]
    static func platform(_ row: Int, _ col: Int) -> Int { row / 2 * 3 + col / 2 }
    static func valid(_ command: Command?, in state: BoardState) -> Bool {
        guard let command else { return true }
        return (0..<9).contains(command.platform) && [-1, 1].contains(command.dir) && !state.cooldown.contains(command.platform)
    }
    static func rotateMask(_ mask: Int, by quarters: Int) -> Int {
        let q = (quarters % 4 + 4) % 4
        return (0..<4).reduce(0) { $0 | ((mask & (1 << $1)) == 0 ? 0 : 1 << (($1 + q) % 4)) }
    }
    static func otherPort(_ mask: Int, _ entry: Int) -> Int {
        (0..<4).first { $0 != entry && mask & (1 << $0) != 0 } ?? entry
    }
    static func rotatedCell(_ row: Int, _ col: Int, _ q: Int) -> (Int, Int) {
        var (r, c) = (row, col)
        for _ in 0..<((q % 4 + 4) % 4) { (r, c) = (c, 1-r) }
        return (r, c)
    }
    static func rotate(_ state: inout BoardState, platform p: Int, quarters: Int) {
        let q = (quarters % 4 + 4) % 4
        guard q != 0 else { return }
        let (r0, c0) = (p / 3 * 2, p % 3 * 2), old = state.cells
        for r in 0..<2 { for c in 0..<2 {
            let (nr, nc) = rotatedCell(r, c, q)
            state.cells[r0+nr][c0+nc] = rotateMask(old[r0+r][c0+c], by: q)
        } }
        for i in state.balls.indices where platform(state.balls[i].row, state.balls[i].col) == p {
            let (r, c) = rotatedCell(state.balls[i].row-r0, state.balls[i].col-c0, q)
            state.balls[i].row = r0+r; state.balls[i].col = c0+c
            state.balls[i].exit = (state.balls[i].exit+q)%4
        }
    }
    static func spawnExit(mask: Int, tick: Int, source: Int, id: Int) -> Int? {
        let ports = (0..<4).filter { mask & (1 << $0) != 0 }
        guard !ports.isEmpty else { return nil }
        var x = (UInt32(truncatingIfNeeded: tick) &* 0x9e3779b1) ^ (UInt32(source) &* 0x85ebca6b) ^ (UInt32(truncatingIfNeeded: id) &* 0xc2b2ae35)
        x = (x ^ (x >> 16)) &* 0x7feb352d
        x = (x ^ (x >> 15)) &* 0x846ca68b
        return ports[Int(x ^ (x >> 16)) % ports.count]
    }
    @discardableResult static func resolve(_ state: inout BoardState, top: Command?, bottom: Command?) -> Turn {
        var event = Turn()
        guard !state.finished else { return event }
        state.tick += 1
        if spawnTicks.contains(state.tick) {
            for (index, cell) in [(2,2), (3,3)].enumerated() {
                let (r,c) = cell
                guard !state.balls.contains(where: { $0.row == r && $0.col == c }),
                      let exit = spawnExit(mask: state.cells[r][c], tick: state.tick, source: index, id: state.nextBallId) else { continue }
                let ball = Ball(id: state.nextBallId, row: r, col: c, exit: exit)
                state.nextBallId += 1; state.balls.append(ball); event.spawned.append(ball)
            }
        }
        var order: [Int] = []
        for command in [top, bottom] {
            guard let command, valid(command, in: state) else { continue }
            if event.rotations[command.platform] == nil { order.append(command.platform) }
            event.rotations[command.platform, default: 0] += command.dir
        }
        for p in order { rotate(&state, platform: p, quarters: event.rotations[p]!) }
        let dr = [-1,0,1,0], dc = [0,1,0,-1]
        var pending: [Int: Ball] = [:], bounce: [Int: Int] = [:], delivered = Set<Int>()
        for ball in state.balls {
            let mask = state.cells[ball.row][ball.col]
            guard mask & (1 << ball.exit) != 0 else { continue }
            let nr = ball.row + dr[ball.exit], nc = ball.col + dc[ball.exit]
            if nr < 0 || nr >= 6 {
                let side: Side = nr < 0 ? .top : .bottom
                delivered.insert(ball.id); event.delivered.append((ball, side)); continue
            }
            if nc < 0 || nc >= 6 || state.cells[nr][nc] & (1 << ((ball.exit+2)%4)) == 0 {
                bounce[ball.id] = otherPort(mask, ball.exit); continue
            }
            pending[ball.id] = Ball(id: ball.id, row: nr, col: nc, exit: otherPort(state.cells[nr][nc], (ball.exit+2)%4))
        }
        var changed = true
        while changed {
            changed = false
            let occupied = Set(state.balls.filter { !delivered.contains($0.id) && pending[$0.id] == nil }.map { $0.row*6+$0.col })
            var claims: [Int:Int] = [:], swaps = Set<Int>()
            for target in pending.values { claims[target.row*6+target.col, default: 0] += 1 }
            for ball in state.balls {
                guard let target = pending[ball.id], let other = state.balls.first(where: { $0.row == target.row && $0.col == target.col }),
                      let otherTarget = pending[other.id], otherTarget.row == ball.row, otherTarget.col == ball.col else { continue }
                swaps.insert(ball.id); swaps.insert(other.id)
            }
            for ball in state.balls {
                guard let target = pending[ball.id] else { continue }
                let key = target.row*6+target.col
                if occupied.contains(key) || claims[key, default: 0] > 1 || swaps.contains(ball.id) {
                    pending.removeValue(forKey: ball.id)
                    bounce[ball.id] = otherPort(state.cells[ball.row][ball.col], ball.exit)
                    changed = true
                }
            }
        }
        state.balls = state.balls.filter { !delivered.contains($0.id) }.map { ball in
            if let target = pending[ball.id] { return target }
            var value = ball
            if let exit = bounce[ball.id] { value.exit = exit }
            return value
        }
        for (_, side) in event.delivered { state.score[side] += 1 }
        state.cooldown = order
        state.finished = state.tick >= rounds || state.score.top >= 7 || state.score.bottom >= 7
        return event
    }
}
