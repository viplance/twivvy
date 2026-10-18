import RealityKit
import UIKit
import simd

/// Original, code-authored model. Named pivots form a small articulation rig;
/// RealityKit owns looping animation playback and transform interpolation.
@MainActor final class HamsterRig {
    let root = Entity()
    let body = Entity()
    let head = Entity()
    private(set) var eyes: [Entity] = []
    private var paws: [Entity] = []
    private var cheeks: [Entity] = []
    private var brows: [Entity] = []
    private var ears: [Entity] = []
    private var idle: [AnimationPlaybackController] = []
    private let seed: Int
    private var isCrawling = false
    private static var bodyMesh: MeshResource?

    init(id: Int) {
        seed = abs(id)
        root.name = "hamster-\(id)"; body.name = "squash-body"; head.name = "face-pivot"
        root.addChild(body); body.addChild(head)
        let coats: [UInt32] = [0xE8AD66,0xD9C9BD,0xCDA0C4,0xBC9474,0xF0D99B]
        let fur = UIColor(lab:coats[seed % coats.count]), pale = UIColor(lab:0xFFF0DC)
        if Self.bodyMesh == nil { Self.bodyMesh = try? Self.sculptBody() }
        if let mesh = Self.bodyMesh {
            let torso = ModelEntity(mesh:mesh,materials:[LabGeometry.material(fur)])
            torso.name = "pear-shaped-torso"; body.addChild(torso)
        }
        body.addChild(LabGeometry.ellipsoid([0.106,0.106,0.155],at:[0,-0.055,-0.04],color:pale))
        head.position = [0,0.035,-0.135]
        head.addChild(LabGeometry.ellipsoid([0.135,0.116,0.125],at:.zero,color:fur))
        // Oversized muzzle, independent cheek pouches and two tiny incisors.
        for sign: Float in [-1,1] {
            let cheek = LabGeometry.ellipsoid([0.081,0.068,0.074],at:[sign*0.084,-0.025,-0.067],color:pale)
            cheek.name = "cheek-pouch"; cheeks.append(cheek); head.addChild(cheek)
            let blush = LabGeometry.ellipsoid([0.026,0.014,0.007],at:[sign*0.123,-0.005,-0.112],color:UIColor(lab:0xF2A8A5))
            head.addChild(blush)
            let ear = Entity(); ear.position = [sign*0.104,0.097,0.011]
            ear.addChild(LabGeometry.ellipsoid([0.060,0.066,0.025],at:.zero,color:fur))
            ear.addChild(LabGeometry.ellipsoid([0.040,0.045,0.009],at:[0,0,-0.021],color:UIColor(lab:0xEFA5AC)))
            head.addChild(ear); ears.append(ear)
            let eye = Entity(); eye.name = "blink-eye"; eye.position = [sign*0.057,0.047,-0.105]
            eye.addChild(LabGeometry.ellipsoid([0.034,0.042,0.022],at:.zero,color:UIColor(lab:0x272238)))
            eye.addChild(LabGeometry.ellipsoid([0.011,0.014,0.006],at:[-0.008,0.013,-0.020],color:.white))
            eye.addChild(LabGeometry.ellipsoid([0.005,0.005,0.003],at:[0.012,-0.008,-0.021],color:.white))
            head.addChild(eye); eyes.append(eye)
            let brow = LabGeometry.line(from:[-0.022,0,0],to:[0.019,0.006,0],width:0.009,color:UIColor(lab:0x805D4D))
            brow.position = [sign*0.057,0.102,-0.102]; head.addChild(brow); brows.append(brow)
            let tooth = LabGeometry.box([0.014,0.025,0.012],at:[sign*0.009,-0.055,-0.135],color:.white,radius:0.004)
            head.addChild(tooth)
            for index in 0..<3 {
                let y = Float(index-1)*0.014
                head.addChild(LabGeometry.line(from:[sign*0.095,-0.026+y,-0.131],to:[sign*0.195,-0.018+y*2,-0.115],width:0.003,color:UIColor(lab:0xDEC9BD)))
            }
        }
        head.addChild(LabGeometry.ellipsoid([0.025,0.019,0.014],at:[0,-0.009,-0.145],color:UIColor(lab:0xDE8998)))
        // The little smile is two diagonal strokes beneath the nose.
        for sign: Float in [-1,1] {
            head.addChild(LabGeometry.line(from:[0,-0.027,-0.141],to:[sign*0.026,-0.039,-0.133],width:0.005,color:UIColor(lab:0x825A64)))
        }
        for i in 0..<4 {
            let paw = Entity(); paw.name = "paw-\(i)"
            paw.position = [i%2 == 0 ? -0.119 : 0.119,-0.103,i<2 ? -0.12 : 0.12]
            paw.addChild(LabGeometry.ellipsoid([0.044,0.038,0.065],at:[0,-0.008,-0.015],color:UIColor(lab:0xF4B2AD)))
            for toe in -1...1 {
                paw.addChild(LabGeometry.ellipsoid([0.007,0.009,0.023],at:[Float(toe)*0.016,-0.015,-0.066],color:pale))
            }
            body.addChild(paw); paws.append(paw)
        }
        body.addChild(LabGeometry.ellipsoid([0.030,0.031,0.034],at:[0,-0.04,0.208],color:UIColor(lab:0xEFB1AD)))
        // Individual dorsal markings distinguish the five lab residents.
        for i in 0..<3 {
            body.addChild(LabGeometry.ellipsoid([0.025,0.009,0.060],at:[Float(i-1)*0.04,0.113,0.04],color:fur.withAlphaComponent(1)))
        }
        startIdle()
    }
    private static func sculptBody() throws -> MeshResource {
        var points: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], triangles: [UInt32] = []
        let rings=20, sides=28
        for i in 0...rings {
            let v = Float(i)/Float(rings), theta = v * .pi
            let z = cos(theta) * 0.205
            let haunch: Float = 1 + 0.17*cos(theta)
            for j in 0...sides {
                let phi = Float(j)/Float(sides)*2 * .pi
                let n = SIMD3<Float>(sin(theta)*cos(phi),sin(theta)*sin(phi),cos(theta))
                points.append([n.x*0.139*haunch,n.y*0.134-0.018,z]); normals.append(simd_normalize([n.x/0.139,n.y/0.134,n.z/0.205]))
            }
        }
        for i in 0..<rings { for j in 0..<sides {
            let a=UInt32(i*(sides+1)+j), b=a+1, c=a+UInt32(sides+1), d=c+1
            triangles += [a,c,b,b,c,d]
        } }
        var mesh=MeshDescriptor(name:"HamsterLab-original-pear-body")
        mesh.positions = .init(points); mesh.normals = .init(normals); mesh.primitives = .triangles(triangles)
        return try MeshResource.generate(from:[mesh])
    }
    func refreshMotionPreferences() {
        idle.forEach { $0.stop() }; idle.removeAll()
        body.stopAllAnimations(recursive:true)
        body.transform = .identity; head.orientation=simd_quatf()
        eyes.forEach { $0.scale = .one }
        isCrawling=false; startIdle()
    }
    private func loop(_ entity: Entity, to: Transform, seconds: Double, delay: Double = 0) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let definition = FromToByAnimation<Transform>(name:"hamster-idle",from:entity.transform,to:to,duration:seconds,timing:.easeInOut,bindTarget:.transform,repeatMode:.autoReverse,delay:delay)
        if let animation = try? AnimationResource.generate(with:definition) { idle.append(entity.playAnimation(animation.repeat())) }
    }
    private func startIdle() {
        var breathe = body.transform; breathe.scale = [1.025,1.035,0.99]
        loop(body,to:breathe,seconds:1.2+Double(seed%3)*0.15)
        var sniff=head.transform
        sniff.rotation=simd_quatf(angle:-0.06,axis:[1,0,0]) * simd_quatf(angle:0.07,axis:[0,0,1])
        loop(head,to:sniff,seconds:1.7,delay:Double(seed%3)*0.2)
        for (i,ear) in ears.enumerated() {
            var t=ear.transform; t.rotation=simd_quatf(angle:i == 0 ? -0.16 : 0.16,axis:[0,0,1])
            loop(ear,to:t,seconds:0.7+Double(i)*0.2,delay:Double(seed%4)*0.3)
        }
    }
    /// Update the rig from normalized path progress. The stomach elongates at
    /// coupling rings, cheeks puff, paws climb, and the head leads each bend.
    func crawl(progress: Float, time: Double, squeeze: Float) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if !isCrawling { idle.forEach { $0.stop() }; idle.removeAll(); isCrawling=true }
        let phase=progress * .pi * 10
        body.scale = [1-squeeze*0.20,1-squeeze*0.28,1+squeeze*0.24]
        body.position.y = abs(sin(phase))*0.018
        body.orientation = simd_quatf(angle:sin(phase)*0.065,axis:[0,0,1])
        head.orientation = simd_quatf(angle:sin(phase*0.5)*0.08,axis:[0,1,0])
        for (i,paw) in paws.enumerated() {
            let wave=sin(phase + (i==0 || i==3 ? 0 : .pi))
            paw.orientation=simd_quatf(angle:wave*0.6,axis:[1,0,0])
            paw.position.y = -0.10 + max(0,wave)*0.045
        }
        for cheek in cheeks { cheek.scale = [0.081*(1+squeeze*0.2),0.068*(1+squeeze*0.1),0.074] }
        expression(time:time,surprised:squeeze>0.4)
    }
    func rest(time: Double) {
        if isCrawling {
            body.transform = .identity; head.orientation = simd_quatf()
            paws.forEach { $0.orientation=simd_quatf(); $0.position.y = -0.103 }
            cheeks.forEach { $0.scale = [0.081,0.068,0.074] }
            isCrawling=false; startIdle()
        }
        expression(time:time,surprised:false)
    }
    private func expression(time: Double, surprised: Bool) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let phase = (time+Double(seed)*0.67).truncatingRemainder(dividingBy:3.7)
        let blink: Float = phase < 0.14 ? max(0.08,Float(abs(phase-0.07)/0.07)) : 1
        for eye in eyes { eye.scale.y = blink * (surprised ? 1.18 : 1) }
        for (i,brow) in brows.enumerated() {
            brow.orientation=simd_quatf(angle:surprised ? (i==0 ? -0.23 : 0.23) : sin(Float(time)*0.8+Float(seed))*0.09,axis:[0,0,1])
        }
    }
    func celebrate() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let start=body.transform
        var up=start; up.translation.y += 0.12; up.rotation=simd_quatf(angle:-0.25,axis:[1,0,0])
        if let animation=try? AnimationResource.generate(with:FromToByAnimation<Transform>(from:start,to:up,duration:0.24,timing:.easeOut,bindTarget:.transform,repeatMode:.autoReverse)) {
            body.playAnimation(animation.repeat(count:2))
        }
    }
}
