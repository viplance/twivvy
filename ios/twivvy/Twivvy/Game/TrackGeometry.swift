import CoreGraphics

/// The same quadratic centerline drives both the rail and the balls on it.
struct TrackGeometry {
    let center: CGPoint
    let cellSize: CGFloat
    let mask: Int

    private var ports: [Int] { (0..<4).filter { mask & (1 << $0) != 0 } }

    func endpoint(_ port: Int) -> CGPoint {
        let offsets = [CGPoint(x:0,y:1), CGPoint(x:1,y:0), CGPoint(x:0,y:-1), CGPoint(x:-1,y:0)]
        return CGPoint(x:center.x + offsets[port].x * cellSize / 2,
                       y:center.y + offsets[port].y * cellSize / 2)
    }

    var midpoint: CGPoint {
        guard let first = ports.first, let last = ports.last else { return center }
        let a = endpoint(first), b = endpoint(last)
        return CGPoint(x:(a.x + 2 * center.x + b.x) / 4,
                       y:(a.y + 2 * center.y + b.y) / 4)
    }

    var path: CGPath {
        let path = CGMutablePath()
        guard let first = ports.first, let last = ports.last else { return path }
        path.move(to:endpoint(first))
        path.addQuadCurve(to:endpoint(last), control:center)
        return path
    }

    /// Split the quadratic at t = 0.5 (de Casteljau), preserving its exact shape.
    func appendHalf(to path: CGMutablePath, port: Int, towardPort: Bool) {
        let end = endpoint(port)
        let control = CGPoint(x:(center.x + end.x) / 2, y:(center.y + end.y) / 2)
        path.addQuadCurve(to:towardPort ? end : midpoint, control:control)
    }

    func path(to destination: TrackGeometry, exit: Int) -> CGPath {
        let path = CGMutablePath()
        path.move(to:midpoint)
        appendHalf(to:path, port:exit, towardPort:true)
        // Adjacent platforms have a small gap between their edge ports.
        let entry = (exit + 2) % 4
        path.addLine(to:destination.endpoint(entry))
        destination.appendHalf(to:path, port:entry, towardPort:false)
        return path
    }

    func deliveryPath(exit: Int, receiverY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to:midpoint)
        appendHalf(to:path, port:exit, towardPort:true)
        path.addLine(to:CGPoint(x:endpoint(exit).x, y:receiverY))
        return path
    }
}
