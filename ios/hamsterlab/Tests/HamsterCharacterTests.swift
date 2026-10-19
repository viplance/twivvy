import XCTest
import RealityKit
import UIKit
import simd
@testable import HamsterLab

final class HamsterCharacterTests: XCTestCase {
    @MainActor func testSeatedCharacterRendersAndCanRunAgain() async throws {
        let renderer=ARView(frame:CGRect(x:0,y:0,width:650,height:650),cameraMode:.nonAR,automaticallyConfigureSession:false)
        renderer.renderOptions=[.disableMotionBlur,.disableCameraGrain,.disableDepthOfField]
        renderer.environment.background = .color(.white)
        let anchor=AnchorEntity(world:.zero), camera=PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees=36
        camera.look(at:[0,0.24,0],from:[0.36,0.55,-1.25],relativeTo:nil); anchor.addChild(camera)
        let light=DirectionalLight(); light.light.intensity=2000
        light.look(at:.zero,from:[-1,3,-2],relativeTo:nil); anchor.addChild(light)
        let fill=DirectionalLight(); fill.light.intensity=900
        fill.look(at:.zero,from:[2,2,-1],relativeTo:nil); anchor.addChild(fill)
        let rig=HamsterRig(id:0); anchor.addChild(rig.root)
        func lowestVertex(_ entity: Entity) -> Float {
            var lowest=Float.infinity
            if let model=entity as? ModelEntity,let mesh=model.model?.mesh {
                let matrix=entity.transformMatrix(relativeTo:anchor)
                for part in mesh.contents.models.flatMap({ $0.parts }) {
                    for point in part.positions {
                        lowest=min(lowest,(matrix*SIMD4<Float>(point,1)).y)
                    }
                }
            }
            for child in entity.children { lowest=min(lowest,lowestVertex(child)) }
            return lowest
        }
        anchor.addChild(LabGeometry.box([1.1,0.06,0.85],at:[0,-0.04,0],color:UIColor(lab:0xB4CEE8)))
        renderer.scene.addAnchor(anchor)
        let controller=UIViewController(), window=UIWindow(frame:renderer.bounds)
        window.rootViewController=controller; controller.view.addSubview(renderer); window.makeKeyAndVisible()
        defer { renderer.removeFromSuperview(); window.isHidden=true }
        for step in 0...2 {
            let t=Float(step)/2
            rig.root.position.y=0.16*(1-t)
            rig.sit(progress:t,time:Double(t))
            let bounds=rig.root.visualBounds(relativeTo:rig.root)
            XCTAssertLessThan(bounds.extents.y,0.8,"Sitting must preserve anatomical proportions")
            XCTAssertGreaterThan(lowestVertex(rig.root),-0.025,"Actual feet/haunches must stay on the home floor")
            try await Task.sleep(for:.milliseconds(250))
            let snapshot: UIImage? = await withCheckedContinuation { continuation in
                renderer.snapshot(saveToHDR:false) { continuation.resume(returning:$0) }
            }
            let attachment=XCTAttachment(image:try XCTUnwrap(snapshot))
            attachment.name="home-sit-\(step)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        rig.run(progress:0.2,time:2)
        XCTAssertEqual(rig.body.position.y,abs(sin(Float(0.2)*Float.pi*4))*0.010,accuracy:0.00001)
        XCTAssertEqual(rig.head.position,[0,0.029,-0.116])
        XCTAssertEqual(simd_length(rig.body.orientation.vector),1,accuracy:0.0001)
    }
    @MainActor func testCharacterInsideRenderedGlassElbows() async throws {
        let renderer=ARView(frame:CGRect(x:0,y:0,width:900,height:650),cameraMode:.nonAR,automaticallyConfigureSession:false)
        renderer.renderOptions=[.disableMotionBlur,.disableCameraGrain,.disableDepthOfField]
        renderer.environment.background = .color(.white)
        let anchor=AnchorEntity(world:.zero), camera=PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees=38
        camera.look(at:[0.48,0,0],from:[0.85,1.5,2.1],relativeTo:nil); anchor.addChild(camera)
        let light=DirectionalLight(); light.light.intensity=2200
        light.look(at:.zero,from:[-1,3,2],relativeTo:nil); anchor.addChild(light)
        let fill=DirectionalLight(); fill.light.intensity=1200
        fill.look(at:.zero,from:[2,2,-1],relativeTo:nil); anchor.addChild(fill)
        let source=TubePath(center:.zero,mask:3), destination=TubePath(center:[TubePath.cell,0,0],mask:12)
        for path in [source,destination] {
            anchor.addChild(LabGeometry.tubeAssembly(points:(0...28).map { path.sample(Float($0)/28) },tint:LabGeometry.mint))
        }
        anchor.addChild(LabGeometry.box([2.2,0.08,1.25],at:[0.49,-0.29,0],color:UIColor(lab:0xEDF5FF)))
        let rig=HamsterRig(id:0); anchor.addChild(rig.root); renderer.scene.addAnchor(anchor)
        let controller=UIViewController(), window=UIWindow(frame:renderer.bounds)
        window.rootViewController=controller; controller.view.addSubview(renderer); window.makeKeyAndVisible()
        defer { renderer.removeFromSuperview(); window.isHidden=true }
        for step in 0...4 {
            let progress=Float(step)/4
            rig.crawl(progress:progress,time:Double(progress),squeeze:sin(progress * .pi))
            rig.followTube { source.travel(to:destination,exit:1,progress:progress,offset:$0) }
            try await Task.sleep(for:.milliseconds(300))
            let snapshot: UIImage? = await withCheckedContinuation { continuation in
                renderer.snapshot(saveToHDR:false) { continuation.resume(returning:$0) }
            }
            let attachment=XCTAttachment(image:try XCTUnwrap(snapshot))
            attachment.name="glass-elbow-\(step)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        for step in 0...4 {
            let progress=Float(step)/4
            rig.turnAround(progress:progress,time:Double(progress),
                from:{ source.fromMidpoint(toward:1,distance:$0) },
                to:{ source.fromMidpoint(toward:0,distance:$0) })
            try await Task.sleep(for:.milliseconds(250))
            let snapshot: UIImage? = await withCheckedContinuation { continuation in
                renderer.snapshot(saveToHDR:false) { continuation.resume(returning:$0) }
            }
            let attachment=XCTAttachment(image:try XCTUnwrap(snapshot))
            attachment.name="glass-turn-\(step)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    @MainActor func testRepeatedSqueezesRestoreEveryArticulationAndKeepValidRotations() throws {
        let rig = HamsterRig(id: 4)
        let names = ["face-pivot", "smile-pivot", "sniff-nose", "paw-0", "paw-1", "paw-2", "paw-3"]
        let pivots = try names.map { try XCTUnwrap(rig.root.findEntity(named: $0)) }
        let original = pivots.map(\.transform)
        for round in 0..<8 {
            for frame in 0...30 {
                let progress = Float(frame) / 30
                rig.crawl(progress: progress, time: Double(round) + Double(progress), squeeze: sin(progress * .pi))
                for entity in pivots + [rig.body] {
                    XCTAssertEqual(simd_length(entity.orientation.vector), 1, accuracy: 0.0001)
                    XCTAssertTrue(entity.scale.x > 0 && entity.scale.y > 0 && entity.scale.z > 0)
                    XCTAssertTrue(entity.position.x.isFinite && entity.position.y.isFinite && entity.position.z.isFinite)
                }
            }
            // Toggling Reduce Motion while crawling must clear ALL face/limb
            // deformation, including cheek inflation and a partially shut blink.
            rig.refreshMotionPreferences()
            for (entity, expected) in zip(pivots, original) {
                XCTAssertLessThan(simd_distance(entity.position, expected.translation), 0.00001)
                XCTAssertLessThan(simd_distance(entity.scale, expected.scale), 0.00001)
                XCTAssertGreaterThan(abs(simd_dot(entity.orientation.vector, expected.rotation.vector)), 0.99999)
            }
            XCTAssertEqual(rig.body.scale, .one)
            XCTAssertEqual(rig.body.position, .zero)
        }
    }

    /// Capture the actual RealityKit character at readable size, from multiple
    /// directions and in a squeeze pose. Attachments stay in local test results.
    @MainActor func testCharacterTurnaroundAndSqueezeRenders() async throws {
        let renderer = ARView(frame: CGRect(x: 0, y: 0, width: 600, height: 600), cameraMode: .nonAR, automaticallyConfigureSession: false)
        renderer.renderOptions = [.disableMotionBlur, .disableCameraGrain, .disableDepthOfField]
        renderer.environment.background = .color(UIColor(lab: 0x213746))
        let anchor = AnchorEntity(world: .zero), camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 38
        anchor.addChild(camera)
        let key = DirectionalLight(); key.light.intensity = 1800; key.light.color = UIColor(lab: 0xFFF1DF)
        key.look(at: .zero, from: [-2, 3, -4], relativeTo: nil); anchor.addChild(key)
        let fill = DirectionalLight(); fill.light.intensity = 900
        fill.look(at: .zero, from: [3, 2, 1], relativeTo: nil); anchor.addChild(fill)
        let rig = HamsterRig(id: 0); anchor.addChild(rig.root)
        renderer.scene.addAnchor(anchor)
        let controller = UIViewController(), window = UIWindow(frame: renderer.bounds)
        window.rootViewController = controller; controller.view.addSubview(renderer); window.makeKeyAndVisible()
        defer { renderer.removeFromSuperview(); window.isHidden = true }
        let views: [(String, SIMD3<Float>)] = [
            ("character-front", [0, 0.20, -0.90]),
            ("character-three-quarter", [0.55, 0.30, -0.76]),
            ("character-profile", [0.90, 0.22, -0.05]),
            ("character-back", [0.40, 0.32, 0.85]),
            ("character-squeeze", [0.45, 0.25, -0.82])
        ]
        for (name, position) in views {
            camera.look(at: [0, 0, -0.02], from: position, relativeTo: nil)
            if name == "character-squeeze" { rig.crawl(progress: 0.38, time: 1, squeeze: 1) }
            else { rig.rest(time: 1) }
            try await Task.sleep(for: .milliseconds(350))
            let screenshot: UIImage? = await withCheckedContinuation { continuation in
                renderer.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let image = try XCTUnwrap(screenshot)
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
