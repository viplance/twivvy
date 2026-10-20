import RealityKit
import UIKit
import Combine
import simd

@MainActor final class BoardScene {
    var onSelect: ((Int, Int?) -> Void)?
    var onDragStart: (() -> Void)?
    var onTurnLimit: (() -> Void)?
    var onTurnaround: (() -> Void)?
    let anchor = AnchorEntity(world:.zero)
    let world = Entity()
    let camera = PerspectiveCamera()
    private(set) var tiles: [Int: Entity] = [:]
    private(set) var hamsters: [Int: HamsterRig] = [:]
    struct HomeSeat: Hashable {
        let receiver: Side
        let index: Int
    }
    private(set) var homeHamsters: [HomeSeat:HamsterRig] = [:]
    private struct Arrival {
        let start: SIMD3<Float>
        let orientation: simd_quatf
        let started: Double
        let duration: Double
        var turnCuePlayed=false
    }
    private var arrivals: [HomeSeat:Arrival] = [:]
    private(set) var isAnimating = false
    private var tileBases: [Int: ModelEntity] = [:]
    private var tileLayouts: [Int:[Int]] = [:]
    private var tileStyles: [Int:Int] = [:]
    private var tileContent = Entity()
    private var residents = Entity()
    private var homeFurniture = Entity()
    private var couplers = Entity()
    private static var couplerTemplate: Entity?
    private var state = BoardState()
    private var side: Side = .bottom
    private var enabled = false
    private var selection: Command?
    private var drag: Drag?
    private var transition: Transition?
    private var clock = 0.0
    private struct Smoke {
        let root: Entity
        let path: TubePath
        let exit: Int
        var elapsed = 0.0
    }
    private var smoke: Smoke?
    private static let smokeMesh = MeshResource.generateSphere(radius:1)
    /// A small fixed pool, attached to the tube's tile so dragging/rotation
    /// cannot separate the puff from its glass enclosure.
    func showOopsSmoke() {
        guard !showcase, !isAnimating,
              let ball=state.balls.filter({ hamsters[$0.id] != nil }).randomElement(),
              let tile=tiles[Rules.platform(ball.row,ball.col)] else { return }
        clearOopsSmoke()
        let root=Entity(); root.name="oops-smoke"
        tile.addChild(root)
        for _ in 0..<7 {
            root.addChild(ModelEntity(mesh:Self.smokeMesh,materials:[UnlitMaterial(color:.green)]))
        }
        smoke=Smoke(root:root,path:TubePath(row:ball.row,col:ball.col,state:state),exit:ball.exit)
        updateOopsSmoke(delta:0)
    }
    private func clearOopsSmoke() {
        smoke?.root.removeFromParent(); smoke=nil
    }
    private func updateOopsSmoke(delta: Double) {
        guard var smoke else { return }
        smoke.elapsed += delta
        guard smoke.elapsed < 1.35 else { clearOopsSmoke(); return }
        let t=Float(smoke.elapsed/1.35)
        let offset=smoke.root.parent?.position ?? .zero
        for (i,child) in smoke.root.children.enumerated() {
            guard let puff=child as? ModelEntity else { continue }
            let phase=Float(i)*2.4
            let radius: Float=0.035+0.045*min(1,t*3)+Float(i%3)*0.008
            // Every sphere stays within the bore and before the open end.
            // Its centre follows the actual elbow, never a straight tangent.
            let distance=min(0.235+t*0.12+Float(i)*0.008,smoke.path.length/2-radius-0.045)
            let radial=SIMD3<Float>(cos(phase)*0.025,sin(phase)*0.025+t*0.035,0)
            puff.position=smoke.path.fromMidpoint(toward:smoke.exit,distance:-distance)-offset+radial
            puff.scale = .init(repeating:radius)
            var material=UnlitMaterial(color:UIColor(lab:i%2 == 0 ? 0x88C94E : 0xACDA69))
            material.blending = .transparent(opacity:.init(floatLiteral:0.46*(1-t)*min(1,0.2+t*12)))
            puff.model?.materials=[material]
        }
        self.smoke=smoke
    }
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
    private struct Drag { let platform: Int; let start: SIMD3<Float>; let angle: Float; let selected: Command?; var delta: Float = 0; var moved = false }
    private struct Transition {
        let after: BoardState
        let rotated: BoardState
        let turn: Turn
        var elapsed = 0.0
        var moving = false
        var turnsAround = false
    }

    init(showcase: Bool = false) {
        self.showcase=showcase
        anchor.addChild(world); world.addChild(tileContent); world.addChild(residents); world.addChild(couplers)
        residents.addChild(homeFurniture)
        configureCamera(); configureLighting()
        if showcase { buildShowcase() } else { buildEnvironment(); render(BoardState(),side:.bottom) }
    }
    func refreshMotionPreferences() {
        hero?.refreshMotionPreferences()
        homeHamsters.values.forEach { $0.refreshMotionPreferences() }
        if UIAccessibility.isReduceMotionEnabled { arrivals.removeAll() }
        updateHomes()
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
            view.environment.background = .color(UIColor(lab:0xFFFFFF))
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
        clearOopsSmoke()
        updateSubscription?.cancel(); updateSubscription=nil
        anchor.isEnabled=false; view.isHidden=true
        view.removeFromSuperview()
    }
    func resizeViewport(_ size: CGSize) {
        guard !showcase, size.width > 0, size.height > 0 else { return }
        // Preserve the board's horizontal framing as its canvas becomes shorter.
        // A minimum vertical angle keeps both homes visible in wide layouts.
        let aspect = Float(size.width / size.height)
        let halfHorizontal = tan(Float.pi * 46 / 360) * (720.0 / 828.0)
        let fieldOfView = max(38, 2 * atan(halfHorizontal / aspect) * 180 / .pi)
        if abs(camera.camera.fieldOfViewInDegrees - fieldOfView) > 0.01 {
            camera.camera.fieldOfViewInDegrees = fieldOfView
        }
    }
    private func configureCamera() {
        camera.camera.fieldOfViewInDegrees = showcase ? 38 : 46
        camera.position = showcase ? [0,3.25,5.4] : [0,8.8,7.0]
        camera.look(at:showcase ? [0,0.75,0] : [0,0.05,0.65],from:camera.position,relativeTo:nil)
        anchor.addChild(camera)
    }
    private func configureLighting() {
        let key=DirectionalLight(); key.light.color=UIColor(lab:0xF5F9FF); key.light.intensity=2400
        key.look(at:.zero,from:[-4,8,5],relativeTo:nil)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance:18,depthBias:2)
        anchor.addChild(key)
        let fill=DirectionalLight(); fill.light.color=UIColor(lab:0xA4D9FF); fill.light.intensity=1200
        fill.look(at:.zero,from:[5,4,-3],relativeTo:nil); anchor.addChild(fill)
        let rim=PointLight(); rim.light.color=LabGeometry.lavender; rim.light.intensity=400
        rim.light.attenuationRadius=15; rim.position=[0,4,-4]; anchor.addChild(rim)
    }
    private func buildEnvironment() {
        world.addChild(LabGeometry.box([7.15,0.28,7.65],at:[0,-0.25,0],color:UIColor(lab:0xB5CCE3),radius:0.24))
        world.addChild(LabGeometry.box([6.86,0.06,6.85],at:[0,-0.065,0],color:UIColor(lab:0xDFECFA),radius:0.17))
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
            return TubePath.quadratic([-2.0,0.92,-0.65],[0,0.92,-0.65],[0,0.92,1.12],t)
        }
        world.addChild(LabGeometry.tubeAssembly(points:points,tint:LabGeometry.mint,radius:0.74))
        for position: SIMD3<Float> in [[-1.70,0.31,-0.62],[-0.08,0.31,0.69]] {
            world.addChild(LabGeometry.box([0.65,0.70,0.13],at:position,color:LabGeometry.lavender,radius:0.04))
        }
        // The hero peeks from the open end, along the tube's actual axis.
        let hamster=HamsterRig(id:0); hamster.root.position=[-0.08,0.93,0.22]; hamster.root.scale = .init(repeating:4.0)
        hamster.root.orientation=simd_quatf(angle:.pi-0.08,axis:[0,1,0]); world.addChild(hamster.root); hero=hamster
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
        clearOopsSmoke()
        self.state=state; self.side=side
        world.orientation=simd_quatf(angle:side == .top ? .pi : 0,axis:[0,1,0])
        let remaining=Set(state.balls.map(\.id))
        for id in Array(hamsters.keys) where !remaining.contains(id) {
            hamsters.removeValue(forKey:id)?.root.removeFromParent()
        }
        hamsters.values.forEach { $0.root.removeFromParent() }
        rebuildTiles(state); rebuildCouplers(state); rebuildReceivers(state)
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
            tile.addChild(LabGeometry.box([2.06,0.10,2.06],at:[0,0.02,0],color:UIColor(lab:0x6B9BC6),radius:0.14))
            let base=LabGeometry.box([1.99,0.08,1.99],at:[0,0.10,0],color:UIColor(lab:0xC4DEF4),radius:0.13)
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
                        let points=(0...28).map { path.sample(Float($0)/28) }
                        template=LabGeometry.tubeAssembly(points:points,tint:tint)
                        Self.tubeTemplates[key]=template
                    }
                    let tube=template.clone(recursive:true); tube.position=[center.x,0,center.z]; tile.addChild(tube)
                } else {
                    let dot=ModelEntity(mesh:.generateSphere(radius:0.025),materials:[LabGeometry.material(tint)])
                    dot.position=[center.x,0.17,center.z]; tile.addChild(dot)
                }
            } }
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
    func homePosition(_ seat: HomeSeat) -> SIMD3<Float> {
        // Stable, centre-out seats: existing residents never slide sideways when
        // a new hamster joins them. The full twelve-hamster population fits.
        let step=Float((seat.index+1)/2), sign: Float=seat.index%2 == 1 ? -1 : 1
        return [step*sign*0.47,0.09,seat.receiver == .top ? -3.72 : 3.72]
    }
    private var homeFacing: simd_quatf {
        simd_quatf(angle:side == .top ? 0 : .pi,axis:[0,1,0])
    }
    private func rebuildReceivers(_ state: BoardState) {
        homeFurniture.children.removeAll()
        for seat in Array(homeHamsters.keys) where seat.index >= state.score[seat.receiver] {
            homeHamsters.removeValue(forKey:seat)?.root.removeFromParent()
            arrivals.removeValue(forKey:seat)
        }
        for receiver in [Side.top,.bottom] {
            // The player's home is always shown below, including online games
            // where the board rotates to the top player's point of view.
            let tint=UIColor(lab:receiver == side ? 0x63C987 : 0xE87979)
            let z: Float=receiver == .top ? -3.66 : 3.66
            homeFurniture.addChild(LabGeometry.box([6.3,0.12,0.82],at:[0,0.03,z],color:tint,radius:0.12))
            for index in 0..<max(7,state.score[receiver]) {
                let seat=HomeSeat(receiver:receiver,index:index), point=homePosition(seat)
                if index < state.score[receiver] {
                    // A restored game only retains counts, not the delivered IDs.
                    // Live arrivals always keep the original articulated rig.
                    if homeHamsters[seat] == nil {
                        let rig=HamsterRig(id:(receiver == .top ? 1000 : 2000)+index)
                        residents.addChild(rig.root); homeHamsters[seat]=rig
                    }
                } else {
                    let dot=ModelEntity(mesh:.generateSphere(radius:0.025),materials:[LabGeometry.glow(tint.withAlphaComponent(0.45))])
                    dot.position=point+[0,0.015,0]; homeFurniture.addChild(dot)
                }
            }
        }
        updateHomes()
    }
    private func welcome(_ rig: HamsterRig, to seat: HomeSeat) {
        let position=rig.root.position(relativeTo:world), orientation=rig.root.orientation(relativeTo:world)
        rig.root.removeFromParent(); residents.addChild(rig.root)
        rig.root.position=position; rig.root.orientation=orientation; rig.root.scale = .one
        homeHamsters[seat]?.root.removeFromParent(); homeHamsters[seat]=rig
        let target=homePosition(seat), distance=simd_length(SIMD2<Float>(target.x-position.x,target.z-position.z))
        if !UIAccessibility.isReduceMotionEnabled {
            arrivals[seat]=Arrival(start:position,orientation:orientation,started:clock,duration:Double(max(0.45,distance/2.5)))
        }
    }
    private func updateHomes() {
        var turnedAround=false
        for (seat,rig) in homeHamsters {
            let destination=homePosition(seat)
            guard var arrival=arrivals[seat],!UIAccessibility.isReduceMotionEnabled else {
                rig.root.position=destination; rig.root.orientation=homeFacing
                rig.sit(progress:1,time:clock); continue
            }
            let elapsed=clock-arrival.started
            if elapsed < arrival.duration {
                let t=max(0,min(1,Float(elapsed/arrival.duration)))
                let end=destination+[0,0.16,0]
                let control=SIMD3<Float>(destination.x,end.y,arrival.start.z)
                var point=TubePath.quadratic(arrival.start,control,end,t)
                point.y=end.y+(arrival.start.y-end.y)*pow(max(0,1-t*4),2)
                let direction=2*(1-t)*(control-arrival.start)+2*t*(end-control)
                let forward=SIMD2<Float>(direction.x,direction.z)
                let facing=simd_length(forward)>0.0001 ? simd_quatf(angle:atan2(-direction.x,-direction.z),axis:[0,1,0]) : homeFacing
                rig.root.position=point
                rig.root.orientation=simd_slerp(arrival.orientation,facing,min(1,t*6))
                rig.run(progress:Float(elapsed)*1.6,time:clock)
            } else {
                let t=min(1,Float((elapsed-arrival.duration)/0.38)), ease=t*t*(3-2*t)
                // Finish the last bend, turn towards the viewer and lower the
                // pelvis onto the pad. No pop-in or replacement mascot.
                let incoming=simd_quatf(angle:atan2(0,arrival.start.z-destination.z),axis:[0,1,0])
                if !arrival.turnCuePlayed {
                    arrival.turnCuePlayed=true; arrivals[seat]=arrival
                    turnedAround = turnedAround || simd_dot(incoming.act([0,0,-1]),homeFacing.act([0,0,-1])) < -0.5
                }
                rig.root.position=destination+[0,0.16*(1-ease),0]
                rig.root.orientation=simd_slerp(incoming,homeFacing,ease)
                rig.sit(progress:t,time:clock)
                if t >= 1 { arrivals.removeValue(forKey:seat) }
            }
        }
        if turnedAround { onTurnaround?() }
    }
    private func rebuildCouplers(_ state: BoardState) {
        couplers.children.removeAll(); couplers.isEnabled=true
        let gap=TubePath.pitch-2*TubePath.cell
        if Self.couplerTemplate == nil {
            Self.couplerTemplate=LabGeometry.tubeAssembly(points:[[0,0,-gap/2],[0,0,gap/2]],tint:LabGeometry.mint,collars:false)
        }
        for row in 0..<6 { for col in 0..<6 {
            for exit in [1,2] {
                let nr=row+(exit == 2 ? 1 : 0), nc=col+(exit == 1 ? 1 : 0)
                guard nr<6,nc<6,Rules.platform(row,col) != Rules.platform(nr,nc) else { continue }
                let source=TubePath(row:row,col:col,state:state), destination=TubePath(row:nr,col:nc,state:state)
                guard source.ports.contains(exit),destination.ports.contains((exit+2)%4),let template=Self.couplerTemplate else { continue }
                let a=source.endpoint(exit), b=destination.endpoint((exit+2)%4)
                let sleeve=template.clone(recursive:true)
                sleeve.position=(a+b)/2
                sleeve.orientation=simd_quatf(from:[0,0,1],to:simd_normalize(b-a))
                couplers.addChild(sleeve)
            }
        } }
    }
    private func install(_ ball: Ball, in state: BoardState) {
        let hamster=hamsters[ball.id] ?? HamsterRig(id:ball.id)
        let tile=tiles[Rules.platform(ball.row,ball.col)]!
        tile.addChild(hamster.root)
        hamster.root.scale = .one
        hamster.rest(time:clock)
        pose(hamster, ball:ball, state:state)
        hamsters[ball.id]=hamster
    }
    private func pose(_ hamster: HamsterRig, ball: Ball, state: BoardState) {
        let path=TubePath(row:ball.row,col:ball.col,state:state)
        let tileOffset=TubePath.tileCenter(Rules.platform(ball.row,ball.col))
        let offset=hamster.root.parent === world ? SIMD3<Float>.zero : tileOffset
        hamster.followTube { path.fromMidpoint(toward:ball.exit,distance:$0)-offset }
    }
    func setSelection(_ selection: Command?, highlighted: Int?, enabled: Bool, animated: Bool = true) {
        self.selection=selection; self.enabled=enabled
        guard !isAnimating else { return }
        couplers.isEnabled = selection == nil && drag == nil
        for (p,tile) in tiles {
            let selected=selection?.platform == p
            let hot=state.cooldown.contains(p)
            let style=hot ? 2 : selected ? 1 : 0
            if tileStyles[p] != style {
                tileBases[p]?.model?.materials=[LabGeometry.material(hot ? UIColor(lab:0xEAB2BD) : selected ? UIColor(lab:0xFFD973) : UIColor(lab:0xC4DEF4))]
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
        clearOopsSmoke()
        let visible=tiles.mapValues { $0.transform }
        selection=nil; enabled=false; transition=nil; drag=nil
        if self.state != before || self.side != side { render(before,side:side) }
        tiles.values.forEach { $0.stopAllAnimations(recursive:false) }
        let turnsAround=HamsterSound.hasTurnaround(before:before,after:after,turn:turn)
        // Two players can combine quarter-turns into a full half-turn.
        // Include newly spawned residents that ride that platform as well.
        let platformTurnaround=(before.balls+turn.spawned).contains {
            abs(turn.rotations[Rules.platform($0.row,$0.col),default:0]) % 4 == 2
        }
        if platformTurnaround { onTurnaround?() }
        guard !UIAccessibility.isReduceMotionEnabled else {
            if turnsAround { onTurnaround?() }
            render(after,side:side); return
        }
        isAnimating=true
        couplers.isEnabled=false
        var rotated=before; rotated.balls.append(contentsOf:turn.spawned)
        for ball in turn.spawned {
            install(ball,in:before)
            if let root=hamsters[ball.id]?.root {
                let destination=root.transform
                root.scale = .init(repeating:0.1)
                root.move(to:destination,relativeTo:root.parent,duration:0.24 / HamsterMotion.speed,timingFunction:.easeOut)
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
        transition=Transition(after:after,rotated:rotated,turn:turn,turnsAround:turnsAround)
        AudioEngine.shared.play(turn.spawned.isEmpty ? "crawl" : "chirp")
    }
    func update(delta: Double) {
        updateOopsSmoke(delta:delta)
        // One scaled character clock keeps running, sitting, breathing and
        // facial movements at the same pace without changing the game timer.
        clock += delta * HamsterMotion.speed
        if let hero { hero.rest(time:clock) }
        updateHomes()
        guard var transition else {
            for ball in state.balls {
                guard let hamster=hamsters[ball.id] else { continue }
                hamster.rest(time:clock); pose(hamster,ball:ball,state:state)
            }
            return
        }
        transition.elapsed += delta
        if transition.elapsed >= HamsterMotion.rotationDuration && !transition.moving {
            for hamster in hamsters.values {
                let t=hamster.root.transformMatrix(relativeTo:world)
                hamster.root.removeFromParent(); world.addChild(hamster.root); hamster.root.setTransformMatrix(t,relativeTo:world)
            }
            rebuildTiles(transition.after)
            rebuildCouplers(transition.after)
            transition.moving=true
            if transition.turnsAround { onTurnaround?() }
        }
        if transition.moving {
            let t=min(1,Float((transition.elapsed-HamsterMotion.rotationDuration)/HamsterMotion.crossingDuration))
            for ball in transition.after.balls {
                guard let origin=transition.rotated.balls.first(where:{$0.id==ball.id}), let hamster=hamsters[ball.id] else { continue }
                let source=TubePath(row:origin.row,col:origin.col,state:transition.rotated)
                if origin.row != ball.row || origin.col != ball.col {
                    let destination=TubePath(row:ball.row,col:ball.col,state:transition.after)
                    let squeeze=max(0,1-abs(t-0.5)*4)
                    hamster.crawl(progress:t,time:clock,squeeze:squeeze)
                    hamster.followTube { source.travel(to:destination,exit:origin.exit,progress:t,offset:$0) }
                } else if origin.exit != ball.exit {
                    hamster.turnAround(progress:t,time:clock,
                        from:{ source.fromMidpoint(toward:origin.exit,distance:$0) },
                        to:{ source.fromMidpoint(toward:ball.exit,distance:$0) })
                } else {
                    hamster.rest(time:clock); pose(hamster,ball:ball,state:transition.after)
                }
            }
            for (ball,receiver) in transition.turn.delivered {
                guard let hamster=hamsters[ball.id] else { continue }
                let source=TubePath(row:ball.row,col:ball.col,state:transition.rotated)
                let end=SIMD3<Float>(source.endpoint(ball.exit).x,TubePath.height,receiver == .top ? -3.43 : 3.43)
                let first=source.length/2, distance=t*(first+simd_distance(source.endpoint(ball.exit),end))
                hamster.crawl(progress:t,time:clock,squeeze:max(0,1-abs(t-0.6)*5))
                hamster.followTube { offset in
                    if distance+offset <= first { return source.fromMidpoint(toward:ball.exit,distance:distance+offset) }
                    let direction=simd_normalize(end-source.endpoint(ball.exit))
                    return source.endpoint(ball.exit)+direction*(distance+offset-first)
                }
            }
        }
        if transition.elapsed >= HamsterMotion.resolveDuration {
            let final=transition.after
            self.transition=nil; isAnimating=false
            // The final tube layout is already installed. Keep the articulated
            // models instead of allocating a second scene at every round end.
            self.state=final
            for receiver in [Side.top,.bottom] {
                let delivered=transition.turn.delivered.filter { $0.1 == receiver }
                let firstSeat=final.score[receiver]-delivered.count
                for (offset,delivery) in delivered.enumerated() {
                    guard let rig=hamsters.removeValue(forKey:delivery.0.id) else { continue }
                    welcome(rig,to:HomeSeat(receiver:receiver,index:firstSeat+offset))
                }
            }
            let remaining=Set(final.balls.map(\.id))
            for id in Array(hamsters.keys) where !remaining.contains(id) {
                hamsters.removeValue(forKey:id)?.root.removeFromParent()
            }
            for ball in final.balls {
                guard let hamster=hamsters[ball.id],let tile=tiles[Rules.platform(ball.row,ball.col)] else { continue }
                hamster.root.stopAllAnimations(recursive:false)
                hamster.root.removeFromParent(); tile.addChild(hamster.root)
                hamster.root.scale = .one
                hamster.rest(time:clock)
                pose(hamster,ball:ball,state:final)
            }
            rebuildReceivers(final)
            setSelection(selection,highlighted:selection?.platform,enabled:enabled,animated:false)
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
            couplers.isEnabled=false
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
