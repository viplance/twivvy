import XCTest
import SpriteKit
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
                scene.setSelection(Command(platform:platform,dir:dir),highlighted:platform,enabled:true)
                var preview = state
                Rules.rotate(&preview,platform:platform,quarters:dir)
                try assertBalls(scene,in:preview)
            } }
            scene.setSelection(nil,highlighted:nil,enabled:true)
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
                scene.setSelection(dir == 0 ? nil : Command(platform:4,dir:dir),highlighted:nil,enabled:true)
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
        scene.render(fixture(),side:.bottom)
        let view = SKView(frame:CGRect(x:0,y:0,width:720,height:828))
        view.presentScene(scene)
        let texture = try XCTUnwrap(view.texture(from:scene))
        let attachment = XCTAttachment(image:UIImage(cgImage:texture.cgImage()))
        attachment.name = "rails-all-corners-and-straights"
        attachment.lifetime = .keepAlways
        add(attachment)
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
