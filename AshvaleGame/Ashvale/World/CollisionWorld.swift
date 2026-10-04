//
//  CollisionWorld.swift
//  Ashvale
//
//  Static + door colliders in a uniform XZ grid (CSR layout) with box queries,
//  raycasts and ground height queries.
//

import Foundation

struct Collider {
    var box: AABB
    var flags: ColliderFlags
    var surface: SurfaceKind
    /// Index into World.doors for door leaves, -1 otherwise.
    var door: Int32
}

struct RayHit {
    var distance: Float
    var point: Vec3
    var normal: Vec3
    var collider: Int32   // -1 = terrain
    var surface: SurfaceKind
}

final class CollisionWorld {
    let cellSize: Float = 4
    let cellsPerSide: Int
    var colliders: [Collider] = []
    private var cellStart: [Int32] = []
    private var cellItems: [Int32] = []
    private var stamps: [UInt32] = []
    private var stamp: UInt32 = 0
    private let lock = NSLock()
    /// Extra coverage boxes (e.g. union of door open/closed states) used for grid insertion.
    private var insertionBoxes: [Int: AABB] = [:]

    init(worldSize: Float) {
        cellsPerSide = Int(worldSize / cellSize)
    }

    @discardableResult
    func add(_ box: AABB, _ flags: ColliderFlags, _ surface: SurfaceKind, door: Int32 = -1, coverage: AABB? = nil) -> Int {
        colliders.append(Collider(box: box, flags: flags, surface: surface, door: door))
        if let c = coverage { insertionBoxes[colliders.count - 1] = c }
        return colliders.count - 1
    }

    @inline(__always) private func cellRange(_ b: AABB) -> (Int, Int, Int, Int) {
        let maxC = cellsPerSide - 1
        let x0 = max(0, min(maxC, Int(floorf(b.min.x / cellSize))))
        let x1 = max(0, min(maxC, Int(floorf(b.max.x / cellSize))))
        let z0 = max(0, min(maxC, Int(floorf(b.min.z / cellSize))))
        let z1 = max(0, min(maxC, Int(floorf(b.max.z / cellSize))))
        return (x0, x1, z0, z1)
    }

    /// Builds the CSR grid. Call after all colliders are added.
    func finalize() {
        let n = cellsPerSide * cellsPerSide
        var counts = [Int32](repeating: 0, count: n + 1)
        for (i, c) in colliders.enumerated() {
            let b = insertionBoxes[i] ?? c.box
            let (x0, x1, z0, z1) = cellRange(b)
            for z in z0...z1 { for x in x0...x1 { counts[z * cellsPerSide + x] += 1 } }
        }
        cellStart = [Int32](repeating: 0, count: n + 1)
        var acc: Int32 = 0
        for i in 0..<n {
            cellStart[i] = acc
            acc += counts[i]
        }
        cellStart[n] = acc
        cellItems = [Int32](repeating: 0, count: Int(acc))
        var fill = [Int32](repeating: 0, count: n)
        for (i, c) in colliders.enumerated() {
            let b = insertionBoxes[i] ?? c.box
            let (x0, x1, z0, z1) = cellRange(b)
            for z in z0...z1 {
                for x in x0...x1 {
                    let cell = z * cellsPerSide + x
                    cellItems[Int(cellStart[cell] + fill[cell])] = Int32(i)
                    fill[cell] += 1
                }
            }
        }
        stamps = [UInt32](repeating: 0, count: colliders.count)
        insertionBoxes.removeAll()
    }

    @inline(__always) private func nextStamp() -> UInt32 {
        stamp &+= 1
        if stamp == 0 {
            for i in 0..<stamps.count { stamps[i] = 0 }
            stamp = 1
        }
        return stamp
    }

    /// Calls `body` for every collider whose box intersects `box` (deduplicated).
    func forEach(in box: AABB, _ body: (Int, Collider) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !cellStart.isEmpty else { return }
        let s = nextStamp()
        let (x0, x1, z0, z1) = cellRange(box)
        for z in z0...z1 {
            for x in x0...x1 {
                let cell = z * cellsPerSide + x
                let a = Int(cellStart[cell]), b = Int(cellStart[cell + 1])
                if a == b { continue }
                for k in a..<b {
                    let idx = Int(cellItems[k])
                    if stamps[idx] == s { continue }
                    stamps[idx] = s
                    let c = colliders[idx]
                    if c.box.intersects(box) { body(idx, c) }
                }
            }
        }
    }

    /// Raycast against colliders matching `mask` (any flag in common). DDA over grid cells.
    func raycast(origin: Vec3, direction d: Vec3, maxDistance: Float, mask: ColliderFlags, ignoreDoors: Bool = false) -> RayHit? {
        lock.lock()
        defer { lock.unlock() }
        guard !cellStart.isEmpty else { return nil }
        let ray = Ray(origin: origin, direction: d)
        let s = nextStamp()
        var best: Float = maxDistance
        var bestIdx: Int = -1

        // Grid traversal in XZ.
        var cx = Int(floorf(origin.x / cellSize)), cz = Int(floorf(origin.z / cellSize))
        let stepX = d.x >= 0 ? 1 : -1, stepZ = d.z >= 0 ? 1 : -1
        let nextBoundX = Float(cx + (stepX > 0 ? 1 : 0)) * cellSize
        let nextBoundZ = Float(cz + (stepZ > 0 ? 1 : 0)) * cellSize
        var tMaxX = abs(d.x) > 1e-9 ? (nextBoundX - origin.x) / d.x : Float.greatestFiniteMagnitude
        var tMaxZ = abs(d.z) > 1e-9 ? (nextBoundZ - origin.z) / d.z : Float.greatestFiniteMagnitude
        let tDeltaX = abs(d.x) > 1e-9 ? cellSize / abs(d.x) : Float.greatestFiniteMagnitude
        let tDeltaZ = abs(d.z) > 1e-9 ? cellSize / abs(d.z) : Float.greatestFiniteMagnitude
        var tCell: Float = 0
        var iterations = 0
        while tCell <= best && iterations < 4096 {
            iterations += 1
            let inside = cx >= 0 && cz >= 0 && cx < cellsPerSide && cz < cellsPerSide
            if inside {
                let cell = cz * cellsPerSide + cx
                let a = Int(cellStart[cell]), b = Int(cellStart[cell + 1])
                if a < b {
                    for k in a..<b {
                        let idx = Int(cellItems[k])
                        if stamps[idx] == s { continue }
                        stamps[idx] = s
                        let c = colliders[idx]
                        if c.flags.isDisjoint(with: mask) { continue }
                        if ignoreDoors && c.door >= 0 { continue }
                        if let t = c.box.rayIntersect(origin: ray.origin, invDir: ray.invDir, maxDist: best), t < best {
                            best = t
                            bestIdx = idx
                        }
                    }
                }
            } else if (cx < 0 && stepX < 0) || (cx >= cellsPerSide && stepX > 0) || (cz < 0 && stepZ < 0) || (cz >= cellsPerSide && stepZ > 0) {
                break
            }
            if tMaxX < tMaxZ {
                tCell = tMaxX
                tMaxX += tDeltaX
                cx += stepX
            } else {
                tCell = tMaxZ
                tMaxZ += tDeltaZ
                cz += stepZ
            }
        }
        if bestIdx < 0 { return nil }
        let c = colliders[bestIdx]
        let p = origin + d * best
        return RayHit(distance: best, point: p, normal: c.box.faceNormal(at: p), collider: Int32(bestIdx), surface: c.surface)
    }

    /// Highest walkable top surface under a circle footprint, not higher than `maxY`.
    func groundHeight(x: Float, z: Float, radius: Float, maxY: Float, minY: Float) -> (height: Float, collider: Int)? {
        var best: Float = -Float.greatestFiniteMagnitude
        var bestIdx = -1
        let q = AABB(min: Vec3(x - radius, minY, z - radius), max: Vec3(x + radius, maxY, z + radius))
        forEach(in: q) { idx, c in
            guard c.flags.contains(.solid) else { return }
            let top = c.box.max.y
            if top <= maxY && top > best { best = top; bestIdx = idx }
        }
        return bestIdx >= 0 ? (best, bestIdx) : nil
    }

    /// Updates a door collider box (grid membership was registered for the full swept coverage).
    func updateDoorBox(_ index: Int, box: AABB, solid: Bool) {
        lock.lock()
        colliders[index].box = box
        var f = colliders[index].flags
        if solid { f.insert(.solid) } else { f.remove(.solid) }
        colliders[index].flags = f
        lock.unlock()
    }
}
