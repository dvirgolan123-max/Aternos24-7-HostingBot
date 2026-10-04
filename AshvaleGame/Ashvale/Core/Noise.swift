//
//  Noise.swift
//  Ashvale
//
//  Gradient noise and fractal helpers used for terrain, vegetation placement
//  and procedural textures.
//

import Foundation

final class Noise2D {
    private var perm = [Int32](repeating: 0, count: 512)
    private static let gradients: [Vec2] = (0..<16).map { i -> Vec2 in
        let a = Float(i) / 16 * kTwoPi
        return Vec2(cosf(a), sinf(a))
    }

    init(seed: UInt64) {
        var rng = RNG(seed: seed)
        var p = [Int32](0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = rng.int(0, i)
            p.swapAt(i, j)
        }
        for i in 0..<512 { perm[i] = p[i & 255] }
    }

    @inline(__always) private func grad(_ ix: Int, _ iy: Int, _ fx: Float, _ fy: Float) -> Float {
        let h = Int(perm[Int(perm[ix & 255]) + (iy & 255)]) & 15
        let g = Noise2D.gradients[h]
        return g.x * fx + g.y * fy
    }

    /// Perlin-style gradient noise, roughly in [-1, 1].
    func noise(_ x: Float, _ y: Float) -> Float {
        let fx0 = floorf(x), fy0 = floorf(y)
        let ix = Int(fx0), iy = Int(fy0)
        let fx = x - fx0, fy = y - fy0
        let u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        let v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        let n00 = grad(ix, iy, fx, fy)
        let n10 = grad(ix + 1, iy, fx - 1, fy)
        let n01 = grad(ix, iy + 1, fx, fy - 1)
        let n11 = grad(ix + 1, iy + 1, fx - 1, fy - 1)
        let a = mixf(n00, n10, u)
        let b = mixf(n01, n11, u)
        return mixf(a, b, v) * 1.414
    }

    /// Tileable variant (period in lattice cells) for seamless textures.
    func tileNoise(_ x: Float, _ y: Float, period: Int) -> Float {
        let fx0 = floorf(x), fy0 = floorf(y)
        let ix = Int(fx0), iy = Int(fy0)
        let fx = x - fx0, fy = y - fy0
        let u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        let v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        let x0 = ((ix % period) + period) % period, x1 = (x0 + 1) % period
        let y0 = ((iy % period) + period) % period, y1 = (y0 + 1) % period
        let n00 = grad(x0, y0, fx, fy)
        let n10 = grad(x1, y0, fx - 1, fy)
        let n01 = grad(x0, y1, fx, fy - 1)
        let n11 = grad(x1, y1, fx - 1, fy - 1)
        return mixf(mixf(n00, n10, u), mixf(n01, n11, u), v) * 1.414
    }

    func fbm(_ x: Float, _ y: Float, octaves: Int, lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, freq: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += noise(x * freq, y * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }

    func tileFbm(_ x: Float, _ y: Float, period: Int, octaves: Int, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0
        var p = period, f: Float = 1
        for _ in 0..<octaves {
            sum += tileNoise(x * f, y * f, period: p) * amp
            norm += amp
            amp *= gain
            f *= 2
            p *= 2
        }
        return sum / norm
    }

    /// Ridged multifractal for rocky hills.
    func ridged(_ x: Float, _ y: Float, octaves: Int) -> Float {
        var sum: Float = 0, amp: Float = 0.5, freq: Float = 1
        for _ in 0..<octaves {
            let n = 1 - abs(noise(x * freq, y * freq))
            sum += n * n * amp
            amp *= 0.5
            freq *= 2
        }
        return sum
    }
}
