//
//  Navigation.swift
//  Ashvale
//
//  Ground-level navigation grid (1 m cells, built lazily per chunk) and A*
//  pathfinding. Closed doors block paths dynamically.
//

import Foundation

final class NavGrid {
    let world: World
    private var chunks: [Int: [UInt8]] = [:]          // 0 = walkable, 1 = blocked
    private var doorCells: [Int: [Int: [Int]]] = [:]  // chunk -> cell -> door indices
    private let cellsPerChunk = 64
    private var buildQueue: [Int] = []

    init(world: World) {
        self.world = world
    }

    @inline(__always) private func chunkKey(_ cx: Int, _ cz: Int) -> Int { cz * World.chunksPerSide + cx }

    private func buildChunk(_ cx: Int, _ cz: Int) {
        let key = chunkKey(cx, cz)
        var cells = [UInt8](repeating: 0, count: cellsPerChunk * cellsPerChunk)
        var doors: [Int: [Int]] = [:]
        let ox = Float(cx) * World.chunkSize, oz = Float(cz) * World.chunkSize
        for j in 0..<cellsPerChunk {
            for i in 0..<cellsPerChunk {
                let x = ox + Float(i) + 0.5, z = oz + Float(j) + 0.5
                let th = world.terrain.height(x, z)
                let g = world.groundHeight(at: Vec3(x, th + 0.6, z), radius: 0.2, stepHeight: 0.0).height
                var blocked = false
                let q = AABB(min: Vec3(x - 0.35, g + 0.45, z - 0.35), max: Vec3(x + 0.35, g + 1.6, z + 0.35))
                world.collision.forEach(in: q) { _, c in
                    if c.door >= 0 {
                        doors[j * cellsPerChunk + i, default: []].append(Int(c.door))
                    } else if c.flags.contains(.solid) {
                        blocked = true
                    }
                }
                // Steep terrain is not walkable.
                if !blocked {
                    let n = world.terrain.normal(x, z)
                    if n.y < 0.72 && g - th < 0.1 { blocked = true }
                }
                if world.isInWater(Vec3(x, g + 0.1, z)) > 1.0 { blocked = true }
                cells[j * cellsPerChunk + i] = blocked ? 1 : 0
            }
        }
        chunks[key] = cells
        doorCells[key] = doors
    }

    /// Ensures nav data exists for chunks around a point (spread over frames by callers).
    func prepare(around p: Vec3, radius: Int = 1) {
        let cx0 = Int(p.x / World.chunkSize), cz0 = Int(p.z / World.chunkSize)
        for dz in -radius...radius {
            for dx in -radius...radius {
                let cx = cx0 + dx, cz = cz0 + dz
                if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                if chunks[chunkKey(cx, cz)] == nil { buildChunk(cx, cz) }
            }
        }
    }

    func isWalkable(_ gx: Int, _ gz: Int) -> Bool {
        let n = Int(World.size)
        if gx < 0 || gz < 0 || gx >= n || gz >= n { return false }
        let cx = gx / cellsPerChunk, cz = gz / cellsPerChunk
        let key = chunkKey(cx, cz)
        if chunks[key] == nil { buildChunk(cx, cz) }
        let li = (gz % cellsPerChunk) * cellsPerChunk + (gx % cellsPerChunk)
        if chunks[key]![li] != 0 { return false }
        if let ds = doorCells[key]?[li] {
            for d in ds where !world.doors[d].isOpen && abs(world.doors[d].angle) < 0.8 { return false }
        }
        return true
    }

    private struct MinHeap {
        private var f: [Float] = []
        private var idx: [Int] = []
        var isEmpty: Bool { f.isEmpty }

        mutating func push(_ key: Float, _ value: Int) {
            f.append(key)
            idx.append(value)
            var c = f.count - 1
            while c > 0 {
                let p = (c - 1) / 2
                if f[p] <= f[c] { break }
                f.swapAt(p, c)
                idx.swapAt(p, c)
                c = p
            }
        }

        mutating func pop() -> (f: Float, idx: Int) {
            let top = (f[0], idx[0])
            let lastF = f.removeLast(), lastI = idx.removeLast()
            if !f.isEmpty {
                f[0] = lastF
                idx[0] = lastI
                var p = 0
                let n = f.count
                while true {
                    let l = 2 * p + 1, r = l + 1
                    var m = p
                    if l < n && f[l] < f[m] { m = l }
                    if r < n && f[r] < f[m] { m = r }
                    if m == p { break }
                    f.swapAt(p, m)
                    idx.swapAt(p, m)
                    p = m
                }
            }
            return top
        }
    }

    /// A* from a to b on ground level. Returns world-space waypoints (without the start).
    func findPath(from a: Vec3, to b: Vec3, maxNodes: Int = 5000) -> [Vec3]? {
        let sx = Int(a.x), sz = Int(a.z)
        var tx = Int(b.x), tz = Int(b.z)
        if !isWalkable(tx, tz) {
            // Use the nearest walkable cell around the target.
            var found = false
            outer: for r in 1...3 {
                for dz in -r...r {
                    for dx in -r...r where isWalkable(tx + dx, tz + dz) {
                        tx += dx
                        tz += dz
                        found = true
                        break outer
                    }
                }
            }
            if !found { return nil }
        }
        if sx == tx && sz == tz { return [b] }
        // Local window.
        let minX = min(sx, tx) - 24, minZ = min(sz, tz) - 24
        let maxX = max(sx, tx) + 24, maxZ = max(sz, tz) + 24
        let w = maxX - minX + 1, h = maxZ - minZ + 1
        if w * h > 160 * 160 { return nil }
        var g = [Float](repeating: .greatestFiniteMagnitude, count: w * h)
        var parent = [Int32](repeating: -1, count: w * h)
        var closed = [Bool](repeating: false, count: w * h)
        var open = MinHeap()
        func li(_ x: Int, _ z: Int) -> Int { (z - minZ) * w + (x - minX) }
        func heuristic(_ x: Int, _ z: Int) -> Float {
            let dx = Float(abs(x - tx)), dz = Float(abs(z - tz))
            return max(dx, dz) + 0.414 * min(dx, dz)
        }
        let start = li(sx, sz)
        g[start] = 0
        open.push(heuristic(sx, sz), start)
        var expanded = 0
        var goal = -1
        let dirs: [(Int, Int, Float)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
        while !open.isEmpty && expanded < maxNodes {
            let cur = open.pop()
            if closed[cur.idx] { continue }
            closed[cur.idx] = true
            expanded += 1
            let cx = cur.idx % w + minX, cz = cur.idx / w + minZ
            if cx == tx && cz == tz { goal = cur.idx; break }
            for (dx, dz, cost) in dirs {
                let nx = cx + dx, nz = cz + dz
                if nx < minX || nz < minZ || nx > maxX || nz > maxZ { continue }
                let ni = li(nx, nz)
                if closed[ni] || !isWalkable(nx, nz) { continue }
                if dx != 0 && dz != 0 && (!isWalkable(cx + dx, cz) || !isWalkable(cx, cz + dz)) { continue }
                let ng = g[cur.idx] + cost
                if ng < g[ni] {
                    g[ni] = ng
                    parent[ni] = Int32(cur.idx)
                    open.push(ng + heuristic(nx, nz), ni)
                }
            }
        }
        guard goal >= 0 else { return nil }
        var cells: [Int] = []
        var c = goal
        while c != start && c >= 0 {
            cells.append(c)
            c = Int(parent[c])
        }
        cells.reverse()
        // Convert and simplify (keep every 3rd point plus corners).
        var pts: [Vec3] = []
        for (k, ci) in cells.enumerated() {
            let x = Float(ci % w + minX) + 0.5, z = Float(ci / w + minZ) + 0.5
            if k % 2 == 0 || k == cells.count - 1 {
                pts.append(Vec3(x, 0, z))
            }
        }
        if let last = pts.last, vdistanceXZ(last, b) < 1.5 { pts[pts.count - 1] = Vec3(b.x, 0, b.z) }
        return pts
    }
}

extension Array {
    mutating func swapRemoveAt(_ i: Int) -> Element {
        let e = self[i]
        self[i] = self[count - 1]
        removeLast()
        return e
    }
}
