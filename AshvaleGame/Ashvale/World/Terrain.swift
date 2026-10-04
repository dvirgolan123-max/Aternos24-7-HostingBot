//
//  Terrain.swift
//  Ashvale
//
//  Heightfield terrain covering the whole map, with splat weights for texturing.
//

import Foundation

final class Terrain {
    static let worldSize: Float = 2048
    static let cellSize: Float = 2
    static let resolution: Int = 1025 // samples per side

    let res = Terrain.resolution
    let cell = Terrain.cellSize
    var heights: [Float]
    /// Packed splat weights: grass, dirt, rock, forest floor.
    var splat: [UInt32]
    /// Bit 0: plowed field.  Bit 1: town ground (gravel / pavement edges).
    var flags: [UInt8]
    /// Forest density 0...1 at each sample (used for vegetation and texturing).
    var forest: [Float]

    let noise: Noise2D
    let detailNoise: Noise2D

    init(seed: UInt64) {
        let n = Terrain.resolution * Terrain.resolution
        heights = [Float](repeating: 0, count: n)
        splat = [UInt32](repeating: 0, count: n)
        flags = [UInt8](repeating: 0, count: n)
        forest = [Float](repeating: 0, count: n)
        noise = Noise2D(seed: seed)
        detailNoise = Noise2D(seed: seed &+ 77)
    }

    @inline(__always) func index(_ ix: Int, _ iz: Int) -> Int { iz * res + ix }

    @inline(__always) func sample(_ ix: Int, _ iz: Int) -> Float {
        let x = ix < 0 ? 0 : (ix >= res ? res - 1 : ix)
        let z = iz < 0 ? 0 : (iz >= res ? res - 1 : iz)
        return heights[z * res + x]
    }

    /// Raw procedural height before any flattening.
    func rawHeight(_ x: Float, _ z: Float) -> Float {
        let s: Float = 1.0 / 700
        var h = noise.fbm(x * s, z * s, octaves: 4) * 38
        // Rolling hills and rocky ridges towards the map edges.
        let ridge = noise.ridged(x / 420 + 13.7, z / 420 - 4.1, octaves: 4)
        let cx = x / Terrain.worldSize - 0.5, cz = z / Terrain.worldSize - 0.5
        let edge = smoothstepf(0.28, 0.5, sqrtf(cx * cx + cz * cz))
        h += ridge * (18 + edge * 55)
        h += noise.fbm(x / 130 + 31, z / 130 + 17, octaves: 3) * 5.5
        h += detailNoise.fbm(x / 28, z / 28, octaves: 2) * 0.7
        return h + 40
    }

    /// Height at world position using the same triangulation as the rendered mesh.
    func height(_ x: Float, _ z: Float) -> Float {
        let fx = clampf(x / cell, 0, Float(res - 1) - 0.001)
        let fz = clampf(z / cell, 0, Float(res - 1) - 0.001)
        let ix = Int(fx), iz = Int(fz)
        let tx = fx - Float(ix), tz = fz - Float(iz)
        let h00 = heights[iz * res + ix]
        let h10 = heights[iz * res + ix + 1]
        let h01 = heights[(iz + 1) * res + ix]
        let h11 = heights[(iz + 1) * res + ix + 1]
        // Quads are split along the (0,0)-(1,1) diagonal.
        if tx >= tz {
            return h00 + (h10 - h00) * tx + (h11 - h10) * tz
        } else {
            return h00 + (h11 - h01) * tx + (h01 - h00) * tz
        }
    }

    func normal(_ x: Float, _ z: Float) -> Vec3 {
        let e: Float = 1.0
        let hl = height(x - e, z), hr = height(x + e, z)
        let hd = height(x, z - e), hu = height(x, z + e)
        return vnormalize(Vec3(hl - hr, 2 * e, hd - hu))
    }

    func sampleNormal(_ ix: Int, _ iz: Int) -> Vec3 {
        let hl = sample(ix - 1, iz), hr = sample(ix + 1, iz)
        let hd = sample(ix, iz - 1), hu = sample(ix, iz + 1)
        return vnormalize(Vec3(hl - hr, 2 * cell, hd - hu))
    }

    func forestDensity(_ x: Float, _ z: Float) -> Float {
        let ix = Int(clampf(x / cell + 0.5, 0, Float(res - 1)))
        let iz = Int(clampf(z / cell + 0.5, 0, Float(res - 1)))
        return forest[iz * res + ix]
    }

    func isField(_ x: Float, _ z: Float) -> Bool {
        let ix = Int(clampf(x / cell + 0.5, 0, Float(res - 1)))
        let iz = Int(clampf(z / cell + 0.5, 0, Float(res - 1)))
        return flags[iz * res + ix] & 1 != 0
    }

    /// Raymarches the heightfield. Returns hit distance.
    func raycast(origin: Vec3, direction: Vec3, maxDist: Float) -> Float? {
        var t: Float = 0
        let step: Float = 1.0
        var prevT: Float = 0
        var prevAbove = origin.y - height(origin.x, origin.z)
        if prevAbove < 0 { return 0 }
        while t < maxDist {
            t = Swift.min(t + step, maxDist)
            let p = origin + direction * t
            let above = p.y - height(p.x, p.z)
            if above <= 0 {
                // Bisection refine.
                var lo = prevT, hi = t
                for _ in 0..<8 {
                    let mid = (lo + hi) * 0.5
                    let q = origin + direction * mid
                    if q.y - height(q.x, q.z) > 0 { lo = mid } else { hi = mid }
                }
                return hi
            }
            prevT = t
            prevAbove = above
            if t >= maxDist { break }
        }
        _ = prevAbove
        return nil
    }

    // MARK: Generation helpers

    func generateBase() {
        for iz in 0..<res {
            for ix in 0..<res {
                heights[iz * res + ix] = rawHeight(Float(ix) * cell, Float(iz) * cell)
            }
        }
    }

    /// Blends heights towards `target` inside a rectangle (with smooth falloff margin).
    func flattenRect(center c: Vec2, halfSize hs: Vec2, target: Float, margin: Float) {
        let minX = Int(max(0, (c.x - hs.x - margin) / cell)), maxX = Int(min(Float(res - 1), (c.x + hs.x + margin) / cell + 1))
        let minZ = Int(max(0, (c.y - hs.y - margin) / cell)), maxZ = Int(min(Float(res - 1), (c.y + hs.y + margin) / cell + 1))
        if minX > maxX || minZ > maxZ { return }
        for iz in minZ...maxZ {
            for ix in minX...maxX {
                let x = Float(ix) * cell, z = Float(iz) * cell
                let dx = max(0, abs(x - c.x) - hs.x), dz = max(0, abs(z - c.y) - hs.y)
                let d = sqrtf(dx * dx + dz * dz)
                let w = 1 - smoothstepf(0, margin, d)
                if w <= 0 { continue }
                let i = iz * res + ix
                heights[i] = mixf(heights[i], target, w)
            }
        }
    }

    func flattenCircle(center c: Vec2, radius: Float, target: Float, margin: Float, strength: Float = 1) {
        let r = radius + margin
        let minX = Int(max(0, (c.x - r) / cell)), maxX = Int(min(Float(res - 1), (c.x + r) / cell + 1))
        let minZ = Int(max(0, (c.y - r) / cell)), maxZ = Int(min(Float(res - 1), (c.y + r) / cell + 1))
        if minX > maxX || minZ > maxZ { return }
        for iz in minZ...maxZ {
            for ix in minX...maxX {
                let x = Float(ix) * cell, z = Float(iz) * cell
                let d = sqrtf((x - c.x) * (x - c.x) + (z - c.y) * (z - c.y))
                let w = (1 - smoothstepf(radius, r, d)) * strength
                if w <= 0 { continue }
                let i = iz * res + ix
                heights[i] = mixf(heights[i], target, w)
            }
        }
    }

    /// Carves a lake basin: depth below water level with sloped banks.
    func carveLake(center c: Vec2, radius: Float, waterLevel: Float, depth: Float) {
        let r = radius * 1.8
        let minX = Int(max(0, (c.x - r) / cell)), maxX = Int(min(Float(res - 1), (c.x + r) / cell + 1))
        let minZ = Int(max(0, (c.y - r) / cell)), maxZ = Int(min(Float(res - 1), (c.y + r) / cell + 1))
        for iz in minZ...maxZ {
            for ix in minX...maxX {
                let x = Float(ix) * cell, z = Float(iz) * cell
                // Irregular shoreline.
                let ang = atan2f(z - c.y, x - c.x)
                let wobble = 1 + noise.noise(cosf(ang) * 2 + 5, sinf(ang) * 2 + 9) * 0.22
                let d = sqrtf((x - c.x) * (x - c.x) + (z - c.y) * (z - c.y)) / (radius * wobble)
                let i = iz * res + ix
                if d < 1 {
                    let bed = waterLevel - depth * (1 - d * d) - 0.3
                    heights[i] = min(heights[i], mixf(bed, waterLevel - 0.3, smoothstepf(0.6, 1, d)))
                } else if d < 1.8 {
                    let bank = waterLevel - 0.3 + (d - 1) * 4
                    let w = 1 - smoothstepf(1, 1.8, d)
                    heights[i] = mixf(heights[i], min(heights[i], bank) * 0.5 + bank * 0.5, w)
                }
            }
        }
    }

    // MARK: Splat

    func computeSplat(roadDistance: (Float, Float) -> Float, townMask: (Float, Float) -> Float) {
        for iz in 0..<res {
            for ix in 0..<res {
                let i = iz * res + ix
                let x = Float(ix) * cell, z = Float(iz) * cell
                let n = sampleNormal(ix, iz)
                let slope = 1 - n.y
                var grass: Float = 1, dirt: Float = 0, rock: Float = 0
                var forestFloor = forest[i]
                // Patchy dirt / dry grass.
                let patch = detailNoise.fbm(x / 18, z / 18, octaves: 3)
                dirt += saturatef(patch * 1.4 - 0.25) * 0.8
                // Steep slopes become rock.
                rock = smoothstepf(0.18, 0.38, slope)
                // Road shoulders.
                let rd = roadDistance(x, z)
                dirt += (1 - smoothstepf(0, 3.5, rd)) * 1.2
                // Town ground: worn dirt/gravel.
                let tm = townMask(x, z)
                dirt += tm * 0.55
                forestFloor *= (1 - tm)
                if flags[i] & 1 != 0 { dirt += 2.5; grass *= 0.15 }
                grass *= (1 - rock)
                dirt *= (1 - rock)
                forestFloor *= (1 - rock) * 1.3
                let total = max(grass + dirt + rock + forestFloor, 0.0001)
                let w0 = UInt8(clampf(grass / total, 0, 1) * 255)
                let w1 = UInt8(clampf(dirt / total, 0, 1) * 255)
                let w2 = UInt8(clampf(rock / total, 0, 1) * 255)
                let w3 = UInt8(clampf(forestFloor / total, 0, 1) * 255)
                splat[i] = packRGBA(w0, w1, w2, w3)
            }
        }
    }
}
