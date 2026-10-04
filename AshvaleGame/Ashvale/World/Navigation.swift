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
    /// One byte per 1 m cell over the whole map: 0 walkable, 1 blocked, 2 walkable unless a closed door is there.
    private var cells: [UInt8]
    private var built: [Bool]
    private var doorCells: [Int: [Int]] = [:]      // global cell -> door indices
    private let cellsPerChunk = 64
    private let side: Int
    // Incremental (budgeted) chunk building.
    private var pendingChunk = -1
    private var pendingRow = 0
    private(set) var builtChunks = 0
    /// Path searches allowed per frame across all agents (reset by `beginFrame`).
    private(set) var searchesLeft = 3

    init(world: World) {
        self.world = world
        side = Int(World.size)
        cells = [UInt8](repeating: 0, count: side * side)
        built = [Bool](repeating: false, count: World.chunksPerSide * World.chunksPerSide)
    }

    @inline(__always) private func chunkKey(_ cx: Int, _ cz: Int) -> Int { cz * World.chunksPerSide + cx }

    func beginFrame() { searchesLeft = 3 }

    private var passageCacheKey = -1
    private var passageCache: [NavPassage] = []

    /// Door and doorway passages touching a chunk (cached for the chunk being built).
    private func passages(_ cx: Int, _ cz: Int) -> [NavPassage] {
        let key = chunkKey(cx, cz)
        if key == passageCacheKey { return passageCache }
        let x0 = Float(cx) * World.chunkSize - 2, z0 = Float(cz) * World.chunkSize - 2
        let x1 = x0 + World.chunkSize + 4, z1 = z0 + World.chunkSize + 4
        passageCache = world.passages.filter { $0.center.x >= x0 && $0.center.x <= x1 && $0.center.z >= z0 && $0.center.z <= z1 }
        passageCacheKey = key
        return passageCache
    }

    /// Classifies one row of cells of a chunk.
    private func buildRow(_ cx: Int, _ cz: Int, row j: Int) {
        let ox = Float(cx) * World.chunkSize, oz = Float(cz) * World.chunkSize
        let gz = cz * cellsPerChunk + j
        let ps = passages(cx, cz)
        for i in 0..<cellsPerChunk {
            let gx = cx * cellsPerChunk + i
            let x = ox + Float(i) + 0.5, z = oz + Float(j) + 0.5
            let th = world.terrain.height(x, z)
            let g = world.groundHeight(at: Vec3(x, th + 0.6, z), radius: 0.2, stepHeight: 0.0).height
            var blocked = false
            var doors: [Int] = []
            let q = AABB(min: Vec3(x - 0.25, g + 0.45, z - 0.25), max: Vec3(x + 0.25, g + 1.6, z + 0.25))
            world.collision.forEach(in: q) { _, c in
                if c.door >= 0 {
                    doors.append(Int(c.door))
                } else if c.flags.contains(.solid) {
                    blocked = true
                }
            }
            // Steep terrain is not walkable.
            if !blocked {
                let n = world.terrain.normal(x, z)
                if n.y < 0.72 && g - th < 0.1 { blocked = true }
            }
            if !blocked && world.isInWater(Vec3(x, g + 0.1, z)) > 1.0 { blocked = true }
            // Doorways are narrower than a cell's clearance test at some grid alignments: carve a
            // strip through every floor-level opening so rooms stay connected.
            for p in ps where abs(p.center.y - g) < 1.2 {
                let dx = x - p.center.x, dz = z - p.center.z
                let along = dx * p.across.x + dz * p.across.z
                let lateral = dz * p.across.x - dx * p.across.z
                if abs(along) <= 0.9 && abs(lateral) <= max(0.5, p.width * 0.5) + 0.25 {
                    blocked = false
                    if p.door >= 0 && !doors.contains(p.door) { doors.append(p.door) }
                }
            }
            let ci = gz * side + gx
            if blocked {
                cells[ci] = 1
            } else if !doors.isEmpty {
                cells[ci] = 2
                doorCells[ci] = doors
            } else {
                cells[ci] = 0
            }
        }
    }

    /// Finishes building a chunk synchronously (used when a search reaches an unbuilt chunk).
    private func buildChunk(_ cx: Int, _ cz: Int) {
        let key = chunkKey(cx, cz)
        if built[key] { return }
        let first = pendingChunk == key ? pendingRow : 0
        for j in first..<cellsPerChunk { buildRow(cx, cz, row: j) }
        if pendingChunk == key { pendingChunk = -1 }
        built[key] = true
        builtChunks += 1
    }

    /// Ensures nav data exists for chunks around a point right now (loading screens, spawning).
    func prepare(around p: Vec3, radius: Int = 1) {
        let cx0 = Int(p.x / World.chunkSize), cz0 = Int(p.z / World.chunkSize)
        for dz in -radius...radius {
            for dx in -radius...radius {
                let cx = cx0 + dx, cz = cz0 + dz
                if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                buildChunk(cx, cz)
            }
        }
    }

    /// Builds missing chunks near the player a few rows per frame so searches never stall a frame.
    func warm(around p: Vec3, radius: Int = 2, rowBudget: Int = 6) {
        var rows = rowBudget
        while rows > 0 {
            if pendingChunk < 0 {
                // Pick the nearest unbuilt chunk in range.
                let cx0 = Int(p.x / World.chunkSize), cz0 = Int(p.z / World.chunkSize)
                var best = -1
                var bestD = Int.max
                for dz in -radius...radius {
                    for dx in -radius...radius {
                        let cx = cx0 + dx, cz = cz0 + dz
                        if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                        let k = chunkKey(cx, cz)
                        if built[k] { continue }
                        let d = dx * dx + dz * dz
                        if d < bestD { bestD = d; best = k }
                    }
                }
                if best < 0 { return }
                pendingChunk = best
                pendingRow = 0
            }
            let cx = pendingChunk % World.chunksPerSide, cz = pendingChunk / World.chunksPerSide
            buildRow(cx, cz, row: pendingRow)
            pendingRow += 1
            rows -= 1
            if pendingRow >= cellsPerChunk {
                built[pendingChunk] = true
                builtChunks += 1
                pendingChunk = -1
            }
        }
    }

    @inline(__always) func isWalkable(_ gx: Int, _ gz: Int) -> Bool {
        if gx < 0 || gz < 0 || gx >= side || gz >= side { return false }
        let key = chunkKey(gx / cellsPerChunk, gz / cellsPerChunk)
        if !built[key] { buildChunk(gx / cellsPerChunk, gz / cellsPerChunk) }
        let ci = gz * side + gx
        let v = cells[ci]
        if v == 0 { return true }
        if v == 1 { return false }
        if let ds = doorCells[ci] {
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
    func findPath(from a: Vec3, to b: Vec3, maxNodes: Int = 2500) -> [Vec3]? {
        searchesLeft -= 1
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
