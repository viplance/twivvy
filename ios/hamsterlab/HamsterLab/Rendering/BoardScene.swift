import RealityKit
import UIKit
import Combine
import simd

@MainActor final class BoardScene {
    var onSelect: ((Int, Int?) -> Void)?
    var onDragStart: (() -> Void)?
    var onTurnLimit: (() -> Void)?
    let anchor = AnchorEntity(world:.zero)
    let world = Entity()
    let camera = PerspectiveCamera()
    private(set) var tiles: [Int: Entity] = [:]
    private(set) var hamsters: [Int: HamsterRig] = [:]
    private(set) var isAnimating = false
    private var tileBases: [Int: ModelEntity] = [:]
    private var tileLayouts: [Int:[Int]] = [:]
    private var tileStyles: [Int:Int] = [:]
    private var tileContent = Entity()
    private var residents = Entity()
    private var state = BoardState()
    private var side: Side = .bottom
    private var enabled = false
    private var selection: Command?
    private var drag: Drag?
    private var transition: Transition?
    private var clock = 0.0
    weak var view: ARView?
    private var storedView: ARView?
    func rendererView() -> ARView {
        if let storedView { attach(to:storedView); return storedView }
        let created=ARView(frame:.zero,cameraMode:.nonAR,automaticallyConfigureSession:false)
        created.renderOptions = [.disableMotionBlur, .disableCameraGrain, .disableDepthOfField]
        storedView=created; attach(to:created); return created
    }
    let showcase: Bool
    private var hero: HamsterRig?
    private var updateSubscription: (any Cancellable)?
    private static var tubeTemplates: [String: Entity] = [:]
    private static var labelMeshes: [Int:MeshResource] = [:]
    private struct Drag { let platform: Int; let start: SIMD3<Float>; let angle: Float; let selected: Command?; var delta: Float = 0; var moved = false }
    private struct Transition {
        let after: BoardState
        let rotated: BoardState
        let turn: Turn
        var elapsed = 0.0
        var moving = false
    }

    init(showcase: Bool = false) {
        self.showcase=showcase
        anchor.addChild(world); world.addChild(tileContent); world.addChild(residents)
        configureCamera(); configureLighting()
        if showcase { buildShowcase() } else { buildEnvironment(); render(BoardState(),side:.bottom) }
    }
    func refreshMotionPreferences() {
        hero?.refreshMotionPreferences()
        if let transition {
            self.transition=nil; isAnimating=false
            render(transition.after,side:side)
        } else {
            hamsters.values.forEach { $0.refreshMotionPreferences() }
            setSelection(selection,highlighted:selection?.platform,enabled:enabled,animated:false)
        }
    }
    func attach(to view: ARView) {
        if self.view !== view {
            updateSubscription?.cancel(); updateSubscription=nil; self.view=view
            view.scene.addAnchor(anchor)
            view.environment.background = .color(UIColor(lab:0x102537))
            view.environment.lighting.intensityExponent = 0.6
        }
        view.isHidden=false; anchor.isEnabled=true
        guard updateSubscription == nil else { return }
        updateSubscription = view.scene.subscribe(to:SceneEvents.Update.self) { [weak self] event in
            let delta=event.deltaTime
            Task { @MainActor [weak self] in self?.update(delta:delta) }
        }
    }
    /// Retain the renderer across SwiftUI layout changes: moving a camera's
    /// anchor to a new ARView can leave the replacement without an active camera.
    /// A hidden scene has no updates, enabled entities or visible render target.
    func pauseRenderer(from host: UIView) {
        guard let view, view.superview === host else { return }
        updateSubscription?.cancel(); updateSubscription=nil
        anchor.isEnabled=false; view.isHidden=true
        view.removeFromSuperview()
    }
    private func configureCamera() {
        camera.camera.fieldOfViewInDegrees = showcase ? 38 : 43
        camera.position = showcase ? [0,3.25,5.4] : [0,8.8,7.0]
        camera.look(at:showcase ? [0,0.75,0] : [0,0.05,0.65],from:camera.position,relativeTo:nil)
        anchor.addChild(camera)
    }
    private func configureLighting() {
        let key=DirectionalLight(); key.light.color=UIColor(lab:0xFFF0DE); key.light.intensity=2400
        key.look(at:.zero,from:[-4,8,5],relativeTo:nil)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance:18,depthBias:2)
        anchor.addChild(key)
        let fill=DirectionalLight(); fill.light.color=UIColor(lab:0xA4D9FF); fill.light.intensity=1200
        fill.look(at:.zero,from:[5,4,-3],relativeTo:nil); anchor.addChild(fill)
        let rim=PointLight(); rim.light.color=LabGeometry.lavender; rim.light.intensity=400
        rim.light.attenuationRadius=15; rim.position=[0,4,-4]; anchor.addChild(rim)
    }
    private func buildEnvironment() {
        world.addChild(LabGeometry.box([7.15,0.28,7.65],at:[0,-0.25,0],color:UIColor(lab:0x203C50),radius:0.24))
        world.addChild(LabGeometry.box([6.86,0.06,6.85],at:[0,-0.065,0],color:UIColor(lab:0x698090),radius:0.17))
        // Corner fasteners, tiny status LEDs, and the laboratory workbench.
        for x: Float in [-3.34,3.34] { for z: Float in [-3.46,3.46] {
            world.addChild(LabGeometry.ellipsoid([0.055,0.02,0.055],at:[x,-0.08,z],color:UIColor(lab:0xB5CBD1)))
            world.addChild(LabGeometry.line(from:[x,-0.055,z-0.025],to:[x,-0.055,z+0.025],width:0.008,color:LabGeometry.ink))
        } }
        for x: Float in [-3.44,3.44] {
            for i in 0..<5 {
                let lamp=ModelEntity(mesh:.generateSphere(radius:0.025),materials:[LabGeometry.glow(i<3 ? LabGeometry.mint : LabGeometry.lavender)])
                lamp.position=[x,0,Float(i)*0.16-0.3]; world.addChild(lamp)
            }
        }
    }
    private func buildShowcase() {
        world.addChild(LabGeometry.box([4.5,0.22,2.9],at:[0,-0.20,0],color:UIColor(lab:0x6B8291),radius:0.28))
        world.addChild(LabGeometry.box([4.32,0.10,2.72],at:[0,-0.04,0],color:UIColor(lab:0xB7C9D0),radius:0.24))
        let points=(0...30).map { i -> SIMD3<Float> in
            let t=Float(i)/30
            return [-2.0+4*t,0.92,sin(t * .pi*2)*0.38]
        }
        world.addChild(LabGeometry.tubeAssembly(points:points,tint:LabGeometry.mint,radius:0.74))
        for x: Float in [-1.7,1.7] {
            world.addChild(LabGeometry.box([0.13,0.70,0.65],at:[x,0.31,0],color:LabGeometry.lavender,radius:0.04))
        }
        let hamster=HamsterRig(id:0); hamster.root.position=[-0.12,0.93,0]; hamster.root.scale = .init(repeating:4.0)
        hamster.root.orientation=simd_quatf(angle:.pi-0.22,axis:[0,1,0]); world.addChild(hamster.root); hero=hamster
        // A flask and a rack of specimen vials reinforce the miniature lab.
        let flask=Entity(); flask.position=[1.46,0.37,-0.85]
        let sphere=LabGeometry.ellipsoid([0.32,0.34,0.32],at:.zero,color:LabGeometry.mint)
        sphere.model?.materials=[LabGeometry.glass()]; flask.addChild(sphere)
        flask.addChild(LabGeometry.ellipsoid([0.28,0.13,0.28],at:[0,-0.12,0],color:LabGeometry.lavender))
        flask.addChild(LabGeometry.tubeAssembly(points:[[0,0.23,0],[0,0.70,0]],tint:LabGeometry.lavender,radius:0.13))
        world.addChild(flask)
        for i in 0..<3 {
            world.addChild(LabGeometry.tubeAssembly(points:[[-1.6+Float(i)*0.23,0.08,-0.96],[-1.6+Float(i)*0.23,0.63,-0.96]],tint:i==1 ? LabGeometry.pink : LabGeometry.mint,radius:0.075))
        }
    }
    func render(_ state: BoardState, side: Side) {
        guard !showcase else { return }
        if let transition, transition.after == state { return }
        if !tiles.isEmpty,self.state==state,self.side==side {
            setSelection(selection,highlighted:selection?.platform,enabled:enabled,animated:false)
            return
        }
        self.transition=nil; isAnimating=false; drag=nil
        self.state=state; self.side=side
        world.orientation=simd_quatf(angle:side == .top ? .pi : 0,axis:[0,1,0])
        let remaining=Set(state.balls.map(\.id))
        for id in Array(hamsters.keys) where !remaining.contains(id) {
            hamsters.removeValue(forKey:id)?.root.removeFromParent()
        }
        hamsters.values.forEach { $0.root.removeFromParent() }
        rebuildTiles(state); rebuildReceivers(state)
        for ball in state.balls { install(ball,in:state) }
        setSelection(selection,highlighted:selection?.platform,enabled:enabled,animated:false)
    }
    private func rebuildTiles(_ state: BoardState) {
        let palette=[LabGeometry.mint,LabGeometry.lavender,LabGeometry.pink]
        var rebuiltCenter=false
        for p in 0..<9 {
            let layout=(0..<4).map { state.cells[p/3*2+$0/2][p%3*2+$0%2] }
            if let tile=tiles[p],tileLayouts[p]==layout {
                tile.stopAllAnimations(recursive:false)
                tile.orientation=Transform.identity.rotation
                continue
            }
            tiles[p]?.removeFromParent()
            tileLayouts[p]=layout; tileStyles[p]=nil
            if p==4 { rebuiltCenter=true }
            let tile=Entity(); tile.name="platform-\(p)"; tile.position=TubePath.tileCenter(p)
            let tint=palette[(p+p/3)%3]
            tile.addChild(LabGeometry.box([2.06,0.10,2.06],at:[0,0.02,0],color:UIColor(lab:0x263D54),radius:0.14))
            let base=LabGeometry.box([1.99,0.08,1.99],at:[0,0.10,0],color:UIColor(lab:0x527184),radius:0.13)
            base.name="base"; tile.addChild(base); tileBases[p]=base
            // Drag/tap selection uses boardPoint's ray/plane intersection;
            // invisible physics/collision meshes are unnecessary.
            for r in 0..<2 { for c in 0..<2 {
                let mask=state.cells[p/3*2+r][p%3*2+c]
                let center=SIMD3<Float>(Float(c)*TubePath.cell-TubePath.cell/2,TubePath.height,Float(r)*TubePath.cell-TubePath.cell/2)
                if mask != 0 {
                    let key="\(mask)-\((p+p/3)%3)"
                    let template: Entity
                    if let cached=Self.tubeTemplates[key] { template=cached }
                    else {
                        let path=TubePath(center:[0,TubePath.height,0],mask:mask)
                        let points=(0...18).map { path.sample(Float($0)/18) }
                        template=LabGeometry.tubeAssembly(points:points,tint:tint)
                        Self.tubeTemplates[key]=template
                    }
                    let tube=template.clone(recursive:true); tube.position=[center.x,0,center.z]; tile.addChild(tube)
                } else {
                    let dot=ModelEntity(mesh:.generateSphere(radius:0.025),materials:[LabGeometry.material(tint)])
                    dot.position=[center.x,0.17,center.z]; tile.addChild(dot)
                }
            } }
            let labelMesh: MeshResource
            if let cached=Self.labelMeshes[p] { labelMesh=cached }
            else {
                labelMesh = .generateText(String(format:"%02d",p+1),extrusionDepth:0.001,font:.monospacedSystemFont(ofSize:0.11,weight:.bold))
                Self.labelMeshes[p]=labelMesh
            }
            let label=ModelEntity(mesh:labelMesh,materials:[LabGeometry.material(UIColor(lab:0xB8D2DC))])
            label.position=[-0.88,0.15,0.91]; label.orientation=simd_quatf(angle:-.pi/2,axis:[1,0,0]); tile.addChild(label)
            tileContent.addChild(tile); tiles[p]=tile
        }
        guard rebuiltCenter else { return }
        for (i,cell) in [(2,2),(3,3)].enumerated() {
            let path=TubePath(row:cell.0,col:cell.1,state:state)
            guard let tile=tiles[4] else { continue }
            let portal=Entity(); portal.name="source-\(i)"; portal.position=path.midpoint-TubePath.tileCenter(4)
            let ring=LabGeometry.collar(at:.zero,tangent:[0,1,0.01],color:UIColor(lab:0xFFD888),radius:0.26)
            portal.addChild(ring)
            // Two gold docking lamps identify the two fixed spawn cells.
            portal.addChild(LabGeometry.ellipsoid([0.045,0.045,0.045],at:[i==0 ? -0.28 : 0.28,-0.04,0],color:UIColor(lab:0xFFD888)))
            tile.addChild(portal)
        }
    }
    private func rebuildReceivers(_ state: BoardState) {
        residents.children.removeAll()
        for receiver in [Side.top,.bottom] {
            let tint=receiver == side ? LabGeometry.mint : LabGeometry.pink
            let z: Float=receiver == .top ? -3.67 : 3.67
            residents.addChild(LabGeometry.box([5.9,0.12,0.43],at:[0,0.03,z],color:UIColor(lab:0x314D60),radius:0.12))
            for i in 0..<max(7,state.score[receiver]) {
                let x=Float(i)*0.34-Float(max(7,state.score[receiver])-1)*0.17
                if i < state.score[receiver] {
                    let head=LabGeometry.ellipsoid([0.12,0.10,0.10],at:[x,0.16,z],color:LabGeometry.cream)
                    residents.addChild(head)
                    for sign: Float in [-1,1] {
                        residents.addChild(LabGeometry.ellipsoid([0.035,0.04,0.025],at:[x+sign*0.08,0.23,z],color:LabGeometry.pink))
                    }
                } else {
                    let dot=ModelEntity(mesh:.generateSphere(radius:0.035),materials:[LabGeometry.glow(tint.withAlphaComponent(0.45))]); dot.position=[x,0.12,z]; residents.addChild(dot)
                }
            }
        }
    }
    private func install(_ ball: Ball, in state: BoardState) {
        let hamster=hamsters[ball.id] ?? HamsterRig(id:ball.id)
        let tile=tiles[Rules.platform(ball.row,ball.col)]!
        tile.addChild(hamster.root)
        hamster.root.position=TubePath(row:ball.row,col:ball.col,state:state).midpoint-TubePath.tileCenter(Rules.platform(ball.row,ball.col))
        hamster.root.orientation=simd_quatf(angle:TubePath.heading(exit:ball.exit),axis:[0,1,0])
        hamster.root.scale = .one
        hamster.rest(time:clock)
        hamsters[ball.id]=hamster
    }
    func setSelection(_ selection: Command?, highlighted: Int?, enabled: Bool, animated: Bool = true) {
        self.selection=selection; self.enabled=enabled
        guard !isAnimating else { return }
        for (p,tile) in tiles {
            let selected=selection?.platform == p
            let hot=state.cooldown.contains(p)
            let style=hot ? 2 : selected ? 1 : 0
            if tileStyles[p] != style {
                tileBases[p]?.model?.materials=[LabGeometry.material(hot ? UIColor(lab:0x9B687C) : selected ? UIColor(lab:0xC5AE72) : UIColor(lab:0x527184))]
                tileStyles[p]=style
            }
            guard drag?.platform != p else { continue }
            let angle=selected ? -Float(selection!.dir) * .pi/2 : 0
            let transform=Transform(scale:.one,rotation:simd_quatf(angle:angle,axis:[0,1,0]),translation:tile.position)
            if abs(simd_dot(tile.orientation.vector,transform.rotation.vector)) > 0.999999 {
                // A selection may be cleared before its animation's first frame.
                tile.stopAllAnimations(recursive:false); tile.transform=transform
                continue
            }
            if animated && !UIAccessibility.isReduceMotionEnabled { tile.move(to:transform,relativeTo:tile.parent,duration:0.25,timingFunction:.easeInOut) }
            else { tile.stopAllAnimations(recursive:false); tile.transform=transform }
        }
    }
    func animate(before: BoardState, after: BoardState, turn: Turn, side: Side) {
        let visible=tiles.mapValues { $0.transform }
        selection=nil; enabled=false; transition=nil; drag=nil
        if self.state != before || self.side != side { render(before,side:side) }
        tiles.values.forEach { $0.stopAllAnimations(recursive:false) }
        guard !UIAccessibility.isReduceMotionEnabled else { render(after,side:side); return }
        isAnimating=true
        var rotated=before; rotated.balls.append(contentsOf:turn.spawned)
        for ball in turn.spawned {
            install(ball,in:before)
            if let root=hamsters[ball.id]?.root {
                let destination=root.transform
                root.scale = .init(repeating:0.1)
                root.move(to:destination,relativeTo:root.parent,duration:0.24,timingFunction:.easeOut)
            }
        }
        for p in Set(turn.rotations.keys).union(visible.keys) {
            guard let tile=tiles[p] else { continue }
            if let transform=visible[p] { tile.transform=transform }
            let q=turn.rotations[p,default:0]
            let target=Transform(scale:.one,rotation:simd_quatf(angle:-Float(q) * .pi/2,axis:[0,1,0]),translation:tile.position)
            if abs(simd_dot(tile.orientation.vector,target.rotation.vector)) < 0.999999 {
                tile.move(to:target,relativeTo:tile.parent,duration:0.38,timingFunction:.easeInOut)
            }
            Rules.rotate(&rotated,platform:p,quarters:q)
        }
        transition=Transition(after:after,rotated:rotated,turn:turn)
        AudioEngine.shared.play(turn.spawned.isEmpty ? "crawl" : "chirp")
    }
    func update(delta: Double) {
        clock += delta
        if let hero { hero.rest(time:clock) }
        guard var transition else {
            for hamster in hamsters.values { hamster.rest(time:clock) }
            return
        }
        transition.elapsed += delta
        if transition.elapsed >= 0.4 && !transition.moving {
            for hamster in hamsters.values {
                let t=hamster.root.transformMatrix(relativeTo:world)
                hamster.root.removeFromParent(); world.addChild(hamster.root); hamster.root.setTransformMatrix(t,relativeTo:world)
            }
            rebuildTiles(transition.after)
            transition.moving=true
        }
        if transition.moving {
            let t=min(1,Float((transition.elapsed-0.4)/0.68))
            for ball in transition.after.balls {
                guard let origin=transition.rotated.balls.first(where:{$0.id==ball.id}), let hamster=hamsters[ball.id] else { continue }
                let source=TubePath(row:origin.row,col:origin.col,state:transition.rotated)
                if origin.row != ball.row || origin.col != ball.col {
                    let destination=TubePath(row:ball.row,col:ball.col,state:transition.after)
                    let point=source.travel(to:destination,exit:origin.exit,progress:t)
                    let ahead=source.travel(to:destination,exit:origin.exit,progress:min(1,t+0.015))
                    let behind=source.travel(to:destination,exit:origin.exit,progress:max(0,t-0.015))
                    hamster.root.position=point
                    let d=ahead-behind
                    if simd_length(d)>0.0001 { hamster.root.orientation=simd_quatf(angle:atan2(-d.x,-d.z),axis:[0,1,0]) }
                    let squeeze=max(0,1-abs(t-0.5)*4)
                    hamster.crawl(progress:t,time:clock,squeeze:squeeze)
                } else {
                    hamster.root.position=source.midpoint
                    hamster.root.orientation=simd_quatf(angle:TubePath.heading(exit:ball.exit),axis:[0,1,0]); hamster.rest(time:clock)
                }
            }
            for (ball,receiver) in transition.turn.delivered {
                guard let hamster=hamsters[ball.id] else { continue }
                let source=TubePath(row:ball.row,col:ball.col,state:transition.rotated)
                let end=SIMD3<Float>(source.endpoint(ball.exit).x,TubePath.height,receiver == .top ? -3.67 : 3.67)
                let point: SIMD3<Float>
                if t<0.65 { point=source.half(port:ball.exit,towardPort:true,progress:t/0.65) }
                else { point=simd_mix(source.endpoint(ball.exit),end,.init(repeating:(t-0.65)/0.35)) }
                hamster.root.position=point
                hamster.root.orientation=simd_quatf(angle:TubePath.heading(exit:ball.exit),axis:[0,1,0])
                hamster.crawl(progress:t,time:clock,squeeze:max(0,1-abs(t-0.6)*5))
            }
        }
        if transition.elapsed >= 1.1 {
            let final=transition.after
            self.transition=nil; isAnimating=false
            // The final tube layout is already installed. Keep the articulated
            // models instead of allocating a second scene at every round end.
            self.state=final
            let remaining=Set(final.balls.map(\.id))
            for id in Array(hamsters.keys) where !remaining.contains(id) {
                hamsters.removeValue(forKey:id)?.root.removeFromParent()
            }
            for ball in final.balls {
                guard let hamster=hamsters[ball.id],let tile=tiles[Rules.platform(ball.row,ball.col)] else { continue }
                hamster.root.stopAllAnimations(recursive:false)
                hamster.root.removeFromParent(); tile.addChild(hamster.root)
                hamster.root.position=TubePath(row:ball.row,col:ball.col,state:final).midpoint-TubePath.tileCenter(Rules.platform(ball.row,ball.col))
                hamster.root.orientation=simd_quatf(angle:TubePath.heading(exit:ball.exit),axis:[0,1,0])
                hamster.root.scale = .one
                hamster.rest(time:clock)
            }
            rebuildReceivers(final)
            setSelection(selection,highlighted:selection?.platform,enabled:enabled,animated:false)
            if !transition.turn.delivered.isEmpty {
                AudioEngine.shared.play("happy")
                for (ball,receiver) in transition.turn.delivered {
                    let visitor=HamsterRig(id:ball.id)
                    visitor.root.position=[TubePath(row:ball.row,col:ball.col,state:transition.rotated).endpoint(ball.exit).x,0.30,receiver == .top ? -3.67 : 3.67]
                    visitor.root.orientation=simd_quatf(angle:side == .top ? 0 : .pi,axis:[0,1,0])
                    residents.addChild(visitor.root); visitor.celebrate()
                    Task { @MainActor in
                        try? await Task.sleep(for:.milliseconds(700))
                        visitor.root.removeFromParent()
                    }
                }
            }
        } else { self.transition=transition }
    }
    func accessibilityFrame(platform p: Int, size: CGSize) -> CGRect {
        if let view,view.bounds.width>0,view.bounds.height>0 {
            let center=TubePath.tileCenter(p)+[0,TubePath.height,0]
            let points: [CGPoint] = [SIMD3<Float>(-0.98,0,-0.98),[0.98,0,-0.98],[-0.98,0,0.98],[0.98,0,0.98]].compactMap {
                view.project(world.convert(position:center+$0,to:nil))
            }
            if points.count==4 {
                let sx=size.width/view.bounds.width, sy=size.height/view.bounds.height
                let left=points.map(\.x).min()! * sx, top=points.map(\.y).min()! * sy
                let right=points.map(\.x).max()! * sx, bottom=points.map(\.y).max()! * sy
                return CGRect(x:left,y:top,width:right-left,height:bottom-top)
            }
        }
        let index=side == .top ? 8-p : p
        return CGRect(x:CGFloat(index%3)*size.width/3,y:CGFloat(index/3)*size.height/3,width:size.width/3,height:size.height/3)
    }
    private func boardPoint(_ location: CGPoint) -> SIMD3<Float>? {
        guard let ray=view?.ray(through:location), abs(ray.direction.y)>0.0001 else { return nil }
        let t=(TubePath.height-ray.origin.y)/ray.direction.y
        guard t>0 else { return nil }
        return world.convert(position:ray.origin+ray.direction*t,from:nil)
    }
    func platform(at point: SIMD3<Float>) -> Int? {
        let col=Int(round(point.x/TubePath.pitch))+1, row=Int(round(point.z/TubePath.pitch))+1
        guard (0..<3).contains(row),(0..<3).contains(col) else { return nil }
        let p=row*3+col, local=point-TubePath.tileCenter(p)
        return abs(local.x)<=1.04 && abs(local.z)<=1.04 ? p : nil
    }
    func dragChanged(start: CGPoint, location: CGPoint) {
        guard enabled,!isAnimating,let point=boardPoint(location) else { return }
        if drag == nil {
            guard let initial=boardPoint(start),let p=platform(at:initial),!state.cooldown.contains(p) else { return }
            onDragStart?(); tiles[p]?.stopAllAnimations(recursive:false)
            let local=initial-TubePath.tileCenter(p)
            drag=Drag(platform:p,start:initial,angle:atan2(local.z,local.x),selected:selection)
        }
        guard var drag,let tile=tiles[drag.platform] else { return }
        let local=point-TubePath.tileCenter(drag.platform)
        var delta=atan2(local.z,local.x)-drag.angle
        delta=atan2(sin(delta),cos(delta))
        if simd_distance(point,drag.start)>0.08 { drag.moved=true }
        drag.delta=delta; self.drag=drag
        let startAngle=drag.selected?.platform == drag.platform ? -Float(drag.selected!.dir) * .pi/2 : 0
        tile.orientation=simd_quatf(angle:startAngle-delta,axis:[0,1,0])
    }
    func dragEnded(at point: CGPoint) { finishDrag() }
    func finishDrag(cancelled: Bool = false) {
        guard let drag else { return }
        self.drag=nil
        guard !cancelled else { setSelection(selection,highlighted:selection?.platform,enabled:enabled); return }
        if !drag.moved { onSelect?(drag.platform,nil) }
        else if abs(drag.delta)>0.14 {
            let direction=drag.delta>0 ? 1 : -1
            if let selected=drag.selected, selected.platform==drag.platform {
                if selected.dir==direction { onTurnLimit?(); setSelection(selection,highlighted:selection?.platform,enabled:enabled) }
                else { onSelect?(drag.platform,nil) }
            } else { onSelect?(drag.platform,direction) }
        } else { setSelection(selection,highlighted:selection?.platform,enabled:enabled) }
    }
}
