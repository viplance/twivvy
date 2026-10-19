import RealityKit
import UIKit
import simd

/// An original, reusable character rig. Sculpted fur surfaces share resources;
/// named pivots keep expressions independent of the body's squash and stretch.
@MainActor final class HamsterRig {
    let root = Entity()
    let body = Entity()
    let head = Entity()
    private(set) var eyes: [Entity] = []
    private var pupils: [Entity] = []
    private var paws: [Entity] = []
    private var cheeks: [Entity] = []
    private var brows: [Entity] = []
    private var ears: [Entity] = []
    private var whiskers: [Entity] = []
    private let mouth = Entity()
    private let nose = Entity()
    private var idle: [AnimationPlaybackController] = []
    private var neutral: [(Entity, Transform)] = []
    private let seed: Int
    private var isCrawling = false
    private var isInTube = false
    private var tubeScaleApplied = SIMD3<Float>.one
    private let headTilt = simd_quatf(angle: 0.18, axis: [1, 0, 0])

    init(id: Int) {
        seed = Int(id.magnitude % 10000)
        root.name = "hamster-\(id)"; body.name = "squash-body"; head.name = "face-pivot"
        root.addChild(body); body.addChild(head)
        let torso = HamsterSculpt.fur(.torso, variant: seed)
        torso.name = "pear-shaped-torso"; body.addChild(torso)
        head.position = [0, 0.029, -0.116]; head.orientation = headTilt
        head.addChild(HamsterSculpt.fur(.head, variant: seed))
        head.addChild(HamsterSculpt.tufts(cream: false, variant: seed))
        head.addChild(HamsterSculpt.tufts(cream: true, variant: seed))

        for sign: Float in [-1, 1] {
            let cheek = Entity(); cheek.name = "cheek-pouch"
            cheek.position = [sign * 0.078, -0.031, -0.071]
            cheek.addChild(HamsterSculpt.fur(.cheek, variant: seed))
            cheeks.append(cheek); head.addChild(cheek)

            let ear = Entity(); ear.name = "ear-pivot"
            ear.position = [sign * 0.103, 0.100, 0.005]
            ear.orientation = simd_quatf(angle: sign * -0.26, axis: [0, 0, 1])
            ear.addChild(HamsterSculpt.ear(variant: seed))
            head.addChild(ear); ears.append(ear)

            let eye = Entity(); eye.name = "blink-eye"
            eye.position = [sign * 0.058, 0.046, -0.108]
            eye.orientation = simd_quatf(angle: sign * -0.12, axis: [0, 1, 0])
            eye.addChild(part([0.037, 0.046, 0.023], at: .zero, color: UIColor(lab: 0xFFF9EF), roughness: 0.32))
            let gaze = Entity(); gaze.name = "gaze-pivot"; gaze.position = [-sign * 0.004, 0.001, -0.019]
            gaze.addChild(part([0.024, 0.030, 0.006], at: .zero, color: UIColor(lab: 0x6E4025), roughness: 0.26))
            gaze.addChild(part([0.0165, 0.023, 0.003], at: [0, 0, -0.004], color: UIColor(lab: 0x201A1B), roughness: 0.20))
            gaze.addChild(part([0.007, 0.009, 0.002], at: [-0.007, 0.012, -0.0075], color: .white, roughness: 0.18))
            gaze.addChild(part([0.003, 0.004, 0.001], at: [0.008, -0.010, -0.008], color: .white))
            eye.addChild(gaze); pupils.append(gaze); head.addChild(eye); eyes.append(eye)

            let brow = Entity(); brow.position = [sign * 0.058, 0.096, -0.101]
            brow.addChild(part([0.025, 0.006, 0.007], at: .zero, color: UIColor(lab: 0x80532D)))
            brow.orientation = simd_quatf(angle: sign * -0.16, axis: [0, 0, 1])
            head.addChild(brow); brows.append(brow)
            head.addChild(part([0.030, 0.022, 0.018], at: [sign * 0.023, -0.013, -0.134], color: HamsterSculpt.cream))
            let whisker = Entity(); whisker.name = "whisker-pivot"
            whisker.addChild(HamsterSculpt.whiskers(sign: sign)); head.addChild(whisker); whiskers.append(whisker)
        }

        nose.name = "sniff-nose"; nose.position = [0, 0.002, -0.158]
        let tip = part([0.020, 0.013, 0.012], at: .zero, color: UIColor(lab: 0xD77982), roughness: 0.38)
        nose.addChild(tip)
        nose.addChild(part([0.006, 0.003, 0.003], at: [-0.006, 0.006, -0.010], color: UIColor(lab: 0xFFD7CB)))
        head.addChild(nose)
        mouth.name = "smile-pivot"; mouth.position = [0, -0.039, -0.139]
        mouth.addChild(part([0.034, 0.027, 0.012], at: .zero, color: HamsterSculpt.dark))
        mouth.addChild(part([0.017, 0.009, 0.004], at: [0, -0.014, -0.011], color: UIColor(lab: 0xEF9A9D)))
        for sign: Float in [-1, 1] {
            mouth.addChild(LabGeometry.box([0.013, 0.019, 0.009], at: [sign * 0.008, 0.010, -0.014], color: UIColor(lab: 0xFFFAE8), radius: 0.004))
        }
        head.addChild(mouth)
        for i in 0..<4 {
            let sign: Float = i % 2 == 0 ? -1 : 1
            let paw = Entity(); paw.name = "paw-\(i)"
            paw.position = [sign * 0.118, -0.091, i < 2 ? -0.107 : 0.137]
            let sleeve = part([0.032, 0.044, 0.037], at: [0, 0.005, 0.004], color: HamsterSculpt.cream)
            paw.addChild(sleeve)
            let hand = HamsterSculpt.paw(); hand.position = [sign * 0.005, -0.034, -0.019]
            paw.addChild(hand); body.addChild(paw); paws.append(paw)
        }
        body.addChild(part([0.020, 0.022, 0.027], at: [0, -0.073, 0.223], color: HamsterSculpt.skin))
        neutral = ([body, head, mouth, nose] + eyes + pupils + paws + cheeks + brows + ears + whiskers).map { ($0, $0.transform) }
        startIdle()
    }

    private func part(_ radii: SIMD3<Float>, at point: SIMD3<Float>, color: UIColor, roughness: Float = 0.82) -> ModelEntity {
        let model = LabGeometry.ellipsoid(radii, at: point, color: color)
        model.model?.materials = [LabGeometry.material(color, roughness: roughness)]
        return model
    }
    private func resetPose() {
        idle.forEach { $0.stop() }; idle.removeAll()
        body.stopAllAnimations(recursive: true)
        for (entity, transform) in neutral { entity.transform = transform }
        tubeScaleApplied = .one
    }
    func refreshMotionPreferences() {
        resetPose(); isCrawling = false; startIdle()
    }
    private func loop(_ entity: Entity, to: Transform, seconds: Double, delay: Double = 0) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let definition = FromToByAnimation<Transform>(name: "hamster-idle", from: entity.transform, to: to,
            duration: seconds, timing: .easeInOut, bindTarget: .transform, repeatMode: .autoReverse, delay: delay)
        if let animation = try? AnimationResource.generate(with: definition) { idle.append(entity.playAnimation(animation.repeat())) }
    }
    private func startIdle() {
        guard !isInTube else { return }
        var breathe = body.transform; breathe.scale = [1.018, 1.028, 0.994]
        loop(body, to: breathe, seconds: 1.3 + Double(seed % 3) * 0.17)
        var sniff = head.transform
        sniff.rotation = headTilt * simd_quatf(angle: 0.045, axis: [0, 0, 1]) * simd_quatf(angle: -0.06, axis: [0, 1, 0])
        loop(head, to: sniff, seconds: 1.9, delay: Double(seed % 3) * 0.23)
    }
    /// Two deliberate stride cycles per crossing. Feet lift during recovery and
    /// push backwards during contact; the shoulders counter-rotate the haunches.
    func crawl(progress: Float, time: Double, squeeze: Float) {
        clearTubeFit()
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if !isCrawling { resetPose(); isCrawling = true }
        head.position = [0, 0.029, -0.116]
        let amount = max(0, min(1, squeeze)), phase = progress * .pi * 4
        body.scale = [1 - amount * 0.17, 1 - amount * 0.20, 1 + amount * 0.22]
        body.position.y = abs(sin(phase)) * 0.010
        body.orientation = simd_quatf(angle: sin(phase) * 0.045, axis: [0, 0, 1])
        head.orientation = headTilt * simd_quatf(angle: sin(phase) * -0.06, axis: [0, 1, 0])
        for (i, paw) in paws.enumerated() {
            let wave = sin(phase + (i == 0 || i == 3 ? 0 : .pi))
            paw.orientation = simd_quatf(angle: wave * 0.42 - amount * 0.16, axis: [1, 0, 0])
            paw.position.y = -0.091 + max(0, wave) * 0.028
            paw.position.z = (i < 2 ? -0.107 : 0.137) + cos(phase + (i == 0 || i == 3 ? 0 : .pi)) * 0.020
        }
        for cheek in cheeks { cheek.scale = [1 + amount * 0.10, 1 + amount * 0.06, 1 - amount * 0.04] }
        expression(time: time, effort: amount)
    }
    func rest(time: Double) {
        clearTubeFit()
        if isCrawling { resetPose(); isCrawling = false; startIdle() }
        if isInTube {
            let breath = sin(Float(time) * 2.4) * 0.008
            body.scale = [1 + breath, 1 + breath, 1]
            body.position = .zero; body.orientation = Transform.identity.rotation
            head.position = [0, 0.029, -0.116]; head.orientation = headTilt
        }
        expression(time: time, effort: 0)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // A short inquisitive paw lift, with long rests between gestures.
        let phase = Float((time + Double(seed) * 1.31).truncatingRemainder(dividingBy: 8.6))
        let lift: Float = phase > 6.9 ? pow(sin((phase - 6.9) / 1.7 * .pi), 2) : 0
        let paw = paws[seed % 2]
        paw.orientation = simd_quatf(angle: -lift * 0.65, axis: [1, 0, 0])
        paw.position.y = -0.091 + lift * 0.025
    }
    /// The same arc-length path drives the trunk, neck and gaze. In particular,
    /// a resident at the middle of an elbow faces its tangent, not a grid axis.
    /// Coordinates are supplied in the root parent's space (tile or world).
    func followTube(_ position: (Float) -> SIMD3<Float>) {
        clearTubeFit()
        if !isInTube {
            isInTube = true
            idle.forEach { $0.stop() }; idle.removeAll()
        }
        let center = position(0), forward = position(0.012) - position(-0.012)
        guard simd_length(forward) > 0.00001 else { return }
        root.position = center
        root.orientation = simd_quatf(angle:atan2(-forward.x,-forward.z),axis:[0,1,0])
        // A little clearance lets the ears, pouches and lifted feet move inside
        // the bore. Do not elongate the body through the outside of an elbow.
        let noseForward = simd_normalize(position(0.17)-position(0.14))
        let bend = min(1,simd_length(noseForward-simd_normalize(forward))*2)
        tubeScaleApplied = SIMD3<Float>(0.94,0.94,1-bend*0.10)
        body.scale *= tubeScaleApplied
        let inverse = root.orientation.inverse
        let neck = inverse.act(position(0.116)-center)
        head.position = body.orientation.inverse.act(neck + [0,0.029,0] - body.position) / body.scale
        let localDirection = inverse.act(noseForward)
        head.orientation = simd_quatf(angle:atan2(-localDirection.x,-localDirection.z),axis:[0,1,0]) * headTilt
        for whisker in whiskers { whisker.scale.x = 1-bend*0.18 }
    }
    private func clearTubeFit() {
        body.scale /= tubeScaleApplied
        tubeScaleApplied = .one
    }
    private func expression(time: Double, effort: Float) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let local = time + Double(seed) * 0.67
        let phase = local.truncatingRemainder(dividingBy: 4.3)
        let blink: Float = phase < 0.17 ? max(0.07, Float(abs(phase - 0.085) / 0.085)) : 1
        let glance = sin(Float(local) * 0.73) * 0.005
        for (i, eye) in eyes.enumerated() {
            eye.scale.y = blink * (1 + effort * 0.12)
            pupils[i].position.x = (i == 0 ? 0.004 : -0.004) + glance
            pupils[i].position.y = sin(Float(local) * 0.51) * 0.003 + effort * 0.004
        }
        for (i, brow) in brows.enumerated() {
            let sign: Float = i == 0 ? -1 : 1
            brow.position.y = 0.096 + effort * 0.008
            brow.orientation = simd_quatf(angle: sign * (-0.16 + effort * 0.34), axis: [0, 0, 1])
        }
        mouth.scale = [1 - effort * 0.22, 1 + effort * 0.27, 1]
        let sniff = pow(max(0, sin(Float(local) * 2.2)), 10)
        nose.scale = [1 + sniff * 0.06, 1 - sniff * 0.08, 1]
        for (i, whisker) in whiskers.enumerated() {
            whisker.orientation = simd_quatf(angle: (i == 0 ? -1 : 1) * sniff * 0.035, axis: [0, 1, 0])
        }
        for (i, ear) in ears.enumerated() {
            let sign: Float = i == 0 ? -1 : 1
            let twitch = pow(max(0, sin(Float(local) * 1.5 + Float(i))), 18) * 0.10
            ear.orientation = simd_quatf(angle: sign * (-0.26 + twitch), axis: [0, 0, 1])
                * simd_quatf(angle: -effort * 0.25, axis: [1, 0, 0])
        }
    }
    func celebrate() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        resetPose()
        for (i, paw) in paws.prefix(2).enumerated() {
            paw.orientation = simd_quatf(angle: -1.0, axis: [1, 0, 0]) * simd_quatf(angle: i == 0 ? -0.4 : 0.4, axis: [0, 0, 1])
        }
        let start = body.transform
        var up = start; up.translation.y += 0.10; up.rotation = simd_quatf(angle: -0.20, axis: [1, 0, 0])
        if let animation = try? AnimationResource.generate(with: FromToByAnimation<Transform>(from: start, to: up, duration: 0.26, timing: .easeOut, bindTarget: .transform, repeatMode: .autoReverse)) {
            body.playAnimation(animation.repeat(count: 2))
        }
    }
}
