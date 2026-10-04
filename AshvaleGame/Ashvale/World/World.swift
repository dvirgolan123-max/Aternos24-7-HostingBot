//
//  World.swift
//  Ashvale
//
//  The generated world and its runtime state (doors). Provides spatial
//  queries used by gameplay systems.
//

import Foundation

struct DoorState {
    var hinge: Vec3
    var baseYaw: Float
    var width: Float
    var height: Float
    var openSign: Float
    var angle: Float = 0          // current opening angle (0 = closed, +-pi/2 = open)
    var isOpen: Bool = false      // target state
    var style: DoorStyle
    var collider: Int = -1
    var building: Int

    var transform: Mat4 { Mat4.translation(hinge) * Mat4.rotationY(baseYaw + angle) }

    func leafBox(angle a: Float) -> AABB {
        let m = Mat4.translation(hinge) * Mat4.rotationY(baseYaw + a)
        return AABB(min: Vec3(0, 0, -0.035), max: Vec3(width, height, 0.035)).transformed(m)
    }

    /// Center of the doorway (for interaction).
    var center: Vec3 {
        let m = Mat4.translation(hinge) * Mat4.rotationY(baseYaw)
        return m.transformPoint(Vec3(width * 0.5, 1.0, 0))
    }
}

struct NavPassage {
    var center: Vec3
    var across: Vec3
    var width: Float
    /// World door index, or -1 for an open doorway.
    var door: Int
}

struct WorldLootSpot {
    var position: Vec3
    var category: LootCategory
    var yaw: Float
    var large: Bool
    var area: AreaKind
}

final class World {
    static let size: Float = 2048
    static let chunkSize: Float = 64
    static let chunksPerSide = 32

    let seed: UInt64
    let terrain: Terrain
    let roads = RoadNetwork()
    let collision: CollisionWorld

    var locations: [Location] = []
    var buildings: [BuildingPlacement] = []
    var buildingModels: [Int: BuildingModel] = [:]
    var props: [PropInstance] = []
    var propModels: [Int: PropModel] = [:]
    var trees: [TreeInstance] = []
    var water: [WaterBody] = []
    var waterSources: [WaterSource] = []
    var spawnPoints: [SpawnPoint] = []
    var lootSpots: [WorldLootSpot] = []
    var doors: [DoorState] = []
    var sidewalks: [AABB] = []
    /// World-space stair waypoint chains per building index.
    var buildingStairs: [Int: [[Vec3]]] = [:]
    /// World-space walkable openings (doors and doorways) used to keep the nav grid connected.
    var passages: [NavPassage] = []
    var fields: [(min: Vec2, max: Vec2)] = []

    // Per-chunk instance lists for culling.
    var buildingsByChunk: [[Int]] = Array(repeating: [], count: World.chunksPerSide * World.chunksPerSide)
    var propsByChunk: [[Int]] = Array(repeating: [], count: World.chunksPerSide * World.chunksPerSide)
    var treesByChunk: [[Int]] = Array(repeating: [], count: World.chunksPerSide * World.chunksPerSide)
    var doorsByChunk: [[Int]] = Array(repeating: [], count: World.chunksPerSide * World.chunksPerSide)

    // Mesh ids (filled by registerMeshes).
    var buildingMeshIDs: [Int: (shell: MeshID, interior: MeshID, plugs: MeshID)] = [:]
    var propMeshIDs: [Int: MeshID] = [:]
    var treeMeshIDs: [Int: (hi: MeshID, lo: MeshID)] = [:]
    var doorMeshIDs: [Int: MeshID] = [:]

    init(seed: UInt64) {
        self.seed = seed
        terrain = Terrain(seed: seed)
        collision = CollisionWorld(worldSize: World.size)
    }

    static func modelKey(_ type: BuildingType, _ variant: Int) -> Int { type.rawValue * 16 + variant }

    @inline(__always) static func chunkIndex(_ x: Float, _ z: Float) -> Int {
        let cx = max(0, min(chunksPerSide - 1, Int(x / chunkSize)))
        let cz = max(0, min(chunksPerSide - 1, Int(z / chunkSize)))
        return cz * chunksPerSide + cx
    }

    // MARK: Queries

    /// Ground height under a footprint: max(terrain, walkable collider tops) not above `maxY`.
    func groundHeight(at p: Vec3, radius: Float = 0.2, stepHeight: Float = 0.45) -> (height: Float, surface: SurfaceKind, onCollider: Bool) {
        var h = terrain.height(p.x, p.z)
        var surface: SurfaceKind = terrain.forestDensity(p.x, p.z) > 0.4 ? .dirt : .grass
        if roads.edgeDistance(p.x, p.z) < 0 { surface = .concrete }
        var onCollider = false
        if let g = collision.groundHeight(x: p.x, z: p.z, radius: radius, maxY: p.y + stepHeight, minY: h - 0.5), g.height > h {
            h = g.height
            surface = collision.colliders[g.collider].surface
            onCollider = true
        }
        return (h, surface, onCollider)
    }

    /// Returns true if the point is inside a building interior volume.
    func isIndoors(_ p: Vec3) -> Bool {
        return buildingAt(p) != nil
    }

    func buildingAt(_ p: Vec3) -> Int? {
        let ci = World.chunkIndex(p.x, p.z)
        let cx = ci % World.chunksPerSide, cz = ci / World.chunksPerSide
        for dz in -1...1 {
            for dx in -1...1 {
                let x = cx + dx, z = cz + dz
                if x < 0 || z < 0 || x >= World.chunksPerSide || z >= World.chunksPerSide { continue }
                for bi in buildingsByChunk[z * World.chunksPerSide + x] {
                    let b = buildings[bi]
                    let fp = b.worldFootprint
                    if p.x < fp.min.x || p.x > fp.max.x || p.z < fp.min.y || p.z > fp.max.y { continue }
                    guard let model = buildingModels[World.modelKey(b.type, b.variant)] else { continue }
                    let local = b.transform.inverse.transformPoint(p)
                    for v in model.indoorVolumes where v.expanded(by: 0.05).contains(local) {
                        return bi
                    }
                }
            }
        }
        return nil
    }

    func location(at p: Vec3) -> Location? {
        var best: Location?
        var bestD = Float.greatestFiniteMagnitude
        for l in locations {
            let d = vlength2(Vec2(p.x, p.z) - l.center)
            if d < l.radius && d < bestD && l.kind != .forest {
                best = l
                bestD = d
            }
        }
        return best
    }

    func areaKind(at p: Vec3) -> AreaKind {
        if let l = location(at: p) { return l.kind }
        return terrain.forestDensity(p.x, p.z) > 0.45 ? .forest : .wilderness
    }

    func nearestWaterSource(to p: Vec3, maxDistance: Float) -> WaterSource? {
        var best: WaterSource?
        var bestD = maxDistance
        for w in waterSources {
            let d = vdistance(w.position, p)
            if d < bestD { bestD = d; best = w }
        }
        // Lake shores: any point at the water edge.
        for lake in water {
            let d = vlength2(Vec2(p.x, p.z) - lake.center)
            if d < lake.radius * 1.2 && abs(p.y - lake.level) < 2.5 && terrain.height(p.x, p.z) < lake.level + 0.6 {
                return WaterSource(position: Vec3(p.x, lake.level, p.z), kind: 0, safe: false)
            }
        }
        return best
    }

    func isInWater(_ p: Vec3) -> Float {
        for lake in water {
            let d = vlength2(Vec2(p.x, p.z) - lake.center)
            if d < lake.radius * 1.4 {
                let depth = lake.level - p.y
                if depth > 0 && terrain.height(p.x, p.z) < lake.level { return depth }
            }
        }
        return 0
    }

    // MARK: Doors

    func doorsNear(_ p: Vec3, radius: Float) -> [Int] {
        var out: [Int] = []
        let ci = World.chunkIndex(p.x, p.z)
        let cx = ci % World.chunksPerSide, cz = ci / World.chunksPerSide
        for dz in -1...1 {
            for dx in -1...1 {
                let x = cx + dx, z = cz + dz
                if x < 0 || z < 0 || x >= World.chunksPerSide || z >= World.chunksPerSide { continue }
                for di in doorsByChunk[z * World.chunksPerSide + x] where vdistance(doors[di].center, p) < radius {
                    out.append(di)
                }
            }
        }
        return out
    }

    func toggleDoor(_ i: Int) {
        doors[i].isOpen.toggle()
    }

    func setDoor(_ i: Int, open: Bool, immediate: Bool = false) {
        doors[i].isOpen = open
        if immediate {
            doors[i].angle = open ? doors[i].openSign * kPi * 0.5 : 0
            syncDoorCollider(i)
        }
    }

    /// Animates doors; only doors near the focus point are updated for efficiency.
    func updateDoors(dt: Float, focus: Vec3) {
        for di in doorsNear(focus, radius: 120) {
            let target: Float = doors[di].isOpen ? doors[di].openSign * kPi * 0.5 : 0
            if doors[di].angle != target {
                let before = abs(doors[di].angle) > kPi * 0.25
                doors[di].angle = moveTowards(doors[di].angle, target, dt * 3.2)
                let after = abs(doors[di].angle) > kPi * 0.25
                if before != after || doors[di].angle == target { syncDoorCollider(di) }
            }
        }
    }

    func syncDoorCollider(_ i: Int) {
        let d = doors[i]
        guard d.collider >= 0 else { return }
        let openish = abs(d.angle) > kPi * 0.25
        let box = d.leafBox(angle: openish ? d.openSign * kPi * 0.5 : 0)
        collision.updateDoorBox(d.collider, box: box, solid: true)
    }

    // MARK: Spawn

    func randomSpawn(_ rng: inout RNG) -> SpawnPoint {
        guard !spawnPoints.isEmpty else { return SpawnPoint(position: Vec3(1024, terrain.height(1024, 1024) + 1, 1024), yaw: 0) }
        return rng.pick(spawnPoints)
    }
}
