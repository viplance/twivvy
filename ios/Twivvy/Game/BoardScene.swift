import SpriteKit
import UIKit

@MainActor final class BoardScene: SKScene {
    var onSelect: ((Int, Int?) -> Void)?
    private let world = SKNode()
    private var tiles: [Int: SKNode] = [:]
    private var ballNodes: [Int: SKNode] = [:]
    private var current = BoardState()
    private var perspective: Side = .bottom
    private var inputEnabled = false
    private var touchStart: CGPoint?
    private var touchPlatform: Int?
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
    private func rounded(_ rect: CGRect, radius: CGFloat, fill: UIColor, stroke: UIColor = .clear, width: CGFloat = 1) -> SKShapeNode {
        let shape = SKShapeNode(rect: rect, cornerRadius: radius)
        shape.fillColor = fill; shape.strokeColor = stroke; shape.lineWidth = width
        return shape
    }
    func render(_ state: BoardState, side: Side) {
        removeAllActions(); world.removeAllChildren(); tiles.removeAll(); ballNodes.removeAll()
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
            let badge = SKLabelNode(fontNamed:"AvenirNext-Bold")
            badge.text = "\(p+1)"; badge.fontSize = 15; badge.fontColor = colors[p].withAlphaComponent(0.55)
            badge.position = CGPoint(x:0,y:-7); badge.zRotation = side == .top ? .pi : 0
            tile.addChild(badge); world.addChild(tile); tiles[p] = tile
            if state.cooldown.contains(p) {
                let lock = SKLabelNode(fontNamed:"AvenirNext-Bold")
                lock.text = "×"; lock.fontSize = 28; lock.fontColor = UIColor(hex:0xFFCC8C)
                lock.position = CGPoint(x:80,y:69); lock.name = "lock"; tile.addChild(lock)
            }
        }
        for (index, position) in [(2,2),(3,3)].enumerated() {
            let source = SKShapeNode(circleOfRadius:19)
            source.position = point(position.0,position.1); source.strokeColor = UIColor(hex:0xFFE7A2)
            source.lineWidth = 2.5; source.fillColor = UIColor(hex:0xFFCE76).withAlphaComponent(0.12)
            source.zPosition = 3
            let upcoming = Rules.spawnTicks.contains(state.tick+1) && !state.finished
            source.alpha = upcoming ? 1 : 0.45
            if upcoming && !UIAccessibility.isReduceMotionEnabled {
                source.run(.repeatForever(.sequence([.fadeAlpha(to:0.4,duration:0.9),.fadeAlpha(to:1,duration:0.9)])))
            }
            let dot = SKShapeNode(circleOfRadius:4); dot.fillColor = UIColor(hex:0xFFE7A2); dot.strokeColor = .clear
            dot.position.x = index == 0 ? -25 : 25; source.addChild(dot); world.addChild(source)
        }
        for ball in state.balls { let node = orb(exit:ball.exit); node.position = point(ball.row,ball.col); world.addChild(node); ballNodes[ball.id] = node }
        receiver(.top, score:state.score.top); receiver(.bottom, score:state.score.bottom)
        setSelection(selection, highlighted: highlighted, enabled:inputEnabled)
    }
    private func addTrack(to parent: SKNode, center: CGPoint, mask: Int, color: UIColor) {
        let ends = [CGPoint(x:0,y:cell/2),CGPoint(x:cell/2,y:0),CGPoint(x:0,y:-cell/2),CGPoint(x:-cell/2,y:0)]
        let ports = (0..<4).filter { mask & (1 << $0) != 0 }
        guard let first = ports.first, let last = ports.last else { return }
        let path = CGMutablePath()
        path.move(to:CGPoint(x:center.x+ends[first].x,y:center.y+ends[first].y))
        if abs(first-last) == 2 { path.addLine(to:CGPoint(x:center.x+ends[last].x,y:center.y+ends[last].y)) }
        else { path.addQuadCurve(to:CGPoint(x:center.x+ends[last].x,y:center.y+ends[last].y),control:center) }
        for (width, tint) in [(CGFloat(27),UIColor(hex:0x060D20)),(CGFloat(17),color.withAlphaComponent(0.22)),(CGFloat(7),color),(CGFloat(2),UIColor.white.withAlphaComponent(0.75))] {
            let track = SKShapeNode(path:path); track.lineWidth = width; track.strokeColor = tint
            track.lineCap = .round; track.lineJoin = .round; parent.addChild(track)
        }
    }
    private func orb(exit: Int = 0) -> SKNode {
        let node = SKNode(); node.zPosition = 10
        let halo = SKShapeNode(circleOfRadius:22); halo.fillColor = UIColor(hex:0xFFD88A).withAlphaComponent(0.15)
        halo.strokeColor = .clear; halo.glowWidth = 9; node.addChild(halo)
        let ball = SKShapeNode(circleOfRadius:13); ball.fillColor = UIColor(hex:0xFFD580)
        ball.strokeColor = UIColor(hex:0xFFF5CE); ball.lineWidth = 2.5; node.addChild(ball)
        let highlight = SKShapeNode(circleOfRadius:4); highlight.position = CGPoint(x:-4,y:5)
        highlight.fillColor = .white; highlight.strokeColor = .clear; node.addChild(highlight)
        let direction = CGMutablePath()
        direction.move(to:CGPoint(x:-5,y:23)); direction.addLine(to:CGPoint(x:0,y:29)); direction.addLine(to:CGPoint(x:5,y:23))
        let arrow = SKShapeNode(path:direction); arrow.name = "heading"; arrow.strokeColor = UIColor(hex:0xFFE7A2); arrow.lineWidth = 2.5
        arrow.lineCap = .round; arrow.lineJoin = .round; arrow.zRotation = -CGFloat(exit) * .pi / 2; node.addChild(arrow)
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
    func setSelection(_ selection: Command?, highlighted: Int?, enabled: Bool) {
        self.selection = selection; self.highlighted = highlighted; inputEnabled = enabled
        for (p,tile) in tiles {
            guard let base = tile.childNode(withName:"base") as? SKShapeNode else { continue }
            let chosen = p == highlighted
            tile.zRotation = selection?.platform == p ? -CGFloat(selection!.dir) * .pi / 2 : 0
            base.strokeColor = chosen ? UIColor(hex:0xFFE7A2) : colors[p].withAlphaComponent(current.cooldown.contains(p) ? 0.18 : 0.45)
            base.lineWidth = chosen ? 5 : 2; base.glowWidth = chosen ? 5 : 0
            tile.childNode(withName:"preview")?.removeFromParent()
            if selection?.platform == p {
                let arrow = SKLabelNode(fontNamed:"AvenirNext-Bold")
                arrow.name = "preview"; arrow.text = selection?.dir == 1 ? "↻" : "↺"
                arrow.fontSize = 48; arrow.fontColor = UIColor(hex:0xFFE7A2)
                arrow.position = CGPoint(x:0,y:-16); arrow.zPosition = 20
                arrow.zRotation = (perspective == .top ? .pi : 0) - tile.zRotation; tile.addChild(arrow)
            }
        }
        var preview = current
        if let selection { Rules.rotate(&preview,platform:selection.platform,quarters:selection.dir) }
        for ball in preview.balls {
            ballNodes[ball.id]?.position = point(ball.row,ball.col)
            ballNodes[ball.id]?.childNode(withName:"heading")?.zRotation = -CGFloat(ball.exit) * .pi / 2
        }
    }
    func animate(before: BoardState, after: BoardState, turn: Turn, side: Side) {
        selection = nil; highlighted = nil; inputEnabled = false
        render(before, side:side)
        guard !UIAccessibility.isReduceMotionEnabled else { render(after,side:side); return }
        var rotated = before
        rotated.balls.append(contentsOf:turn.spawned)
        for ball in turn.spawned {
            let node = orb(exit:ball.exit); node.position = point(ball.row,ball.col); node.setScale(0.1)
            world.addChild(node); ballNodes[ball.id] = node; node.run(.scale(to:1,duration:0.25))
        }
        for (p,q) in turn.rotations {
            tiles[p]?.run(.rotate(byAngle:-CGFloat(q) * .pi / 2,duration:0.38))
            Rules.rotate(&rotated,platform:p,quarters:q)
        }
        for ball in rotated.balls { ballNodes[ball.id]?.run(.move(to:point(ball.row,ball.col),duration:0.38)) }
        let rotatedSnapshot = rotated
        run(.sequence([.wait(forDuration:0.4),.run { [weak self] in
            guard let self else { return }
            self.render(after,side:side)
            for ball in after.balls {
                guard let origin = rotatedSnapshot.balls.first(where:{$0.id == ball.id}), let node = self.ballNodes[ball.id] else { continue }
                node.position = self.point(origin.row,origin.col)
                node.run(.move(to:self.point(ball.row,ball.col),duration:0.52))
            }
            for (ball, receiver) in turn.delivered {
                let node = self.orb(exit:ball.exit); node.position = self.point(ball.row,ball.col); self.world.addChild(node)
                let target = CGPoint(x:node.position.x,y:receiver == .top ? 377 : -377)
                node.run(.sequence([.move(to:target,duration:0.45),.run { [weak self] in self?.burst(at:target) },.fadeOut(withDuration:0.15),.removeFromParent()]))
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
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputEnabled, let touch = touches.first else { return }
        let location = touch.location(in:world)
        guard let p = (0..<9).first(where: { let c = tileCenter($0); return abs(c.x-location.x)<tileSize/2 && abs(c.y-location.y)<tileSize/2 }) else { return }
        touchStart = location; touchPlatform = p
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputEnabled, let touch = touches.first, let start = touchStart, let p = touchPlatform else { return }
        let end = touch.location(in:world), center = tileCenter(p)
        let distance = hypot(end.x-start.x,end.y-start.y)
        var dir: Int?
        if distance > 28 {
            let cross = (start.x-center.x)*(end.y-center.y)-(start.y-center.y)*(end.x-center.x)
            dir = cross < 0 ? 1 : -1
        }
        onSelect?(p,dir); touchStart = nil; touchPlatform = nil
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchStart = nil; touchPlatform = nil }
}

extension UIColor {
    convenience init(hex: UInt32) { self.init(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0,rr:CGFloat=0,gg:CGFloat=0,bb:CGFloat=0,aa:CGFloat=0
        getRed(&r,green:&g,blue:&b,alpha:&a); other.getRed(&rr,green:&gg,blue:&bb,alpha:&aa)
        return UIColor(red:r+(rr-r)*amount,green:g+(gg-g)*amount,blue:b+(bb-b)*amount,alpha:1)
    }
}
