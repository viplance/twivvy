import RealityKit
import UIKit
import simd

/// Glass and characters share the same constant-radius elbow or straight bore.
/// World X follows columns, Z follows rows; visual height never changes rules.
struct TubePath {
    let center: SIMD3<Float>
    let mask: Int
    static let cell: Float = 0.98
    static let pitch: Float = 2.16
    static let height: Float = 0.43
    static let radius: Float = 0.245
    static let wall: Float = 0.012
    var ports: [Int] { (0..<4).filter { mask & (1 << $0) != 0 } }
    static func tileCenter(_ platform: Int) -> SIMD3<Float> {
        [Float(platform % 3 - 1) * pitch, 0, Float(platform / 3 - 1) * pitch]
    }
    static func cellCenter(row: Int, col: Int) -> SIMD3<Float> {
        tileCenter(Rules.platform(row, col)) + [Float(col % 2) * cell - cell / 2, height, Float(row % 2) * cell - cell / 2]
    }
    init(row: Int, col: Int, state: BoardState) {
        center = Self.cellCenter(row: row, col: col); mask = state.cells[row][col]
    }
    init(center: SIMD3<Float>, mask: Int) { self.center = center; self.mask = mask }
    func endpoint(_ port: Int) -> SIMD3<Float> {
        center + [SIMD3<Float>(0,0,-1), [1,0,0], [0,0,1], [-1,0,0]][port] * Self.cell / 2
    }
    var isElbow: Bool { ports.count == 2 && (ports[0] + 2) % 4 != ports[1] }
    var length: Float { isElbow ? Self.cell * .pi / 4 : Self.cell }
    private var bendCenter: SIMD3<Float> {
        guard let a=ports.first, let b=ports.last else { return center }
        return endpoint(a) + endpoint(b) - center
    }
    func tangent(_ t: Float) -> SIMD3<Float> {
        guard let a=ports.first, let b=ports.last, a != b else { return [0,0,-1] }
        if !isElbow { return simd_normalize(endpoint(b)-endpoint(a)) }
        let u=simd_normalize(endpoint(a)-bendCenter), v=simd_normalize(endpoint(b)-bendCenter)
        let angle=max(0,min(1,t)) * .pi/2
        return -u*sin(angle) + v*cos(angle)
    }
    func sample(_ t: Float) -> SIMD3<Float> {
        guard let a=ports.first, let b=ports.last else { return center }
        // Continue along the port axis when the nose/tail spans a joint.
        if t < 0 { return endpoint(a) + tangent(0) * (t * length) }
        if t > 1 { return endpoint(b) + tangent(1) * ((t-1) * length) }
        if !isElbow { return simd_mix(endpoint(a),endpoint(b),SIMD3(repeating:t)) }
        let angle=t * .pi/2
        return bendCenter + (endpoint(a)-bendCenter)*cos(angle) + (endpoint(b)-bendCenter)*sin(angle)
    }
    var midpoint: SIMD3<Float> { sample(0.5) }
    static func quadratic(_ a: SIMD3<Float>, _ c: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        (1-t)*(1-t)*a + 2*(1-t)*t*c + t*t*b
    }
    func fromMidpoint(toward port: Int, distance: Float) -> SIMD3<Float> {
        sample(0.5 + (port == ports.first ? -1 : 1) * distance / length)
    }
    func half(port: Int, towardPort: Bool, progress: Float) -> SIMD3<Float> {
        fromMidpoint(toward:port,distance:(towardPort ? progress : 1-progress)*length/2)
    }
    func travel(to destination: TubePath, exit: Int, progress: Float, offset: Float = 0) -> SIMD3<Float> {
        let entry=(exit+2)%4, gap=simd_distance(endpoint(exit),destination.endpoint(entry))
        let first=length/2, last=destination.length/2
        let distance=progress*(first+gap+last)+offset
        if distance <= first { return fromMidpoint(toward:exit,distance:distance) }
        if distance >= first+gap {
            return destination.fromMidpoint(toward:entry,distance:first+gap+last-distance)
        }
        return simd_mix(endpoint(exit),destination.endpoint(entry),SIMD3(repeating:(distance-first)/gap))
    }
    static func heading(exit: Int) -> Float { Float(exit) * -.pi / 2 }
}

@MainActor enum LabGeometry {
    private static let sphere = MeshResource.generateSphere(radius:1)
    private struct BoxKey: Hashable { let size: SIMD3<Float>; let radius: Float }
    private struct MaterialKey: Hashable { let color: UIColor; let metallic: Float; let roughness: Float }
    private static var boxes: [BoxKey:MeshResource] = [:]
    private static var materials: [MaterialKey:PhysicallyBasedMaterial] = [:]
    static let mint = UIColor(lab:0x4799D1), lavender = UIColor(lab:0x9174CF), pink = UIColor(lab:0xD98B9D)
    static let ink = UIColor(lab:0x152B40), cream = UIColor(lab:0xFFF0CE)
    static func material(_ color: UIColor, metallic: Float = 0, roughness: Float = 0.55) -> PhysicallyBasedMaterial {
        let key = MaterialKey(color:color,metallic:metallic,roughness:roughness)
        if let cached = materials[key] { return cached }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color); m.metallic = .init(floatLiteral:metallic); m.roughness = .init(floatLiteral:roughness)
        materials[key] = m
        return m
    }
    static func glow(_ color: UIColor) -> UnlitMaterial { UnlitMaterial(color:color) }
    static func glass(_ color: UIColor = UIColor(lab:0xADD3FF)) -> PhysicallyBasedMaterial {
        // Inner and outer walls both blend over the residents. Keep each layer
        // clear so the blue glass does not wash out their fur and expressions.
        var m = material(color, metallic:0, roughness:0.08)
        m.specular = .init(floatLiteral:0.20)
        m.blending = .transparent(opacity:.init(floatLiteral:0.12))
        m.faceCulling = .back // Inner and outer walls already have opposite winding.
        return m
    }
    private static func tubeWall() -> PhysicallyBasedMaterial {
        var m = glass(UIColor(lab:0x72B9EB))
        m.blending = .transparent(opacity:.init(floatLiteral:0.42))
        return m
    }
    static func box(_ size: SIMD3<Float>, at position: SIMD3<Float>, color: UIColor, radius: Float = 0.06) -> ModelEntity {
        let e = ModelEntity(mesh:boxMesh(size,radius:radius),materials:[material(color)])
        e.position = position; return e
    }
    private static func boxMesh(_ size: SIMD3<Float>, radius: Float) -> MeshResource {
        let key = BoxKey(size:size,radius:radius)
        if let cached = boxes[key] { return cached }
        let mesh = MeshResource.generateBox(size:size,cornerRadius:radius)
        boxes[key] = mesh
        return mesh
    }
    static func ellipsoid(_ scale: SIMD3<Float>, at position: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let e = ModelEntity(mesh:sphere,materials:[material(color)])
        e.scale = scale; e.position = position; return e
    }
    static func line(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, color: UIColor, luminous: Bool = false) -> ModelEntity {
        let length = simd_distance(a,b)
        let materials: [any Material] = luminous ? [glow(color)] : [material(color,metallic:0.3)]
        let e = ModelEntity(mesh:boxMesh([width,width,max(width,length)],radius:width/2),materials:materials)
        e.position = (a+b)/2
        if length > 0.0001 { e.orientation = simd_quatf(from:[0,0,1],to:simd_normalize(b-a)) }
        return e
    }
    /// A swept, hollow mesh with inner walls and open ends, not a solid cylinder.
    static func tube(points: [SIMD3<Float>], radius: Float = TubePath.radius, thickness: Float = TubePath.wall) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        var wallMaterials: [UInt32] = []
        let sides = 24, count = points.count
        guard count >= 2 else { throw GeometryError.emptyPath }
        for shell in 0..<2 {
            let r = shell == 0 ? radius : radius-thickness
            for i in 0..<count {
                let tangent = simd_normalize(points[min(count-1,i+1)] - points[max(0,i-1)])
                let reference: SIMD3<Float> = abs(tangent.y) > 0.95 ? [1,0,0] : [0,1,0]
                let side = simd_normalize(simd_cross(tangent, reference))
                let up = simd_cross(side,tangent)
                for j in 0..<sides {
                    let angle = Float(j) / Float(sides) * 2 * .pi
                    let normal = side*cos(angle) + up*sin(angle)
                    vertices.append(points[i]+normal*r); normals.append(shell == 0 ? normal : -normal)
                }
            }
        }
        for shell in 0..<2 { for i in 0..<count-1 { for j in 0..<sides {
            let a = UInt32(shell*count*sides+i*sides+j), b = UInt32(shell*count*sides+i*sides+(j+1)%sides)
            let c = a+UInt32(sides), d = b+UInt32(sides)
            indices += shell == 0 ? [a,c,b,b,c,d] : [a,b,c,b,d,c]
            // A clear upper window preserves the residents' colors. The sides
            // and underside carry the denser blue tint that defines the tube.
            let lowerWall: UInt32 = sin((Float(j)+0.5)/Float(sides)*2 * .pi) < 0.25 ? 1 : 0
            wallMaterials += [lowerWall,lowerWall]
        } } }
        // Lip rings join the inner and outer wall; the bore stays open.
        for i in [0,count-1] { for j in 0..<sides {
            let a=UInt32(i*sides+j), b=UInt32(i*sides+(j+1)%sides)
            let c=a+UInt32(count*sides), d=b+UInt32(count*sides)
            indices += i == 0 ? [a,c,b,b,c,d] : [a,b,c,b,d,c]
            wallMaterials += [1,1]
        } }
        var descriptor = MeshDescriptor(name:"HamsterLab-hollow-tube")
        descriptor.positions = .init(vertices); descriptor.normals = .init(normals); descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(wallMaterials)
        return try MeshResource.generate(from:[descriptor])
    }
    static func collar(at position: SIMD3<Float>, tangent: SIMD3<Float>, color: UIColor, radius: Float = TubePath.radius + 0.01) -> Entity {
        let root = Entity(); root.position = position
        let direction = simd_normalize(tangent)
        let reference: SIMD3<Float> = abs(direction.y)>0.95 ? [1,0,0] : [0,1,0]
        let side = simd_normalize(simd_cross(direction,reference))
        let up = simd_cross(side,direction)
        let ring = (0...24).map { i -> SIMD3<Float> in
            let angle = Float(i)*2 * .pi/24
            return (side*cos(angle)+up*sin(angle))*radius
        }
        do { root.addChild(ModelEntity(mesh:try strokes([ring],radius:0.017,closed:true),materials:[material(color,metallic:0.3)])) }
        catch { assertionFailure("Collar mesh: \(error)") }
        return root
    }
    /// Bake static strokes into one mesh instead of submitting a model for every
    /// segment. Keeps the rounded collars/highlights without thousands of entities.
    private static func strokes(_ paths: [[SIMD3<Float>]], radius: Float, closed: Bool = false) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        let sides = 6
        for points in paths where points.count >= 2 {
            let offset = vertices.count
            for i in points.indices {
                let previous = closed && i == 0 ? points[points.count-2] : points[max(0,i-1)]
                let next = closed && i == points.count-1 ? points[1] : points[min(points.count-1,i+1)]
                let tangent = simd_normalize(next-previous)
                let reference: SIMD3<Float> = abs(tangent.y)>0.95 ? [1,0,0] : [0,1,0]
                let side = simd_normalize(simd_cross(tangent,reference)), up = simd_cross(side,tangent)
                for j in 0..<sides {
                    let angle = Float(j)*2 * .pi/Float(sides)
                    let normal = side*cos(angle)+up*sin(angle)
                    vertices.append(points[i]+normal*radius); normals.append(normal)
                }
            }
            for i in 0..<points.count-1 { for j in 0..<sides {
                let a = UInt32(offset+i*sides+j), b = UInt32(offset+i*sides+(j+1)%sides)
                let c = a+UInt32(sides), d = b+UInt32(sides)
                indices += [a,c,b,b,c,d]
            } }
        }
        guard !vertices.isEmpty else { throw GeometryError.emptyPath }
        var descriptor = MeshDescriptor(name:"HamsterLab-batched-strokes")
        descriptor.positions = .init(vertices); descriptor.normals = .init(normals); descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from:[descriptor])
    }
    static func tubeAssembly(points: [SIMD3<Float>], tint: UIColor, collars: Bool = true, radius: Float = TubePath.radius) -> Entity {
        let root = Entity()
        do { root.addChild(ModelEntity(mesh:try tube(points:points,radius:radius),materials:[glass(),tubeWall()])) }
        catch { assertionFailure("Tube mesh: \(error)") }
        // Thin highlights make transparent glass readable against the laboratory.
        let highlights: [[SIMD3<Float>]] = [-radius*0.94,radius*0.94].map { offset in
            points.indices.map { i -> SIMD3<Float> in
                let tangent=simd_normalize(points[min(points.count-1,i+1)]-points[max(0,i-1)])
                let reference: SIMD3<Float> = abs(tangent.y)>0.95 ? [1,0,0] : [0,1,0]
                let side=simd_normalize(simd_cross(tangent,reference))
                return points[i] + side*offset + [0,radius*0.34,0]
            }
        }
        do { root.addChild(ModelEntity(mesh:try strokes(highlights,radius:0.009),materials:[glow(UIColor(lab:0x72B4E3))])) }
        catch { assertionFailure("Highlight mesh: \(error)") }
        if collars, points.count > 1 {
            root.addChild(collar(at:points[0],tangent:points[1]-points[0],color:tint,radius:radius+0.01))
            root.addChild(collar(at:points.last!,tangent:points.last!-points[points.count-2],color:tint,radius:radius+0.01))
        }
        return root
    }
    enum GeometryError: Error { case emptyPath }
}

extension UIColor {
    convenience init(lab hex: UInt32) { self.init(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
}
