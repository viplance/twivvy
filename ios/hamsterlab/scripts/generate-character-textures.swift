#!/usr/bin/env swift
import AppKit
import simd

// Original opaque coat/normal maps for HamsterSculpt. Bake offline so the first
// hamster of a new color never generates textures on the game's main thread.
let destination = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ios/hamsterlab/HamsterLab/Resources/HamsterCoats", isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let width = 512, height = 256
let colors: [SIMD3<Float>] = [
    [0.83, 0.48, 0.17], [0.61, 0.53, 0.46], [0.91, 0.69, 0.36],
    [0.51, 0.34, 0.22], [0.78, 0.72, 0.61]
]
var randomState: UInt32 = 0x48414D53
func random() -> Float {
    randomState = randomState &* 1664525 &+ 1013904223
    return Float(randomState >> 8) / Float(1 << 24)
}
// Tapered, irregular short fibers avoid a repeating knitted/plastic pattern.
// Both the painted coat and its normal map use this same tiny height field.
var fibers = [Float](repeating: 0, count: width * height)
for _ in 0..<26000 {
    let x = random() * Float(width), y = random() * Float(height)
    let length = 2.5 + random() * 5, drift = (random() - 0.5) * 2.5
    let strength = 0.10 + random() * 0.20
    for step in 0...10 {
        let t = Float(step) / 10
        let column = Int(x + drift * t + Float(width)) % width
        let row = Int(y + length * t) % height
        let value = sin(t * .pi) * strength
        let index = row * width + column
        fibers[index] = max(fibers[index], value)
        for side in [-1, 1] {
            let neighbor = row * width + (column + side + width) % width
            fibers[neighbor] = max(fibers[neighbor], value * 0.25)
        }
    }
}
func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}
func write(_ pixels: [UInt8], name: String) throws {
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try png.write(to: destination.appendingPathComponent(name + ".png"))
}
for part in ["torso", "head", "cheek"] {
    for index in 0..<(part == "cheek" ? 1 : colors.count) {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let gold = colors[index], pale = SIMD3<Float>(1, 0.945, 0.85)
        for y in 0..<height { for x in 0..<width {
            let theta = Float(y) / Float(height - 1) * .pi
            let phi = Float(x) / Float(width - 1) * 2 * .pi
            let n = SIMD3<Float>(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
            let front = max(0, -n.z)
            let bib: Float
            switch part {
            case "torso": bib = smooth(-0.12, 0.22, -n.y + front * 0.27)
            case "head":
                let cheeks = smooth(-0.10, 0.32, -n.y) * smooth(0.05, 0.50, front)
                let blaze = exp(-pow(n.x / 0.20, 2)) * smooth(0.25, 0.85, front) * 0.82
                bib = max(cheeks, blaze)
            default: bib = 1
            }
            let fiber = fibers[y * width + x] - 0.12
            let grain = sin(Float(x * 73 + y * 179)) * 0.008
            let stripe = part == "torso" ? exp(-pow(n.x / 0.22, 2)) * max(0, n.y) * 0.13 : 0
            let c = simd_mix(gold * (1 - stripe), pale, SIMD3(repeating: bib)) * (1 + fiber * 0.32 + grain)
            for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = UInt8(max(0, min(255, c[channel] * 255))) }
        } }
        try write(pixels, name: "hamster-\(part)-\(index)")
    }
}
var pixels = [UInt8](repeating: 255, count: width * height * 4)
for y in 0..<height { for x in 0..<width {
    let dx = fibers[y * width + (x + 1) % width] - fibers[y * width + (x + width - 1) % width]
    let dy = fibers[((y + 1) % height) * width + x] - fibers[((y + height - 1) % height) * width + x]
    let n = simd_normalize(SIMD3<Float>(-dx * 0.65, dy * 0.65, 1))
    for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = UInt8((n[channel] * 0.5 + 0.5) * 255) }
} }
try write(pixels, name: "hamster-fur-normal")
print("Baked 11 original coat maps and one shared fur normal map into \(destination.path)")
