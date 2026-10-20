import SwiftUI

@MainActor @Observable final class GameModel {
    enum Screen { case menu, lobby, game, result }
    var screen: Screen = .menu
    var board = BoardState()
    var selection: Command?
    var turnLimitHint = false
    var side: Side = .bottom
    var peerName = ""
    var name = UserDefaults.standard.string(forKey: "playerName") ?? ""
    var difficulty: Difficulty = .medium
    var training = false
    var active = false
    var paused = false
    var remaining = 30.0
    var roomCode = ""
    private(set) var isHostingPrivateRoom = false
    var status = ""
    var error: String?
    var onlineCount = 0
    var rematchRequested = false
    var peerRematch = false
    var hasSavedGame = SessionVault.read() != nil
    var boardScene = BoardScene()
    var bridge: OnlineBridge?
    var resultReason: String?
    private var timer: Timer?
    private var deadline = Date()
    private var botMove: Command?
    private var generation = 0
    private var countdown = 4
    private var lastSaved: Data?
    private var presenceTask: Task<Void, Never>?
    private var suspendedTraining = false
    private var awaitingRecovery = false
    private var thinkingSound=ThinkingSoundSchedule()
    private var audioSuspended=false

    var ownScore: Int { board.score[side] }
    var opponentScore: Int { board.score[side.opposite] }
    var displayRound: Int { min(board.tick + (board.finished ? 0 : 1),30) }
    var roundLabel: String { LF("status.round", ["round":"\(displayRound)", "total":"30"]) }
    var resultTitle: String {
        if let resultReason { return resultReason }
        return L(ownScore == opponentScore ? "result.draw" : ownScore > opponentScore ? "result.win" : "result.loss")
    }
    var inviteURL: URL { URL(string: "https://twivvy.e-notix.com/\(roomCode)")! }
    var showsRoomInvitation: Bool { isHostingPrivateRoom && !roomCode.isEmpty }

    init() {
        AudioEngine.shared.onSampleStarted = { [weak self] sound in
            guard let self, sound == .oops, self.screen == .game,
                  self.active, !self.paused, !self.audioSuspended else { return }
            self.boardScene.showOopsSmoke()
        }
        boardScene.onTurnaround = { [weak self] in
            guard let self, self.screen == .game, !self.paused, !self.audioSuspended else { return }
            AudioEngine.shared.playSample(.turnaround)
        }
        boardScene.onDragStart = { [weak self] in self?.turnLimitHint = false }
        boardScene.onTurnLimit = { [weak self] in
            guard let self, self.active, !self.paused else { return }
            self.turnLimitHint = true
        }
        boardScene.onSelect = { [weak self] platform, direction in
            self?.chooseTurn(platform:platform,direction:direction)
        }
        boardScene.render(board, side: side)
    }
    func ensureBridge() {
        guard bridge == nil else { return }
        let created = OnlineBridge()
        created.onEvent = { [weak self] type, data in self?.receive(type, data) }
        bridge = created
    }
    func rememberName() -> Bool {
        name = String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(24))
        guard !name.isEmpty else { error = L("error.nameRequired"); return false }
        UserDefaults.standard.set(name, forKey: "playerName")
        return true
    }
    func startTraining() {
        guard rememberName() else { return }
        leave()
        training = true; peerName = L("player.bot"); side = .bottom
        board = BoardState(map: Int.random(in: 0..<3)); screen = .game
        boardScene.render(board, side: side)
        beginTrainingRound()
        // Advisory presence only. Offline training never depends on this request.
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let url = URL(string: "https://us-central1-enotix.cloudfunctions.net/twivvy-signal/api/matchmaking")!
                    var request = URLRequest(url: url); request.timeoutInterval = 8
                    let (data, _) = try await URLSession.shared.data(for: request)
                    if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let count = object["online"] as? Int { self?.onlineCount = max(0,count) }
                } catch { }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
    private func beginTrainingRound() {
        guard training else { return }
        if board.finished { finish(); return }
        selection = nil; turnLimitHint = false; active = false
        countdown = 4; remaining = 30; paused = false
        let snapshot = board, level = difficulty, token = generation
        Task {
            let move = await Task.detached(priority: .userInitiated) { Bot.choose(snapshot, difficulty: level) }.value
            guard generation == token, training, !suspendedTraining else { return }
            botMove = move; active = true; deadline = Date().addingTimeInterval(remaining)
            refreshScene(); startClock()
        }
    }
    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickClock() }
        }
    }
    private func tickClock() {
        guard training, active, !paused else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        playThinkingCue()
        let second = Int(ceil(remaining))
        if (1...3).contains(second), second < countdown { countdown = second; AudioEngine.shared.play("countdown") }
        if remaining == 0 { resolveTraining() }
    }
    func resolveTraining() {
        guard training, active else { return }
        boardScene.finishDrag()
        timer?.invalidate(); active = false
        let before = board
        let turn = Rules.resolve(&board, top: botMove, bottom: selection)
        selection = nil; turnLimitHint = false
        animate(before: before, turn: turn)
        let token = generation
        Task {
            try? await Task.sleep(for: .milliseconds(HamsterMotion.roundPauseMilliseconds))
            guard token == generation, !suspendedTraining else { return }
            beginTrainingRound()
        }
    }
    /// Drives a single local match for simulator previews. A rematch, leave or
    /// suspension changes generation and ends this run before another move.
    func autoplayTraining() async {
        let token=generation
        for _ in 0..<30 {
            guard token==generation,training,screen == .game else { break }
            for _ in 0..<100 {
                if active || token != generation { break }
                try? await Task.sleep(for:.milliseconds(50))
            }
            guard !Task.isCancelled,token==generation,active else { break }
            resolveTraining()
            try? await Task.sleep(for:.milliseconds(HamsterMotion.roundPauseMilliseconds + 250))
        }
    }
    func chooseTurn(platform: Int, direction: Int?) {
        guard active, !paused, (0..<9).contains(platform) else { return }
        let command = direction.map { Command(platform:platform,dir:$0) }
        guard Rules.valid(command,in:board) else { return }
        turnLimitHint = false
        selection = command
        if !training {
            let value: Any = command.map { ["platform":$0.platform,"dir":$0.dir] as Any } ?? NSNull()
            bridge?.send(["action":"choose","command":value])
        }
        refreshScene()
        if direction != nil { AudioEngine.shared.play("turn") }
    }
    func startOnline(_ action: String, code: String = "") {
        guard rememberName() else { return }
        leave(); ensureBridge()
        training = false; screen = .lobby; roomCode = code
        isHostingPrivateRoom = action == "host"
        status = L(action == "online" ? "status.finding" : "status.connecting")
        bridge?.send(["action":action,"name":name,"code":code])
    }
    func resume() {
        guard let data = SessionVault.read(), let savedJSON = String(data:data,encoding:.utf8) else { hasSavedGame = false; return }
        ensureBridge(); screen = .lobby; training = false; status = L("native.recovering")
        isHostingPrivateRoom = false
        bridge?.send(["action":"resume","savedJSON":savedJSON])
    }
    func requestRematch() {
        if training { startTraining(); return }
        guard !rematchRequested else { return }
        rematchRequested = true; bridge?.send(["action":"rematch"])
    }
    func leave() {
        AudioEngine.shared.endGameMusic()
        thinkingSound=ThinkingSoundSchedule()
        AudioEngine.shared.stop()
        generation += 1; timer?.invalidate(); presenceTask?.cancel(); presenceTask = nil
        if !training, screen != .menu { bridge?.send(["action":"leave"]); SessionVault.clear(); hasSavedGame = false }
        training = false; active = false; paused = false; suspendedTraining = false
        selection = nil; turnLimitHint = false; roomCode = ""; resultReason = nil
        isHostingPrivateRoom = false
        rematchRequested = false; peerRematch = false; status = ""; screen = .menu
        board = BoardState(); side = .bottom; boardScene.render(board, side: side)
    }
    func background() {
        AudioEngine.shared.endGameMusic()
        audioSuspended=true
        AudioEngine.shared.stop()
        if training, screen == .game {
            remaining = active ? max(0,deadline.timeIntervalSinceNow) : remaining
            suspendedTraining = true; paused = true; timer?.invalidate(); generation += 1
        } else if screen == .game || screen == .lobby { bridge?.send(["action":"suspend"]) }
    }
    func foreground() {
        audioSuspended=false
        if training, suspendedTraining {
            suspendedTraining = false; paused = false
            if active { deadline = Date().addingTimeInterval(remaining); startClock(); refreshScene() }
            else { beginTrainingRound() }
        } else if screen == .game || screen == .lobby { bridge?.send(["action":"foreground"]) }
    }
    func handleURL(_ url: URL) -> String? { Self.roomCode(url.absoluteString) }
    static func roomCode(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: String
        if let url = URL(string: trimmed), let scheme = url.scheme {
            guard (scheme == "https" && url.host == "twivvy.e-notix.com") || ["twivvy", "hamsterlab"].contains(scheme) else { return nil }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            raw = query?.first(where: { ["game","join","code"].contains($0.name) })?.value ?? (["twivvy", "hamsterlab"].contains(scheme) ? url.host ?? "" : url.lastPathComponent)
        } else { raw = trimmed }
        let code = raw.uppercased()
        return code.range(of: "^[A-Z0-9]{4,8}$", options: .regularExpression) != nil ? code : nil
    }
    private func decode<T: Decodable>(_ object: Any?, as: T.Type) -> T? {
        guard let object, JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func receive(_ type: String, _ data: [String: Any]) {
        switch type {
        case "save":
            if let saved = data["savedJSON"] as? String, let encoded = saved.data(using:.utf8) {
                // Limit keychain writes while preserving each changed commitment and board.
                if encoded != lastSaved { lastSaved = encoded; hasSavedGame = SessionVault.save(encoded) }
            }
        case "clearSave": SessionVault.clear(); lastSaved = nil; hasSavedGame = false
        case "room":
            roomCode = data["code"] as? String ?? roomCode
            if screen == .lobby { status = L(isHostingPrivateRoom ? "lobby.waiting" : "status.connecting") }
        case "count": onlineCount = data["online"] as? Int ?? 0
        case "status": status = L(data["key"] as? String ?? "status.connecting")
        case "peer": peerName = data["name"] as? String ?? L("player.opponent")
        case "started", "restore", "active":
            if let value = decode(data["match"], as: BoardState.self) { board = value }
            if let value = data["side"] as? String { side = Side(rawValue: value) ?? .bottom }
            if let value = data["peerName"] as? String { peerName = value }
            selection = decode(data["selection"], as: Command.self); turnLimitHint = false
            remaining = data["remaining"] as? Double ?? remaining
            if type == "started" {
                thinkingSound=ThinkingSoundSchedule()
                resultReason = nil; rematchRequested = false; peerRematch = false
            }
            screen = .game
            active = type == "active" && (data["active"] as? Bool ?? false)
            paused = type != "active"
            boardScene.render(board, side: side); refreshScene()
        case "timer":
            remaining = data["remaining"] as? Double ?? remaining
            playThinkingCue()
        case "lock": active = false; AudioEngine.shared.stopThinkingSample(); refreshScene()
        case "paused": paused = true; active = false; AudioEngine.shared.endGameMusic(); AudioEngine.shared.stop(); status = L("native.recovering"); refreshScene()
        case "resolved":
            guard let before = decode(data["before"], as: BoardState.self), let after = decode(data["match"], as: BoardState.self),
                  let event = data["event"] as? [String:Any], let commands = event["commands"] as? [String:Any] else { return }
            var verified = before
            let turn = Rules.resolve(&verified, top: decode(commands["top"], as: Command.self), bottom: decode(commands["bottom"], as: Command.self))
            guard verified == after else { resultReason = L("error.restoreMismatch"); finish(); bridge?.send(["action":"suspend"]); return }
            board = verified; selection = nil; turnLimitHint = false; active = false; paused = false
            animate(before: before, turn: turn)
        case "finished":
            if let value = decode(data["match"], as: BoardState.self) { board = value }
            if let reason = data["reason"] as? String { resultReason = L(reason == "expired" || reason.contains("30") ? "error.peerAbsent" : "error.restoreMismatch") }
            finish()
        case "rematch": peerRematch = true
        case "error": error = L(data["key"] as? String ?? "error.connectFailed"); rematchRequested = false
        case "terminated": paused = true; active = false; AudioEngine.shared.endGameMusic(); AudioEngine.shared.stop(); awaitingRecovery = true
        case "ready": if awaitingRecovery { awaitingRecovery = false; resume() }
        default: break
        }
    }
    private func animate(before: BoardState, turn: Turn) {
        AudioEngine.shared.stopThinkingSample()
        if !turn.rotations.isEmpty { AudioEngine.shared.play("turn") }
        boardScene.animate(before: before, after: board, turn: turn, side: side)
        if !turn.delivered.isEmpty {
            let token = generation
            let sounds=HamsterSound.deliveries(turn,side:side)
            Task {
                try? await Task.sleep(for:.milliseconds(HamsterMotion.deliveryCueMilliseconds))
                guard token == generation, screen == .game, !paused, !audioSuspended else { return }
                for sound in sounds { AudioEngine.shared.playSample(sound) }
            }
        }
    }
    private func finish() {
        AudioEngine.shared.endGameMusic()
        AudioEngine.shared.stopThinkingSample()
        timer?.invalidate(); active = false; paused = false; screen = .result
        refreshScene()
        if !audioSuspended,let sound=HamsterSound.result(own:ownScore,opponent:opponentScore) {
            AudioEngine.shared.playSample(sound)
        }
    }
    private func playThinkingCue() {
        guard screen == .game,active,!paused,!audioSuspended else { return }
        thinkingSound.begin(round:displayRound,remaining:remaining)
        if thinkingSound.takeCue(remaining:remaining) { AudioEngine.shared.playSample(.oops) }
    }
    func refreshScene() {
        boardScene.setSelection(selection, highlighted: selection?.platform, enabled: active && !paused)
        if screen == .game,!paused,!audioSuspended { AudioEngine.shared.startGameMusic() }
        if screen == .game,active,!paused {
            thinkingSound.begin(round:displayRound,remaining:remaining)
        }
    }
}
