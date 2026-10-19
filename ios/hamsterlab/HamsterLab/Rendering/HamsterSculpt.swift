import RealityKit
import UIKit
import simd

/// Original sculpted surfaces and painted coats, shared by every resident.
/// Fur detail lives in a small opaque texture and a few silhouette tufts;
/// there are no transparent fur shells, particles, or per-hair entities.
@MainActor enum HamsterSculpt {
    enum Part: String { case torso, head, cheek }
    private static var meshes: [Part: MeshResource] = [:]
    private static var coats: [String: PhysicallyBasedMaterial] = [:]
    private static var details: [String: MeshResource] = [:]
    private static var furNormal: TextureResource?
    static let cream = UIColor(lab: 0xFFF1D9)
    static let skin = UIColor(lab: 0xEDA6A0)
    static let dark = UIColor(lab: 0x342126)
    // Natural Syrian/dwarf hamster colors, rather than purple plastic coats.
    private static let colors: [SIMD3<Float>] = [
        [0.83, 0.48, 0.17], [0.61, 0.53, 0.46], [0.91, 0.69, 0.36],
        [0.51, 0.34, 0.22], [0.78, 0.72, 0.61]
    ]

    static func fur(_ part: Part, variant: Int) -> ModelEntity {
        let mesh: MeshResource
        if let cached = meshes[part] { mesh = cached }
        else {
            mesh = surface(name: part.rawValue) { direction in point(direction, part: part) }
            meshes[part] = mesh
        }
        return ModelEntity(mesh: mesh, materials: [coat(part, variant: variant)])
    }

    private static func point(_ n: SIMD3<Float>, part: Part) -> SIMD3<Float> {
        switch part {
        case .torso:
            // Full haunches flow into a short neck; a flattened underside sits
            // over the feet. No separate belly sphere intersects the torso.
            let haunch: Float = 1 + 0.12 * n.z - 0.08 * n.y
            return [n.x * 0.148 * haunch, n.y * 0.143 - 0.012, n.z * 0.208 + 0.025]
        case .head:
            let cheek = exp(-pow((n.y + 0.32) / 0.52, 2)) * max(0, -n.z)
            return [n.x * (0.137 + 0.047 * cheek), n.y * 0.126, n.z * 0.119 - 0.014 * cheek]
        case .cheek:
            // Pouches taper into the head at their upper edge.
            return [n.x * 0.076 * (1 - 0.15 * n.y), n.y * 0.072, n.z * 0.058]
        }
    }

    private static func surface(name: String, point: (SIMD3<Float>) -> SIMD3<Float>) -> MeshResource {
        let rings = 28, sides = 40
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = [], bitangents: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = [], indices: [UInt32] = []
        func direction(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
            [sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi)]
        }
        for row in 0...rings {
            let v = Float(row) / Float(rings)
            // Tiny caps avoid degenerate pole normals during differentiation.
            let theta = max(0.0001, min(.pi - 0.0001, v * .pi))
            for col in 0...sides {
                let u = Float(col) / Float(sides), phi = u * 2 * .pi
                let n = direction(theta, phi)
                let a = point(direction(theta + 0.001, phi)) - point(direction(theta - 0.001, phi))
                let b = point(direction(theta, phi + 0.001)) - point(direction(theta, phi - 0.001))
                positions.append(point(n)); normals.append(simd_normalize(simd_cross(a, b)))
                tangents.append(simd_normalize(b)); bitangents.append(-simd_normalize(a))
                uv.append([u, 1 - v])
            }
        }
        for row in 0..<rings { for col in 0..<sides {
            let a = UInt32(row * (sides + 1) + col), b = a + 1, c = a + UInt32(sides + 1)
            indices += [a, c, b, b, c, c + 1]
        } }
        var descriptor = MeshDescriptor(name: "HamsterLab-sculpt-\(name)")
        descriptor.positions = .init(positions); descriptor.normals = .init(normals)
        descriptor.tangents = .init(tangents); descriptor.bitangents = .init(bitangents)
        descriptor.textureCoordinates = .init(uv); descriptor.primitives = .triangles(indices)
        return generate(descriptor)
    }

    private static func coat(_ part: Part, variant: Int) -> PhysicallyBasedMaterial {
        let index = part == .cheek ? 0 : variant % colors.count, key = "\(part.rawValue)-\(index)"
        if let cached = coats[key] { return cached }
        var material = LabGeometry.material(cream, roughness: 0.92)
        material.specular = .init(floatLiteral: 0.16)
        material.sheen = .init(tint: UIColor(lab: 0x665341))
        material.baseColor = .init(tint: .white, texture: .init(texture("hamster-\(key)", semantic: .color)))
        if furNormal == nil { furNormal = texture("hamster-fur-normal", semantic: .normal) }
        material.normal = .init(texture: furNormal.map { .init($0) })
        coats[key] = material
        return material
    }
    private static func texture(_ name: String, semantic: TextureResource.Semantic) -> TextureResource {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png")
        else { preconditionFailure("Missing bundled hamster texture: \(name)") }
        do { return try TextureResource.load(contentsOf: url, options: .init(semantic: semantic)) }
        catch { preconditionFailure("Hamster coat texture: \(error)") }
    }

    static func ear(variant: Int) -> Entity {
        let ear = Entity()
        for inner in [false, true] {
            let key = inner ? "inner-ear" : "outer-ear"
            let mesh: MeshResource
            if let cached = details[key] { mesh = cached }
            else {
                mesh = surface(name: key) { n in
                    let radii: SIMD3<Float> = inner ? [0.038, 0.046, 0.012] : [0.049, 0.058, 0.023]
                    var p = n * radii
                    // Turn the front dome inward to form a genuinely cupped ear.
                    p.z += (inner ? 0.021 : 0.038) * pow(max(0, -n.z), 6)
                    if inner { p.z -= 0.009 }
                    return p
                }
                details[key] = mesh
            }
            let c = colors[variant % colors.count] * 0.80
            let tint = inner ? skin : UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
            ear.addChild(ModelEntity(mesh: mesh, materials: [LabGeometry.material(tint, roughness: 0.85)]))
        }
        return ear
    }

    /// A single mesh for each hand: a soft palm and four splayed pink digits.
    static func paw() -> ModelEntity {
        let mesh = cachedDetail("paw") {
            var builder = DetailMesh()
            builder.ellipsoid(center: [0, 0, 0], radii: [0.025, 0.019, 0.032])
            for finger in 0..<4 {
                let x = (Float(finger) - 1.5) * 0.013
                builder.ellipsoid(center: [x, -0.002, -0.030], radii: [0.008, 0.011, finger == 0 || finger == 3 ? 0.017 : 0.023])
            }
            return builder.descriptor("soft-fingered-paw")
        }
        return ModelEntity(mesh: mesh, materials: [LabGeometry.material(skin, roughness: 0.73)])
    }

    /// Opaque, curved wisps along the silhouette give the sculpt a furry edge.
    /// All wisps of one color are one model, including the forehead cowlick.
    static func tufts(cream: Bool, variant: Int) -> ModelEntity {
        let mesh = cachedDetail(cream ? "cheek-tufts" : "crown-tufts") {
            var builder = DetailMesh()
            if cream {
                for sign: Float in [-1, 1] { for i in 0..<7 {
                    let t = Float(i) / 6
                    let start = SIMD3<Float>(sign * (0.148 - t * t * 0.022), -0.010 - t * 0.073, -0.075)
                    builder.wisp(start, start + [sign * 0.010, -0.003, -0.003], start + [sign * 0.014, -0.010, -0.002], width: 0.009)
                } }
            } else {
                for i in 0..<3 {
                    let x = Float(i - 1) * 0.014
                    let start = SIMD3<Float>(x, 0.115 - abs(x) * 0.15, -0.010)
                    let height: Float = [0.022, 0.032, 0.026][i]
                    builder.wisp(start, start + [-0.005, height, 0], start + [-0.020, height * 0.82, -0.004], width: 0.022)
                }
            }
            return builder.descriptor("fur-silhouette")
        }
        let c = colors[variant % colors.count]
        let tint = cream ? Self.cream : UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        return ModelEntity(mesh: mesh, materials: [LabGeometry.material(tint, roughness: 0.95)])
    }

    static func whiskers(sign: Float) -> ModelEntity {
        let mesh = cachedDetail(sign < 0 ? "whiskers-left" : "whiskers-right") {
            var builder = DetailMesh()
            for i in 0..<3 {
                let y = Float(i - 1) * 0.011
                let a = SIMD3<Float>(sign * 0.067, -0.025 + y, -0.144)
                builder.wisp(a, [sign * 0.143, -0.021 + y * 1.6, -0.154], [sign * 0.194, -0.008 + y * 2.5, -0.126], width: 0.0015)
            }
            return builder.descriptor("curved-whiskers")
        }
        return ModelEntity(mesh: mesh, materials: [LabGeometry.material(UIColor(lab: 0x775E47), roughness: 0.85)])
    }

    private static func cachedDetail(_ name: String, build: () -> MeshDescriptor) -> MeshResource {
        if let cached = details[name] { return cached }
        let mesh = generate(build()); details[name] = mesh; return mesh
    }
    private static func generate(_ descriptor: MeshDescriptor) -> MeshResource {
        do { return try MeshResource.generate(from: [descriptor]) }
        catch { preconditionFailure("Hamster sculpt mesh: \(error)") }
    }

    private struct DetailMesh {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        mutating func ellipsoid(center: SIMD3<Float>, radii: SIMD3<Float>) {
            let offset = UInt32(positions.count), rings = 8, sides = 12
            for i in 0...rings { for j in 0...sides {
                let theta = Float(i) / Float(rings) * .pi, phi = Float(j) / Float(sides) * 2 * .pi
                let n = SIMD3<Float>(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
                positions.append(center + n * radii); normals.append(simd_normalize(n / radii))
            } }
            for i in 0..<rings { for j in 0..<sides {
                let a = offset + UInt32(i * (sides + 1) + j), c = a + UInt32(sides + 1)
                indices += [a, c, a + 1, a + 1, c, c + 1]
            } }
        }
        mutating func wisp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, width: Float) {
            let offset = UInt32(positions.count), sides = 5, steps = 5
            for i in 0...steps {
                let t = Float(i) / Float(steps), center = TubePath.quadratic(a, b, c, t)
                let tangent = simd_normalize((1 - t) * (b - a) + t * (c - b))
                let reference: SIMD3<Float> = abs(tangent.y) > 0.9 ? [1, 0, 0] : [0, 1, 0]
                let side = simd_normalize(simd_cross(tangent, reference)), up = simd_cross(side, tangent)
                for j in 0..<sides {
                    let angle = Float(j) * 2 * .pi / Float(sides), n = side * cos(angle) + up * sin(angle)
                    positions.append(center + n * max(0.0001, width * (1 - t) * 0.5)); normals.append(n)
                }
            }
            for i in 0..<steps { for j in 0..<sides {
                let a = offset + UInt32(i * sides + j), b = offset + UInt32(i * sides + (j + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                indices += [a, c, b, b, c, d]
            } }
        }
        func descriptor(_ name: String) -> MeshDescriptor {
            var mesh = MeshDescriptor(name: name)
            mesh.positions = .init(positions); mesh.normals = .init(normals); mesh.primitives = .triangles(indices)
            return mesh
        }
    }
}
