//
//  ChunkMesher.swift
//  Ashvale
//
//  Builds terrain chunk meshes (with road surfaces, sidewalks and lane
//  markings) at two levels of detail. Runs on background threads; reads only
//  immutable world data.
//

import Foundation

enum ChunkMesher {

    static func build(world: World, cx: Int, cz: Int, lod: Int) -> MeshBuilder {
        let m = MeshBuilder()
        let t = world.terrain
        let step = lod == 0 ? 1 : 4
        let samplesPerChunk = Int(World.chunkSize / t.cell)
        let ix0 = cx * samplesPerChunk, iz0 = cz * samplesPerChunk
        let n = samplesPerChunk / step
        m.reserve(vertices: (n + 1) * (n + 1) + 400, indices: n * n * 6 + 800)
        let tintNoise = t.detailNoise

        // Terrain grid.
        let base = UInt32(m.vertices.count)
        for j in 0...n {
            for i in 0...n {
                let ix = min(t.res - 1, ix0 + i * step), iz = min(t.res - 1, iz0 + j * step)
                let idx = iz * t.res + ix
                let x = Float(ix) * t.cell, z = Float(iz) * t.cell
                let p = Vec3(x, t.heights[idx], z)
                let nrm = t.sampleNormal(ix, iz)
                let fieldFlag = t.flags[idx] & 1 != 0
                m.flags = fieldFlag ? VertexFlag.fieldRows : 0
                // Grass hue variation and darker forest floor.
                let v = tintNoise.noise(x / 45, z / 45) * 0.5 + 0.5
                let dry = tintNoise.noise(x / 160 + 7, z / 160 - 3) * 0.5 + 0.5
                let tint = Vec3(mixf(0.92, 1.12, dry), mixf(1.0, 0.92, dry), mixf(0.95, 0.8, dry)) * mixf(0.9, 1.05, v)
                let sky = 1 - t.forest[idx] * 0.3
                m.addVertex(p, nrm, Vec2(x, z) * 0.25, weights: t.splat[idx], materialOverride: Mat.terrain, colorOverride: packColor(tint, sky))
            }
        }
        let stride = UInt32(n + 1)
        for j in 0..<n {
            for i in 0..<n {
                let a = base + UInt32(j) * stride + UInt32(i)
                let b = a + 1
                let c = a + stride + 1
                let d = a + stride
                // Split along a-c to match Terrain.height().
                m.addTriangle(a, c, b)
                m.addTriangle(a, d, c)
            }
        }
        m.flags = 0

        // Skirts for distant chunks hide cracks between LODs.
        if lod > 0 {
            addSkirts(m, world: world, ix0: ix0, iz0: iz0, n: n, step: step)
        }

        let minX = Float(cx) * World.chunkSize, minZ = Float(cz) * World.chunkSize
        let maxX = minX + World.chunkSize, maxZ = minZ + World.chunkSize
        addRoads(m, world: world, minX: minX, minZ: minZ, maxX: maxX, maxZ: maxZ, lod: lod)
        if lod == 0 {
            addSidewalks(m, world: world, minX: minX, minZ: minZ, maxX: maxX, maxZ: maxZ)
        }
        return m
    }

    private static func addSkirts(_ m: MeshBuilder, world: World, ix0: Int, iz0: Int, n: Int, step: Int) {
        let t = world.terrain
        func vtx(_ i: Int, _ j: Int, drop: Float) -> UInt32 {
            let ix = min(t.res - 1, ix0 + i * step), iz = min(t.res - 1, iz0 + j * step)
            let idx = iz * t.res + ix
            let p = Vec3(Float(ix) * t.cell, t.heights[idx] - drop, Float(iz) * t.cell)
            return m.addVertex(p, t.sampleNormal(ix, iz), Vec2(p.x, p.z) * 0.25, weights: t.splat[idx], materialOverride: Mat.terrain, colorOverride: packColor(Vec3(0.95, 0.95, 0.9), 1))
        }
        let edges: [[(Int, Int)]] = [
            (0...n).map { ($0, 0) }, (0...n).map { ($0, n) }, (0...n).map { (0, $0) }, (0...n).map { (n, $0) },
        ]
        for e in edges {
            for k in 0..<(e.count - 1) {
                let a = vtx(e[k].0, e[k].1, drop: 0), b = vtx(e[k + 1].0, e[k + 1].1, drop: 0)
                let c = vtx(e[k + 1].0, e[k + 1].1, drop: 4), d = vtx(e[k].0, e[k].1, drop: 4)
                // Double-sided so orientation does not matter.
                m.addTriangle(a, b, c); m.addTriangle(a, c, d)
                m.addTriangle(a, c, b); m.addTriangle(a, d, c)
            }
        }
    }

    private static func addRoads(_ m: MeshBuilder, world: World, minX: Float, minZ: Float, maxX: Float, maxZ: Float, lod: Int) {
        let stepPts = lod == 0 ? 1 : 3
        for (ri, r) in world.roads.roads.enumerated() {
            let pts = r.points
            if pts.count < 2 { continue }
            let hw = r.width * 0.5
            let lift: Float = 0.05 + Float(ri % 4) * 0.004
            // Quick reject.
            var i = 0
            while i < pts.count - 1 {
                let j = min(pts.count - 1, i + stepPts)
                let a = pts[i], b = pts[j]
                let mid = (a + b) * 0.5
                if mid.x >= minX && mid.x < maxX && mid.z >= minZ && mid.z < maxZ {
                    let na = perpendicular(pts, i), nb = perpendicular(pts, j)
                    let la = Vec3(a.x + na.x * hw, a.y + lift, a.z + na.y * hw)
                    let ra = Vec3(a.x - na.x * hw, a.y + lift, a.z - na.y * hw)
                    let lb = Vec3(b.x + nb.x * hw, b.y + lift, b.z + nb.y * hw)
                    let rb = Vec3(b.x - nb.x * hw, b.y + lift, b.z - nb.y * hw)
                    let va = r.lengths[i] / r.width, vb = r.lengths[j] / r.width
                    let mat: Mat = r.kind == .dirt ? .gravel : .asphalt
                    m.material = mat
                    m.flags = 0
                    m.skyVisibility = 1
                    m.color = r.kind == .dirt ? Vec3(0.78, 0.7, 0.58) : Vec3(0.95, 0.95, 0.95)
                    let up = Vec3(0, 1, 0)
                    let i0 = m.addVertex(la, up, Vec2(0, va)), i1 = m.addVertex(ra, up, Vec2(1, va))
                    let i2 = m.addVertex(rb, up, Vec2(1, vb)), i3 = m.addVertex(lb, up, Vec2(0, vb))
                    // Orient upward.
                    let cr = vcross(ra - la, rb - la)
                    if cr.y >= 0 { m.addTriangle(i0, i1, i2); m.addTriangle(i0, i2, i3) } else { m.addTriangle(i0, i2, i1); m.addTriangle(i0, i3, i2) }
                    // Dashed center line on asphalt roads.
                    if lod == 0 && r.kind != .dirt {
                        let dashPhase = fmodf(r.lengths[i], 9)
                        if dashPhase < 4.5 {
                            let w: Float = 0.07
                            let cl0 = Vec3(a.x + na.x * w, a.y + lift + 0.006, a.z + na.y * w)
                            let cr0 = Vec3(a.x - na.x * w, a.y + lift + 0.006, a.z - na.y * w)
                            let cl1 = Vec3(b.x + nb.x * w, b.y + lift + 0.006, b.z + nb.y * w)
                            let cr1 = Vec3(b.x - nb.x * w, b.y + lift + 0.006, b.z - nb.y * w)
                            m.material = .plastic
                            m.color = r.kind == .townStreet ? Vec3(0.9, 0.9, 0.85) : Vec3(0.9, 0.8, 0.3)
                            let j0 = m.addVertex(cl0, up, Vec2(0, 0)), j1 = m.addVertex(cr0, up, Vec2(1, 0))
                            let j2 = m.addVertex(cr1, up, Vec2(1, 1)), j3 = m.addVertex(cl1, up, Vec2(0, 1))
                            if cr.y >= 0 { m.addTriangle(j0, j1, j2); m.addTriangle(j0, j2, j3) } else { m.addTriangle(j0, j2, j1); m.addTriangle(j0, j3, j2) }
                        }
                    }
                }
                i = j
            }
        }
    }

    private static func perpendicular(_ pts: [Vec3], _ i: Int) -> Vec2 {
        let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
        let d = vnormalize2(Vec2(b.x - a.x, b.z - a.z))
        return Vec2(-d.y, d.x)
    }

    private static func addSidewalks(_ m: MeshBuilder, world: World, minX: Float, minZ: Float, maxX: Float, maxZ: Float) {
        m.material = .concrete
        m.color = Vec3(0.72, 0.71, 0.68)
        m.skyVisibility = 1
        m.flags = 0
        m.uvScale = 0.5
        for s in world.sidewalks {
            let c = s.center
            if c.x >= minX && c.x < maxX && c.z >= minZ && c.z < maxZ {
                m.addBox(min: s.min, max: s.max, faces: [.posY, .posX, .negX, .posZ, .negZ])
                // Curb stone.
                m.color = Vec3(0.6, 0.6, 0.58)
                m.color = Vec3(0.72, 0.71, 0.68)
            }
        }
    }

    /// Water surface mesh for a lake.
    static func lakeMesh(_ lake: WaterBody) -> MeshBuilder {
        let m = MeshBuilder()
        m.material = .glass
        m.color = Vec3(0.2, 0.3, 0.32)
        m.flags = VertexFlag.glossy
        let seg = 48
        let r = lake.radius * 1.4
        let center = m.addVertex(Vec3(lake.center.x, lake.level, lake.center.y), Vec3(0, 1, 0), Vec2(0, 0))
        var ring: [UInt32] = []
        for i in 0...seg {
            let a = Float(i) / Float(seg) * kTwoPi
            let p = Vec3(lake.center.x + cosf(a) * r, lake.level, lake.center.y + sinf(a) * r)
            ring.append(m.addVertex(p, Vec3(0, 1, 0), Vec2(cosf(a), sinf(a))))
        }
        for i in 0..<seg { m.addTriangle(center, ring[i + 1], ring[i]) }
        return m
    }
}
