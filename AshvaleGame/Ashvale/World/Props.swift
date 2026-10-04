//
//  Props.swift
//  Ashvale
//
//  Outdoor props: abandoned vehicles, barriers, fences, street furniture,
//  wells, fuel tanks... Each prop has a mesh, colliders and loot spots.
//

import Foundation

enum PropType: Int, CaseIterable {
    case sedan, hatchback, van, pickup, militaryTruck, bus, tractor, wreck, apc
    case jerseyBarrier, sandbags, barrierGate, woodFence, concreteWall, chainBarrier
    case streetLight, powerPole, bench, dumpster, busStop, waterWell, waterPump
    case roundBale, fuelTank, roadSign, picnicTable, firewood, boulder, trafficCone
    case palletStack, tireStack, cableSpool, crateStack, oilDrums, playground

    var isVehicle: Bool {
        switch self {
        case .sedan, .hatchback, .van, .pickup, .militaryTruck, .bus, .tractor, .wreck, .apc: return true
        default: return false
        }
    }

    /// Max distance at which the prop is drawn.
    var drawDistance: Float {
        switch self {
        case .trafficCone, .firewood, .tireStack, .oilDrums, .bench, .picnicTable: return 140
        case .streetLight, .powerPole, .bus, .militaryTruck, .apc, .fuelTank, .boulder: return 600
        default: return 300
        }
    }
}

final class PropModel {
    let mesh = MeshBuilder()
    var colliders: [LocalCollider] = []
    var lootSpots: [LootSpotSpec] = []
    var waterPoint: Vec3?
    var radius: Float = 2
}

enum PropFactory {

    static func make(_ type: PropType) -> PropModel {
        let p = PropModel()
        let m = p.mesh
        m.skyVisibility = 1
        m.uvScale = 1
        var rng = RNG(seed: stableHash("prop-\(type.rawValue)"))
        switch type {
        case .sedan:
            vehicle(p, length: 4.5, width: 1.78, wheelR: 0.33, color: Vec3(0.55, 0.12, 0.1),
                    body: [(-2.25, 0.35), (2.25, 0.35), (2.3, 0.6), (2.2, 0.82), (1.1, 0.92), (-1.6, 0.95), (-2.2, 0.88), (-2.3, 0.6)],
                    cabin: [(-1.5, 0.92), (1.05, 0.92), (0.4, 1.42), (-1.0, 1.44)], wheelX: [1.4, -1.35], rng: &rng)
        case .hatchback:
            vehicle(p, length: 3.9, width: 1.7, wheelR: 0.31, color: Vec3(0.2, 0.32, 0.5),
                    body: [(-1.95, 0.35), (1.95, 0.35), (2.0, 0.6), (1.9, 0.8), (0.9, 0.9), (-1.9, 0.95), (-2.0, 0.6)],
                    cabin: [(-1.9, 0.92), (0.85, 0.92), (0.25, 1.45), (-1.75, 1.46)], wheelX: [1.25, -1.25], rng: &rng)
        case .van:
            vehicle(p, length: 5.0, width: 1.95, wheelR: 0.36, color: Vec3(0.85, 0.85, 0.82),
                    body: [(-2.5, 0.4), (2.5, 0.4), (2.55, 0.65), (2.45, 1.0), (1.6, 1.1), (1.6, 2.05), (-2.5, 2.1)],
                    cabin: [(1.35, 1.1), (2.35, 1.05), (1.75, 1.8), (1.35, 1.85)], wheelX: [1.75, -1.7], rng: &rng)
        case .pickup:
            vehicle(p, length: 5.2, width: 1.9, wheelR: 0.4, color: Vec3(0.3, 0.38, 0.3),
                    body: [(-2.6, 0.5), (2.6, 0.5), (2.65, 0.75), (2.55, 1.05), (1.2, 1.1), (-2.6, 1.1)],
                    cabin: [(-0.6, 1.1), (1.15, 1.1), (0.6, 1.75), (-0.5, 1.78)], wheelX: [1.75, -1.7], rng: &rng)
            // Cargo bed walls.
            m.withTransform(Mat4.rotationY(kPi * 0.5)) {
                m.material = .metalPainted
                m.color = Vec3(0.28, 0.35, 0.28)
                m.addBox(min: Vec3(-2.6, 1.1, -0.95), max: Vec3(-0.7, 1.45, -0.88))
                m.addBox(min: Vec3(-2.6, 1.1, 0.88), max: Vec3(-0.7, 1.45, 0.95))
                m.addBox(min: Vec3(-2.62, 1.1, -0.95), max: Vec3(-2.55, 1.45, 0.95))
            }
        case .militaryTruck:
            militaryTruck(p)
        case .bus:
            vehicle(p, length: 11, width: 2.5, wheelR: 0.5, color: Vec3(0.85, 0.6, 0.15),
                    body: [(-5.5, 0.45), (5.5, 0.45), (5.55, 1.2), (5.45, 3.0), (-5.5, 3.05)],
                    cabin: [(-5.3, 1.7), (5.4, 1.7), (5.35, 2.6), (-5.3, 2.6)], wheelX: [3.8, -3.6], rng: &rng, cabinWidthInset: -0.02)
        case .tractor:
            tractor(p)
        case .wreck:
            vehicle(p, length: 4.5, width: 1.78, wheelR: 0.3, color: Vec3(0.18, 0.15, 0.13),
                    body: [(-2.25, 0.3), (2.25, 0.3), (2.3, 0.55), (2.2, 0.78), (1.1, 0.88), (-1.6, 0.9), (-2.2, 0.84), (-2.3, 0.55)],
                    cabin: [(-1.5, 0.88), (1.05, 0.88), (0.4, 1.36), (-1.0, 1.38)], wheelX: [1.4, -1.35], rng: &rng, burnt: true)
        case .apc:
            apc(p)
        case .jerseyBarrier:
            m.material = .concrete
            m.color = Vec3(0.68, 0.67, 0.64)
            m.uvScale = 0.7
            m.addPrismZ([Vec2(-0.3, 0), Vec2(0.3, 0), Vec2(0.3, 0.08), Vec2(0.12, 0.3), Vec2(0.1, 0.8), Vec2(-0.1, 0.8), Vec2(-0.12, 0.3), Vec2(-0.3, 0.08)], z0: -1.5, z1: 1.5)
            m.color = Vec3(0.75, 0.6, 0.1)
            m.addBox(min: Vec3(-0.105, 0.6, -1.5), max: Vec3(0.105, 0.68, 1.5), faces: .sides)
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.3, -0.3, -1.5), max: Vec3(0.3, 0.8, 1.5)), flags: .lowCover, surface: .concrete))
            p.radius = 1.6
        case .sandbags:
            m.material = .burlap
            m.color = Vec3(0.6, 0.55, 0.4)
            m.uvScale = 2
            for row in 0..<4 {
                let y = Float(row) * 0.26
                let off: Float = row % 2 == 0 ? 0 : 0.3
                var z: Float = -1.5 + off
                while z < 1.5 - 0.3 {
                    m.addEllipsoid(center: Vec3(0, y + 0.13, z + 0.3), radii: Vec3(0.33, 0.15, 0.31), rings: 4, segments: 8)
                    z += 0.6
                }
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.35, -0.2, -1.5), max: Vec3(0.35, 1.05, 1.5)), flags: .lowCover, surface: .dirt))
            p.radius = 1.6
        case .barrierGate:
            m.material = .concrete
            m.color = Vec3(0.6, 0.6, 0.58)
            m.addBox(min: Vec3(-0.4, 0, -0.4), max: Vec3(0.4, 1.1, 0.4))
            m.material = .metalPainted
            m.color = Vec3(0.85, 0.85, 0.85)
            m.addBox(min: Vec3(-0.06, 0.9, 0.4), max: Vec3(0.06, 1.02, 6.0))
            m.color = Vec3(0.8, 0.1, 0.1)
            var z: Float = 0.8
            while z < 6.0 {
                m.addBox(min: Vec3(-0.065, 0.89, z), max: Vec3(0.065, 1.03, z + 0.4))
                z += 0.8
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.4, -0.2, -0.4), max: Vec3(0.4, 1.1, 0.4)), flags: .lowCover, surface: .concrete))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.06, 0.85, 0.4), max: Vec3(0.06, 1.05, 6.0)), flags: [.solid, .vaultable], surface: .metal))
            p.radius = 6
        case .woodFence:
            m.material = .woodPlanks
            m.color = Vec3(0.55, 0.45, 0.32)
            m.uvScale = 1
            for i in 0...4 {
                let z = -2.0 + Float(i)
                m.addBox(min: Vec3(-0.06, -0.3, z - 0.06), max: Vec3(0.06, 1.1, z + 0.06))
            }
            m.addBox(min: Vec3(-0.03, 0.35, -2.0), max: Vec3(0.03, 0.47, 2.0))
            m.addBox(min: Vec3(-0.03, 0.85, -2.0), max: Vec3(0.03, 0.97, 2.0))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.08, -0.3, -2.0), max: Vec3(0.08, 1.1, 2.0)), flags: .fence, surface: .wood))
            p.radius = 2.1
        case .concreteWall:
            m.material = .concrete
            m.color = Vec3(0.62, 0.62, 0.6)
            m.uvScale = 0.5
            m.addBox(min: Vec3(-0.15, -0.5, -2.0), max: Vec3(0.15, 2.6, 2.0))
            m.material = .metalPainted
            m.color = Vec3(0.3, 0.3, 0.3)
            m.addBox(min: Vec3(-0.02, 2.6, -2.0), max: Vec3(0.02, 2.65, 2.0))
            for i in 0...4 {
                let z = -2.0 + Float(i)
                m.addBox(min: Vec3(-0.02, 2.6, z - 0.02), max: Vec3(0.02, 3.0, z + 0.02))
            }
            m.addBox(min: Vec3(-0.01, 2.8, -2.0), max: Vec3(0.01, 2.82, 2.0))
            m.addBox(min: Vec3(-0.01, 2.95, -2.0), max: Vec3(0.01, 2.97, 2.0))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.15, -0.5, -2.0), max: Vec3(0.15, 3.0, 2.0)), flags: .wall, surface: .concrete))
            p.radius = 2.1
        case .chainBarrier:
            m.material = .metalPainted
            m.color = Vec3(0.75, 0.6, 0.1)
            m.addBox(min: Vec3(-0.05, 0, -1.55), max: Vec3(0.05, 0.9, -1.45))
            m.addBox(min: Vec3(-0.05, 0, 1.45), max: Vec3(0.05, 0.9, 1.55))
            m.color = Vec3(0.3, 0.3, 0.3)
            m.addBox(min: Vec3(-0.02, 0.6, -1.5), max: Vec3(0.02, 0.64, 1.5))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.06, 0, -1.55), max: Vec3(0.06, 0.9, 1.55)), flags: .fence, surface: .metal))
            p.radius = 1.6
        case .streetLight:
            m.material = .metalPainted
            m.color = Vec3(0.35, 0.37, 0.38)
            m.addCylinder(center: Vec3(0, -0.3, 0), radiusBottom: 0.1, radiusTop: 0.06, height: 6.8, segments: 8)
            m.addBox(min: Vec3(-0.04, 6.3, -0.04), max: Vec3(0.04, 6.38, 1.4))
            m.addBox(min: Vec3(-0.15, 6.15, 1.1), max: Vec3(0.15, 6.32, 1.6))
            m.material = .glass
            m.color = Vec3(0.8, 0.8, 0.7)
            m.addBox(min: Vec3(-0.12, 6.12, 1.15), max: Vec3(0.12, 6.15, 1.55))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.1, -0.3, -0.1), max: Vec3(0.1, 6.5, 0.1)), flags: [.solid, .blocksBullets], surface: .metal))
            p.radius = 7
        case .powerPole:
            m.material = .woodDark
            m.color = Vec3(0.35, 0.28, 0.2)
            m.addCylinder(center: Vec3(0, -0.5, 0), radiusBottom: 0.14, radiusTop: 0.11, height: 9.5, segments: 8)
            m.addBox(min: Vec3(-0.06, 8.3, -1.0), max: Vec3(0.06, 8.45, 1.0))
            m.material = .plastic
            m.color = Vec3(0.8, 0.8, 0.75)
            for z in [Float(-0.85), 0.0, 0.85] {
                m.addCylinder(center: Vec3(0, 8.45, z), radiusBottom: 0.04, radiusTop: 0.03, height: 0.15, segments: 6)
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.14, -0.5, -0.14), max: Vec3(0.14, 9, 0.14)), flags: [.solid, .blocksBullets], surface: .wood))
            p.radius = 9
        case .bench:
            m.material = .woodPlanks
            m.color = Vec3(0.5, 0.36, 0.22)
            m.addBox(min: Vec3(-0.9, 0.42, -0.2), max: Vec3(0.9, 0.46, 0.22))
            m.addBox(min: Vec3(-0.9, 0.55, -0.24), max: Vec3(0.9, 0.85, -0.2))
            m.material = .metalPainted
            m.color = Vec3(0.2, 0.22, 0.2)
            for x in [Float(-0.75), 0.75] {
                m.addBox(min: Vec3(x - 0.03, 0, -0.22), max: Vec3(x + 0.03, 0.85, 0.22))
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.9, 0, -0.24), max: Vec3(0.9, 0.46, 0.22)), flags: [.solid, .vaultable], surface: .wood))
            p.lootSpots.append(LootSpotSpec(position: Vec3(0.3, 0.46, 0), category: .living, yaw: 0.3, large: false))
            p.radius = 1
        case .dumpster:
            m.material = .metalPainted
            m.color = rng.pick([Vec3(0.2, 0.35, 0.25), Vec3(0.25, 0.3, 0.4)])
            m.addPrismZ([Vec2(-0.85, 0.15), Vec2(0.85, 0.15), Vec2(0.95, 1.25), Vec2(-0.95, 1.25)], z0: -0.75, z1: 0.75)
            m.material = .plastic
            m.color = Vec3(0.12, 0.12, 0.12)
            m.addBox(min: Vec3(-0.97, 1.25, -0.77), max: Vec3(0.97, 1.32, 0.77))
            m.material = .rubber
            for (x, z) in [(Float(-0.7), Float(-0.6)), (0.7, -0.6), (-0.7, 0.6), (0.7, 0.6)] {
                m.addBox(min: Vec3(x - 0.06, 0, z - 0.06), max: Vec3(x + 0.06, 0.15, z + 0.06))
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.95, 0, -0.77), max: Vec3(0.95, 1.32, 0.77)), flags: .lowCover, surface: .metal))
            p.lootSpots.append(LootSpotSpec(position: Vec3(0, 0, 1.1), category: .living, yaw: 1, large: true))
            p.radius = 1.3
        case .busStop:
            m.material = .metalPainted
            m.color = Vec3(0.3, 0.35, 0.4)
            for (x, z) in [(Float(-1.5), Float(-0.6)), (1.5, -0.6), (-1.5, 0.6), (1.5, 0.6)] {
                m.addBox(min: Vec3(x - 0.04, 0, z - 0.04), max: Vec3(x + 0.04, 2.4, z + 0.04))
            }
            m.addBox(min: Vec3(-1.7, 2.4, -0.8), max: Vec3(1.7, 2.5, 0.8))
            m.material = .glass
            m.color = Vec3(0.5, 0.58, 0.6)
            m.flags = 16
            m.addBox(min: Vec3(-1.5, 0.3, -0.62), max: Vec3(1.5, 2.3, -0.6))
            m.flags = 0
            m.material = .woodPlanks
            m.color = Vec3(0.5, 0.36, 0.22)
            m.addBox(min: Vec3(-1.2, 0.45, -0.58), max: Vec3(1.2, 0.5, -0.25))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.55, 0, -0.65), max: Vec3(1.55, 2.4, -0.55)), flags: [.solid, .blocksBullets], surface: .glass))
            p.lootSpots.append(LootSpotSpec(position: Vec3(0.4, 0.5, -0.4), category: .living, yaw: 0, large: false))
            p.radius = 2
        case .waterWell:
            m.material = .rock
            m.color = Vec3(0.6, 0.58, 0.55)
            m.uvScale = 1.5
            m.addCylinder(center: Vec3(0, -0.3, 0), radiusBottom: 0.8, radiusTop: 0.8, height: 1.1, segments: 14, capTop: false)
            m.material = .plastic
            m.color = Vec3(0.05, 0.08, 0.1)
            m.addDisc(center: Vec3(0, 0.6, 0), radius: 0.65, up: true, segments: 14)
            m.material = .woodDark
            m.color = Vec3(0.4, 0.3, 0.2)
            m.addBox(min: Vec3(-0.75, 0.8, -0.06), max: Vec3(-0.65, 2.2, 0.06))
            m.addBox(min: Vec3(0.65, 0.8, -0.06), max: Vec3(0.75, 2.2, 0.06))
            m.addBox(min: Vec3(-0.75, 1.8, -0.04), max: Vec3(0.75, 1.88, 0.04))
            m.material = .roofTiles
            m.color = Vec3(0.4, 0.25, 0.2)
            m.addGableRoof(minX: -0.6, maxX: 0.6, minZ: -0.9, maxZ: 0.9, baseY: 2.1, ridgeHeight: 0.6, overhang: 0.1, thickness: 0.05)
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.8, -0.3, -0.8), max: Vec3(0.8, 0.8, 0.8)), flags: .lowCover, surface: .concrete))
            p.waterPoint = Vec3(0, 0.8, 0)
            p.radius = 1.2
        case .waterPump:
            m.material = .metalPainted
            m.color = Vec3(0.2, 0.32, 0.25)
            m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.1, radiusTop: 0.09, height: 1.1, segments: 8)
            m.addBox(min: Vec3(-0.04, 0.75, 0.05), max: Vec3(0.04, 0.82, 0.32))
            m.addBox(min: Vec3(-0.03, 1.05, -0.5), max: Vec3(0.03, 1.1, 0.05))
            m.material = .concrete
            m.color = Vec3(0.55, 0.55, 0.52)
            m.addBox(min: Vec3(-0.4, -0.2, -0.3), max: Vec3(0.4, 0.05, 0.6))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.12, 0, -0.12), max: Vec3(0.12, 1.1, 0.12)), flags: [.solid], surface: .metal))
            p.waterPoint = Vec3(0, 0.6, 0.35)
            p.radius = 0.8
        case .roundBale:
            m.material = .burlap
            m.color = Vec3(0.85, 0.75, 0.45)
            m.uvScale = 1.5
            m.withTransform(Mat4.translation(Vec3(0, 0.7, -0.6)) * Mat4.rotationX(kPi * 0.5)) {
                m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.7, radiusTop: 0.7, height: 1.2, segments: 14)
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.7, 0, -0.6), max: Vec3(0.7, 1.4, 0.6)), flags: [.solid, .blocksBullets], surface: .fabric))
            p.radius = 1
        case .fuelTank:
            m.material = .metalPainted
            m.color = Vec3(0.82, 0.82, 0.8)
            m.withTransform(Mat4.translation(Vec3(0, 1.6, -3.5)) * Mat4.rotationX(kPi * 0.5)) {
                m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 1.3, radiusTop: 1.3, height: 7, segments: 18)
            }
            m.color = Vec3(0.3, 0.3, 0.3)
            for z in [Float(-2.5), 2.5] {
                m.addBox(min: Vec3(-1.0, -0.2, z - 0.2), max: Vec3(1.0, 0.6, z + 0.2))
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.3, -0.2, -3.5), max: Vec3(1.3, 2.9, 3.5)), flags: .wall, surface: .metal))
            p.radius = 4
        case .roadSign:
            m.material = .metalPainted
            m.color = Vec3(0.6, 0.6, 0.6)
            m.addBox(min: Vec3(-0.04, -0.3, -0.04), max: Vec3(0.04, 2.3, 0.04))
            m.color = rng.pick([Vec3(0.15, 0.35, 0.65), Vec3(0.8, 0.12, 0.1), Vec3(0.9, 0.75, 0.15)])
            m.addBox(min: Vec3(-0.03, 1.7, -0.45), max: Vec3(0.03, 2.3, 0.45))
            m.color = Vec3(0.9, 0.9, 0.9)
            m.addBox(min: Vec3(0.03, 1.85, -0.35), max: Vec3(0.035, 2.15, 0.35))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.05, -0.3, -0.05), max: Vec3(0.05, 2.3, 0.05)), flags: [.solid], surface: .metal))
            p.radius = 2.5
        case .picnicTable:
            m.material = .woodPlanks
            m.color = Vec3(0.55, 0.42, 0.28)
            m.addBox(min: Vec3(-0.4, 0.72, -1.0), max: Vec3(0.4, 0.77, 1.0))
            m.addBox(min: Vec3(-0.75, 0.42, -1.0), max: Vec3(-0.5, 0.46, 1.0))
            m.addBox(min: Vec3(0.5, 0.42, -1.0), max: Vec3(0.75, 0.46, 1.0))
            for z in [Float(-0.8), 0.8] {
                m.addBox(min: Vec3(-0.7, 0, z - 0.04), max: Vec3(0.7, 0.1, z + 0.04))
                m.addBox(min: Vec3(-0.05, 0.1, z - 0.04), max: Vec3(0.05, 0.72, z + 0.04))
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.75, 0, -1.0), max: Vec3(0.75, 0.77, 1.0)), flags: [.solid, .vaultable], surface: .wood))
            p.lootSpots.append(LootSpotSpec(position: Vec3(0.1, 0.77, 0.3), category: .living, yaw: 0.5, large: false))
            p.radius = 1.2
        case .firewood:
            m.material = .bark
            m.color = Vec3(0.55, 0.45, 0.35)
            for row in 0..<3 {
                for i in 0..<(5 - row) {
                    let x = -0.6 + Float(i) * 0.25 + Float(row) * 0.12
                    m.withTransform(Mat4.translation(Vec3(x, 0.12 + Float(row) * 0.22, -0.5)) * Mat4.rotationX(kPi * 0.5)) {
                        m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.11, radiusTop: 0.11, height: 1.0, segments: 7)
                    }
                }
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.65, 0, -0.5), max: Vec3(0.65, 0.7, 0.5)), flags: .lowCover, surface: .wood))
            p.radius = 0.9
        case .boulder:
            m.material = .rock
            m.color = Vec3(0.55, 0.54, 0.52)
            m.uvScale = 0.6
            m.addEllipsoid(center: Vec3(0, 0.4, 0), radii: Vec3(1.6, 1.1, 1.3), rings: 7, segments: 11, jitter: 0.35, seed: 5)
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.3, -0.5, -1.0), max: Vec3(1.3, 1.4, 1.0)), flags: .wall, surface: .concrete))
            p.radius = 1.8
        case .trafficCone:
            m.material = .plastic
            m.color = Vec3(0.95, 0.4, 0.05)
            m.addCylinder(center: Vec3(0, 0.03, 0), radiusBottom: 0.15, radiusTop: 0.025, height: 0.68, segments: 10)
            m.addBox(min: Vec3(-0.2, 0, -0.2), max: Vec3(0.2, 0.03, 0.2))
            m.color = Vec3(0.95, 0.95, 0.95)
            m.addCylinder(center: Vec3(0, 0.35, 0), radiusBottom: 0.095, radiusTop: 0.075, height: 0.1, segments: 10, capTop: false, capBottom: false)
            p.radius = 0.4
        case .palletStack:
            m.material = .woodPlanks
            m.color = Vec3(0.62, 0.52, 0.38)
            for i in 0..<6 {
                let y = Float(i) * 0.15
                m.addBox(min: Vec3(-0.6, y + 0.1, -0.5), max: Vec3(0.6, y + 0.14, 0.5))
                for z in [Float(-0.45), 0, 0.45] {
                    m.addBox(min: Vec3(-0.6, y, z - 0.05), max: Vec3(0.6, y + 0.1, z + 0.05))
                }
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.6, 0, -0.5), max: Vec3(0.6, 0.9, 0.5)), flags: .lowCover, surface: .wood))
            p.radius = 0.9
        case .tireStack:
            m.material = .rubber
            m.color = Vec3(0.1, 0.1, 0.1)
            for i in 0..<4 {
                m.addCylinder(center: Vec3(0, Float(i) * 0.24, 0), radiusBottom: 0.36, radiusTop: 0.36, height: 0.23, segments: 12)
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.36, 0, -0.36), max: Vec3(0.36, 0.95, 0.36)), flags: .lowCover, surface: .dirt))
            p.radius = 0.5
        case .cableSpool:
            m.material = .woodPlanks
            m.color = Vec3(0.55, 0.45, 0.32)
            m.withTransform(Mat4.translation(Vec3(0, 0.75, -0.5)) * Mat4.rotationX(kPi * 0.5)) {
                m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.75, radiusTop: 0.75, height: 0.08, segments: 14)
                m.addCylinder(center: Vec3(0, 0.92, 0), radiusBottom: 0.75, radiusTop: 0.75, height: 0.08, segments: 14)
                m.material = .rubber
                m.color = Vec3(0.12, 0.12, 0.12)
                m.addCylinder(center: Vec3(0, 0.08, 0), radiusBottom: 0.55, radiusTop: 0.55, height: 0.84, segments: 12, capTop: false, capBottom: false)
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.75, 0, -0.5), max: Vec3(0.75, 1.5, 0.5)), flags: [.solid, .blocksBullets], surface: .wood))
            p.radius = 1
        case .crateStack:
            m.material = .woodPlanks
            m.color = Vec3(0.55, 0.45, 0.32)
            m.addBox(min: Vec3(-1.0, 0, -0.45), max: Vec3(0, 0.9, 0.45))
            m.addBox(min: Vec3(0.05, 0, -0.45), max: Vec3(1.05, 0.9, 0.45))
            m.color = Vec3(0.35, 0.4, 0.28)
            m.addBox(min: Vec3(-0.5, 0.9, -0.4), max: Vec3(0.5, 1.6, 0.4))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.0, 0, -0.45), max: Vec3(1.05, 0.9, 0.45)), flags: .lowCover, surface: .wood))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.5, 0.9, -0.4), max: Vec3(0.5, 1.6, 0.4)), flags: .furniture, surface: .wood))
            p.lootSpots.append(LootSpotSpec(position: Vec3(0.6, 0.9, 0), category: .military, yaw: 0, large: false))
            p.radius = 1.2
        case .oilDrums:
            for (x, z, c) in [(Float(-0.32), Float(-0.3), Vec3(0.2, 0.32, 0.55)), (0.32, -0.3, Vec3(0.55, 0.15, 0.1)), (0, 0.28, Vec3(0.3, 0.35, 0.25))] {
                m.material = .metalPainted
                m.color = c
                m.addCylinder(center: Vec3(x, 0, z), radiusBottom: 0.29, radiusTop: 0.29, height: 0.9, segments: 12)
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-0.62, 0, -0.6), max: Vec3(0.62, 0.9, 0.58)), flags: .lowCover, surface: .metal))
            p.radius = 0.8
        case .playground:
            m.material = .metalPainted
            m.color = Vec3(0.75, 0.2, 0.15)
            for (x, z) in [(Float(-1.5), Float(-0.8)), (1.5, -0.8), (-1.5, 0.8), (1.5, 0.8)] {
                m.addBox(min: Vec3(x - 0.05, 0, z - 0.05), max: Vec3(x + 0.05, 2.2, z + 0.05))
            }
            m.addBox(min: Vec3(-1.55, 2.2, -0.05), max: Vec3(1.55, 2.28, 0.05))
            m.color = Vec3(0.2, 0.2, 0.2)
            for x in [Float(-0.7), 0.7] {
                m.addBox(min: Vec3(x - 0.01, 0.5, -0.01), max: Vec3(x + 0.01, 2.2, 0.01))
                m.addBox(min: Vec3(x - 0.25, 0.45, -0.1), max: Vec3(x + 0.25, 0.5, 0.1))
            }
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.55, 0, -0.85), max: Vec3(-1.45, 2.3, 0.85)), flags: [.solid], surface: .metal))
            p.colliders.append(LocalCollider(box: AABB(min: Vec3(1.45, 0, -0.85), max: Vec3(1.55, 2.3, 0.85)), flags: [.solid], surface: .metal))
            p.radius = 2
        }
        if type.isVehicle {
            // Loot lying beside the vehicle.
            p.lootSpots.append(LootSpotSpec(position: Vec3(1.4, 0, 0.6), category: .vehicle, yaw: 0.4, large: true))
            p.lootSpots.append(LootSpotSpec(position: Vec3(-1.3, 0, -1.2), category: .vehicle, yaw: 2.1, large: false))
        }
        return p
    }

    // MARK: Vehicles

    /// Generic road vehicle: body and cabin side profiles (X forward, Y up) extruded across the width.
    static func vehicle(_ p: PropModel, length: Float, width: Float, wheelR: Float, color: Vec3,
                        body: [(Float, Float)], cabin: [(Float, Float)], wheelX: [Float], rng: inout RNG,
                        cabinWidthInset: Float = 0.08, burnt: Bool = false) {
        let m = p.mesh
        let hw = width * 0.5
        let paint = burnt ? color : color * rng.range(0.8, 1.1)
        m.withTransform(Mat4.rotationY(kPi * 0.5)) {
            m.material = burnt ? .rust : .metalPainted
            m.color = paint
            m.uvScale = 0.6
            m.addPrismZ(body.map { Vec2($0.0, $0.1) }, z0: -hw, z1: hw)
            // Cabin glass and roof.
            m.material = .glass
            m.color = burnt ? Vec3(0.05, 0.05, 0.05) : Vec3(0.2, 0.25, 0.3)
            m.flags = 16
            m.addPrismZ(cabin.map { Vec2($0.0, $0.1) }, z0: -hw + cabinWidthInset, z1: hw - cabinWidthInset)
            m.flags = 0
            // Roof panel following the top edge of the cabin.
            let top = cabin.max { $0.1 < $1.1 }!.1
            let tops = cabin.filter { $0.1 > top - 0.1 }
            if let minX = tops.map({ $0.0 }).min(), let maxX = tops.map({ $0.0 }).max() {
                m.material = burnt ? .rust : .metalPainted
                m.color = paint
                m.addBox(min: Vec3(minX - 0.05, top - 0.04, -hw + cabinWidthInset - 0.02), max: Vec3(maxX + 0.05, top + 0.03, hw - cabinWidthInset + 0.02))
            }
            // Bumpers and lights.
            let frontX = body.map { $0.0 }.max()!, rearX = body.map { $0.0 }.min()!
            let low = body.map { $0.1 }.min()!
            m.material = .plastic
            m.color = Vec3(0.08, 0.08, 0.08)
            m.addBox(min: Vec3(frontX - 0.1, low + 0.02, -hw + 0.05), max: Vec3(frontX + 0.06, low + 0.2, hw - 0.05))
            m.addBox(min: Vec3(rearX - 0.06, low + 0.02, -hw + 0.05), max: Vec3(rearX + 0.1, low + 0.2, hw - 0.05))
            m.material = .glass
            m.color = burnt ? Vec3(0.1, 0.1, 0.1) : Vec3(0.9, 0.9, 0.8)
            m.addBox(min: Vec3(frontX - 0.04, low + 0.3, -hw + 0.12), max: Vec3(frontX + 0.03, low + 0.42, -hw + 0.38))
            m.addBox(min: Vec3(frontX - 0.04, low + 0.3, hw - 0.38), max: Vec3(frontX + 0.03, low + 0.42, hw - 0.12))
            m.color = burnt ? Vec3(0.1, 0.1, 0.1) : Vec3(0.7, 0.05, 0.05)
            m.addBox(min: Vec3(rearX - 0.03, low + 0.3, -hw + 0.1), max: Vec3(rearX + 0.04, low + 0.45, -hw + 0.3))
            m.addBox(min: Vec3(rearX - 0.03, low + 0.3, hw - 0.3), max: Vec3(rearX + 0.04, low + 0.45, hw - 0.1))
            // Wheels.
            let flat = rng.int(0, 3)
            var wi = 0
            for wx in wheelX {
                for side in [Float(-1), 1] {
                    let r = (wi == flat && !burnt) ? wheelR * 0.82 : wheelR
                    let z = side * (hw - 0.12)
                    m.withTransform(Mat4.translation(Vec3(wx, r, z)) * Mat4.rotationX(kPi * 0.5)) {
                        m.material = .rubber
                        m.color = Vec3(0.09, 0.09, 0.09)
                        m.addCylinder(center: Vec3(0, -0.12, 0), radiusBottom: r, radiusTop: r, height: 0.24, segments: 14)
                        m.material = .gunMetal
                        m.color = burnt ? Vec3(0.2, 0.15, 0.12) : Vec3(0.6, 0.6, 0.62)
                        m.addCylinder(center: Vec3(0, side > 0 ? 0.12 : -0.125, 0), radiusBottom: r * 0.55, radiusTop: r * 0.55, height: 0.005, segments: 10)
                    }
                    wi += 1
                }
            }
        }
        // Collider: body + cabin (vehicle local X forward becomes -Z after the 90 degree rotation).
        let bodyTop = body.map { $0.1 }.max()!
        let cabTop = cabin.map { $0.1 }.max()!
        let rot = Mat4.rotationY(kPi * 0.5)
        let bodyBox = AABB(min: Vec3(-length * 0.5, 0, -hw), max: Vec3(length * 0.5, bodyTop, hw)).transformed(rot)
        p.colliders.append(LocalCollider(box: bodyBox, flags: .lowCover, surface: .metal))
        let cx0 = cabin.map { $0.0 }.min()!, cx1 = cabin.map { $0.0 }.max()!
        let cabBox = AABB(min: Vec3(cx0, bodyTop - 0.05, -hw + 0.1), max: Vec3(cx1, cabTop, hw - 0.1)).transformed(rot)
        p.colliders.append(LocalCollider(box: cabBox, flags: [.solid, .blocksSight, .vaultable], surface: .metal))
        p.radius = length * 0.5 + 0.5
    }

    static func militaryTruck(_ p: PropModel) {
        let m = p.mesh
        let olive = Vec3(0.3, 0.34, 0.24)
        m.withTransform(Mat4.rotationY(kPi * 0.5)) {
            m.material = .metalPainted
            m.color = olive
            // Chassis.
            m.addBox(min: Vec3(-3.3, 0.7, -1.0), max: Vec3(3.3, 1.0, 1.0))
            // Cab.
            m.addPrismZ([Vec2(1.6, 1.0), Vec2(3.4, 1.0), Vec2(3.4, 1.8), Vec2(3.0, 2.6), Vec2(1.6, 2.65)], z0: -1.15, z1: 1.15)
            m.material = .glass
            m.color = Vec3(0.18, 0.22, 0.25)
            m.flags = 16
            m.addBox(min: Vec3(2.9, 1.95, -1.0), max: Vec3(3.25, 2.5, 1.0))
            m.flags = 0
            // Cargo bed with canvas cover.
            m.material = .woodPlanks
            m.color = Vec3(0.35, 0.36, 0.28)
            m.addBox(min: Vec3(-3.4, 1.0, -1.2), max: Vec3(1.5, 1.6, 1.2))
            m.material = .canvas
            m.color = Vec3(0.36, 0.38, 0.28)
            m.addPrismZ([Vec2(-3.4, 1.6), Vec2(1.5, 1.6), Vec2(1.5, 2.9), Vec2(1.2, 3.2), Vec2(-3.1, 3.2), Vec2(-3.4, 2.9)], z0: -1.2, z1: 1.2)
            m.material = .plastic
            m.color = Vec3(0.1, 0.1, 0.1)
            m.addBox(min: Vec3(3.35, 0.6, -1.1), max: Vec3(3.5, 0.95, 1.1))
            for wx in [Float(2.5), -1.5, -2.8] {
                for side in [Float(-1), 1] {
                    m.withTransform(Mat4.translation(Vec3(wx, 0.55, side * 0.95)) * Mat4.rotationX(kPi * 0.5)) {
                        m.material = .rubber
                        m.color = Vec3(0.08, 0.08, 0.08)
                        m.addCylinder(center: Vec3(0, -0.17, 0), radiusBottom: 0.55, radiusTop: 0.55, height: 0.34, segments: 14)
                        m.material = .metalPainted
                        m.color = olive * 0.8
                        m.addCylinder(center: Vec3(0, side > 0 ? 0.17 : -0.175, 0), radiusBottom: 0.3, radiusTop: 0.3, height: 0.005, segments: 10)
                    }
                }
            }
        }
        let rot = Mat4.rotationY(kPi * 0.5)
        p.colliders.append(LocalCollider(box: AABB(min: Vec3(-3.4, 0, -1.2), max: Vec3(3.5, 3.2, 1.2)).transformed(rot), flags: .wall, surface: .metal))
        p.lootSpots.append(LootSpotSpec(position: Vec3(1.6, 0, 0.5), category: .military, yaw: 0, large: true))
        p.lootSpots.append(LootSpotSpec(position: Vec3(-1.6, 0, 2.0), category: .military, yaw: 1.2, large: false))
        p.radius = 4
    }

    static func tractor(_ p: PropModel) {
        let m = p.mesh
        m.withTransform(Mat4.rotationY(kPi * 0.5)) {
            m.material = .metalPainted
            m.color = Vec3(0.2, 0.45, 0.2)
            m.addBox(min: Vec3(-0.3, 0.7, -0.45), max: Vec3(1.8, 1.5, 0.45))
            m.addBox(min: Vec3(-1.3, 0.8, -0.6), max: Vec3(-0.3, 1.3, 0.6))
            m.material = .glass
            m.color = Vec3(0.2, 0.25, 0.28)
            m.flags = 16
            m.addBox(min: Vec3(-1.3, 1.3, -0.6), max: Vec3(-0.2, 2.5, 0.6))
            m.flags = 0
            m.material = .metalPainted
            m.color = Vec3(0.2, 0.45, 0.2)
            m.addBox(min: Vec3(-1.35, 2.5, -0.65), max: Vec3(-0.15, 2.6, 0.65))
            m.color = Vec3(0.25, 0.25, 0.25)
            m.addCylinder(center: Vec3(1.2, 1.5, 0), radiusBottom: 0.06, radiusTop: 0.06, height: 0.9, segments: 6)
            for (wx, r, wz) in [(Float(-0.9), Float(0.75), Float(0.9)), (1.4, 0.42, 0.75)] {
                for side in [Float(-1), 1] {
                    m.withTransform(Mat4.translation(Vec3(wx, r, side * wz)) * Mat4.rotationX(kPi * 0.5)) {
                        m.material = .rubber
                        m.color = Vec3(0.08, 0.08, 0.08)
                        m.addCylinder(center: Vec3(0, -0.2, 0), radiusBottom: r, radiusTop: r, height: 0.4, segments: 16)
                        m.material = .metalPainted
                        m.color = Vec3(0.85, 0.7, 0.1)
                        m.addCylinder(center: Vec3(0, side > 0 ? 0.2 : -0.205, 0), radiusBottom: r * 0.6, radiusTop: r * 0.6, height: 0.005, segments: 10)
                    }
                }
            }
        }
        let rot = Mat4.rotationY(kPi * 0.5)
        p.colliders.append(LocalCollider(box: AABB(min: Vec3(-1.7, 0, -1.3), max: Vec3(1.9, 2.6, 1.3)).transformed(rot), flags: .wall, surface: .metal))
        p.lootSpots.append(LootSpotSpec(position: Vec3(1.6, 0, 0.3), category: .farm, yaw: 0.2, large: true))
        p.radius = 2.5
    }

    static func apc(_ p: PropModel) {
        let m = p.mesh
        let col = Vec3(0.32, 0.36, 0.26)
        m.withTransform(Mat4.rotationY(kPi * 0.5)) {
            m.material = .camo
            m.color = col
            m.uvScale = 0.4
            m.addPrismZ([Vec2(-3.6, 0.6), Vec2(3.0, 0.6), Vec2(3.8, 1.3), Vec2(3.2, 2.0), Vec2(-3.5, 2.1), Vec2(-3.7, 1.5)], z0: -1.4, z1: 1.4)
            m.addCylinder(center: Vec3(0.2, 2.1, 0), radiusBottom: 0.85, radiusTop: 0.7, height: 0.5, segments: 12)
            m.material = .gunMetal
            m.color = Vec3(0.2, 0.22, 0.2)
            m.withTransform(Mat4.translation(Vec3(0.9, 2.35, 0)) * Mat4.rotationZ(-kPi * 0.5)) {
                m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.07, radiusTop: 0.06, height: 2.4, segments: 8)
            }
            for wx in [Float(2.6), 1.0, -0.8, -2.5] {
                for side in [Float(-1), 1] {
                    m.withTransform(Mat4.translation(Vec3(wx, 0.6, side * 1.3)) * Mat4.rotationX(kPi * 0.5)) {
                        m.material = .rubber
                        m.color = Vec3(0.08, 0.08, 0.08)
                        m.addCylinder(center: Vec3(0, -0.2, 0), radiusBottom: 0.6, radiusTop: 0.6, height: 0.4, segments: 14)
                    }
                }
            }
        }
        let rot = Mat4.rotationY(kPi * 0.5)
        p.colliders.append(LocalCollider(box: AABB(min: Vec3(-3.7, 0, -1.5), max: Vec3(3.8, 2.6, 1.5)).transformed(rot), flags: .wall, surface: .metal))
        p.lootSpots.append(LootSpotSpec(position: Vec3(1.8, 0, 1.0), category: .military, yaw: 0.8, large: true))
        p.radius = 4
    }
}

struct PropInstance {
    var type: PropType
    var position: Vec3
    var yaw: Float
    var tint: Vec3

    var transform: Mat4 { Mat4.translation(position) * Mat4.rotationY(yaw) }
}
