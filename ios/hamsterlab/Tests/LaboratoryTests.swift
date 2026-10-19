import XCTest
import RealityKit
import UIKit
import simd
@testable import HamsterLab

final class LaboratoryTests: XCTestCase {
    @MainActor func testTraversalRunsAtThreeQuartersOfTheOriginalSpeed() throws {
        var before=BoardState(); before.tick=2
        before.cells[2][2]=10; before.cells[2][3]=10
        before.balls=[Ball(id:1,row:2,col:2,exit:1)]
        var after=before
        let turn=Rules.resolve(&after,top:nil,bottom:nil)
        let scene=BoardScene(); scene.render(before,side:.bottom)
        scene.animate(before:before,after:after,turn:turn,side:.bottom)
        scene.update(delta:0.4+0.68)
        XCTAssertTrue(scene.isAnimating,"The former crossing time must now leave 25% of the route to go")
        let source=TubePath(row:2,col:2,state:before), destination=TubePath(row:2,col:3,state:after)
        let rig=try XCTUnwrap(scene.hamsters[1])
        XCTAssertLessThan(simd_distance(rig.root.position(relativeTo:scene.world),source.travel(to:destination,exit:1,progress:0.75)),0.00001)
        scene.update(delta:0.3)
        XCTAssertFalse(scene.isAnimating)
        XCTAssertLessThan(simd_distance(rig.root.position(relativeTo:scene.world),destination.midpoint),0.00001)
        XCTAssertGreaterThan(Double(HamsterMotion.roundPauseMilliseconds)/1000,HamsterMotion.resolveDuration)
    }
    @MainActor func testDeliveredCharactersRunToTheirSeatsAndKeepFacingTheViewer() throws {
        for viewer in [Side.top,.bottom] {
            var before=BoardState(); before.tick=2
            before.score.top=1; before.score.bottom=1
            before.cells[0][0]=5; before.cells[5][5]=5
            before.balls=[Ball(id:21,row:0,col:0,exit:0),Ball(id:22,row:5,col:5,exit:2)]
            let scene=BoardScene(); scene.render(before,side:viewer)
            let originals=scene.hamsters, seated=scene.homeHamsters
            var after=before
            let turn=Rules.resolve(&after,top:nil,bottom:nil)
            XCTAssertEqual(turn.delivered.count,2)
            scene.animate(before:before,after:after,turn:turn,side:viewer)
            for _ in 0..<Int(ceil((HamsterMotion.resolveDuration+0.02)/0.02)) { scene.update(delta:0.02) }
            XCTAssertFalse(scene.isAnimating)
            for (ball,receiver) in turn.delivered {
                let seat=BoardScene.HomeSeat(receiver:receiver,index:1)
                let rig=try XCTUnwrap(scene.homeHamsters[seat])
                XCTAssertTrue(rig === originals[ball.id],"Delivery must keep the actual character")
                let start=rig.root.position(relativeTo:scene.world)
                scene.update(delta:0.12)
                XCTAssertGreaterThan(simd_distance(start,rig.root.position(relativeTo:scene.world)),0.001)
            }
            // The next authoritative update must keep both arrivals and seats.
            var later=after; later.tick += 1
            scene.render(later,side:viewer)
            for (seat,rig) in seated { XCTAssertTrue(scene.homeHamsters[seat] === rig) }
            for _ in 0..<200 { scene.update(delta:0.02) }
            XCTAssertEqual(scene.homeHamsters.count,4)
            for (seat,rig) in scene.homeHamsters {
                XCTAssertLessThan(simd_distance(rig.root.position(relativeTo:scene.world),scene.homePosition(seat)),0.00001)
                let forward=rig.root.orientation(relativeTo:nil).act(SIMD3<Float>(0,0,-1))
                XCTAssertGreaterThan(forward.z,0.99,"Both homes must face the camera for either player")
                XCTAssertGreaterThan(rig.body.position.y,0.20,"The character must sit upright")
                XCTAssertEqual(simd_length(rig.head.orientation.vector),1,accuracy:0.0001)
            }
            scene.render(BoardState(),side:viewer)
            XCTAssertTrue(scene.homeHamsters.isEmpty,"A new game must clear the homes")
        }
    }
    func testElbowsHaveCircularWallsAndAxialPortTangents() {
        for mask in [3,5,6,9,10,12] {
            let path=TubePath(center:.zero,mask:mask)
            let a=path.endpoint(path.ports[0]), b=path.endpoint(path.ports[1])
            XCTAssertLessThan(simd_distance(path.sample(0),a),0.00001)
            XCTAssertLessThan(simd_distance(path.sample(1),b),0.00001)
            XCTAssertGreaterThan(simd_dot(path.tangent(0),simd_normalize(-a)),0.99999)
            XCTAssertGreaterThan(simd_dot(path.tangent(1),simd_normalize(b)),0.99999)
            if path.isElbow {
                let center=a+b
                for step in 0...100 {
                    let point=path.sample(Float(step)/100)
                    XCTAssertEqual(simd_distance(point,center),TubePath.cell/2,accuracy:0.00001)
                    XCTAssertLessThan(distanceToBore(path.half(port:path.ports[0],towardPort:true,progress:Float(step)/100),path:path),0.00001)
                }
            }
        }
    }
    @MainActor func testCharacterMeshesStayInsideEveryCompatibleBendAndJoint() {
        let rig=HamsterRig(id:0)
        // Test real mesh vertices after all head/paw/ear transforms, rather
        // than only checking that the root is on the path centreline.
        func surfaces(_ entity: Entity) -> [(Entity,[SIMD3<Float>])] {
            var result: [(Entity,[SIMD3<Float>])] = []
            if let model=entity as? ModelEntity,let mesh=model.model?.mesh {
                let points=mesh.contents.models.flatMap { $0.parts.flatMap { Array($0.positions) } }
                result.append((entity,stride(from:0,to:points.count,by:4).map { points[$0] }))
            }
            return result+entity.children.flatMap { surfaces($0) }
        }
        let vertices=surfaces(rig.root)
        for mask in [3,5,6,9,10,12] {
            let source=TubePath(center:[0,TubePath.height,0],mask:mask)
            let sourceDistance=boreDistance(source)
            for exit in source.ports {
                let entry=(exit+2)%4, direction=simd_normalize(source.endpoint(exit)-source.center)
                for other in [3,5,6,9,10,12] where other & (1<<entry) != 0 {
                    for gap: Float in [0,TubePath.pitch-2*TubePath.cell] {
                        let destination=TubePath(center:source.center+direction*(TubePath.cell+gap),mask:other)
                        let destinationDistance=boreDistance(destination)
                        for step in 0...8 {
                            let t=Float(step)/8
                            rig.crawl(progress:t,time:Double(t),squeeze:max(0,1-abs(t-0.5)*4))
                            rig.followTube { source.travel(to:destination,exit:exit,progress:t,offset:$0) }
                            var worst: Float=0
                            for (entity,points) in vertices {
                                let transform=entity.transformMatrix(relativeTo:nil)
                                for point in points {
                                    let p=transform*SIMD4<Float>(point,1), world=SIMD3<Float>(p.x,p.y,p.z)
                                    var distance=min(sourceDistance(world),destinationDistance(world))
                                    if gap>0 { distance=min(distance,distanceToSegment(world,source.endpoint(exit),destination.endpoint(entry))) }
                                    worst=max(worst,distance)
                                }
                            }
                            XCTAssertLessThanOrEqual(worst,TubePath.radius-TubePath.wall,"mask \(mask)→\(other), exit \(exit), t \(t), gap \(gap)")
                        }
                    }
                }
            }
        }
        rig.rest(time:2)
        let path=TubePath(center:.zero,mask:3)
        for _ in 0..<100 {
            rig.rest(time:2); rig.followTube { path.fromMidpoint(toward:0,distance:$0) }
            for entity in [rig.root,rig.body,rig.head] {
                XCTAssertEqual(simd_length(entity.orientation.vector),1,accuracy:0.0001)
                XCTAssertTrue(entity.position.x.isFinite && entity.position.y.isFinite && entity.position.z.isFinite)
            }
        }
        XCTAssertGreaterThan(rig.body.scale.x,0.9,"Fitting must not compound scale across frames")
    }
    private func distanceToSegment(_ point: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let delta=b-a
        let t=max(0,min(1,simd_dot(point-a,delta)/max(0.000001,simd_length_squared(delta))))
        return simd_distance(point,a+delta*t)
    }
    private func distanceToBore(_ point: SIMD3<Float>, path: TubePath) -> Float {
        boreDistance(path)(point)
    }
    private func boreDistance(_ path: TubePath) -> (SIMD3<Float>) -> Float {
        let a=path.endpoint(path.ports[0]), b=path.endpoint(path.ports[1])
        if !path.isElbow { return { self.distanceToSegment($0,a,b) } }
        let center=a+b-path.center, u=simd_normalize(a-center), v=simd_normalize(b-center)
        return { point in
            let delta=point-center
            let angle=max(0,min(Float.pi/2,atan2(simd_dot(delta,v),simd_dot(delta,u))))
            return simd_distance(point,center+(u*cos(angle)+v*sin(angle))*TubePath.cell/2)
        }
    }
    func testEveryTubeUsesTheRulesPortsAndTravelIsContinuous() {
        for map in 0..<3 {
            let state=BoardState(map:map)
            for r in 0..<6 { for c in 0..<6 {
                let source=TubePath(row:r,col:c,state:state)
                for exit in source.ports {
                    let nr=r+[-1,0,1,0][exit], nc=c+[0,1,0,-1][exit]
                    guard (0..<6).contains(nr),(0..<6).contains(nc) else { continue }
                    let destination=TubePath(row:nr,col:nc,state:state)
                    guard destination.ports.contains((exit+2)%4) else { continue }
                    XCTAssertLessThan(simd_distance(source.travel(to:destination,exit:exit,progress:0),source.midpoint),0.00001)
                    XCTAssertLessThan(simd_distance(source.travel(to:destination,exit:exit,progress:1),destination.midpoint),0.00001)
                    var last=source.midpoint
                    for i in 1...200 {
                        let point=source.travel(to:destination,exit:exit,progress:Float(i)/200)
                        XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                        XCTAssertLessThan(simd_distance(last,point),0.025,"A hamster must not jump between tube sections")
                        XCTAssertGreaterThanOrEqual(point.y,TubePath.height-0.00001)
                        last=point
                    }
                }
            } }
        }
    }
    func testQuarterTurnsKeepHamstersOnTheRotatedTube() {
        for map in 0..<3 { for p in 0..<9 { for q in [-1,1,2] {
            var state=BoardState(map:map)
            let r=p/3*2,c=p%3*2
            let original=TubePath(row:r,col:c,state:state)
            let ball=Ball(id:1,row:r,col:c,exit:original.ports.first ?? 0)
            state.balls=[ball]
            let pivot=TubePath.tileCenter(p)
            let rotation=simd_quatf(angle:-Float(q) * .pi/2,axis:[0,1,0])
            let expected=pivot+rotation.act(original.midpoint-pivot)
            Rules.rotate(&state,platform:p,quarters:q)
            let rotated=state.balls[0]
            XCTAssertLessThan(simd_distance(expected,TubePath(row:rotated.row,col:rotated.col,state:state).midpoint),0.00001)
        } } }
    }
    @MainActor func testNativeRigHasFacePivotsAndSqueezesWithoutMutatingTheGame() {
        let rig=HamsterRig(id:4)
        XCTAssertEqual(rig.eyes.count,2)
        XCTAssertNotNil(rig.root.findEntity(named:"face-pivot"))
        for i in 0..<4 { XCTAssertNotNil(rig.root.findEntity(named:"paw-\(i)")) }
        rig.crawl(progress:0.5,time:1,squeeze:1)
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertLessThan(rig.body.scale.x,1)
            XCTAssertLessThan(rig.body.scale.y,1)
            XCTAssertGreaterThan(rig.body.scale.z,1)
        }
        rig.rest(time:2)
        XCTAssertEqual(rig.body.position,.zero)
    }
    @MainActor func testPrivateRotationCarriesTheWholeRigAndCooldownRejectsInput() {
        var state=BoardState(); state.balls=[Ball(id:1,row:2,col:2,exit:0)]
        let scene=BoardScene(); scene.render(state,side:.bottom)
        scene.setSelection(Command(platform:4,dir:1),highlighted:4,enabled:true,animated:false)
        let tile=scene.tiles[4]!
        let hamster=scene.hamsters[1]!
        XCTAssertTrue(hamster.root.parent === tile)
        let start=TubePath(row:2,col:2,state:state).midpoint
        let expected=simd_quatf(angle:-Float.pi/2,axis:[0,1,0]).act(start)
        XCTAssertLessThan(simd_distance(hamster.root.position(relativeTo:scene.world),expected),0.00001)
        scene.setSelection(nil,highlighted:nil,enabled:true,animated:false)
        XCTAssertLessThan(simd_distance(hamster.root.position(relativeTo:scene.world),start),0.00001)
    }
    @MainActor func testResolutionSurvivesImmediateOnlineActiveEventAndEndsAtAuthoritativeState() {
        let before=BoardState()
        var after=before
        let turn=Rules.resolve(&after,top:nil,bottom:Command(platform:4,dir:1))
        let scene=BoardScene(); scene.render(before,side:.bottom)
        scene.animate(before:before,after:after,turn:turn,side:.bottom)
        scene.render(after,side:.bottom) // The existing server can send this while interpolation is running.
        scene.setSelection(nil,highlighted:nil,enabled:true)
        for _ in 0..<80 { scene.update(delta:0.02) }
        XCTAssertFalse(scene.isAnimating)
        XCTAssertEqual(Set(scene.hamsters.keys),Set(after.balls.map(\.id)))
        for ball in after.balls {
            XCTAssertLessThan(simd_distance(scene.hamsters[ball.id]!.root.position(relativeTo:scene.world),TubePath(row:ball.row,col:ball.col,state:after).midpoint),0.00001)
        }
    }
    @MainActor func testRealityKitRendererDrivesTheRoundAnimation() async throws {
        let scene=BoardScene()
        let controller=UIViewController()
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        window.rootViewController=controller
        let renderer=scene.rendererView(); renderer.frame=controller.view.bounds
        controller.view.addSubview(renderer); window.makeKeyAndVisible()
        defer { renderer.removeFromSuperview(); window.isHidden=true }
        try await Task.sleep(for:.milliseconds(250))
        let before=BoardState(); var after=before
        let turn=Rules.resolve(&after,top:nil,bottom:Command(platform:4,dir:1))
        scene.animate(before:before,after:after,turn:turn,side:.bottom)
        try await Task.sleep(for:.seconds(2))
        XCTAssertFalse(scene.isAnimating,"The render loop must advance traversal without manual test updates")
        XCTAssertEqual(Set(scene.hamsters.keys),Set(after.balls.map(\.id)))
        for ball in after.balls {
            XCTAssertLessThan(simd_distance(scene.hamsters[ball.id]!.root.position(relativeTo:scene.world),TubePath(row:ball.row,col:ball.col,state:after).midpoint),0.00001)
        }
    }
    @MainActor func testHamsterLabAndLegacyInvitationsAreAccepted() {
        XCTAssertEqual(GameModel.roomCode("hamsterlab://join?code=ABCD7"),"ABCD7")
        XCTAssertEqual(GameModel.roomCode("twivvy://join?code=ABCD7"),"ABCD7")
        XCTAssertEqual(GameModel.roomCode("https://twivvy.e-notix.com/ABCD7"),"ABCD7")
        XCTAssertNil(GameModel.roomCode("https://other.example/ABCD7"))
    }
    @MainActor func testUnchangedPlatformsAndHamsterRigsSurviveRoundChanges() throws {
        var before=BoardState()
        before.balls=[Ball(id:99,row:0,col:0,exit:1)]
        before.nextBallId=100
        let scene=BoardScene(); scene.render(before,side:.bottom)
        let tiles=scene.tiles, hamster=try XCTUnwrap(scene.hamsters[99])
        var after=before
        let turn=Rules.resolve(&after,top:nil,bottom:Command(platform:4,dir:1))
        scene.animate(before:before,after:after,turn:turn,side:.bottom)
        for _ in 0..<80 { scene.update(delta:0.02) }
        for p in 0..<9 where p != 4 { XCTAssertTrue(scene.tiles[p] === tiles[p],"Platform \(p) must be reused") }
        XCTAssertTrue(scene.hamsters[99] === hamster)
        let survivor=try XCTUnwrap(after.balls.first(where:{$0.id==99}))
        let expected=TubePath(row:survivor.row,col:survivor.col,state:after).midpoint
        XCTAssertLessThan(simd_distance(hamster.root.position(relativeTo:scene.world),expected),0.00001)
        let tile=try XCTUnwrap(scene.tiles[4])
        XCTAssertEqual(tile.children.filter { $0.name.hasPrefix("source-") }.count,2)
        after.tick += 1; scene.render(after,side:.bottom)
        XCTAssertTrue(scene.tiles[4] === tile)
        XCTAssertEqual(tile.children.filter { $0.name.hasPrefix("source-") }.count,2,"Cached center must not duplicate spawn portals")
    }
    @MainActor func testOffscreenRendererPausesSceneAndCanBeReopened() {
        let scene=BoardScene(showcase:true), firstHost=UIView(), nextHost=UIView()
        let first=scene.rendererView(); firstHost.addSubview(first)
        XCTAssertEqual(first.scene.anchors.count,1)
        nextHost.addSubview(first)
        scene.pauseRenderer(from:firstHost)
        XCTAssertTrue(scene.view === first,"An outgoing orientation host must not release the adopted renderer")
        scene.pauseRenderer(from:nextHost)
        XCTAssertFalse(scene.anchor.isEnabled)
        XCTAssertTrue(first.isHidden)
        XCTAssertNil(first.superview)
        let reopened=scene.rendererView()
        XCTAssertTrue(reopened === first)
        XCTAssertTrue(scene.anchor.isEnabled)
        XCTAssertFalse(reopened.isHidden)
        XCTAssertEqual(reopened.scene.anchors.count,1)
    }
    @MainActor func testClearingPreviewBeforeItsFirstFrameCancelsRotation() async throws {
        let scene=BoardScene()
        scene.setSelection(Command(platform:4,dir:1),highlighted:4,enabled:true)
        scene.setSelection(nil,highlighted:nil,enabled:true)
        try await Task.sleep(for:.milliseconds(350))
        XCTAssertGreaterThan(abs(simd_dot(scene.tiles[4]!.orientation.vector,Transform.identity.rotation.vector)),0.99999)
    }
    @MainActor func testDetachedHostLayoutDoesNotRecreateAnOffscreenRenderer() throws {
        let scene=BoardScene(), replacement=BoardScene(showcase:true)
        let controller=UIViewController(), window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        window.rootViewController=controller
        let host=LabSceneHost(scene:scene); host.frame=controller.view.bounds
        controller.view.addSubview(host); window.makeKeyAndVisible()
        defer { host.removeFromSuperview(); window.isHidden=true }
        let original=try XCTUnwrap(scene.view)
        host.removeFromSuperview()
        XCTAssertFalse(scene.anchor.isEnabled)
        host.setNeedsLayout(); host.layoutIfNeeded()
        XCTAssertFalse(scene.anchor.isEnabled,"An offscreen layout must not restart the menu renderer")
        XCTAssertTrue(scene.view === original)
        controller.view.addSubview(host)
        XCTAssertNotNil(scene.view)
        XCTAssertTrue(scene.view === original)
        XCTAssertTrue(scene.anchor.isEnabled)
        host.scene=replacement
        XCTAssertFalse(scene.anchor.isEnabled)
        XCTAssertNotNil(replacement.view)
        host.removeFromSuperview()
        XCTAssertFalse(replacement.anchor.isEnabled)
    }
}
