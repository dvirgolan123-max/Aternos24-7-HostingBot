//
//  WorldGenerator.swift
//  Ashvale
//
//  Builds the world of Ashvale: terrain, roads, the town of Halden, the
//  village of Brekka, Northmill industrial works, Camp Vigil military base,
//  the Route 9 checkpoint, Lake Silva, forests, fields, vehicles and props.
//

import Foundation

final class WorldGenerator {
    let world: World
    var rng: RNG
    let progress: (Float, String) -> Void

    init(seed: UInt64, progress: @escaping (Float, String) -> Void) {
        world = World(seed: seed)
        rng = RNG(seed: seed &* 31 &+ 7)
        self.progress = progress
    }

    static func generate(seed: UInt64, progress: @escaping (Float, String) -> Void = { _, _ in }) -> World {
        let g = WorldGenerator(seed: seed, progress: progress)
        g.run()
        return g.world
    }

    private var terrain: Terrain { world.terrain }

    func run() {
        progress(0.02, "Shaping terrain")
        terrain.generateBase()
        defineLocations()
        progress(0.15, "Flattening settlements")
        flattenAreas()
        progress(0.22, "Carving Lake Silva")
        carveLake()
        progress(0.28, "Laying roads")
        buildRoads()
        progress(0.38, "Raising buildings")
        placeTown()
        placeVillage()
        placeIndustrial()
        placeMilitary()
        placeCheckpoint()
        placeRoadside()
        resampleRoadHeights()
        progress(0.5, "Growing forests")
        computeFieldsAndForest()
        terrain.computeSplat(roadDistance: { [world] x, z in world.roads.edgeDistance(x, z) },
                             townMask: { [weak self] x, z in self?.settlementMask(x, z) ?? 0 })
        plantTrees()
        progress(0.62, "Constructing interiors")
        instantiateBuildings()
        instantiateProps()
        defineSpawns()
        progress(0.7, "Building collision")
        world.collision.finalize()
        progress(0.72, "World ready")
    }

    // MARK: Locations

    func defineLocations() {
        world.locations = [
            Location(name: "Halden", kind: .town, center: Vec2(1050, 1050), radius: 270, infectedBudget: 24),
            Location(name: "Brekka", kind: .village, center: Vec2(520, 722), radius: 170, infectedBudget: 9),
            Location(name: "Northmill Works", kind: .industrial, center: Vec2(1505, 630), radius: 150, infectedBudget: 10),
            Location(name: "Camp Vigil", kind: .military, center: Vec2(1560, 1560), radius: 130, infectedBudget: 12),
            Location(name: "Route 9 Checkpoint", kind: .checkpoint, center: Vec2(1350, 1330), radius: 60, infectedBudget: 5),
            Location(name: "Lake Silva", kind: .wilderness, center: Vec2(700, 1350), radius: 130, infectedBudget: 2),
            Location(name: "Greywood", kind: .forest, center: Vec2(300, 1150), radius: 360, infectedBudget: 3),
            Location(name: "Kettle Hills", kind: .forest, center: Vec2(900, 300), radius: 320, infectedBudget: 2),
        ]
    }

    func flattenAreas() {
        let town = Vec2(1050, 1050)
        terrain.flattenCircle(center: town, radius: 250, target: terrain.rawHeight(town.x, town.y), margin: 160, strength: 0.92)
        let village = Vec2(520, 722)
        terrain.flattenCircle(center: village, radius: 150, target: terrain.rawHeight(village.x, village.y), margin: 110, strength: 0.85)
        let ind = Vec2(1505, 630)
        terrain.flattenRect(center: ind, halfSize: Vec2(110, 150), target: terrain.rawHeight(ind.x, ind.y), margin: 90)
        let mil = Vec2(1560, 1560)
        terrain.flattenRect(center: mil, halfSize: Vec2(100, 85), target: terrain.rawHeight(mil.x, mil.y), margin: 90)
        let cp = Vec2(1350, 1330)
        terrain.flattenCircle(center: cp, radius: 45, target: terrain.rawHeight(cp.x, cp.y), margin: 60, strength: 0.8)
    }

    func carveLake() {
        let c = Vec2(700, 1350)
        // Water level sits below the lowest point of the surrounding shore so the basin holds it.
        var shoreMin = Float.greatestFiniteMagnitude
        for i in 0..<48 {
            let a = Float(i) / 48 * kTwoPi
            for rr in [Float(1.25), 1.5, 1.8] {
                let q = c + Vec2(cosf(a), sinf(a)) * 72 * rr
                shoreMin = min(shoreMin, terrain.height(q.x, q.y))
            }
        }
        let level = min(terrain.height(c.x, c.y) - 1.2, shoreMin - 0.6)
        terrain.carveLake(center: c, radius: 72, waterLevel: level, depth: 4.5)
        world.water.append(WaterBody(center: c, radius: 72, level: level))
        // Shore drinking spots.
        for i in 0..<12 {
            let a = Float(i) / 12 * kTwoPi
            let p = c + Vec2(cosf(a), sinf(a)) * 74
            world.waterSources.append(WaterSource(position: Vec3(p.x, level, p.y), kind: 0, safe: false))
        }
    }

    func settlementMask(_ x: Float, _ z: Float) -> Float {
        var m: Float = 0
        for l in world.locations where l.kind == .town || l.kind == .village || l.kind == .industrial || l.kind == .military || l.kind == .checkpoint {
            let d = vlength2(Vec2(x, z) - l.center)
            m = max(m, 1 - smoothstepf(l.radius * 0.6, l.radius * 1.05, d))
        }
        return m
    }

    // MARK: Roads

    func catmullRom(_ ctrl: [Vec2], spacing: Float) -> [Vec2] {
        if ctrl.count == 2 {
            let len = vlength2(ctrl[1] - ctrl[0])
            let n = max(1, Int(len / spacing))
            return (0...n).map { ctrl[0] + (ctrl[1] - ctrl[0]) * (Float($0) / Float(n)) }
        }
        var out: [Vec2] = []
        let pts = [ctrl[0]] + ctrl + [ctrl[ctrl.count - 1]]
        for i in 1..<(pts.count - 2) {
            let p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2]
            let len = vlength2(p2 - p1)
            let n = max(1, Int(len / spacing))
            for s in 0..<n {
                let t = Float(s) / Float(n)
                let t2 = t * t, t3 = t2 * t
                let a = p1 * 2
                let b = (p2 - p0) * t
                let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        out.append(ctrl[ctrl.count - 1])
        return out
    }

    func addRoad(_ ctrl: [Vec2], width: Float, kind: RoadKind) {
        let pts2 = catmullRom(ctrl, spacing: 2)
        // Height profile: smoothed terrain.
        var hs = pts2.map { terrain.height($0.x, $0.y) }
        let window = kind == .townStreet ? 6 : 12
        for _ in 0..<3 {
            var sm = hs
            for i in 0..<hs.count {
                let a = max(0, i - window), b = min(hs.count - 1, i + window)
                var s: Float = 0
                for j in a...b { s += hs[j] }
                sm[i] = s / Float(b - a + 1)
            }
            hs = sm
        }
        let pts = zip(pts2, hs).map { Vec3($0.0.x, $0.1, $0.0.y) }
        world.roads.add(Road(points: pts, width: width, kind: kind))
    }

    func buildRoads() {
        addRoad([Vec2(30, 780), Vec2(200, 745), Vec2(380, 722), Vec2(660, 722), Vec2(720, 760), Vec2(760, 860), Vec2(775, 980), Vec2(800, 1040), Vec2(835, 1050)], width: 7, kind: .asphalt)
        addRoad([Vec2(835, 1050), Vec2(1265, 1050)], width: 8, kind: .townStreet)
        addRoad([Vec2(1265, 1050), Vec2(1320, 1035), Vec2(1400, 960), Vec2(1460, 870), Vec2(1500, 800), Vec2(1560, 730), Vec2(1700, 660), Vec2(1850, 620), Vec2(2020, 600)], width: 7, kind: .asphalt)
        addRoad([Vec2(960, 880), Vec2(960, 1220)], width: 8, kind: .townStreet)
        addRoad([Vec2(1140, 870), Vec2(1140, 1230)], width: 8, kind: .townStreet)
        addRoad([Vec2(880, 950), Vec2(1220, 950)], width: 7, kind: .townStreet)
        addRoad([Vec2(880, 1150), Vec2(1220, 1150)], width: 7, kind: .townStreet)
        addRoad([Vec2(1140, 1230), Vec2(1150, 1290), Vec2(1200, 1325), Vec2(1250, 1330), Vec2(1450, 1330), Vec2(1500, 1350), Vec2(1520, 1400), Vec2(1520, 1610)], width: 7, kind: .asphalt)
        addRoad([Vec2(560, 722), Vec2(580, 900), Vec2(620, 1080), Vec2(680, 1220), Vec2(790, 1290), Vec2(880, 1250), Vec2(960, 1220)], width: 4.5, kind: .dirt)
        addRoad([Vec2(960, 880), Vec2(975, 760), Vec2(1030, 600), Vec2(1100, 400), Vec2(1140, 200), Vec2(1150, 20)], width: 4.5, kind: .dirt)
        addRoad([Vec2(1500, 800), Vec2(1500, 700), Vec2(1500, 500), Vec2(1490, 300), Vec2(1470, 40)], width: 6, kind: .asphalt)
        addRoad([Vec2(1520, 1610), Vec2(1560, 1750), Vec2(1700, 1900), Vec2(1800, 2030)], width: 4.5, kind: .dirt)
        addRoad([Vec2(380, 722), Vec2(370, 600), Vec2(330, 450), Vec2(300, 250), Vec2(260, 30)], width: 4.5, kind: .dirt)
        addRoad([Vec2(620, 1080), Vec2(450, 1200), Vec2(300, 1350), Vec2(120, 1500), Vec2(20, 1560)], width: 4.5, kind: .dirt)
        world.roads.buildIndex()
        flattenAlongRoads()
        // Town sidewalks (axis aligned streets only).
        for (ri, r) in world.roads.roads.enumerated() where r.kind == .townStreet {
            guard let a = r.points.first, let b = r.points.last else { continue }
            let alongX = abs(b.x - a.x) > abs(b.z - a.z)
            let hw = r.width * 0.5
            let len = alongX ? abs(b.x - a.x) : abs(b.z - a.z)
            for side in [Float(-1), 1] {
                var s: Float = 0
                while s < len {
                    let e = min(len, s + 6)
                    let p0 = alongX ? Vec2(min(a.x, b.x) + s, a.z) : Vec2(a.x, min(a.z, b.z) + s)
                    let p1 = alongX ? Vec2(min(a.x, b.x) + e, a.z) : Vec2(a.x, min(a.z, b.z) + e)
                    s = e
                    let mid = (p0 + p1) * 0.5
                    let h = terrain.height(mid.x, mid.y)
                    let inner = side * hw, outer = side * (hw + 2)
                    let box: AABB
                    if alongX {
                        box = AABB(min: Vec3(p0.x, h - 0.4, a.z + min(inner, outer)), max: Vec3(p1.x, h + 0.22, a.z + max(inner, outer)))
                    } else {
                        box = AABB(min: Vec3(a.x + min(inner, outer), h - 0.4, p0.y), max: Vec3(a.x + max(inner, outer), h + 0.22, p1.y))
                    }
                    // Skip where another road crosses.
                    var crosses = false
                    for (rj, r2) in world.roads.roads.enumerated() where rj != ri {
                        for q in r2.points where abs(q.x - box.center.x) < box.halfExtents.x + r2.width * 0.5 + 1.0 &&
                            abs(q.z - box.center.z) < box.halfExtents.z + r2.width * 0.5 + 1.0 {
                            crosses = true
                            break
                        }
                        if crosses { break }
                    }
                    if !crosses { world.sidewalks.append(box) }
                }
            }
        }
    }

    func resampleRoadHeights() {
        for ri in 0..<world.roads.roads.count {
            for pi in 0..<world.roads.roads[ri].points.count {
                let p = world.roads.roads[ri].points[pi]
                world.roads.roads[ri].points[pi].y = max(p.y, terrain.height(p.x, p.z) + 0.02)
            }
        }
    }

    func flattenAlongRoads() {
        let res = terrain.res
        let cell = terrain.cell
        for iz in 0..<res {
            for ix in 0..<res {
                let x = Float(ix) * cell, z = Float(iz) * cell
                guard let n = world.roads.nearest(x, z) else { continue }
                let hw = world.roads.roads[n.road].width * 0.5
                let d = n.distance
                if d > hw + 9 { continue }
                let w = 1 - smoothstepf(hw + 0.8, hw + 9, d)
                let i = iz * res + ix
                terrain.heights[i] = mixf(terrain.heights[i], n.height - 0.08, w)
            }
        }
        // Re-sample road heights against final terrain so the surface sits just above it.
        for ri in 0..<world.roads.roads.count {
            for pi in 0..<world.roads.roads[ri].points.count {
                let p = world.roads.roads[ri].points[pi]
                world.roads.roads[ri].points[pi].y = max(p.y, terrain.height(p.x, p.z) + 0.02)
            }
        }
    }

    // MARK: Building placement

    func footprintFree(center: Vec2, half: Vec2, margin: Float, roadMargin: Float) -> Bool {
        if center.x - half.x < 20 || center.y - half.y < 20 || center.x + half.x > World.size - 20 || center.y + half.y > World.size - 20 { return false }
        for b in world.buildings {
            let fp = b.worldFootprint
            if center.x - half.x - margin < fp.max.x && center.x + half.x + margin > fp.min.x &&
                center.y - half.y - margin < fp.max.y && center.y + half.y + margin > fp.min.y { return false }
        }
        if world.roads.intersectsRect(center: center, halfSize: half, margin: roadMargin) { return false }
        for lake in world.water where vlength2(center - lake.center) < lake.radius * 1.3 + max(half.x, half.y) { return false }
        return true
    }

    @discardableResult
    func placeBuilding(_ type: BuildingType, at c: Vec2, rotation: Int, area: AreaKind, variant: Int? = nil, check: Bool = true, roadMargin: Float = 1.5) -> Bool {
        let f = type.footprint
        let half = rotation % 2 == 0 ? Vec2(f.x, f.y) * 0.5 : Vec2(f.y, f.x) * 0.5
        if check && !footprintFree(center: c, half: half, margin: 2.0, roadMargin: roadMargin) { return false }
        // Flatten terrain under the lot.
        let h = terrain.height(c.x, c.y)
        terrain.flattenRect(center: c, halfSize: half + Vec2(1.0, 1.0), target: h - 0.2, margin: 5)
        let v = variant ?? rng.int(0, type.variantCount - 1)
        let tints: [Vec3] = [Vec3(1, 1, 1), Vec3(0.95, 0.88, 0.75), Vec3(0.85, 0.9, 0.95), Vec3(0.92, 0.8, 0.78), Vec3(0.82, 0.88, 0.78), Vec3(0.98, 0.92, 0.7)]
        let tint = rng.pick(tints) * rng.range(0.85, 1.0)
        let placement = BuildingPlacement(type: type, variant: v, position: Vec3(c.x, h + 0.05, c.y), rotation: rotation, tint: tint,
                                          area: area, id: world.buildings.count)
        world.buildings.append(placement)
        return true
    }

    /// Places buildings along an axis-aligned street side.
    func placeRow(alongX: Bool, fixed: Float, from: Float, to: Float, side: Float, setback: Float, types: [BuildingType], area: AreaKind) {
        var cursor = from + rng.range(2, 6)
        var ti = 0
        var attempts = 0
        while cursor < to && attempts < 60 {
            attempts += 1
            var type = types[ti % types.count]
            var placed = false
            for attempt in 0..<2 {
                if attempt == 1 { type = rng.chance(0.5) ? .houseSmall : .shed }
                let f = type.footprint
                let width = f.x, depth = f.y
                if cursor + width > to { break }
                let along = cursor + width * 0.5
                let perp = fixed + side * (setback + depth * 0.5)
                let rot: Int
                let c: Vec2
                if alongX {
                    rot = side > 0 ? 2 : 0
                    c = Vec2(along, perp)
                } else {
                    rot = side > 0 ? 3 : 1
                    c = Vec2(perp, along)
                }
                if placeBuilding(type, at: c, rotation: rot, area: area) {
                    cursor += width + rng.range(3, 8)
                    placed = true
                    ti += 1
                    break
                }
            }
            if !placed { cursor += 4 }
        }
    }

    func placeTown() {
        let a = AreaKind.town
        // Landmarks.
        placeBuilding(.police, at: Vec2(1050, 1050 - 8.5 - 7), rotation: 0, area: a, check: true)
        placeBuilding(.hospital, at: Vec2(1050, 1050 + 8.5 + 8), rotation: 2, area: a, check: true)
        placeBuilding(.gasStation, at: Vec2(1225, 1050 + 8.5 + 10), rotation: 2, area: a, check: true)
        placeBuilding(.apartment, at: Vec2(925, 1050 - 8.5 - 6), rotation: 0, area: a)
        placeBuilding(.apartment, at: Vec2(1100, 950 + 8.5 + 6), rotation: 2, area: a)
        placeBuilding(.shop, at: Vec2(1180, 1050 - 8.5 - 6), rotation: 0, area: a)
        placeBuilding(.shop, at: Vec2(900, 1050 + 8.5 + 6), rotation: 2, area: a)
        // Street rows.
        let sb: Float = 8.5
        placeRow(alongX: true, fixed: 1050, from: 838, to: 1262, side: -1, setback: sb, types: [.houseTwoStory, .shop, .apartment, .houseSmall, .garage], area: a)
        placeRow(alongX: true, fixed: 1050, from: 838, to: 1262, side: 1, setback: sb, types: [.houseTwoStory, .houseSmall, .apartment, .shop], area: a)
        placeRow(alongX: true, fixed: 950, from: 884, to: 1216, side: -1, setback: sb, types: [.houseSmall, .houseTwoStory, .houseSmall, .garage, .houseTwoStory], area: a)
        placeRow(alongX: true, fixed: 950, from: 884, to: 1216, side: 1, setback: sb, types: [.houseSmall, .garage, .houseTwoStory, .shed], area: a)
        placeRow(alongX: true, fixed: 1150, from: 884, to: 1216, side: -1, setback: sb, types: [.houseSmall, .houseTwoStory, .apartment], area: a)
        placeRow(alongX: true, fixed: 1150, from: 884, to: 1216, side: 1, setback: sb, types: [.houseTwoStory, .houseSmall, .garage, .houseSmall], area: a)
        placeRow(alongX: false, fixed: 960, from: 884, to: 1216, side: -1, setback: sb, types: [.houseSmall, .houseTwoStory, .houseSmall], area: a)
        placeRow(alongX: false, fixed: 960, from: 884, to: 1216, side: 1, setback: sb, types: [.apartment, .houseSmall], area: a)
        placeRow(alongX: false, fixed: 1140, from: 874, to: 1226, side: 1, setback: sb, types: [.warehouse, .houseSmall, .garage, .houseTwoStory], area: a)
        placeRow(alongX: false, fixed: 1140, from: 874, to: 1226, side: -1, setback: sb, types: [.houseSmall, .shop, .houseSmall], area: a)

        // Street furniture.
        for r in world.roads.roads where r.kind == .townStreet {
            guard let p0 = r.points.first, let p1 = r.points.last else { continue }
            let alongX = abs(p1.x - p0.x) > abs(p1.z - p0.z)
            let len = alongX ? abs(p1.x - p0.x) : abs(p1.z - p0.z)
            var s: Float = 12
            var side: Float = 1
            while s < len - 8 {
                let base = alongX ? Vec2(min(p0.x, p1.x) + s, p0.z) : Vec2(p0.x, min(p0.z, p1.z) + s)
                let off = r.width * 0.5 + 1.3
                let pos = alongX ? Vec2(base.x, base.y + side * off) : Vec2(base.x + side * off, base.y)
                let yaw: Float = alongX ? (side > 0 ? kPi : 0) : (side > 0 ? kPi * 0.5 : -kPi * 0.5)
                addProp(.streetLight, at: pos, yaw: yaw + kPi, checkFree: true)
                // Parked / abandoned cars.
                if rng.chance(0.4) {
                    let carOff = r.width * 0.5 - 1.2
                    let cpos = alongX ? Vec2(base.x + 7, base.y - side * carOff) : Vec2(base.x - side * carOff, base.y + 7)
                    let carYaw = (alongX ? kPi * 0.5 : 0) + (rng.chance(0.5) ? kPi : 0) + rng.range(-0.12, 0.12)
                    addProp(rng.pick([.sedan, .hatchback, .sedan, .van, .wreck, .pickup]), at: cpos, yaw: carYaw, checkFree: true)
                }
                if rng.chance(0.25) {
                    let bpos = alongX ? Vec2(base.x + 4, base.y + side * (off + 0.2)) : Vec2(base.x + side * (off + 0.2), base.y + 4)
                    addProp(rng.chance(0.6) ? .bench : .dumpster, at: bpos, yaw: yaw, checkFree: true)
                }
                s += 30
                side = -side
            }
        }
        addProp(.busStop, at: Vec2(1000, 1050 - 7.0), yaw: 0, checkFree: true)
        addProp(.busStop, at: Vec2(1100, 1050 + 7.0), yaw: kPi, checkFree: true)
        addProp(.playground, at: Vec2(1050, 1000 + 0), yaw: 0, checkFree: true)
        // A few roadblocks inside town hint at the collapse.
        addProp(.jerseyBarrier, at: Vec2(1140, 1245), yaw: kPi * 0.5 + 0.2, checkFree: true)
        addProp(.wreck, at: Vec2(1135, 1262), yaw: 0.4, checkFree: true)
        addProp(.trafficCone, at: Vec2(1145, 1240), yaw: 0, checkFree: true)
        addProp(.trafficCone, at: Vec2(1137, 1238), yaw: 0, checkFree: true)
        // Hand pumps for water.
        for p in [Vec2(1050, 1000), Vec2(905, 1100), Vec2(1190, 990)] {
            addProp(.waterPump, at: p + Vec2(6, 0), yaw: 0, checkFree: true)
        }
    }

    func placeVillage() {
        let a = AreaKind.village
        placeRow(alongX: true, fixed: 722, from: 400, to: 650, side: -1, setback: 7, types: [.houseSmall, .houseTwoStory, .houseSmall, .shed, .houseSmall], area: a)
        placeRow(alongX: true, fixed: 722, from: 400, to: 650, side: 1, setback: 7, types: [.houseTwoStory, .houseSmall, .garage, .houseSmall], area: a)
        placeBuilding(.barn, at: Vec2(470, 680), rotation: 0, area: .farm)
        placeBuilding(.barn, at: Vec2(600, 775), rotation: 2, area: .farm)
        placeBuilding(.shed, at: Vec2(445, 770), rotation: 1, area: .farm)
        addProp(.waterWell, at: Vec2(520, 735), yaw: 0, checkFree: true)
        addProp(.tractor, at: Vec2(488, 692), yaw: 0.3, checkFree: true)
        addProp(.busStop, at: Vec2(540, 715), yaw: 0, checkFree: true)
        for _ in 0..<10 {
            addProp(.roundBale, at: Vec2(rng.range(390, 750), rng.chance(0.5) ? rng.range(570, 670) : rng.range(790, 880)), yaw: rng.range(0, kTwoPi), checkFree: true)
        }
        addProp(.firewood, at: Vec2(455, 700), yaw: 0, checkFree: true)
        addProp(.pickup, at: Vec2(610, 730), yaw: kPi * 0.5, checkFree: true)
        // Wooden fences along the fields.
        for i in 0..<14 {
            addProp(.woodFence, at: Vec2(400 + Float(i) * 4.0, 700), yaw: kPi * 0.5, checkFree: true)
            addProp(.woodFence, at: Vec2(560 + Float(i) * 4.0, 748), yaw: kPi * 0.5, checkFree: true)
        }
    }

    func placeIndustrial() {
        let a = AreaKind.industrial
        placeBuilding(.factory, at: Vec2(1474, 610), rotation: 1, area: a, check: true, roadMargin: 2)
        placeBuilding(.warehouse, at: Vec2(1522, 560), rotation: 3, area: a)
        placeBuilding(.warehouse, at: Vec2(1522, 690), rotation: 3, area: a)
        placeBuilding(.garage, at: Vec2(1478, 680), rotation: 1, area: a)
        placeBuilding(.garage, at: Vec2(1478, 690), rotation: 1, area: a)
        // Container yard.
        for i in 0..<3 {
            for j in 0..<2 {
                placeBuilding(.container, at: Vec2(1555 + Float(i) * 6, 610 + Float(j) * 14), rotation: 0, area: a)
            }
        }
        addProp(.fuelTank, at: Vec2(1455, 535), yaw: 0, checkFree: true)
        addProp(.fuelTank, at: Vec2(1455, 520), yaw: 0, checkFree: true)
        for _ in 0..<8 {
            addProp(rng.pick([.palletStack, .cableSpool, .oilDrums, .tireStack, .crateStack]),
                    at: Vec2(rng.range(1455, 1600), rng.range(500, 740)), yaw: rng.range(0, kTwoPi), checkFree: true)
        }
        addProp(.militaryTruck, at: Vec2(1540, 640), yaw: 0.1, checkFree: true)
        addProp(.van, at: Vec2(1510, 760), yaw: 0, checkFree: true)
        // Perimeter wall pieces.
        for i in 0..<8 { addProp(.concreteWall, at: Vec2(1440, 480 + Float(i) * 4), yaw: 0, checkFree: true) }
        for i in 0..<10 { addProp(.concreteWall, at: Vec2(1600, 520 + Float(i) * 4), yaw: 0, checkFree: true) }
    }

    func placeMilitary() {
        let a = AreaKind.military
        // Perimeter wall with a gate in the north wall at x = 1520.
        let x0: Float = 1470, x1: Float = 1650, z0: Float = 1490, z1: Float = 1630
        var x = x0 + 2
        while x < x1 {
            if abs(x - 1520) > 7 { addProp(.concreteWall, at: Vec2(x, z0), yaw: kPi * 0.5, checkFree: false) }
            addProp(.concreteWall, at: Vec2(x, z1), yaw: kPi * 0.5, checkFree: false)
            x += 4
        }
        var z = z0 + 2
        while z < z1 {
            addProp(.concreteWall, at: Vec2(x0, z), yaw: 0, checkFree: false)
            addProp(.concreteWall, at: Vec2(x1, z), yaw: 0, checkFree: false)
            z += 4
        }
        placeBuilding(.barracks, at: Vec2(1598, 1512), rotation: 0, area: a, check: false)
        placeBuilding(.barracks, at: Vec2(1598, 1540), rotation: 0, area: a, check: false)
        placeBuilding(.barracks, at: Vec2(1598, 1568), rotation: 0, area: a, check: false)
        placeBuilding(.warehouse, at: Vec2(1590, 1610), rotation: 2, area: a, check: false)
        for i in 0..<4 {
            placeBuilding(.tent, at: Vec2(1488, 1515 + Float(i) * 13), rotation: 1, area: a, variant: i % 2, check: false)
        }
        placeBuilding(.guardBooth, at: Vec2(1530, 1497), rotation: 2, area: a, check: false)
        placeBuilding(.container, at: Vec2(1640, 1515), rotation: 0, area: a, variant: 1, check: false)
        addProp(.barrierGate, at: Vec2(1514, 1490), yaw: -kPi * 0.5 + kPi, checkFree: false)
        addProp(.militaryTruck, at: Vec2(1556, 1580), yaw: 0, checkFree: false)
        addProp(.militaryTruck, at: Vec2(1566, 1580), yaw: 0.05, checkFree: false)
        addProp(.apc, at: Vec2(1630, 1595), yaw: 0.2, checkFree: false)
        addProp(.apc, at: Vec2(1540, 1540), yaw: kPi * 0.5, checkFree: false)
        for p in [Vec2(1508, 1484), Vec2(1532, 1484)] { addProp(.sandbags, at: p, yaw: kPi * 0.5, checkFree: false) }
        for _ in 0..<6 {
            addProp(rng.pick([.crateStack, .oilDrums, .sandbags, .crateStack]), at: Vec2(rng.range(1500, 1640), rng.range(1500, 1620)), yaw: rng.range(0, kTwoPi), checkFree: true)
        }
    }

    func placeCheckpoint() {
        let center = Vec2(1350, 1330)
        guard let n = world.roads.nearest(center.x, center.y) else { return }
        let r = world.roads.roads[n.road]
        let a = r.points[n.segment], b = r.points[n.segment + 1]
        let c = Vec2(mixf(a.x, b.x, n.t), mixf(a.z, b.z, n.t))
        let dir = n.direction
        let normal = Vec2(-dir.y, dir.x)
        let roadYaw = yawFromDirection(dir.x, dir.y)
        // Chicane of barriers.
        for (along, side) in [(Float(-14), Float(1)), (-6, -1), (2, 1), (10, -1)] {
            let p = c + dir * along + normal * side * 1.6
            addProp(.jerseyBarrier, at: p, yaw: roadYaw + kPi * 0.5, checkFree: false)
        }
        addProp(.barrierGate, at: c + dir * 18 + normal * 3.8, yaw: roadYaw + kPi * 0.5 + kPi, checkFree: false)
        placeBuilding(.guardBooth, at: c + dir * 18 + normal * 7.5, rotation: 0, area: .checkpoint, check: false)
        for k in 0..<4 {
            addProp(.sandbags, at: c + dir * (Float(k) * 3.5 - 4) + normal * -7, yaw: roadYaw + kPi * 0.5, checkFree: false)
        }
        placeBuilding(.tent, at: c + dir * -4 + normal * 14, rotation: 0, area: .checkpoint, variant: 1, check: false)
        addProp(.militaryTruck, at: c + dir * 26 + normal * -8, yaw: roadYaw, checkFree: false)
        // Civilian queue that never made it through.
        for k in 0..<4 {
            let p = c - dir * (24 + Float(k) * 7) + normal * (rng.chance(0.5) ? -1.6 : 1.6)
            addProp(rng.pick([.sedan, .hatchback, .van, .pickup, .wreck]), at: p, yaw: roadYaw + rng.range(-0.25, 0.25), checkFree: false)
        }
        addProp(.crateStack, at: c + dir * 20 + normal * -9, yaw: roadYaw, checkFree: false)
    }

    func placeRoadside() {
        // Abandoned vehicles and power poles along the main roads.
        for (ri, r) in world.roads.roads.enumerated() where r.kind != .townStreet {
            var nextCar: Float = rng.range(60, 140)
            var nextPole: Float = 20
            for i in 1..<r.points.count {
                let dist = r.lengths[i]
                let p = r.points[i], q = r.points[i - 1]
                let dir = vnormalize2(Vec2(p.x - q.x, p.z - q.z))
                let normal = Vec2(-dir.y, dir.x)
                let pos2 = Vec2(p.x, p.z)
                if settlementMask(p.x, p.z) > 0.6 { continue }
                if dist > nextCar {
                    nextCar = dist + rng.range(90, 220)
                    let side: Float = rng.chance(0.5) ? 1 : -1
                    let crashed = rng.chance(0.3)
                    let off = crashed ? r.width * 0.5 + 2.5 : r.width * 0.25
                    let yaw = yawFromDirection(dir.x, dir.y) + (rng.chance(0.5) ? 0 : kPi) + (crashed ? rng.range(-0.8, 0.8) : rng.range(-0.15, 0.15))
                    addProp(rng.pick([.sedan, .hatchback, .van, .pickup, .wreck, .sedan]), at: pos2 + normal * side * off, yaw: yaw, checkFree: true)
                }
                if r.kind == .asphalt && dist > nextPole {
                    nextPole = dist + 45
                    addProp(.powerPole, at: pos2 + normal * (r.width * 0.5 + 5), yaw: yawFromDirection(dir.x, dir.y), checkFree: true)
                }
            }
            _ = ri
        }
        // Road signs at the town entrances.
        addProp(.roadSign, at: Vec2(815, 1058), yaw: kPi * 0.5, checkFree: true)
        addProp(.roadSign, at: Vec2(1285, 1042), yaw: -kPi * 0.5, checkFree: true)
        addProp(.roadSign, at: Vec2(390, 714), yaw: kPi * 0.5, checkFree: true)
        // Scattered boulders in the hills.
        for _ in 0..<70 {
            let p = Vec2(rng.range(60, 1990), rng.range(60, 1990))
            if settlementMask(p.x, p.y) > 0.1 || world.roads.edgeDistance(p.x, p.y) < 8 { continue }
            addProp(.boulder, at: p, yaw: rng.range(0, kTwoPi), checkFree: true)
        }
        // Lake picnic spot.
        addProp(.picnicTable, at: Vec2(785, 1330), yaw: 0.3, checkFree: true)
        addProp(.firewood, at: Vec2(790, 1340), yaw: 1.0, checkFree: true)
        addProp(.hatchback, at: Vec2(800, 1318), yaw: 2.0, checkFree: true)
        // Forest huts.
        placeBuilding(.shed, at: Vec2(330, 1180), rotation: 1, area: .forest)
        placeBuilding(.shed, at: Vec2(860, 330), rotation: 2, area: .forest)
        placeBuilding(.houseSmall, at: Vec2(240, 1330), rotation: 1, area: .forest, variant: 2)
        placeBuilding(.houseSmall, at: Vec2(1120, 440), rotation: 3, area: .forest, variant: 2)
    }

    @discardableResult
    func addProp(_ type: PropType, at p: Vec2, yaw: Float, checkFree: Bool) -> Bool {
        if p.x < 10 || p.y < 10 || p.x > World.size - 10 || p.y > World.size - 10 { return false }
        if checkFree {
            for b in world.buildings {
                let fp = b.worldFootprint
                if p.x > fp.min.x - 2 && p.x < fp.max.x + 2 && p.y > fp.min.y - 2 && p.y < fp.max.y + 2 { return false }
            }
            for lake in world.water where vlength2(p - lake.center) < lake.radius + 3 { return false }
            if !type.isVehicle && type != .streetLight && type != .powerPole && world.roads.edgeDistance(p.x, p.y) < 0.8 { return false }
        }
        let h = terrain.height(p.x, p.y)
        world.props.append(PropInstance(type: type, position: Vec3(p.x, h, p.y), yaw: yaw, tint: Vec3(1, 1, 1)))
        return true
    }

    // MARK: Fields & forests

    func computeFieldsAndForest() {
        world.fields = [
            (Vec2(390, 575), Vec2(500, 685)), (Vec2(590, 570), Vec2(760, 685)),
            (Vec2(380, 765), Vec2(520, 900)), (Vec2(640, 790), Vec2(770, 880)),
            (Vec2(1300, 1110), Vec2(1420, 1240)), (Vec2(1180, 1380), Vec2(1300, 1470)),
        ]
        let res = terrain.res, cell = terrain.cell
        let fn = Noise2D(seed: world.seed &+ 991)
        for iz in 0..<res {
            for ix in 0..<res {
                let x = Float(ix) * cell, z = Float(iz) * cell
                let i = iz * res + ix
                var inField = false
                for f in world.fields where x >= f.min.x && x <= f.max.x && z >= f.min.y && z <= f.max.y {
                    inField = true
                    break
                }
                if inField && world.roads.edgeDistance(x, z) > 2.5 { terrain.flags[i] |= 1 }
                // Forest density.
                var d = fn.fbm(x / 300, z / 300, octaves: 4) * 2.0 + 0.08
                // Big forest regions with organic (domain warped) borders.
                let wx = x + fn.noise(x / 260, z / 260) * 190
                let wz = z + fn.noise(x / 260 + 41, z / 260 + 17) * 190
                let west = 1 - smoothstepf(260, 560, wx)
                let north = 1 - smoothstepf(260, 520, wz)
                let east = smoothstepf(1760, 1950, wx) * (1 - smoothstepf(400, 700, abs(wz - 1100)))
                let lakeD = vlength2(Vec2(x, z) - Vec2(700, 1350))
                let lakeForest = (1 - smoothstepf(150, 380, lakeD + fn.noise(x / 90, z / 90) * 60))
                let south = smoothstepf(1600, 1820, wz) * (1 - smoothstepf(1300, 1600, abs(wx - 900))) + east
                d = max(d, max(west, max(north, max(lakeForest * 0.9, south))) * 0.95)
                d *= 1 - settlementMask(x, z)
                if inField { d = 0 }
                let rd = world.roads.edgeDistance(x, z)
                d *= smoothstepf(3, 14, rd)
                if lakeD < 80 { d = 0 }
                terrain.forest[i] = saturatef(d)
            }
        }
    }

    func plantTrees() {
        let cellSize: Float = 7
        let n = Int(World.size / cellSize)
        var placedCount = 0
        for gz in 0..<n {
            for gx in 0..<n {
                let jx = rng.range(0.1, 0.9), jz = rng.range(0.1, 0.9)
                let x = (Float(gx) + jx) * cellSize, z = (Float(gz) + jz) * cellSize
                let d = terrain.forestDensity(x, z)
                let meadow: Float = 0.012
                let p = d > 0.3 ? d * 0.95 : (d > 0.12 ? d * 0.6 : meadow)
                if !rng.chance(p) { continue }
                if world.roads.edgeDistance(x, z) < 3 { continue }
                if terrain.isField(x, z) { continue }
                // Avoid buildings and props.
                var blocked = false
                for b in world.buildings {
                    let fp = b.worldFootprint
                    if x > fp.min.x - 4 && x < fp.max.x + 4 && z > fp.min.y - 4 && z < fp.max.y + 4 { blocked = true; break }
                }
                if blocked { continue }
                for lake in world.water where vlength2(Vec2(x, z) - lake.center) < lake.radius * 1.05 { blocked = true }
                if blocked { continue }
                let kindRoll = rng.float()
                var kind: TreeKind
                if d < 0.3 {
                    kind = kindRoll < 0.45 ? .bush : (kindRoll < 0.7 ? .oak : (kindRoll < 0.9 ? .birch : .deadTree))
                } else {
                    kind = kindRoll < 0.55 ? .spruce : (kindRoll < 0.7 ? .pine : (kindRoll < 0.85 ? .birch : (kindRoll < 0.93 ? .bush : (kindRoll < 0.97 ? .oak : .deadTree))))
                }
                if settlementMask(x, z) > 0.3 && kind == .spruce { kind = .birch }
                let scale = rng.range(0.75, 1.25) * (kind == .bush ? 1.0 : 1.0)
                let tint = Vec3(rng.range(0.85, 1.12), rng.range(0.88, 1.1), rng.range(0.82, 1.05))
                let h = terrain.height(x, z)
                world.trees.append(TreeInstance(position: Vec3(x, h, z), yaw: rng.range(0, kTwoPi), scale: scale, kind: kind, tint: tint))
                placedCount += 1
            }
        }
        // Yard trees in settlements.
        for b in world.buildings where b.area == .town || b.area == .village {
            if rng.chance(0.6) {
                let fp = b.worldFootprint
                let x = rng.chance(0.5) ? fp.min.x - 3.5 : fp.max.x + 3.5
                let z = rng.range(fp.min.y, fp.max.y)
                if world.roads.edgeDistance(x, z) > 3 {
                    world.trees.append(TreeInstance(position: Vec3(x, terrain.height(x, z), z), yaw: rng.range(0, kTwoPi),
                                                    scale: rng.range(0.7, 1.0), kind: rng.chance(0.5) ? .birch : .bush, tint: Vec3(1, 1, 1)))
                }
            }
        }
        for (i, t) in world.trees.enumerated() {
            world.treesByChunk[World.chunkIndex(t.position.x, t.position.z)].append(i)
            let r = TreeFactory.trunkRadius(t.kind) * t.scale
            if r > 0 {
                world.collision.add(AABB(min: t.position + Vec3(-r, -1, -r), max: t.position + Vec3(r, 6 * t.scale, r)),
                                    [.solid, .blocksBullets, .blocksSight], .wood)
            } else {
                // Bushes: concealment only.
                let br = 1.1 * t.scale
                world.collision.add(AABB(min: t.position + Vec3(-br, 0, -br), max: t.position + Vec3(br, 1.5 * t.scale, br)), [.foliage, .blocksSight], .grass)
            }
        }
    }

    // MARK: Instantiation

    func modelFor(_ type: BuildingType, _ variant: Int) -> BuildingModel {
        let key = World.modelKey(type, variant)
        if let m = world.buildingModels[key] { return m }
        let m = BuildingFactory.make(type, variant: variant)
        world.buildingModels[key] = m
        return m
    }

    func instantiateBuildings() {
        for (bi, b) in world.buildings.enumerated() {
            let model = modelFor(b.type, b.variant)
            let m = b.transform
            for c in model.colliders {
                world.collision.add(c.box.transformed(m), c.flags, c.surface)
            }
            let doorBase = world.doors.count
            for p in model.passages {
                world.passages.append(NavPassage(center: m.transformPoint(p.center), across: vnormalize(m.transformDirection(p.across)),
                                                 width: p.width, door: p.door >= 0 ? doorBase + p.door : -1))
            }
            for d in model.doors {
                let hinge = m.transformPoint(d.hinge)
                let yaw = Float(b.rotation) * kPi * 0.5 + d.closedYaw
                var door = DoorState(hinge: hinge, baseYaw: yaw, width: d.width, height: d.height, openSign: d.openSign,
                                     style: d.style, collider: -1, building: bi)
                // Some doors start open.
                if rng.chance(d.exterior ? 0.25 : 0.45) {
                    door.isOpen = true
                    door.angle = d.openSign * kPi * 0.5
                }
                let closed = door.leafBox(angle: 0)
                let open = door.leafBox(angle: d.openSign * kPi * 0.5)
                var coverage = closed
                coverage.expand(open)
                let current = abs(door.angle) > 0.1 ? open : closed
                let flags: ColliderFlags = d.style == .cell ? [.solid, .door] : [.solid, .door, .blocksSight, .blocksBullets]
                door.collider = world.collision.add(current, flags, d.style == .wood ? .wood : .metal, door: Int32(world.doors.count), coverage: coverage)
                world.doorsByChunk[World.chunkIndex(hinge.x, hinge.z)].append(world.doors.count)
                world.doors.append(door)
            }
            for spot in model.lootSpots {
                world.lootSpots.append(WorldLootSpot(position: m.transformPoint(spot.position), category: spot.category,
                                                     yaw: spot.yaw + Float(b.rotation) * kPi * 0.5, large: spot.large, area: b.area))
            }
            world.buildingsByChunk[World.chunkIndex(b.position.x, b.position.z)].append(bi)
            if !model.stairs.isEmpty {
                world.buildingStairs[bi] = model.stairs.map { chain in chain.map { m.transformPoint($0) } }
            }
        }
        for s in world.sidewalks {
            world.collision.add(s, [.solid], .concrete)
        }
    }

    func instantiateProps() {
        for (pi, p) in world.props.enumerated() {
            let key = p.type.rawValue
            let model: PropModel
            if let m = world.propModels[key] { model = m } else {
                model = PropFactory.make(p.type)
                world.propModels[key] = model
            }
            for c in model.colliders {
                addOrientedCollider(c.box, position: p.position, yaw: p.yaw, flags: c.flags, surface: c.surface)
            }
            let m = p.transform
            for spot in model.lootSpots {
                var wp = m.transformPoint(spot.position)
                if spot.position.y < 0.01 { wp.y = terrain.height(wp.x, wp.z) }
                let area = world.areaKind(at: wp)
                world.lootSpots.append(WorldLootSpot(position: wp, category: spot.category, yaw: spot.yaw + p.yaw, large: spot.large, area: area))
            }
            if let wpnt = model.waterPoint {
                world.waterSources.append(WaterSource(position: m.transformPoint(wpnt), kind: p.type == .waterWell ? 1 : 2, safe: true))
            }
            world.propsByChunk[World.chunkIndex(p.position.x, p.position.z)].append(pi)
        }
    }

    /// Adds a collider for a box rotated by an arbitrary yaw, decomposed into AABB slices.
    func addOrientedCollider(_ local: AABB, position: Vec3, yaw: Float, flags: ColliderFlags, surface: SurfaceKind) {
        let m = Mat4.translation(position) * Mat4.rotationY(yaw)
        let q = abs(wrapAngle(yaw * 2) ) // multiples of 90 degrees produce ~0 or ~pi
        let aligned = q < 0.02 || abs(q - kPi) < 0.02
        if aligned {
            world.collision.add(local.transformed(m), flags, surface)
            return
        }
        let size = local.size
        let alongX = size.x >= size.z
        let long = alongX ? size.x : size.z
        let short = max(0.2, alongX ? size.z : size.x)
        let n = max(1, min(8, Int(ceilf(long / short))))
        for i in 0..<n {
            var b = local
            if alongX {
                b.min.x = local.min.x + size.x * Float(i) / Float(n)
                b.max.x = local.min.x + size.x * Float(i + 1) / Float(n)
            } else {
                b.min.z = local.min.z + size.z * Float(i) / Float(n)
                b.max.z = local.min.z + size.z * Float(i + 1) / Float(n)
            }
            var wb = b.transformed(m)
            // Shrink slices slightly to compensate the AABB overshoot at the corners.
            let shrink = min(wb.size.x, wb.size.z) * 0.12
            wb.min.x += shrink; wb.max.x -= shrink
            wb.min.z += shrink; wb.max.z -= shrink
            world.collision.add(wb, flags, surface)
        }
    }

    func defineSpawns() {
        let pts: [Vec2] = [Vec2(120, 785), Vec2(300, 1342), Vec2(1150, 70), Vec2(1480, 80), Vec2(1990, 603),
                           Vec2(1780, 2000), Vec2(270, 70), Vec2(60, 1550), Vec2(760, 870), Vec2(1700, 900)]
        for p in pts {
            let h = terrain.height(p.x, p.y)
            let yaw = yawFromDirection(1050 - p.x, 1050 - p.y)
            world.spawnPoints.append(SpawnPoint(position: Vec3(p.x, h + 0.05, p.y), yaw: yaw))
        }
    }
}

extension World {
    /// Registers building, prop, tree and door meshes in the registry. Building mesh data is
    /// released from the models afterwards to keep memory low.
    func registerMeshes(_ registry: MeshRegistry) {
        for (key, model) in buildingModels {
            let shell = registry.add("bld-\(key)-shell", model.shell)
            let interior = registry.add("bld-\(key)-int", model.interior)
            let plugs = registry.add("bld-\(key)-plugs", model.lodPlugs)
            buildingMeshIDs[key] = (shell, interior, plugs)
            model.shell.vertices = []; model.shell.indices = []
            model.interior.vertices = []; model.interior.indices = []
            model.lodPlugs.vertices = []; model.lodPlugs.indices = []
        }
        for (key, model) in propModels {
            propMeshIDs[key] = registry.add("prop-\(key)", model.mesh)
            model.mesh.vertices = []; model.mesh.indices = []
        }
        for kind in TreeKind.allCases {
            let (hi, lo) = TreeFactory.make(kind)
            treeMeshIDs[kind.rawValue] = (registry.add("tree-\(kind.rawValue)-hi", hi), registry.add("tree-\(kind.rawValue)-lo", lo))
        }
        for style in [DoorStyle.wood, .metal, .glass, .cell] {
            doorMeshIDs[Int(style.rawValue)] = registry.add("door-\(style.rawValue)", DoorMeshes.make(style))
        }
    }
}

enum DoorMeshes {
    /// Door leaf: hinge at origin, extends along +X (0.9 m reference width scaled by instance), thickness along Z.
    static func make(_ style: DoorStyle) -> MeshBuilder {
        let m = MeshBuilder()
        m.skyVisibility = 0.7
        m.uvScale = 1
        let w: Float = 1.0, h: Float = 2.12
        switch style {
        case .wood:
            m.material = .woodDark
            m.color = Vec3(0.55, 0.4, 0.28)
            m.addBox(min: Vec3(0.0, 0, -0.025), max: Vec3(w, h, 0.025))
            m.color = Vec3(0.48, 0.34, 0.24)
            for (y0, y1) in [(Float(0.25), Float(0.95)), (1.15, 1.9)] {
                m.addBox(min: Vec3(0.12, y0, 0.025), max: Vec3(w - 0.12, y1, 0.035))
                m.addBox(min: Vec3(0.12, y0, -0.035), max: Vec3(w - 0.12, y1, -0.025))
            }
        case .metal:
            m.material = .metalPainted
            m.color = Vec3(0.4, 0.45, 0.48)
            m.addBox(min: Vec3(0.0, 0, -0.03), max: Vec3(w, h, 0.03))
        case .glass:
            m.material = .metalPainted
            m.color = Vec3(0.25, 0.27, 0.3)
            m.addBox(min: Vec3(0, 0, -0.03), max: Vec3(0.07, h, 0.03))
            m.addBox(min: Vec3(w - 0.07, 0, -0.03), max: Vec3(w, h, 0.03))
            m.addBox(min: Vec3(0.07, 0, -0.03), max: Vec3(w - 0.07, 0.15, 0.03))
            m.addBox(min: Vec3(0.07, h - 0.07, -0.03), max: Vec3(w - 0.07, h, 0.03))
            m.material = .glass
            m.color = Vec3(0.45, 0.55, 0.6)
            m.flags = VertexFlag.glossy
            m.addBox(min: Vec3(0.07, 0.15, -0.008), max: Vec3(w - 0.07, h - 0.07, 0.008))
            m.flags = 0
        case .cell:
            m.material = .metalPainted
            m.color = Vec3(0.25, 0.27, 0.3)
            var x: Float = 0.03
            while x < w {
                m.addBox(min: Vec3(x - 0.02, 0, -0.02), max: Vec3(x + 0.02, h, 0.02))
                x += 0.14
            }
            m.addBox(min: Vec3(0, 1.0, -0.03), max: Vec3(w, 1.08, 0.03))
            m.addBox(min: Vec3(0, h - 0.08, -0.03), max: Vec3(w, h, 0.03))
        }
        // Handle.
        if style != .cell {
            m.material = .sheetMetal
            m.color = Vec3(0.75, 0.72, 0.6)
            m.addBox(min: Vec3(w - 0.14, 0.98, 0.03), max: Vec3(w - 0.06, 1.02, 0.08))
            m.addBox(min: Vec3(w - 0.14, 0.98, -0.08), max: Vec3(w - 0.06, 1.02, -0.03))
        }
        return m
    }
}
