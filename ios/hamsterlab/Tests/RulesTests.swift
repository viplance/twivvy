import XCTest
@testable import HamsterLab

final class RulesTests: XCTestCase {
    struct Fixture: Decodable {
        var map: Int
        var turns: [Step]
        struct Step: Decodable { var top: Command?; var bottom: Command?; var state: BoardState }
    }
    func testEveryRoundMatchesBrowserRules() throws {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"web-fixtures",withExtension:"json"))
        let fixtures = try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:url))
        XCTAssertEqual(fixtures.count,45)
        for (index, fixture) in fixtures.enumerated() {
            var state = BoardState(map:fixture.map)
            for turn in fixture.turns {
                Rules.resolve(&state,top:turn.top,bottom:turn.bottom)
                XCTAssertEqual(state,turn.state,"Browser parity: match \(index), round \(state.tick)")
            }
        }
    }
    func testOppositeRotationsCancelButLock() {
        var state = BoardState()
        var skipped = state
        Rules.resolve(&skipped,top:nil,bottom:nil)
        Rules.resolve(&state,top:Command(platform:4,dir:1),bottom:Command(platform:4,dir:-1))
        XCTAssertEqual(state.cells,skipped.cells)
        XCTAssertEqual(state.balls,skipped.balls)
        XCTAssertEqual(state.cooldown,[4])
        XCTAssertFalse(Rules.valid(Command(platform:4,dir:1),in:state))
    }
    func testAdjacentBallsBounceInsteadOfSwapping() {
        var state = BoardState(); state.tick = 1
        state.cells = Array(repeating:Array(repeating:10,count:6),count:6)
        state.balls = [Ball(id:1,row:1,col:1,exit:1),Ball(id:2,row:1,col:2,exit:3)]
        Rules.resolve(&state,top:nil,bottom:nil)
        XCTAssertEqual(state.balls,[Ball(id:1,row:1,col:1,exit:3),Ball(id:2,row:1,col:2,exit:1)])
    }
    func testSevenPointsFinishesAndFurtherTurnsAreNoops() {
        var state = BoardState(); state.tick = 1; state.score.bottom = 6
        state.cells[5][0] = 5; state.balls = [Ball(id:1,row:5,col:0,exit:2)]
        Rules.resolve(&state,top:nil,bottom:nil)
        XCTAssertTrue(state.finished); XCTAssertEqual(state.score.bottom,7)
        let finished = state
        Rules.resolve(&state,top:Command(platform:1,dir:1),bottom:nil)
        XCTAssertEqual(state,finished)
    }
    func testBotsAlwaysChooseLegalMovesWithoutMutatingBoard() {
        var state = BoardState()
        Rules.resolve(&state,top:Command(platform:3,dir:1),bottom:Command(platform:7,dir:-1))
        let before = state
        for level in Difficulty.allCases { XCTAssertTrue(Rules.valid(Bot.choose(state,difficulty:level),in:state)) }
        XCTAssertEqual(state,before)
    }
    @MainActor func testInvitationParsing() {
        XCTAssertEqual(GameModel.roomCode("https://twivvy.e-notix.com/ACDE7"),"ACDE7")
        XCTAssertEqual(GameModel.roomCode("https://twivvy.e-notix.com/?join=acde7"),"ACDE7")
        XCTAssertEqual(GameModel.roomCode("twivvy://join?code=ACDE7"),"ACDE7")
        XCTAssertNil(GameModel.roomCode("https://evil.example/ACDE7"))
        XCTAssertNil(GameModel.roomCode("<script>"))
    }

    @MainActor func testMatchmakingRoomEventsDoNotExposeInvitations() throws {
        let game = GameModel()
        game.name = "Lobby test"
        game.ensureBridge()
        let bridge = try XCTUnwrap(game.bridge)
        // Feed protocol events locally without allowing queued commands to reach a server.
        bridge.webView.stopLoading()
        bridge.webView.configuration.userContentController.removeAllScriptMessageHandlers()
        defer { game.leave() }

        game.startOnline("host")
        XCTAssertFalse(game.showsRoomInvitation)
        bridge.onEvent?("room",["code":"FRND1"])
        XCTAssertTrue(game.showsRoomInvitation)
        XCTAssertEqual(game.status,L("lobby.waiting"))

        // Switching from a private room must not leak its sharing state into matchmaking.
        game.startOnline("online")
        XCTAssertFalse(game.showsRoomInvitation)
        XCTAssertEqual(game.status,L("status.finding"))
        bridge.onEvent?("room",["code":"RAND2"])
        XCTAssertEqual(game.screen,.lobby)
        XCTAssertEqual(game.roomCode,"RAND2","Keep the protocol's room code for the connection")
        XCTAssertFalse(game.showsRoomInvitation,"Hide the code and both share/copy actions while connecting")
        XCTAssertEqual(game.status,L("status.connecting"))

        game.startOnline("join",code:"FRND3")
        bridge.onEvent?("room",["code":"FRND3"])
        XCTAssertFalse(game.showsRoomInvitation)
        game.startOnline("host")
        bridge.onEvent?("room",["code":"FRND4"])
        XCTAssertTrue(game.showsRoomInvitation)
        game.leave()
        XCTAssertFalse(game.showsRoomInvitation)
    }
}
