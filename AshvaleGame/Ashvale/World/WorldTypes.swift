//
//  WorldTypes.swift
//  Ashvale
//
//  Data types describing the generated world: named locations, roads,
//  placed buildings, props, vegetation and water.
//

import Foundation

enum AreaKind: Int, Codable {
    case wilderness, town, village, military, industrial, checkpoint, farm, forest
}

struct Location {
    var name: String
    var kind: AreaKind
    var center: Vec2
    var radius: Float
    /// Infected population budget when the player is nearby.
    var infectedBudget: Int
}

enum RoadKind: Int {
    case asphalt, dirt, townStreet
}

struct Road {
    var points: [Vec3]       // dense centerline samples (y = road surface height)
    var width: Float
    var kind: RoadKind
    var lengths: [Float] = [] // cumulative distance at each point
}

final class RoadNetwork {
    var roads: [Road] = []
    private var grid: [Int: [(Int, Int)]] = [:]
    private let cellSize: Float = 32

    @inline(__always) private func key(_ cx: Int, _ cz: Int) -> Int { (cz + 1000) * 4096 + (cx + 1000) }

    func add(_ road: Road) {
        var r = road
        var acc: Float = 0
        r.lengths = [0]
        for i in 1..<r.points.count {
            acc += vdistanceXZ(r.points[i], r.points[i - 1])
            r.lengths.append(acc)
        }
        roads.append(r)
    }

    func buildIndex() {
        grid.removeAll()
        for (ri, r) in roads.enumerated() {
            for si in 0..<(r.points.count - 1) {
                let a = r.points[si], b = r.points[si + 1]
                let pad = r.width * 0.5 + 12
                let x0 = Int(floorf((min(a.x, b.x) - pad) / cellSize)), x1 = Int(floorf((max(a.x, b.x) + pad) / cellSize))
                let z0 = Int(floorf((min(a.z, b.z) - pad) / cellSize)), z1 = Int(floorf((max(a.z, b.z) + pad) / cellSize))
                for cz in z0...z1 {
                    for cx in x0...x1 {
                        grid[key(cx, cz), default: []].append((ri, si))
                    }
                }
            }
        }
    }

    struct NearestResult {
        var distance: Float
        var road: Int
        var segment: Int
        var t: Float
        var height: Float
        var direction: Vec2
    }

    /// Nearest road centerline within the indexed padding (returns nil if none nearby).
    func nearest(_ x: Float, _ z: Float) -> NearestResult? {
        let cx = Int(floorf(x / cellSize)), cz = Int(floorf(z / cellSize))
        guard let list = grid[key(cx, cz)] else { return nil }
        var best: NearestResult?
        let p = Vec2(x, z)
        for (ri, si) in list {
            let r = roads[ri]
            let a = r.points[si], b = r.points[si + 1]
            let res = distancePointSegment2D(p, Vec2(a.x, a.z), Vec2(b.x, b.z))
            if best == nil || res.dist < best!.distance {
                let dir = vnormalize2(Vec2(b.x - a.x, b.z - a.z))
                best = NearestResult(distance: res.dist, road: ri, segment: si, t: res.t, height: mixf(a.y, b.y, res.t), direction: dir)
            }
        }
        return best
    }

    /// Distance to the edge of the nearest road (negative inside the road).
    func edgeDistance(_ x: Float, _ z: Float) -> Float {
        guard let n = nearest(x, z) else { return 1000 }
        return n.distance - roads[n.road].width * 0.5
    }

    func intersectsRect(center: Vec2, halfSize: Vec2, margin: Float) -> Bool {
        // Sample the rect perimeter and center.
        let pts: [Vec2] = [center, center + Vec2(halfSize.x, halfSize.y), center + Vec2(-halfSize.x, halfSize.y),
                           center + Vec2(halfSize.x, -halfSize.y), center + Vec2(-halfSize.x, -halfSize.y),
                           center + Vec2(halfSize.x, 0), center + Vec2(-halfSize.x, 0), center + Vec2(0, halfSize.y), center + Vec2(0, -halfSize.y)]
        for p in pts where edgeDistance(p.x, p.y) < margin { return true }
        // Also check road points inside the rect.
        for r in roads {
            for q in r.points where abs(q.x - center.x) < halfSize.x + r.width * 0.5 + margin && abs(q.z - center.y) < halfSize.y + r.width * 0.5 + margin {
                return true
            }
        }
        return false
    }
}

struct BuildingPlacement {
    var type: BuildingType
    var variant: Int
    var position: Vec3        // footprint center, y = ground floor level
    var rotation: Int         // multiples of 90 degrees
    var tint: Vec3
    var area: AreaKind
    var id: Int

    var transform: Mat4 { Mat4.translation(position) * Mat4.rotationY(Float(rotation) * kPi * 0.5) }

    var worldFootprint: (min: Vec2, max: Vec2) {
        let f = type.footprint
        let hw = (rotation % 2 == 0 ? f.x : f.y) * 0.5
        let hd = (rotation % 2 == 0 ? f.y : f.x) * 0.5
        return (Vec2(position.x - hw, position.z - hd), Vec2(position.x + hw, position.z + hd))
    }
}

enum TreeKind: Int, CaseIterable {
    case spruce = 0, pine, birch, oak, bush, deadTree
}

struct TreeInstance {
    var position: Vec3
    var yaw: Float
    var scale: Float
    var kind: TreeKind
    var tint: Vec3
}

struct WaterBody {
    var center: Vec2
    var radius: Float
    var level: Float
}

struct WaterSource {
    var position: Vec3
    var kind: Int   // 0 = lake shore, 1 = well, 2 = hand pump
    var safe: Bool
}

struct SpawnPoint {
    var position: Vec3
    var yaw: Float
}
