//
//  Vegetation.swift
//  Ashvale
//
//  Tree and bush meshes (two levels of detail). Foliage vertices are flagged
//  for wind sway and per-instance tinting in the shader.
//

import Foundation

enum VertexFlag {
    static let tintable: UInt8 = 1
    static let fieldRows: UInt8 = 2
    static let emissive: UInt8 = 4
    static let foliage: UInt8 = 8
    static let glossy: UInt8 = 16
    static let skin: UInt8 = 32
}

enum TreeFactory {

    /// Returns (lod0, lod1) meshes for a tree kind. Unit scale; instances scale uniformly.
    static func make(_ kind: TreeKind) -> (MeshBuilder, MeshBuilder) {
        let hi = MeshBuilder(), lo = MeshBuilder()
        var rng = RNG(seed: stableHash("tree-\(kind.rawValue)"))
        switch kind {
        case .spruce:
            trunk(hi, height: 11, r0: 0.28, r1: 0.06, color: Vec3(0.45, 0.36, 0.3), seg: 7)
            trunk(lo, height: 3, r0: 0.28, r1: 0.2, color: Vec3(0.45, 0.36, 0.3), seg: 5)
            let tiers = 7
            for i in 0..<tiers {
                let t = Float(i) / Float(tiers - 1)
                let y = 1.8 + t * 8.2
                let r = mixf(2.6, 0.6, t) * rng.range(0.9, 1.1)
                let h = mixf(2.8, 1.8, t)
                foliageCone(hi, center: Vec3(rng.range(-0.1, 0.1), y, rng.range(-0.1, 0.1)), radius: r, height: h,
                            color: Vec3(0.16, 0.27, 0.15) * rng.range(0.85, 1.1), seg: 9, droop: 0.35)
            }
            foliageCone(lo, center: Vec3(0, 1.8, 0), radius: 2.7, height: 10, color: Vec3(0.15, 0.25, 0.14), seg: 6, droop: 0)
        case .pine:
            trunk(hi, height: 14, r0: 0.3, r1: 0.1, color: Vec3(0.55, 0.38, 0.28), seg: 7)
            trunk(lo, height: 10, r0: 0.3, r1: 0.12, color: Vec3(0.55, 0.38, 0.28), seg: 5)
            for _ in 0..<5 {
                let c = Vec3(rng.range(-1.3, 1.3), rng.range(10.5, 13.5), rng.range(-1.3, 1.3))
                blob(hi, center: c, radii: Vec3(rng.range(1.6, 2.2), rng.range(0.9, 1.3), rng.range(1.6, 2.2)),
                     color: Vec3(0.2, 0.3, 0.16) * rng.range(0.9, 1.1), seed: rng.next(), rings: 5, seg: 8)
            }
            blob(lo, center: Vec3(0, 12, 0), radii: Vec3(2.6, 1.8, 2.6), color: Vec3(0.2, 0.3, 0.16), seed: 3, rings: 4, seg: 6)
        case .birch:
            trunk(hi, height: 9, r0: 0.16, r1: 0.05, color: Vec3(0.88, 0.86, 0.82), seg: 6, mat: .bark)
            trunk(lo, height: 6, r0: 0.16, r1: 0.08, color: Vec3(0.88, 0.86, 0.82), seg: 4, mat: .bark)
            for _ in 0..<6 {
                let c = Vec3(rng.range(-1.2, 1.2), rng.range(5.0, 9.0), rng.range(-1.2, 1.2))
                blob(hi, center: c, radii: Vec3(rng.range(1.0, 1.6), rng.range(1.0, 1.6), rng.range(1.0, 1.6)),
                     color: Vec3(0.38, 0.5, 0.22) * rng.range(0.9, 1.1), seed: rng.next(), rings: 5, seg: 8)
            }
            blob(lo, center: Vec3(0, 7, 0), radii: Vec3(2.0, 2.6, 2.0), color: Vec3(0.36, 0.48, 0.22), seed: 4, rings: 4, seg: 6)
        case .oak:
            trunk(hi, height: 5.5, r0: 0.45, r1: 0.25, color: Vec3(0.4, 0.33, 0.27), seg: 8)
            trunk(lo, height: 5.5, r0: 0.45, r1: 0.3, color: Vec3(0.4, 0.33, 0.27), seg: 5)
            // Branches.
            for i in 0..<4 {
                let a = Float(i) / 4 * kTwoPi + rng.range(-0.3, 0.3)
                let tip = Vec3(cosf(a) * 2.4, 7.2, sinf(a) * 2.4)
                hi.material = .bark
                hi.color = Vec3(0.4, 0.33, 0.27)
                hi.flags = 0
                hi.addCapsule(from: Vec3(0, 4.8, 0), to: tip, radiusA: 0.2, radiusB: 0.09, segments: 6, rings: 1)
            }
            for _ in 0..<7 {
                let c = Vec3(rng.range(-2.4, 2.4), rng.range(6.5, 9.5), rng.range(-2.4, 2.4))
                blob(hi, center: c, radii: Vec3(rng.range(1.8, 2.5), rng.range(1.4, 2.0), rng.range(1.8, 2.5)),
                     color: Vec3(0.24, 0.36, 0.16) * rng.range(0.85, 1.1), seed: rng.next(), rings: 5, seg: 9)
            }
            blob(lo, center: Vec3(0, 8, 0), radii: Vec3(3.6, 2.8, 3.6), color: Vec3(0.24, 0.36, 0.16), seed: 5, rings: 4, seg: 7)
        case .bush:
            for _ in 0..<4 {
                let c = Vec3(rng.range(-0.6, 0.6), rng.range(0.5, 0.9), rng.range(-0.6, 0.6))
                blob(hi, center: c, radii: Vec3(rng.range(0.7, 1.0), rng.range(0.55, 0.8), rng.range(0.7, 1.0)),
                     color: Vec3(0.25, 0.36, 0.16) * rng.range(0.85, 1.1), seed: rng.next(), rings: 4, seg: 7)
            }
            blob(lo, center: Vec3(0, 0.7, 0), radii: Vec3(1.3, 0.9, 1.3), color: Vec3(0.25, 0.36, 0.16), seed: 6, rings: 3, seg: 6)
        case .deadTree:
            trunk(hi, height: 8, r0: 0.3, r1: 0.06, color: Vec3(0.35, 0.32, 0.3), seg: 6)
            trunk(lo, height: 8, r0: 0.3, r1: 0.08, color: Vec3(0.35, 0.32, 0.3), seg: 4)
            for i in 0..<6 {
                let a = Float(i) * 1.9
                let y = 3.0 + Float(i) * 0.8
                let tip = Vec3(cosf(a) * (2.2 - Float(i) * 0.25), y + 1.4, sinf(a) * (2.2 - Float(i) * 0.25))
                hi.material = .bark
                hi.color = Vec3(0.35, 0.32, 0.3)
                hi.flags = 0
                hi.addCapsule(from: Vec3(0, y, 0), to: tip, radiusA: 0.09, radiusB: 0.03, segments: 5, rings: 1)
            }
        }
        return (hi, lo)
    }

    static func trunk(_ m: MeshBuilder, height: Float, r0: Float, r1: Float, color: Vec3, seg: Int, mat: Mat = .bark) {
        m.material = mat
        m.color = color
        m.flags = 0
        m.skyVisibility = 0.9
        m.uvScale = 1
        m.addCylinder(center: Vec3(0, -0.4, 0), radiusBottom: r0, radiusTop: r1, height: height + 0.4, segments: seg, capTop: false, capBottom: false)
    }

    static func foliageCone(_ m: MeshBuilder, center: Vec3, radius: Float, height: Float, color: Vec3, seg: Int, droop: Float) {
        m.material = .foliage
        m.color = color
        m.flags = VertexFlag.foliage | VertexFlag.tintable
        m.skyVisibility = 0.85
        m.uvScale = 0.8
        // Cone with a drooping skirt: outer ring lower than the attachment.
        let base = UInt32(m.vertices.count)
        let tip = m.addVertex(center + Vec3(0, height, 0), Vec3(0, 1, 0), Vec2(0.5, 0))
        for i in 0...seg {
            let a = Float(i) / Float(seg) * kTwoPi
            let jitter = 1 + 0.12 * sinf(a * 3 + center.y)
            let p = center + Vec3(cosf(a) * radius * jitter, -droop, sinf(a) * radius * jitter)
            let n = vnormalize(Vec3(cosf(a) * height, radius * 0.9, sinf(a) * height))
            m.addVertex(p, n, Vec2(Float(i) / Float(seg) * 3, 1.5))
        }
        for i in 0..<seg {
            m.addTriangle(tip, base + 2 + UInt32(i), base + 1 + UInt32(i))
        }
        // Underside.
        m.skyVisibility = 0.4
        let under = m.addVertex(center + Vec3(0, 0.25, 0), Vec3(0, -1, 0), Vec2(0.5, 0.5))
        let ringStart = UInt32(m.vertices.count)
        for i in 0...seg {
            let a = Float(i) / Float(seg) * kTwoPi
            let jitter = 1 + 0.12 * sinf(a * 3 + center.y)
            m.addVertex(center + Vec3(cosf(a) * radius * jitter, -droop, sinf(a) * radius * jitter), Vec3(0, -1, 0), Vec2(Float(i) / Float(seg) * 3, 1))
        }
        for i in 0..<seg {
            m.addTriangle(under, ringStart + UInt32(i), ringStart + UInt32(i) + 1)
        }
        m.flags = 0
    }

    static func blob(_ m: MeshBuilder, center: Vec3, radii: Vec3, color: Vec3, seed: UInt64, rings: Int, seg: Int) {
        m.material = .foliage
        m.color = color
        m.flags = VertexFlag.foliage | VertexFlag.tintable
        m.skyVisibility = 0.85
        m.uvScale = 0.7
        m.addEllipsoid(center: center, radii: radii, rings: rings, segments: seg, jitter: 0.35, seed: UInt32(truncatingIfNeeded: seed))
        m.flags = 0
    }

    /// Trunk collider half-size at unit scale.
    static func trunkRadius(_ kind: TreeKind) -> Float {
        switch kind {
        case .spruce: return 0.28
        case .pine: return 0.3
        case .birch: return 0.17
        case .oak: return 0.45
        case .bush: return 0
        case .deadTree: return 0.3
        }
    }
}
