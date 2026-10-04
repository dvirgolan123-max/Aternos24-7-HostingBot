//
//  TextureFactory.swift
//  Ashvale
//
//  Procedural, tileable material textures (sRGB RGBA8). One layer per `Mat`.
//  Generated on the CPU at load time and uploaded as a texture array.
//

import Foundation

enum TextureFactory {
    static let size = 256

    /// Generates all layers. Uses `concurrentPerform` when available.
    static func generateAll() -> [[UInt8]] {
        let count = Mat.allCases.count
        var layers = [[UInt8]](repeating: [], count: count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let data = generate(Mat.allCases[i])
            lock.lock()
            layers[i] = data
            lock.unlock()
        }
        return layers
    }

    static func generate(_ mat: Mat) -> [UInt8] {
        let n = size
        var px = [UInt8](repeating: 255, count: n * n * 4)
        let noise = Noise2D(seed: 1000 + UInt64(mat.rawValue) * 17)
        let noise2 = Noise2D(seed: 5000 + UInt64(mat.rawValue) * 31)
        let inv = 1 / Float(n)

        func put(_ x: Int, _ y: Int, _ c: Vec3) {
            let i = (y * n + x) * 4
            px[i] = UInt8(clampf(c.x, 0, 1) * 255)
            px[i + 1] = UInt8(clampf(c.y, 0, 1) * 255)
            px[i + 2] = UInt8(clampf(c.z, 0, 1) * 255)
            px[i + 3] = 255
        }
        func fbm(_ u: Float, _ v: Float, _ period: Int, _ oct: Int = 4, gain: Float = 0.5) -> Float {
            noise.tileFbm(u * Float(period), v * Float(period), period: period, octaves: oct, gain: gain)
        }
        func fbm2(_ u: Float, _ v: Float, _ period: Int, _ oct: Int = 4) -> Float {
            noise2.tileFbm(u * Float(period), v * Float(period), period: period, octaves: oct)
        }
        func cellHash(_ x: Int, _ y: Int, _ s: UInt32 = 0) -> Float { hashFloat(Int32(x), Int32(y), UInt32(mat.rawValue) &* 977 &+ s) }

        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) * inv, v = Float(y) * inv
                var c = Vec3(0.5, 0.5, 0.5)
                switch mat {
                case .grass:
                    let base = fbm(u, v, 4, 5) * 0.5 + 0.5
                    let blades = fbm2(u * 1.0, v * 1.0, 64, 2) * 0.5 + 0.5
                    let dry = smoothstepf(0.55, 0.8, fbm(u + 0.3, v + 0.7, 2, 3) * 0.5 + 0.5)
                    let green = Vec3(0.26, 0.38, 0.13), yellow = Vec3(0.45, 0.43, 0.2)
                    c = vlerp(green, yellow, dry * 0.7) * (0.7 + base * 0.35 + blades * 0.25)
                case .dirt:
                    let a = fbm(u, v, 4, 5) * 0.5 + 0.5
                    let pebble = smoothstepf(0.62, 0.7, fbm2(u, v, 32, 2) * 0.5 + 0.5)
                    c = vlerp(Vec3(0.36, 0.28, 0.2), Vec3(0.5, 0.42, 0.31), a) * (1 - pebble * 0.25) + Vec3(pebble * 0.08, pebble * 0.08, pebble * 0.07)
                case .rock:
                    let a = fbm(u, v, 4, 6, gain: 0.55) * 0.5 + 0.5
                    let crack = 1 - smoothstepf(0.0, 0.04, abs(fbm2(u, v, 8, 3)))
                    c = Vec3(0.48, 0.47, 0.45) * (0.65 + a * 0.6) * (1 - crack * 0.4)
                case .forestFloor:
                    let a = fbm(u, v, 4, 5) * 0.5 + 0.5
                    let needles = fbm2(u, v, 48, 2) * 0.5 + 0.5
                    let moss = smoothstepf(0.5, 0.7, fbm(u + 0.5, v, 2, 3) * 0.5 + 0.5)
                    c = vlerp(Vec3(0.3, 0.22, 0.14), Vec3(0.22, 0.3, 0.12), moss) * (0.65 + a * 0.4 + needles * 0.2)
                case .asphalt:
                    let grain = cellHash(x, y) * 0.5 + fbm(u, v, 32, 2) * 0.25
                    let patch = fbm2(u, v, 3, 3) * 0.5 + 0.5
                    let crack = 1 - smoothstepf(0.0, 0.025, abs(fbm(u + 0.2, v + 0.4, 6, 3)))
                    c = Vec3(0.2, 0.2, 0.21) * (0.8 + grain * 0.5) * (0.85 + patch * 0.25) * (1 - crack * 0.5)
                case .concrete:
                    let a = fbm(u, v, 4, 5) * 0.5 + 0.5
                    let stain = smoothstepf(0.55, 0.8, fbm2(u, v, 2, 4) * 0.5 + 0.5)
                    let grain = cellHash(x, y) * 0.08
                    c = Vec3(0.6, 0.6, 0.58) * (0.85 + a * 0.2 + grain) * (1 - stain * 0.25)
                case .brick:
                    let bw: Float = 0.125, bh: Float = 0.0625
                    let row = Int(v / bh)
                    let off: Float = row % 2 == 0 ? 0 : bw * 0.5
                    let bu = fmodf(u + off, bw) / bw, bv = fmodf(v, bh) / bh
                    let col = Int((u + off) / bw)
                    let mortar = bu < 0.06 || bv < 0.12
                    let tone = cellHash(col, row) * 0.25
                    let a = fbm(u, v, 16, 3) * 0.1
                    c = mortar ? Vec3(0.7, 0.68, 0.64) * (0.9 + a) : Vec3(0.6 + tone * 0.4, 0.3 + tone * 0.2, 0.22 + tone * 0.1) * (0.9 + a)
                case .plaster:
                    let a = fbm(u, v, 8, 4) * 0.5 + 0.5
                    let dirt = smoothstepf(0.6, 0.9, fbm2(u, v, 2, 4) * 0.5 + 0.5) * smoothstepf(0.4, 1.0, v)
                    c = Vec3(0.92, 0.91, 0.88) * (0.9 + a * 0.12) * (1 - dirt * 0.3)
                case .woodPlanks:
                    let plank = Int(u * 6)
                    let pu = fmodf(u * 6, 1)
                    let tone = cellHash(plank, 7) * 0.2
                    let grain = sinf((v * 40 + fbm(u, v, 4, 3) * 4 + Float(plank) * 1.7) * kPi) * 0.5 + 0.5
                    let gap = pu < 0.03 ? Float(0.55) : 1
                    c = Vec3(0.62 + tone, 0.46 + tone * 0.7, 0.3 + tone * 0.4) * (0.85 + grain * 0.15) * gap
                case .woodDark:
                    let grain = sinf((u * 30 + fbm(u, v, 4, 3) * 3) * kPi) * 0.5 + 0.5
                    c = Vec3(0.5, 0.36, 0.24) * (0.85 + grain * 0.18)
                case .roofTiles:
                    let rowH: Float = 1.0 / 12, colW: Float = 1.0 / 8
                    let row = Int(v / rowH)
                    let off: Float = row % 2 == 0 ? 0 : colW * 0.5
                    let tv = fmodf(v, rowH) / rowH
                    let tu = fmodf(u + off, colW) / colW
                    let shade = 0.65 + tv * 0.45
                    let edge = tu < 0.05 ? Float(0.7) : 1
                    let tone = cellHash(Int((u + off) / colW), row) * 0.15
                    c = Vec3(0.75 + tone, 0.75 + tone, 0.75 + tone) * shade * edge
                case .metalPainted:
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    let scratch = smoothstepf(0.92, 1.0, fbm2(u * 4, v, 16, 2) * 0.5 + 0.5)
                    let rust = smoothstepf(0.72, 0.9, fbm(u + 0.4, v + 0.1, 4, 4) * 0.5 + 0.5)
                    c = vlerp(Vec3(0.9, 0.9, 0.9) * (0.92 + a * 0.08), Vec3(0.5, 0.3, 0.18), rust * 0.7) + Vec3(scratch, scratch, scratch) * 0.1
                case .metalCorrugated:
                    let ridge = sinf(u * kTwoPi * 16) * 0.5 + 0.5
                    let rust = smoothstepf(0.65, 0.9, fbm(u, v, 4, 4) * 0.5 + 0.5) * smoothstepf(0.3, 1, v)
                    c = vlerp(Vec3(0.85, 0.86, 0.88) * (0.75 + ridge * 0.3), Vec3(0.45, 0.28, 0.16), rust * 0.6)
                case .fabric, .canvas:
                    let wx = sinf(u * kTwoPi * 64) * 0.5 + 0.5, wy = sinf(v * kTwoPi * 64) * 0.5 + 0.5
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    c = Vec3(0.85, 0.85, 0.85) * (0.8 + (wx * wy) * 0.15 + a * 0.1)
                    if mat == .canvas { c *= Vec3(0.95, 0.95, 0.85) }
                case .floorTiles:
                    let t = 8
                    let tu = fmodf(u * Float(t), 1), tv = fmodf(v * Float(t), 1)
                    let grout = tu < 0.04 || tv < 0.04
                    let tone = cellHash(Int(u * Float(t)), Int(v * Float(t))) * 0.06
                    c = grout ? Vec3(0.5, 0.5, 0.48) : Vec3(0.9 - tone, 0.9 - tone, 0.88 - tone) * (0.95 + fbm(u, v, 16, 2) * 0.05)
                case .linoleum:
                    let speck = cellHash(x / 2, y / 2) > 0.92 ? Float(0.85) : 1
                    let a = fbm(u, v, 4, 4) * 0.5 + 0.5
                    c = Vec3(0.85, 0.85, 0.82) * (0.92 + a * 0.08) * speck
                case .gravel:
                    let cell = 24
                    var minD: Float = 10
                    var tone: Float = 0
                    let gx = Int(u * Float(cell)), gy = Int(v * Float(cell))
                    for oy in -1...1 {
                        for ox in -1...1 {
                            let cx = (gx + ox + cell) % cell, cy = (gy + oy + cell) % cell
                            let px2 = (Float(gx + ox) + cellHash(cx, cy)) / Float(cell)
                            let py2 = (Float(gy + oy) + cellHash(cx, cy, 9)) / Float(cell)
                            let d = vlength2(Vec2(u - px2, v - py2)) * Float(cell)
                            if d < minD { minD = d; tone = cellHash(cx, cy, 3) }
                        }
                    }
                    let stone = 1 - smoothstepf(0.3, 0.55, minD)
                    c = vlerp(Vec3(0.35, 0.32, 0.28), Vec3(0.55 + tone * 0.2, 0.52 + tone * 0.2, 0.48 + tone * 0.2), stone)
                case .bark:
                    let streak = fbm(u * 8, v, 4, 4) * 0.5 + 0.5
                    let crack = smoothstepf(0.45, 0.5, abs(sinf(u * kTwoPi * 10 + fbm2(u, v, 4, 3) * 3)))
                    c = Vec3(0.9, 0.85, 0.8) * (0.55 + streak * 0.35) * (0.7 + crack * 0.3)
                case .foliage:
                    let leaves = fbm(u, v, 16, 3) * 0.5 + 0.5
                    let big = fbm2(u, v, 4, 3) * 0.5 + 0.5
                    let gap = smoothstepf(0.25, 0.4, leaves)
                    c = Vec3(0.75, 0.85, 0.65) * (0.45 + gap * 0.45 + big * 0.2)
                case .glass:
                    let a = fbm(u, v, 4, 2) * 0.5 + 0.5
                    c = Vec3(0.7, 0.75, 0.78) * (0.85 + a * 0.15)
                case .rust:
                    let a = fbm(u, v, 8, 5) * 0.5 + 0.5
                    c = vlerp(Vec3(0.35, 0.18, 0.1), Vec3(0.6, 0.35, 0.18), a)
                case .field:
                    let rows = sinf(v * kTwoPi * 24) * 0.5 + 0.5
                    let a = fbm(u, v, 8, 4) * 0.5 + 0.5
                    c = Vec3(0.42, 0.32, 0.22) * (0.7 + rows * 0.3) * (0.85 + a * 0.2)
                case .wallpaper:
                    let stripe = sinf(u * kTwoPi * 16) > 0.6 ? Float(0.93) : 1
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    let damp = smoothstepf(0.65, 0.95, fbm2(u, v, 2, 4) * 0.5 + 0.5)
                    c = Vec3(0.95, 0.95, 0.93) * stripe * (0.92 + a * 0.08) * (1 - damp * 0.25)
                case .burlap:
                    let wx = sinf(u * kTwoPi * 40) * 0.5 + 0.5, wy = sinf(v * kTwoPi * 40) * 0.5 + 0.5
                    c = Vec3(0.85, 0.8, 0.65) * (0.7 + max(wx, wy) * 0.3) * (0.9 + fbm(u, v, 8, 2) * 0.1)
                case .camo:
                    let a = fbm(u, v, 4, 4), b = fbm2(u, v, 4, 4)
                    if a > 0.15 { c = Vec3(0.3, 0.33, 0.22) } else if b > 0.1 { c = Vec3(0.45, 0.42, 0.3) } else if a < -0.25 { c = Vec3(0.18, 0.17, 0.13) } else { c = Vec3(0.38, 0.45, 0.28) }
                    c *= 1 / 0.45
                case .skin:
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    c = Vec3(0.95, 0.95, 0.95) * (0.94 + a * 0.06)
                case .denim:
                    let twill = sinf((u + v) * kTwoPi * 48) * 0.5 + 0.5
                    let fade = fbm(u, v, 4, 3) * 0.5 + 0.5
                    c = Vec3(0.25, 0.33, 0.52) * (0.8 + twill * 0.2) * (0.85 + fade * 0.3)
                case .leather:
                    let a = fbm(u, v, 16, 4) * 0.5 + 0.5
                    c = Vec3(0.75, 0.75, 0.75) * (0.8 + a * 0.25)
                case .plastic, .rubber:
                    let a = fbm(u, v, 8, 2) * 0.5 + 0.5
                    c = Vec3(0.9, 0.9, 0.9) * (0.94 + a * 0.06)
                case .gunMetal:
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    let wear = smoothstepf(0.8, 0.95, fbm2(u, v, 4, 3) * 0.5 + 0.5)
                    c = Vec3(0.9, 0.9, 0.92) * (0.9 + a * 0.1) + Vec3(wear, wear, wear) * 0.15
                case .paper:
                    let a = fbm(u, v, 8, 3) * 0.5 + 0.5
                    let corr = sinf(u * kTwoPi * 30) * 0.5 + 0.5
                    c = Vec3(0.92, 0.92, 0.92) * (0.88 + a * 0.08 + corr * 0.04)
                case .hair:
                    let strand = fbm(u * 6, v, 8, 3) * 0.5 + 0.5
                    c = Vec3(0.9, 0.9, 0.9) * (0.7 + strand * 0.3)
                case .sheetMetal:
                    let brush = fbm(u, v * 6, 8, 2) * 0.5 + 0.5
                    c = Vec3(0.92, 0.92, 0.93) * (0.88 + brush * 0.12)
                case .carpet:
                    let a = cellHash(x, y) * 0.15 + fbm(u, v, 16, 2) * 0.1
                    c = Vec3(0.9, 0.9, 0.9) * (0.85 + a)
                }
                put(x, y, c)
            }
        }
        return px
    }
}
