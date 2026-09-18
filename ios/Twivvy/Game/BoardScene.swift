import SpriteKit
import UIKit

@MainActor final class BoardScene: SKScene {
    var onSelect: ((Int, Int?) -> Void)?
    var onDragStart: (() -> Void)?
    var onTurnLimit: (() -> Void)?
    private let world = SKNode()
    private var tiles: [Int: SKNode] = [:]
    private var ballNodes: [Int: SKNode] = [:]
    private var current = BoardState()
    private var perspective: Side = .bottom
    private var inputEnabled = false
    private var resolving = false
    private struct Drag {
        let platform: Int
        let start: CGPoint
        let startAngle: CGFloat
        let initialCommand: Command?
        var pointerAngle: CGFloat?
        var angle: CGFloat
        var rotation: CGFloat = 0
        var moved = false
    }
    private var drag: Drag?
    private var previewTargets: [Int: CGFloat] = [:]
    private let tileSize: CGFloat = 204
    private let pitch: CGFloat = 216
    private let cell: CGFloat = 98
    private var selection: Command?
    private var highlighted: Int?
    private let colors: [UIColor] = [
        UIColor(hex:0x61EAD0), UIColor(hex:0x63BBFF), UIColor(hex:0xB5A1FF),
        UIColor(hex:0x72BCFF), UIColor(hex:0x77F0CA), UIColor(hex:0xC5A4FF),
        UIColor(hex:0xAAA4FF), UIColor(hex:0x64D9E9), UIColor(hex:0xFFADBA)
    ]
    override init(size: CGSize = CGSize(width: 720, height: 828)) {
        super.init(size: size); scaleMode = .aspectFit; backgroundColor = .clear
        anchorPoint = CGPoint(x:0.5,y:0.5); addChild(world)
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }
    private func tileCenter(_ p: Int) -> CGPoint { CGPoint(x:CGFloat(p%3-1)*pitch,y:CGFloat(1-p/3)*pitch) }
    private func point(_ row: Int, _ col: Int) -> CGPoint {
        let origin = tileCenter(Rules.platform(row,col))
        return CGPoint(x:origin.x + (CGFloat(col%2)-0.5)*cell, y:origin.y + (0.5-CGFloat(row%2))*cell)
    }
    private func track(for ball: Ball, in state: BoardState) -> TrackGeometry {
        track(row:ball.row,col:ball.col,in:state)
    }
    private func track(row: Int, col: Int, in state: BoardState) -> TrackGeometry {
        TrackGeometry(center:point(row,col), cellSize:cell, mask:state.cells[row][col])
    }
    private func rounded(_ rect: CGRect, radius: CGFloat, fill: UIColor, stroke: UIColor = .clear, width: CGFloat = 1) -> SKShapeNode {
        let shape = SKShapeNode(rect: rect, cornerRadius: radius)
        shape.fillColor = fill; shape.strokeColor = stroke; shape.lineWidth = width
        return shape
    }
    func render(_ state: BoardState, side: Side) {
        removeAllActions(); world.removeAllChildren(); tiles.removeAll(); ballNodes.removeAll()
        drag = nil; previewTargets.removeAll()
        resolving = false
        current = state; perspective = side; world.zRotation = side == .top ? .pi : 0
        let frame = rounded(CGRect(x:-338,y:-337,width:676,height:674),radius:36,fill:UIColor(hex:0x111D35),stroke:UIColor(hex:0x33466C),width:2)
        frame.zPosition = -5; world.addChild(frame)
        for p in 0..<9 {
            let tile = SKNode(); tile.position = tileCenter(p); tile.name = "platform-\(p)"
            let shadow = rounded(CGRect(x:-102,y:-111,width:204,height:204),radius:24,fill:UIColor(hex:0x050B1A))
            tile.addChild(shadow)
            let base = rounded(CGRect(x:-102,y:-102,width:204,height:204),radius:24,fill:colors[p].mixed(with:UIColor(hex:0x101C35),amount:0.84),stroke:colors[p].withAlphaComponent(0.45),width:2)
            base.name = "base"; tile.addChild(base)
            let shine = rounded(CGRect(x:-94,y:12,width:188,height:82),radius:19,fill:.white.withAlphaComponent(0.025))
            tile.addChild(shine)
            let r0 = p/3*2, c0 = p%3*2
            for r in 0..<2 { for c in 0..<2 {
                let center = CGPoint(x:(CGFloat(c)-0.5)*cell,y:(0.5-CGFloat(r))*cell)
                let mask = state.cells[r0+r][c0+c]
                if mask != 0 { addTrack(to:tile, center:center, mask:mask, color:colors[p]) }
                else {
                    let dot = SKShapeNode(circleOfRadius:4); dot.position = center
                    dot.fillColor = colors[p].withAlphaComponent(0.2); dot.strokeColor = .clear; tile.addChild(dot)
                }
            } }
            world.addChild(tile); tiles[p] = tile
        }
        for (index, position) in [(2,2),(3,3)].enumerated() {
            guard let tile = tiles[Rules.platform(position.0,position.1)] else { continue }
            let source = SKShapeNode(circleOfRadius:19)
            source.name = "source-\(index)"
            source.position = tile.convert(track(row:position.0,col:position.1,in:state).midpoint,from:world)
            source.strokeColor = UIColor(hex:0xFFE7A2)
            source.lineWidth = 2.5; source.fillColor = UIColor(hex:0xFFCE76).withAlphaComponent(0.12)
            source.zPosition = 3
            let upcoming = Rules.spawnTicks.contains(state.tick+1) && !state.finished
            source.alpha = upcoming ? 1 : 0.45
            if upcoming && !UIAccessibility.isReduceMotionEnabled {
                source.run(.repeatForever(.sequence([.fadeAlpha(to:0.4,duration:0.9),.fadeAlpha(to:1,duration:0.9)])))
            }
            let dot = SKShapeNode(circleOfRadius:4); dot.fillColor = UIColor(hex:0xFFE7A2); dot.strokeColor = .clear
            // Spawn precedes rotation, so its marker rides the same rail during
            // previews and animation. The next render restores the fixed sources.
            dot.position.x = index == 0 ? -25 : 25; source.addChild(dot); tile.addChild(source)
        }
        for ball in state.balls { let node = orb(for:ball); node.position = track(for:ball,in:state).midpoint; world.addChild(node); ballNodes[ball.id] = node }
        receiver(.top, score:state.score.top); receiver(.bottom, score:state.score.bottom)
        setSelection(selection, highlighted: highlighted, enabled:inputEnabled, animated:false)
    }
    private func addTrack(to parent: SKNode, center: CGPoint, mask: Int, color: UIColor) {
        let path = TrackGeometry(center:center,cellSize:cell,mask:mask).path
        for (width, tint) in [(CGFloat(27),UIColor(hex:0x060D20)),(CGFloat(17),color.withAlphaComponent(0.22)),(CGFloat(7),color),(CGFloat(2),UIColor.white.withAlphaComponent(0.75))] {
            let track = SKShapeNode(path:path); track.lineWidth = width; track.strokeColor = tint
            track.lineCap = .round; track.lineJoin = .round; parent.addChild(track)
        }
    }
    private func orb(for value: Ball) -> SKNode {
        let node = SKNode(); node.zPosition = 10; node.name = "ball-\(value.id)"
        let halo = SKShapeNode(circleOfRadius:22); halo.fillColor = UIColor(hex:0xFFD88A).withAlphaComponent(0.15)
        halo.strokeColor = .clear; halo.glowWidth = 9; node.addChild(halo)
        let ball = SKShapeNode(circleOfRadius:13); ball.fillColor = UIColor(hex:0xFFD580)
        ball.strokeColor = UIColor(hex:0x060D20); ball.lineWidth = 3; node.addChild(ball)
        let highlight = SKShapeNode(circleOfRadius:4); highlight.position = CGPoint(x:-4,y:5)
        highlight.fillColor = .white; highlight.strokeColor = .clear; node.addChild(highlight)
        let direction = CGMutablePath()
        direction.move(to:CGPoint(x:-6.5,y:25)); direction.addLine(to:CGPoint(x:0,y:33)); direction.addLine(to:CGPoint(x:6.5,y:25))
        let heading = SKNode(); heading.name = "heading"; heading.zRotation = -CGFloat(value.exit) * .pi / 2
        for (width,color) in [(CGFloat(7.5),UIColor(hex:0x060D20)),(CGFloat(3.5),UIColor(hex:0xFFE7A2))] {
            let arrow = SKShapeNode(path:direction); arrow.strokeColor = color; arrow.lineWidth = width
            arrow.lineCap = .round; arrow.lineJoin = .round; heading.addChild(arrow)
        }
        node.addChild(heading)
        return node
    }
    private func receiver(_ side: Side, score: Int) {
        let color = side == perspective ? UIColor(hex:0x6BF0D0) : UIColor(hex:0xFF9DB7)
        let y: CGFloat = side == .top ? 377 : -377
        let tray = rounded(CGRect(x:-265,y:y-23,width:530,height:46),radius:23,fill:color.withAlphaComponent(0.09),stroke:color.withAlphaComponent(0.5),width:2)
        world.addChild(tray)
        // All delivered balls stay visible (a side may collect more than seven in one turn).
        for index in 0..<max(7,score) {
            let dot = SKShapeNode(circleOfRadius: index < score ? 10 : 6)
            dot.position = CGPoint(x:CGFloat(index)*30-CGFloat(max(7,score)-1)*15,y:y)
            dot.fillColor = index < score ? color : color.withAlphaComponent(0.16)
            dot.strokeColor = .clear; world.addChild(dot)
        }
    }
    func setSelection(_ selection: Command?, highlighted: Int?, enabled: Bool, animated: Bool = true) {
        self.selection = selection; self.highlighted = highlighted; inputEnabled = enabled
        guard !resolving else { inputEnabled = false; return }
        if !enabled { drag = nil }
        for (p,tile) in tiles {
            guard let base = tile.childNode(withName:"base") as? SKShapeNode else { continue }
            let chosen = p == highlighted
            if drag?.platform != p {
                settlePlatform(p,to:selection?.platform == p ? -CGFloat(selection!.dir) * .pi / 2 : 0,animated:animated)
            }
            let hot = current.cooldown.contains(p)
            base.strokeColor = hot ? UIColor(hex:0xFF626B) : chosen ? UIColor(hex:0xFFE7A2) : colors[p].withAlphaComponent(0.45)
            base.lineWidth = hot || chosen ? 5 : 2; base.glowWidth = hot || chosen ? 5 : 0
            tile.childNode(withName:"preview")?.removeFromParent()
            if selection?.platform == p {
                let preview = SKNode(); preview.name = "preview"; preview.zPosition = 20; preview.alpha = 0.6
                let arrow = SKLabelNode(fontNamed:"AvenirNext-Bold")
                arrow.text = selection?.dir == 1 ? "↻" : "↺"
                arrow.fontSize = 72; arrow.fontColor = UIColor(hex:0xFFE7A2)
                // Center the visible glyph, then counter-rotate around the
                // platform center rather than around an offset text baseline.
                let bounds = arrow.frame
                arrow.position = CGPoint(x:-bounds.midX,y:-bounds.midY)
                preview.addChild(arrow)
                preview.zRotation = (perspective == .top ? .pi : 0) - tile.zRotation; tile.addChild(preview)
            }
        }
    }
    private func applyPreviewAngle(_ angle: CGFloat, platform p: Int) {
        guard let tile = tiles[p] else { return }
        tile.zRotation = angle
        tile.childNode(withName:"preview")?.zRotation = (perspective == .top ? .pi : 0) - angle
        let center = tileCenter(p)
        for ball in current.balls where Rules.platform(ball.row,ball.col) == p {
            guard let node = ballNodes[ball.id] else { continue }
            let point = track(for:ball,in:current).midpoint
            let dx = point.x - center.x, dy = point.y - center.y
            node.position = CGPoint(x:center.x + dx * cos(angle) - dy * sin(angle),
                                    y:center.y + dx * sin(angle) + dy * cos(angle))
            node.childNode(withName:"heading")?.zRotation = -CGFloat(ball.exit) * .pi / 2 + angle
        }
    }
    private func settlePlatform(_ p: Int, to target: CGFloat, animated: Bool = true) {
        guard let tile = tiles[p] else { return }
        if animated, previewTargets[p] == target { return }
        tile.removeAction(forKey:"preview-snap")
        previewTargets[p] = target
        let start = tile.zRotation
        guard animated, !UIAccessibility.isReduceMotionEnabled, abs(start-target) > 0.0001 else {
            applyPreviewAngle(target,platform:p); return
        }
        tile.run(.customAction(withDuration:0.24) { [weak self] _, elapsed in
            let t = min(1,elapsed / 0.24)
            let progress = 1 - pow(1 - t,3)
            self?.applyPreviewAngle(start + (target-start) * progress,platform:p)
        },withKey:"preview-snap")
    }

    func animate(before: BoardState, after: BoardState, turn: Turn, side: Side) {
        let visibleAngles = tiles.mapValues { $0.zRotation }
        selection = nil; highlighted = nil; inputEnabled = false
        render(before, side:side)
        guard !UIAccessibility.isReduceMotionEnabled else { render(after,side:side); return }
        resolving = true
        var rotated = before
        rotated.balls.append(contentsOf:turn.spawned)
        for ball in turn.spawned {
            let node = orb(for:ball); node.position = track(for:ball,in:before).midpoint; node.setScale(0.1)
            world.addChild(node); ballNodes[ball.id] = node; node.run(.scale(to:1,duration:0.25))
        }
        let rotatingPlatforms = Set(turn.rotations.keys).union(visibleAngles.filter { abs($0.value) > 0.0001 }.keys)
        for p in rotatingPlatforms {
            let q = turn.rotations[p,default:0]
            // Ride the platform's transform, including the entire rotation arc.
            if let tile = tiles[p] {
                for ball in rotated.balls where Rules.platform(ball.row,ball.col) == p {
                    guard let node = ballNodes[ball.id] else { continue }
                    let position = tile.convert(node.position,from:world)
                    node.removeFromParent(); tile.addChild(node); node.position = position
                }
            }
            let start = visibleAngles[p,default:0]
            tiles[p]?.zRotation = start
            let target = -CGFloat(q) * .pi / 2
            let delta = atan2(sin(target-start),cos(target-start))
            let rotation = SKAction.rotate(byAngle:delta,duration:0.38)
            rotation.timingMode = .easeInEaseOut
            tiles[p]?.run(rotation)
            Rules.rotate(&rotated,platform:p,quarters:q)
        }
        let rotatedSnapshot = rotated
        run(.sequence([.wait(forDuration:0.4),.run { [weak self] in
            guard let self else { return }
            self.render(after,side:side)
            for ball in after.balls {
                guard let origin = rotatedSnapshot.balls.first(where:{$0.id == ball.id}), let node = self.ballNodes[ball.id] else { continue }
                let source = self.track(for:origin,in:rotatedSnapshot)
                node.position = source.midpoint
                if origin.row != ball.row || origin.col != ball.col {
                    let path = source.path(to:self.track(for:ball,in:after),exit:origin.exit)
                    node.run(.follow(path,asOffset:false,orientToPath:false,duration:0.52))
                }
            }
            for (ball, receiver) in turn.delivered {
                let source = self.track(for:ball,in:rotatedSnapshot)
                let node = self.orb(for:ball); node.position = source.midpoint; self.world.addChild(node)
                let path = source.deliveryPath(exit:ball.exit,receiverY:receiver == .top ? 377 : -377)
                let target = path.currentPoint
                node.run(.sequence([.follow(path,asOffset:false,orientToPath:false,duration:0.45),.run { [weak self] in self?.burst(at:target) },.fadeOut(withDuration:0.15),.removeFromParent()]))
            }
        }]))
    }
    private func burst(at point: CGPoint) {
        for i in 0..<14 {
            let spark = SKShapeNode(circleOfRadius:3); spark.fillColor = colors[i%colors.count]; spark.strokeColor = .clear
            spark.position = point; spark.zPosition = 25; world.addChild(spark)
            let angle = CGFloat(i) * 2 * .pi / 14
            spark.run(.sequence([.group([.moveBy(x:cos(angle)*60,y:sin(angle)*60,duration:0.45),.fadeOut(withDuration:0.45)]),.removeFromParent()]))
        }
    }
    // Locations are in board coordinates, so dragging works from either side.
    @discardableResult func beginDrag(at location: CGPoint) -> Bool {
        guard inputEnabled, drag == nil,
              let p = (0..<9).first(where: { let c = tileCenter($0); return abs(c.x-location.x)<tileSize/2 && abs(c.y-location.y)<tileSize/2 }),
              let tile = tiles[p] else { return false }
        tile.removeAction(forKey:"preview-snap")
        previewTargets.removeValue(forKey:p)
        let center = tileCenter(p)
        drag = Drag(platform:p,start:location,startAngle:tile.zRotation,
                    initialCommand:selection?.platform == p ? selection : nil,
                    pointerAngle:hypot(location.x-center.x,location.y-center.y) < 12 ? nil : atan2(location.y-center.y,location.x-center.x),angle:tile.zRotation)
        onDragStart?()
        return true
    }
    func moveDrag(to location: CGPoint) {
        guard inputEnabled, var gesture = drag else { return }
        let threshold = 5 * size.width / max(view?.bounds.width ?? size.width,1)
        if current.cooldown.contains(gesture.platform) {
            // Hot platforms still accept reset taps, but cannot be dragged.
            if hypot(location.x-gesture.start.x,location.y-gesture.start.y) >= threshold { gesture.moved = true }
            drag = gesture; return
        }
        let center = tileCenter(gesture.platform)
        // Crossing the pivot must not turn a tiny finger movement into 180°.
        guard hypot(location.x-center.x,location.y-center.y) >= 12 else {
            gesture.pointerAngle = nil; drag = gesture; return
        }
        let angle = atan2(location.y-center.y,location.x-center.x)
        guard let previous = gesture.pointerAngle else {
            gesture.pointerAngle = angle; drag = gesture; return
        }
        let delta = atan2(sin(angle-previous),cos(angle-previous))
        if !gesture.moved, hypot(location.x-gesture.start.x,location.y-gesture.start.y) >= threshold {
            gesture.moved = true
            for other in tiles.keys where other != gesture.platform { settlePlatform(other,to:0) }
        }
        if gesture.moved {
            gesture.rotation = max(-.pi/2,min(.pi/2,gesture.rotation + delta))
            let displayAngle = gesture.startAngle + gesture.rotation
            // A second turn can be pulled past the chosen quarter-turn, then
            // springs back on release. It never becomes a second logical move.
            gesture.angle = gesture.initialCommand == nil ? max(-.pi/2,min(.pi/2,displayAngle)) : displayAngle
            applyPreviewAngle(gesture.angle,platform:gesture.platform)
            gesture.pointerAngle = angle
        }
        drag = gesture
    }
    func finishDrag(cancelled: Bool = false) {
        guard let gesture = drag else { return }
        drag = nil
        guard gesture.moved else {
            if cancelled {
                setSelection(selection,highlighted:selection?.platform,enabled:inputEnabled)
            } else {
                setSelection(nil,highlighted:nil,enabled:inputEnabled)
                onSelect?(gesture.platform,nil)
            }
            return
        }
        guard !current.cooldown.contains(gesture.platform) else {
            setSelection(selection,highlighted:selection?.platform,enabled:inputEnabled)
            return
        }
        if let initial = gesture.initialCommand {
            if cancelled || abs(gesture.rotation) < .pi/24 {
                setSelection(initial,highlighted:initial.platform,enabled:inputEnabled)
            } else if gesture.rotation * CGFloat(initial.dir) > 0 {
                // Measure the reverse gesture from finger-down, not from the
                // board's zero angle: the same 7.5° threshold also cancels a turn.
                setSelection(nil,highlighted:nil,enabled:inputEnabled)
                onSelect?(gesture.platform,nil)
            } else {
                setSelection(initial,highlighted:initial.platform,enabled:inputEnabled)
                onTurnLimit?()
            }
            return
        }
        let dir: Int? = cancelled || abs(gesture.angle) < .pi/24 ? nil : (gesture.angle < 0 ? 1 : -1)
        let command = dir.map { Command(platform:gesture.platform,dir:$0) }
        setSelection(command,highlighted:command?.platform,enabled:inputEnabled)
        // Commit before settling, so a deadline cannot drop the released move.
        onSelect?(gesture.platform,dir)
    }
    func dragChanged(start: CGPoint, location: CGPoint) {
        if drag == nil { _ = beginDrag(at:convertPoint(fromView:start)) }
        moveDrag(to:convertPoint(fromView:location))
    }
    func dragEnded(at location: CGPoint) {
        moveDrag(to:convertPoint(fromView:location)); finishDrag()
    }
}

extension UIColor {
    convenience init(hex: UInt32) { self.init(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0,rr:CGFloat=0,gg:CGFloat=0,bb:CGFloat=0,aa:CGFloat=0
        getRed(&r,green:&g,blue:&b,alpha:&a); other.getRed(&rr,green:&gg,blue:&bb,alpha:&aa)
        return UIColor(red:r+(rr-r)*amount,green:g+(gg-g)*amount,blue:b+(bb-b)*amount,alpha:1)
    }
}
