import XCTest
import SpriteKit
import SwiftUI
@testable import Twivvy

final class TrackGeometryTests: XCTestCase {
    private let masks = [3, 6, 12, 9, 5, 10]

    func testRestingPointsAreOnEachRail() {
        let expected = [CGPoint(x:12.25,y:12.25), CGPoint(x:12.25,y:-12.25),
                        CGPoint(x:-12.25,y:-12.25), CGPoint(x:-12.25,y:12.25), .zero, .zero]
        for (mask, offset) in zip(masks, expected) {
            let rail = TrackGeometry(center:CGPoint(x:80,y:-37),cellSize:98,mask:mask)
            assertPoint(rail.midpoint, CGPoint(x:80 + offset.x,y:-37 + offset.y))
        }
    }

    func testTravelFollowsBothRailsForEveryCompatiblePairOfPorts() throws {
        for sourceMask in masks { for exit in 0..<4 where sourceMask & (1 << exit) != 0 {
            for targetMask in masks where targetMask & (1 << ((exit + 2) % 4)) != 0 {
                for gap: CGFloat in [0, 20] {
                    let source = TrackGeometry(center:.zero,cellSize:98,mask:sourceMask)
                    let edge = source.endpoint(exit)
                    let target = TrackGeometry(center:CGPoint(x:edge.x * (2 + gap / 49),y:edge.y * (2 + gap / 49)),cellSize:98,mask:targetMask)
                    let parts = elements(source.path(to:target,exit:exit))
                    XCTAssertEqual(parts.map(\.0), [.moveToPoint,.addQuadCurveToPoint,.addLineToPoint,.addQuadCurveToPoint])
                    guard parts.count == 4 else { return }
                    assertPoint(parts[0].1[0],source.midpoint)
                    assertPoint(parts[1].1[1],source.endpoint(exit))
                    assertPoint(parts[2].1[0],target.endpoint((exit + 2) % 4))
                    assertPoint(parts[3].1[1],target.midpoint)
                    // Sample the actual animation curves against the full rendered rails.
                    for i in 0...20 {
                        let t = CGFloat(i) / 20
                        let departing = quadratic(source.midpoint,parts[1].1[0],parts[1].1[1],t)
                        let arriving = quadratic(parts[2].1[0],parts[3].1[0],target.midpoint,t)
                        assertPoint(departing,quadratic(source.endpoint(Rules.otherPort(sourceMask,exit)),source.center,source.endpoint(exit),0.5 + t / 2))
                        let entry = (exit + 2) % 4
                        assertPoint(arriving,quadratic(target.endpoint(entry),target.center,target.endpoint(Rules.otherPort(targetMask,entry)),t / 2))
                    }
                }
            }
        } }
    }

    func testDeliveryLeavesThroughTheRailEndpoint() {
        for mask in masks { for exit in [0, 2] where mask & (1 << exit) != 0 {
            let rail = TrackGeometry(center:CGPoint(x:49,y:265),cellSize:98,mask:mask)
            let y: CGFloat = exit == 0 ? 377 : -377
            let parts = elements(rail.deliveryPath(exit:exit,receiverY:y))
            XCTAssertEqual(parts.map(\.0),[.moveToPoint,.addQuadCurveToPoint,.addLineToPoint])
            assertPoint(parts[0].1[0],rail.midpoint)
            assertPoint(parts[1].1[1],rail.endpoint(exit))
            assertPoint(parts[2].1[0],CGPoint(x:rail.endpoint(exit).x,y:y))
        } }
    }

    @MainActor func testSceneAndPreviewsKeepBallsOnRailsFromBothSides() throws {
        let state = fixture()
        for side in [Side.bottom, .top] {
            let scene = BoardScene()
            scene.render(state,side:side)
            try assertBalls(scene,in:state)
            for platform in 0..<9 { for dir in [-1,1] {
                scene.setSelection(Command(platform:platform,dir:dir),highlighted:platform,enabled:true,animated:false)
                var preview = state
                Rules.rotate(&preview,platform:platform,quarters:dir)
                try assertBalls(scene,in:preview)
            } }
            scene.setSelection(nil,highlighted:nil,enabled:true,animated:false)
            try assertBalls(scene,in:state)
        }
    }

    @MainActor func testSpawnMarkersMatchSpawnedBallsAndRotationPreviews() throws {
        for mask in masks { for side in [Side.bottom, .top] {
            var state = BoardState()
            state.cells[2][2] = mask; state.cells[3][3] = mask
            var spawned = state
            let turn = Rules.resolve(&spawned,top:nil,bottom:nil)
            XCTAssertEqual(turn.spawned.count,2)
            // Spawned balls begin at the markers, before the turn's movement.
            state.balls = turn.spawned
            let scene = BoardScene()
            scene.render(state,side:side)
            for dir in [0,-1,1,0] {
                scene.setSelection(dir == 0 ? nil : Command(platform:4,dir:dir),highlighted:nil,enabled:true,animated:false)
                var preview = state
                Rules.rotate(&preview,platform:4,quarters:dir)
                for (index,ball) in preview.balls.enumerated() {
                    let marker = try XCTUnwrap(scene.childNode(withName:"//source-\(index)"))
                    let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
                    let tile = try XCTUnwrap(marker.parent)
                    XCTAssertEqual(tile.name,"platform-4")
                    let actual = tile.convert(marker.position,to:try XCTUnwrap(node.parent))
                    assertPoint(actual,node.position)
                    assertPoint(actual,geometry(ball,in:preview).midpoint)
                }
            }
        } }
    }

    @MainActor func testAnimatedBallsRideTheRotatingPlatform() throws {
        for q in [-2,-1,0,1,2] {
            let before = fixture()
            let scene = BoardScene()
            var after = before
            Rules.rotate(&after,platform:4,quarters:q)
            scene.animate(before:before,after:after,turn:Turn(rotations:[4:q]),side:.bottom)
            let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
            for (index,position) in [(2,2),(3,3)].enumerated() {
                let marker = try XCTUnwrap(scene.childNode(withName:"//source-\(index)"))
                let ball = try XCTUnwrap(before.balls.first { $0.row == position.0 && $0.col == position.1 })
                let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
                XCTAssertTrue(marker.parent === tile)
                assertPoint(marker.position,node.position)
            }
            for ball in before.balls where Rules.platform(ball.row,ball.col) == 4 {
                let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
                XCTAssertTrue(node.parent === tile)
                let original = geometry(ball,in:before).midpoint
                for fraction: CGFloat in [0,0.25,0.5,0.75,1] {
                    tile.zRotation = -CGFloat(q) * .pi / 2 * fraction
                    let actual = tile.convert(node.position,to:try XCTUnwrap(tile.parent))
                    let angle = tile.zRotation
                    assertPoint(actual,CGPoint(x:original.x * cos(angle) - original.y * sin(angle),y:original.x * sin(angle) + original.y * cos(angle)))
                }
            }
        }
    }

    @MainActor func testCornerRailVisualFixture() throws {
        let scene = BoardScene()
        var state = fixture(); state.cooldown = [0,8]
        scene.render(state,side:.bottom)
        scene.setSelection(Command(platform:4,dir:1),highlighted:4,enabled:true,animated:false)
        let view = SKView(frame:CGRect(x:0,y:0,width:720,height:828))
        view.presentScene(scene)
        let texture = try XCTUnwrap(view.texture(from:scene))
        let attachment = XCTAttachment(image:UIImage(cgImage:texture.cgImage()))
        attachment.name = "rails-all-corners-and-straights"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testDragFollowsFingerAndCarriesBallsWithoutPriorSelection() throws {
        for side in [Side.bottom,.top] { for sign: CGFloat in [-1,1] {
            let state = fixture()
            let scene = BoardScene()
            scene.render(state,side:side)
            scene.setSelection(nil,highlighted:nil,enabled:true)
            var commands: [Command?] = []
            scene.onSelect = { p,dir in commands.append(dir.map { Command(platform:p,dir:$0) }) }
            XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
            let angle = sign * CGFloat.pi / 18
            scene.moveDrag(to:CGPoint(x:80*cos(angle),y:80*sin(angle)))
            let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
            XCTAssertEqual(tile.zRotation,angle,accuracy:0.0001)
            XCTAssertTrue(commands.isEmpty,"Dragging must not commit until release")
            let ball = try XCTUnwrap(state.balls.first { $0.row == 2 && $0.col == 2 })
            let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
            let marker = try XCTUnwrap(scene.childNode(withName:"//source-0"))
            assertPoint(tile.convert(marker.position,to:try XCTUnwrap(tile.parent)),node.position)
            scene.finishDrag()
            XCTAssertEqual(commands,[Command(platform:4,dir:sign < 0 ? 1 : -1)])
            XCTAssertEqual(tile.zRotation,angle,accuracy:0.0001,"Release must start a snap, not jump")
            XCTAssertNotNil(tile.action(forKey:"preview-snap"))
        } }
    }

    @MainActor func testViewDragsRotateTheVisiblePlatformFromEitherPerspective() throws {
        for viewSize in [CGSize(width:360,height:414),CGSize(width:414,height:700)] {
            let scene = BoardScene()
            let view = SKView(frame:CGRect(origin:.zero,size:viewSize))
            view.presentScene(scene)
            defer { view.presentScene(nil) }
            for side in [Side.bottom,.top] { for index in 0..<9 { for direction in [-1,1] {
                scene.render(BoardState(),side:side)
                scene.setSelection(nil,highlighted:nil,enabled:true,animated:false)
                var commands: [Command?] = []
                scene.onSelect = { p,dir in commands.append(dir.map { Command(platform:p,dir:$0) }) }
                // Start on the platform at this visual row/column, as a UIKit finger would.
                let center = CGPoint(x:CGFloat(index % 3 - 1)*216,y:CGFloat(1 - index / 3)*216)
                let angle = -CGFloat(direction) * .pi/6
                let start = scene.convertPoint(toView:CGPoint(x:center.x+80,y:center.y))
                let end = scene.convertPoint(toView:CGPoint(x:center.x+80*cos(angle),y:center.y+80*sin(angle)))
                let expectedPlatform = side == .bottom ? index : 8-index
                scene.dragChanged(start:start,location:end)
                XCTAssertTrue(commands.isEmpty)
                for p in 0..<9 {
                    let tile = try XCTUnwrap(scene.childNode(withName:"//platform-\(p)"))
                    XCTAssertEqual(tile.zRotation,p == expectedPlatform ? angle : 0,accuracy:0.0001,
                                   "Only the platform beneath the finger should follow the drag (\(side), visual \(index))")
                }
                scene.dragEnded(at:end)
                let command = Command(platform:expectedPlatform,dir:direction)
                XCTAssertEqual(commands,[command],"The network command must use canonical board coordinates")

                // Reversing the same visible platform must also use its rotated perspective.
                scene.setSelection(command,highlighted:expectedPlatform,enabled:true,animated:false)
                scene.dragChanged(start:end,location:start)
                scene.dragEnded(at:start)
                XCTAssertEqual(commands.count,2)
                XCTAssertNil(commands.last!)
            } } }
        }
    }

    @MainActor func testShortAndCancelledDragsDoNotChooseAMove() throws {
        for cancelled in [false,true] {
            let scene = BoardScene()
            scene.render(BoardState(),side:.bottom)
            scene.setSelection(nil,highlighted:nil,enabled:true)
            var callbacks = 0
            scene.onSelect = { _,dir in callbacks += 1; XCTAssertNil(dir) }
            XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
            let angle: CGFloat = cancelled ? .pi/3 : .pi/36
            scene.moveDrag(to:CGPoint(x:80*cos(angle),y:80*sin(angle)))
            scene.finishDrag(cancelled:cancelled)
            XCTAssertEqual(callbacks,1)
            XCTAssertNotNil(scene.childNode(withName:"//platform-4")?.action(forKey:"preview-snap"))
        }
        var state = BoardState(); state.cooldown = [4]
        let scene = BoardScene(); scene.render(state,side:.bottom)
        scene.setSelection(nil,highlighted:nil,enabled:true)
        XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
        scene.moveDrag(to:CGPoint(x:56,y:-56))
        scene.finishDrag()
        XCTAssertEqual(scene.childNode(withName:"//platform-4")?.zRotation,0)
        scene.setSelection(nil,highlighted:nil,enabled:false)
        XCTAssertFalse(scene.beginDrag(at:CGPoint(x:216,y:0)))
    }

    @MainActor func testTapOnAnyPlatformClearsTheMoveIncludingHotPlatforms() throws {
        let game = GameModel()
        game.training = true; game.active = true
        game.board.cooldown = [0,8]
        let scene = game.boardScene
        scene.render(game.board,side:.bottom)
        for p in 0..<9 {
            game.selection = Command(platform:4,dir:1)
            scene.setSelection(game.selection,highlighted:4,enabled:true,animated:false)
            let point = CGPoint(x:CGFloat(p % 3 - 1)*216 + 80,y:CGFloat(1 - p / 3)*216)
            XCTAssertTrue(scene.beginDrag(at:point))
            scene.finishDrag()
            XCTAssertNil(game.selection)
            let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
            XCTAssertNil(tile.childNode(withName:"preview"))
            XCTAssertNotNil(tile.action(forKey:"preview-snap"),"Reset must animate back")
        }
        game.chooseTurn(platform:0,direction:1)
        XCTAssertNil(game.selection,"Reset taps must not enable rotation of hot platforms")
        let hot = try XCTUnwrap(scene.childNode(withName:"//platform-0")?.childNode(withName:"base") as? SKShapeNode)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(hot.strokeColor.getRed(&red,green:&green,blue:&blue,alpha:&alpha))
        XCTAssertEqual(red,1,accuracy:0.0001)
        XCTAssertEqual(green,98.0/255,accuracy:0.0001)
        XCTAssertEqual(blue,107.0/255,accuracy:0.0001)
        XCTAssertEqual(hot.glowWidth,5)
        XCTAssertNil(scene.childNode(withName:"//lock"))
    }

    @MainActor func testNewDragCanInterruptSnapAndResolveKeepsVisibleAngle() throws {
        let before = fixture()
        let scene = BoardScene(); scene.render(before,side:.bottom)
        scene.setSelection(nil,highlighted:nil,enabled:true)
        XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
        scene.moveDrag(to:CGPoint(x:56,y:-56))
        scene.finishDrag()
        let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
        XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
        XCTAssertNil(tile.action(forKey:"preview-snap"))
        XCTAssertEqual(tile.zRotation,-.pi/4,accuracy:0.0001)
        scene.moveDrag(to:CGPoint(x:56,y:-56))
        XCTAssertEqual(tile.zRotation,-.pi/2,accuracy:0.0001)
        scene.finishDrag()
        var after = before
        let turn = Rules.resolve(&after,top:nil,bottom:Command(platform:4,dir:1))
        scene.animate(before:before,after:after,turn:turn,side:.bottom)
        let resolvedTile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
        XCTAssertEqual(resolvedTile.zRotation,-.pi/2,accuracy:0.0001)
        let ball = try XCTUnwrap(before.balls.first { $0.row == 2 && $0.col == 2 })
        let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
        XCTAssertTrue(node.parent === resolvedTile)
        let original = geometry(ball,in:before).midpoint
        assertPoint(resolvedTile.convert(node.position,to:try XCTUnwrap(resolvedTile.parent)),CGPoint(x:original.y,y:-original.x))
    }

    @MainActor func testSnapFinishesAtQuarterTurnAndSwitchReturnsPreviousPlatform() async throws {
        let scene = BoardScene()
        scene.render(fixture(),side:.bottom)
        scene.setSelection(nil,highlighted:nil,enabled:true)
        let window = UIWindow(frame:CGRect(x:0,y:0,width:360,height:414))
        let controller = UIViewController()
        let view = SKView(frame:window.bounds)
        controller.view = view; window.rootViewController = controller; window.isHidden = false
        view.presentScene(scene)
        defer { view.presentScene(nil); window.isHidden = true }
        XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
        scene.moveDrag(to:CGPoint(x:56,y:-56)); scene.finishDrag()
        try await Task.sleep(for:.milliseconds(600))
        let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
        XCTAssertEqual(tile.zRotation,-.pi/2,accuracy:0.001)
        XCTAssertTrue(scene.beginDrag(at:CGPoint(x:296,y:0)))
        scene.moveDrag(to:CGPoint(x:272,y:56))
        try await Task.sleep(for:.milliseconds(400))
        XCTAssertEqual(tile.zRotation,0,accuracy:0.001)
        scene.finishDrag(cancelled:true)
    }

    @MainActor func testReverseDragResetsChosenTurnWithTheSameSmallThreshold() throws {
        for side in [Side.bottom,.top] { for dir in [-1,1] { for settled in [false,true] {
            let game = GameModel(); game.training = true; game.active = true
            game.board = fixture(); game.side = side
            let scene = game.boardScene
            scene.render(game.board,side:side)
            game.chooseTurn(platform:4,direction:dir)
            if settled { scene.setSelection(game.selection,highlighted:4,enabled:true,animated:false) }
            let start: CGFloat = 0.6
            XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80*cos(start),y:80*sin(start))))
            // Several samples catch accidental use of the platform angle as the finger angle.
            for degrees in [5.0,10.0] {
                let angle = start + CGFloat(dir) * CGFloat(degrees) * .pi/180
                scene.moveDrag(to:CGPoint(x:80*cos(angle),y:80*sin(angle)))
            }
            scene.finishDrag()
            XCTAssertNil(game.selection)
            XCTAssertFalse(game.turnLimitHint)
            XCTAssertNotNil(scene.childNode(withName:"//platform-4")?.action(forKey:"preview-snap"))
        } } }
    }

    @MainActor func testSecondTurnSpringsBackAndShowsHintWithoutChangingCommand() async throws {
        let game = GameModel(); game.training = true; game.active = true
        game.board = fixture()
        let scene = game.boardScene
        scene.render(game.board,side:.bottom)
        let window = UIWindow(frame:CGRect(x:0,y:0,width:360,height:414))
        let controller = UIViewController(), view = SKView(frame:window.bounds)
        controller.view = view; window.rootViewController = controller; window.isHidden = false
        view.presentScene(scene)
        defer { view.presentScene(nil); window.isHidden = true }
        for dir in [-1,1] {
            let command = Command(platform:4,dir:dir)
            game.chooseTurn(platform:4,direction:dir)
            scene.setSelection(command,highlighted:4,enabled:true,animated:false)
            XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
            let delta = -CGFloat(dir) * .pi/4
            scene.moveDrag(to:CGPoint(x:80*cos(delta),y:80*sin(delta)))
            let tile = try XCTUnwrap(scene.childNode(withName:"//platform-4"))
            XCTAssertEqual(tile.zRotation,-CGFloat(dir) * .pi / 2 + delta,accuracy:0.001)
            scene.finishDrag()
            XCTAssertEqual(game.selection,command)
            XCTAssertTrue(game.turnLimitHint)
            XCTAssertNotNil(tile.action(forKey:"preview-snap"))
            try await Task.sleep(for:.milliseconds(400))
            XCTAssertEqual(tile.zRotation,-CGFloat(dir) * .pi / 2,accuracy:0.001)
            XCTAssertTrue(scene.beginDrag(at:CGPoint(x:80,y:0)))
            scene.moveDrag(to:CGPoint(x:80*cos(-delta),y:80*sin(-delta)))
            scene.finishDrag()
            XCTAssertNil(game.selection)
            XCTAssertFalse(game.turnLimitHint)
            try await Task.sleep(for:.milliseconds(400))
            XCTAssertEqual(tile.zRotation,0,accuracy:0.001)
        }
    }

    @MainActor func testSceneRemainsPresentedAcrossMenuGameAndResultTransitions() async throws {
        let game = GameModel()
        let window = UIWindow(frame:CGRect(x:0,y:0,width:375,height:667))
        let controller = UIHostingController(rootView:ContentView(game:game))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        func checkPresentation(_ step: String) async throws {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for:.milliseconds(350))
            func spriteViews(in parent: UIView) -> [SKView] {
                (parent as? SKView).map { [$0] } ?? parent.subviews.flatMap { spriteViews(in:$0) }
            }
            let views = spriteViews(in:controller.view)
            XCTAssertEqual(views.count,1,"Exactly one visible board after \(step)")
            let view = try XCTUnwrap(views.first)
            let scene = try XCTUnwrap(view.scene,"Visible view lost its scene after \(step)")
            XCTAssertTrue(scene.view === view,"Scene attached to a discarded view after \(step)")
            XCTAssertGreaterThan(view.bounds.width,0)
            XCTAssertGreaterThan(view.bounds.height,0)
        }

        try await checkPresentation("initial menu")
        for round in 0..<3 {
            // Local screen transitions only: no server or matchmaking traffic.
            game.training = true; game.active = true; game.screen = .game
            game.boardScene.render(game.board,side:.bottom)
            game.refreshScene()
            try await checkPresentation("entering game \(round)")
            game.screen = .result
            try await checkPresentation("result \(round)")
            game.leave()
            try await checkPresentation("returning to menu \(round)")
        }
    }

    private func fixture() -> BoardState {
        var state = BoardState()
        for row in 0..<6 { for col in 0..<6 {
            let mask = masks[(row + col) % masks.count]
            state.cells[row][col] = mask
            state.balls.append(Ball(id:row * 6 + col,row:row,col:col,exit:(0..<4).first { mask & (1 << $0) != 0 }!))
        } }
        return state
    }

    private func geometry(_ ball: Ball, in state: BoardState) -> TrackGeometry {
        let p = Rules.platform(ball.row,ball.col)
        return TrackGeometry(center:CGPoint(x:CGFloat(p % 3 - 1) * 216 + (CGFloat(ball.col % 2) - 0.5) * 98,
                                            y:CGFloat(1 - p / 3) * 216 + (0.5 - CGFloat(ball.row % 2)) * 98),cellSize:98,mask:state.cells[ball.row][ball.col])
    }

    @MainActor private func assertBalls(_ scene: BoardScene, in state: BoardState) throws {
        for ball in state.balls {
            let node = try XCTUnwrap(scene.childNode(withName:"//ball-\(ball.id)"))
            assertPoint(node.position,geometry(ball,in:state).midpoint)
        }
    }

    private func elements(_ path: CGPath) -> [(CGPathElementType,[CGPoint])] {
        var result: [(CGPathElementType,[CGPoint])] = []
        path.applyWithBlock { element in
            let value = element.pointee
            let count = value.type == .addQuadCurveToPoint ? 2 : 1
            result.append((value.type,Array(UnsafeBufferPointer(start:value.points,count:count))))
        }
        return result
    }

    private func quadratic(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x:(1-t)*(1-t)*a.x + 2*(1-t)*t*c.x + t*t*b.x,
                y:(1-t)*(1-t)*a.y + 2*(1-t)*t*c.y + t*t*b.y)
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x,expected.x,accuracy:0.0001,file:file,line:line)
        XCTAssertEqual(actual.y,expected.y,accuracy:0.0001,file:file,line:line)
    }
}
