//
//  BuildingTypes.swift
//  Ashvale
//
//  Concrete building designs. Every building is fully enterable: real door
//  and window openings, interior walls, floors, ceilings, stairs, furniture,
//  collision and physical loot spots.
//

import Foundation

enum BuildingType: Int, CaseIterable, Codable {
    case houseSmall, houseTwoStory, apartment, police, hospital, shop, warehouse, barracks
    case garage, barn, gasStation, tent, guardBooth, container, shed, factory

    var footprint: Vec2 {
        switch self {
        case .houseSmall: return Vec2(8, 9)
        case .houseTwoStory: return Vec2(9, 10)
        case .apartment: return Vec2(22, 12)
        case .police: return Vec2(18, 14)
        case .hospital: return Vec2(26, 16)
        case .shop: return Vec2(14, 12)
        case .warehouse: return Vec2(24, 18)
        case .barracks: return Vec2(22, 9)
        case .garage: return Vec2(6, 7)
        case .barn: return Vec2(12, 16)
        case .gasStation: return Vec2(14, 20)
        case .tent: return Vec2(6, 8)
        case .guardBooth: return Vec2(3, 3)
        case .container: return Vec2(2.44, 6.1)
        case .shed: return Vec2(4, 4)
        case .factory: return Vec2(30, 20)
        }
    }

    var variantCount: Int {
        switch self {
        case .houseSmall, .houseTwoStory: return 3
        case .garage, .tent, .container, .shed: return 2
        default: return 1
        }
    }

    var displayName: String {
        switch self {
        case .houseSmall: return "House"
        case .houseTwoStory: return "Family House"
        case .apartment: return "Apartment Block"
        case .police: return "Police Station"
        case .hospital: return "Hospital"
        case .shop: return "Grocery Store"
        case .warehouse: return "Warehouse"
        case .barracks: return "Barracks"
        case .garage: return "Garage"
        case .barn: return "Barn"
        case .gasStation: return "Gas Station"
        case .tent: return "Military Tent"
        case .guardBooth: return "Guard Post"
        case .container: return "Shipping Container"
        case .shed: return "Shed"
        case .factory: return "Factory Hall"
        }
    }
}

enum BuildingFactory {

    static func make(_ type: BuildingType, variant: Int) -> BuildingModel {
        let model = BuildingModel()
        let seed = stableHash("building-\(type.rawValue)-\(variant)")
        switch type {
        case .houseSmall: houseSmall(model, seed, variant)
        case .houseTwoStory: houseTwoStory(model, seed, variant)
        case .apartment: apartment(model, seed)
        case .police: police(model, seed)
        case .hospital: hospital(model, seed)
        case .shop: shop(model, seed)
        case .warehouse: warehouse(model, seed, factory: false)
        case .factory: warehouse(model, seed, factory: true)
        case .barracks: barracks(model, seed)
        case .garage: garage(model, seed, variant)
        case .barn: barn(model, seed)
        case .gasStation: gasStation(model, seed)
        case .tent: tent(model, seed, variant)
        case .guardBooth: guardBooth(model, seed)
        case .container: container(model, seed, variant)
        case .shed: shed(model, seed)
        }
        model.footprint = type.footprint
        return model
    }

    // MARK: Helpers

    static func floorFinish(_ b: BuildingBuilder, _ r: Room, _ mat: Mat, _ color: Vec3) {
        let m = b.model.interior
        m.material = mat
        m.color = color
        m.skyVisibility = 0.5
        m.flags = 0
        m.uvScale = mat == .floorTiles ? 1.0 : 0.6
        m.addBox(min: Vec3(r.x0, r.floorY + 0.002, r.z0), max: Vec3(r.x1, r.floorY + 0.006, r.z1), faces: [.posY])
    }

    static func residentialStyle(_ b: BuildingBuilder) {
        var r = b.rng
        b.style.exteriorMat = r.chance(0.3) ? .brick : .plaster
        b.style.exteriorColor = b.style.exteriorMat == .brick ? Vec3(0.75, 0.62, 0.55) : Vec3(0.92, 0.9, 0.86)
        b.style.interiorMat = .wallpaper
        b.style.interiorColor = r.pick([Vec3(0.85, 0.8, 0.7), Vec3(0.75, 0.8, 0.78), Vec3(0.88, 0.85, 0.8), Vec3(0.8, 0.74, 0.68)])
        b.style.trimColor = r.pick([Vec3(0.95, 0.95, 0.92), Vec3(0.45, 0.3, 0.2), Vec3(0.3, 0.35, 0.3)])
        b.style.tintableExterior = b.style.exteriorMat == .plaster
        b.rng = r
    }

    static func roofColor(_ r: inout RNG) -> Vec3 {
        r.pick([Vec3(0.55, 0.25, 0.2), Vec3(0.35, 0.33, 0.33), Vec3(0.3, 0.35, 0.4), Vec3(0.45, 0.3, 0.22)])
    }

    // MARK: Small house

    static func houseSmall(_ model: BuildingModel, _ seed: UInt64, _ variant: Int) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.8)
        residentialStyle(b)
        let W: Float = 8, D: Float = 9, FH: Float = 2.8
        b.plinth(w: W, d: D)
        let flip: Float = variant == 1 ? -1 : 1
        var leftOps: [Opening] = [Opening.window(2.3), Opening.window(-2.0)]
        var rightOps: [Opening] = [Opening.window(-2.5, width: 0.6, bottom: 1.4)]
        if flip < 0 { leftOps.append(Opening.door(1.6)) } else { rightOps.append(Opening.door(1.6)) }
        // Exterior walls.
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [Opening.door(-1.5 * flip), Opening.window(-3.0 * flip, width: 1.0), Opening.window(2.2 * flip)],
                        back: [Opening.window(-1.5 * flip), Opening.window(2.6 * flip, width: 0.6, bottom: 1.4)],
                        left: leftOps,
                        right: rightOps)
        b.doorStep(at: Vec3(-1.5 * flip, 0, D * 0.5), axis: .x, outwardSign: 1)
        // Interior walls.
        let it: Float = 0.12
        b.wall(axis: .x, fixed: 0.4, from: -3.7, to: 3.7, y0: 0, y1: FH, thickness: it, exterior: false,
               openings: [.door(-1.0 * flip, width: 0.9), .door(2.6 * flip, width: 0.9)])
        b.wall(axis: .z, fixed: 0.6 * flip, from: 0.46, to: 4.2, y0: 0, y1: FH, thickness: it, exterior: false, openings: [.doorway(2.6)])
        b.wall(axis: .z, fixed: 1.5 * flip, from: -4.2, to: 0.34, y0: 0, y1: FH, thickness: it, exterior: false)
        // Floors and ceiling.
        b.slab(x0: -3.7, x1: 3.7, z0: -4.2, z1: 4.2, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.slab(x0: -3.7, x1: 3.7, z0: -4.2, z1: 4.2, top: FH + 0.2, thickness: 0.2, floorMat: .woodPlanks, floorColor: Vec3(0.5, 0.42, 0.33))
        func rx(_ a: Float, _ c: Float) -> (Float, Float) { flip > 0 ? (a, c) : (-c, -a) }
        let (lx0, lx1) = rx(-3.7, 0.54), (kx0, kx1) = rx(0.66, 3.7)
        let (bx0, bx1) = rx(-3.7, 1.44), (wx0, wx1) = rx(1.56, 3.7)
        let living = Room(x0: lx0, x1: lx1, z0: 0.46, z1: 4.2, floorY: 0, type: .living)
        let kitchen = Room(x0: kx0, x1: kx1, z0: 0.46, z1: 4.2, floorY: 0, type: .kitchen)
        let bedroom = Room(x0: bx0, x1: bx1, z0: -4.2, z1: 0.34, floorY: 0, type: .bedroom)
        let bath = Room(x0: wx0, x1: wx1, z0: -4.2, z1: 0.34, floorY: 0, type: variant == 2 ? .storage : .bathroom)
        floorFinish(b, living, .woodPlanks, Vec3(0.62, 0.48, 0.34))
        floorFinish(b, kitchen, .floorTiles, Vec3(0.8, 0.78, 0.72))
        floorFinish(b, bedroom, .carpet, Vec3(0.5, 0.42, 0.38))
        floorFinish(b, bath, .floorTiles, Vec3(0.75, 0.8, 0.82))
        b.furnish(living); b.furnish(kitchen); b.furnish(bedroom); b.furnish(bath)
        var rr = b.rng
        b.gableRoof(w: W, d: D, baseY: FH + 0.2, ridge: 2.4, color: roofColor(&rr), ridgeAlongZ: false)
        b.rng = rr
        chimney(b, x: 2.0 * flip, z: -1.2, base: FH, top: FH + 3.6)
        model.height = FH + 2.8
    }

    static func chimney(_ b: BuildingBuilder, x: Float, z: Float, base: Float, top: Float) {
        let m = b.model.shell
        m.material = .brick
        m.color = Vec3(0.6, 0.4, 0.35)
        m.flags = 0
        m.uvScale = 1
        m.addBox(min: Vec3(x - 0.3, base, z - 0.3), max: Vec3(x + 0.3, top, z + 0.3))
    }

    // MARK: Two-story house

    static func houseTwoStory(_ model: BuildingModel, _ seed: UInt64, _ variant: Int) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.9)
        residentialStyle(b)
        let W: Float = 9, D: Float = 10, FH: Float = 2.9
        b.plinth(w: W, d: D)
        // Ground floor.
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [.door(3.6), .window(-2.5), .window(0.8)],
                        back: [.window(-2.5), .window(0.8)],
                        left: [.window(2.4), .window(-2.4)],
                        right: [.door(-3.0)])
        b.doorStep(at: Vec3(3.6, 0, D * 0.5), axis: .x, outwardSign: 1)
        b.doorStep(at: Vec3(W * 0.5, 0, -3.0), axis: .z, outwardSign: 1)
        let it: Float = 0.12
        b.wall(axis: .z, fixed: 2.95, from: -4.7, to: 4.7, y0: 0, y1: FH, thickness: it, exterior: false,
               openings: [.doorway(3.6), .door(-3.0, width: 0.9)])
        b.wall(axis: .x, fixed: 0, from: -4.2, to: 2.89, y0: 0, y1: FH, thickness: it, exterior: false, openings: [.doorway(-1.0, width: 1.2)])
        b.slab(x0: -4.2, x1: 4.2, z0: -4.7, z1: 4.7, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.straightStairs(x0: 3.07, x1: 4.2, zStart: 2.6, dir: -1, fromY: 0, toY: FH)
        model.stairs.append([Vec3(3.62, 0, 3.3), Vec3(3.62, FH, -2.2)])
        let living = Room(x0: -4.2, x1: 2.89, z0: 0.06, z1: 4.7, floorY: 0, type: .living)
        let kitchen = Room(x0: -4.2, x1: 2.89, z0: -4.7, z1: -0.06, floorY: 0, type: .kitchen)
        floorFinish(b, living, .woodPlanks, Vec3(0.6, 0.46, 0.32))
        floorFinish(b, kitchen, .floorTiles, Vec3(0.78, 0.76, 0.7))
        floorFinish(b, Room(x0: 3.01, x1: 4.2, z0: 2.6, z1: 4.7, floorY: 0, type: .hallway), .floorTiles, Vec3(0.6, 0.55, 0.5))
        b.furnish(living); b.furnish(kitchen)
        // Upper floor.
        let y1 = FH
        b.facadeBand(w: W, d: D, y: y1, color: Vec3(0.7, 0.68, 0.64))
        b.exteriorWalls(w: W, d: D, y0: y1, y1: y1 + FH,
                        front: [.window(-2.2), .window(1.4)],
                        back: [.window(-2.85, width: 0.6, bottom: 1.4), .window(1.5)],
                        left: [.window(1.6)],
                        right: [.window(-3.0)])
        let hole = AABB(min: Vec3(3.04, 0, -1.52), max: Vec3(4.21, 0, 2.66))
        b.slab(x0: -4.2, x1: 4.2, z0: -4.7, z1: 4.7, top: y1, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5), holes: [hole])
        b.wall(axis: .x, fixed: -1.5, from: -4.2, to: 2.95, y0: y1, y1: y1 + FH, thickness: it, exterior: false,
               openings: [.door(-0.9, width: 0.9), .door(1.4, width: 0.9)])
        b.wall(axis: .z, fixed: -0.2, from: -1.44, to: 4.7, y0: y1, y1: y1 + FH, thickness: it, exterior: false)
        b.wall(axis: .z, fixed: -1.5, from: -4.7, to: -1.56, y0: y1, y1: y1 + FH, thickness: it, exterior: false, openings: [.door(-3.1, width: 0.85)])
        b.wall(axis: .z, fixed: 2.95, from: -1.44, to: 4.7, y0: y1, y1: y1 + FH, thickness: it, exterior: false)
        b.railing(from: Vec3(3.05, y1, 2.66), to: Vec3(4.2, y1, 2.66))
        let bedA = Room(x0: -4.2, x1: -0.26, z0: -1.44, z1: 4.7, floorY: y1, type: .bedroom)
        let bedB = Room(x0: -0.14, x1: 2.89, z0: -1.44, z1: 4.7, floorY: y1, type: variant == 1 ? .office : .bedroom)
        let bath = Room(x0: -4.2, x1: -1.56, z0: -4.7, z1: -1.56, floorY: y1, type: .bathroom)
        let hall = Room(x0: -1.44, x1: 4.2, z0: -4.7, z1: -1.56, floorY: y1, type: .hallway)
        floorFinish(b, bedA, .carpet, Vec3(0.45, 0.4, 0.42))
        floorFinish(b, bedB, .woodPlanks, Vec3(0.62, 0.5, 0.36))
        floorFinish(b, bath, .floorTiles, Vec3(0.75, 0.8, 0.82))
        floorFinish(b, hall, .woodPlanks, Vec3(0.55, 0.42, 0.3))
        b.furnish(bedA); b.furnish(bedB, lootOverride: variant == 1 ? .living : nil); b.furnish(bath); b.furnish(hall)
        // Ceiling + roof.
        b.slab(x0: -4.2, x1: 4.2, z0: -4.7, z1: 4.7, top: y1 + FH + 0.2, thickness: 0.2, floorMat: .woodPlanks, floorColor: Vec3(0.5, 0.42, 0.33))
        var rr = b.rng
        b.gableRoof(w: W, d: D, baseY: y1 + FH + 0.2, ridge: 2.8, color: roofColor(&rr), ridgeAlongZ: false)
        b.rng = rr
        chimney(b, x: -2.5, z: 1.8, base: y1 + FH, top: y1 + FH + 3.9)
        model.height = 2 * FH + 3
    }

    // MARK: Apartment block

    static func apartmentUnit(_ b: BuildingBuilder, sign s: Float, y: Float, FH: Float) {
        let it: Float = 0.12
        func X(_ a: Float, _ c: Float) -> (Float, Float) { s > 0 ? (a, c) : (-c, -a) }
        // Partition walls (positive-side coordinates mirrored by s).
        b.wall(axis: .x, fixed: 0.5, from: X(1.66, 10.7).0, to: X(1.66, 10.7).1, y0: y, y1: y + FH, thickness: it, exterior: false,
               openings: [.doorway(7.8 * s, width: 0.9), .doorway(3.3 * s, width: 0.9)])
        b.wall(axis: .z, fixed: 5.0 * s, from: 0.56, to: 5.7, y0: y, y1: y + FH, thickness: it, exterior: false, openings: [.doorway(3.0, width: 1.1)])
        b.wall(axis: .z, fixed: 5.0 * s, from: -5.7, to: 0.44, y0: y, y1: y + FH, thickness: it, exterior: false)
        b.wall(axis: .x, fixed: -2.0, from: X(1.66, 4.94).0, to: X(1.66, 4.94).1, y0: y, y1: y + FH, thickness: it, exterior: false,
               openings: [.door(3.3 * s, width: 0.85)])
        let (lx0, lx1) = X(5.06, 10.7)
        let (kx0, kx1) = X(1.66, 4.94)
        let living = Room(x0: lx0, x1: lx1, z0: 0.56, z1: 5.7, floorY: y, type: .living)
        let kitchen = Room(x0: kx0, x1: kx1, z0: 0.56, z1: 5.7, floorY: y, type: .kitchen)
        let bedroom = Room(x0: lx0, x1: lx1, z0: -5.7, z1: 0.44, floorY: y, type: .bedroom)
        let bath = Room(x0: kx0, x1: kx1, z0: -5.7, z1: -2.06, floorY: y, type: .bathroom)
        let store = Room(x0: kx0, x1: kx1, z0: -1.94, z1: 0.44, floorY: y, type: .hallway)
        BuildingFactory.floorFinish(b, living, .woodPlanks, Vec3(0.58, 0.44, 0.3))
        BuildingFactory.floorFinish(b, kitchen, .linoleum, Vec3(0.7, 0.66, 0.55))
        BuildingFactory.floorFinish(b, bedroom, .carpet, Vec3(0.5, 0.45, 0.4))
        BuildingFactory.floorFinish(b, bath, .floorTiles, Vec3(0.72, 0.78, 0.8))
        BuildingFactory.floorFinish(b, store, .linoleum, Vec3(0.6, 0.58, 0.5))
        b.furnish(living); b.furnish(kitchen); b.furnish(bedroom); b.furnish(bath); b.furnish(store)
    }

    static func apartment(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.0)
        b.style.exteriorMat = .plaster
        b.style.exteriorColor = Vec3(0.82, 0.8, 0.74)
        b.style.interiorMat = .wallpaper
        b.style.interiorColor = Vec3(0.82, 0.8, 0.72)
        b.style.trimColor = Vec3(0.85, 0.85, 0.82)
        let W: Float = 22, D: Float = 12, FH: Float = 3.0, floors = 3
        b.plinth(w: W, d: D)
        let x0: Float = -1.15, w: Float = 1.1, zNear: Float = -2.4
        let hole = b.switchbackHole(x0: x0, zNear: zNear, width: w)
        for f in 0..<floors {
            let y = Float(f) * FH
            let frontOps: [Opening] = (f == 0 ? [Opening.door(0, width: 1.4, style: .metal)] : [Opening.window(0, width: 1.0)]) +
                [.window(-8.5), .window(-3.3), .window(3.3), .window(8.5)]
            b.exteriorWalls(w: W, d: D, y0: y, y1: y + FH,
                            front: frontOps,
                            back: [.window(-7.8), .window(-3.3, width: 0.6, bottom: 1.4), .window(3.3, width: 0.6, bottom: 1.4), .window(7.8)],
                            left: [.window(3.0), .window(-2.6)],
                            right: [.window(3.0), .window(-2.6)])
            if f > 0 { b.facadeBand(w: W, d: D, y: y, color: Vec3(0.6, 0.58, 0.55)) }
            // Floor slab.
            if f == 0 {
                b.slab(x0: -10.7, x1: 10.7, z0: -5.7, z1: 5.7, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
            } else {
                b.slab(x0: -10.7, x1: 10.7, z0: -5.7, z1: 5.7, top: y, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5), holes: [hole])
            }
            // Stair hall walls with apartment doors.
            b.style.interiorColor = Vec3(0.7, 0.72, 0.68)
            b.wall(axis: .z, fixed: -1.6, from: -5.7, to: 5.7, y0: y, y1: y + FH, thickness: 0.15, exterior: false, openings: [.door(2.5, width: 0.95)])
            b.wall(axis: .z, fixed: 1.6, from: -5.7, to: 5.7, y0: y, y1: y + FH, thickness: 0.15, exterior: false, openings: [.door(2.5, width: 0.95)])
            b.style.interiorColor = Vec3(0.82, 0.8, 0.72)
            BuildingFactory.floorFinish(b, Room(x0: -1.52, x1: 1.52, z0: zNear, z1: 5.7, floorY: y, type: .hallway), .floorTiles, Vec3(0.55, 0.55, 0.52))
            if f < floors - 1 {
                b.switchbackFlight(x0: x0, zNear: zNear, width: w, level: f)
            } else {
                // Top floor railings around the open stair well.
                b.railing(from: Vec3(x0, y, zNear), to: Vec3(x0 + w, y, zNear))
                b.railing(from: Vec3(x0 + w + 0.05, y, hole.min.z), to: Vec3(x0 + w + 0.05, y, zNear))
            }
            apartmentUnit(b, sign: -1, y: y, FH: FH)
            apartmentUnit(b, sign: 1, y: y, FH: FH)
            if f == 0 {
                // Mailboxes / clutter in the entrance hall.
                b.placeFurniture(.filingCabinet, at: Vec3(1.2, 0, 4.6), rotation: 3, loot: .living)
            }
        }
        b.slab(x0: -10.7, x1: 10.7, z0: -5.7, z1: 5.7, top: Float(floors) * FH, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.45, 0.45, 0.45))
        b.flatRoof(w: W, d: D, baseY: Float(floors) * FH)
        // Entrance canopy.
        let m = model.shell
        m.material = .concrete
        m.color = Vec3(0.55, 0.55, 0.55)
        m.addBox(min: Vec3(-1.6, 2.6, 6.0), max: Vec3(1.6, 2.75, 7.4))
        b.doorStep(at: Vec3(0, 0, 6), axis: .x, outwardSign: 1, width: 2.4)
        model.height = Float(floors) * FH + 1
    }

    // MARK: Police station

    static func police(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.2)
        b.style.exteriorMat = .brick
        b.style.exteriorColor = Vec3(0.62, 0.6, 0.62)
        b.style.tintableExterior = false
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.78, 0.8, 0.82)
        b.style.trimColor = Vec3(0.25, 0.28, 0.35)
        b.style.trimMat = .metalPainted
        let W: Float = 18, D: Float = 14, FH: Float = 3.2
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [.door(0, width: 1.6, style: .glass), .window(-6.3), .window(-2.5), .window(2.5), .window(6.3)],
                        back: [.window(-7.4, width: 0.6, bottom: 1.8, top: 2.4), .window(-5.2, width: 0.6, bottom: 1.8, top: 2.4),
                               .window(-3.0, width: 0.6, bottom: 1.8, top: 2.4), .door(7.6, style: .metal)],
                        left: [.window(4.0), .window(0.2)],
                        right: [.window(4.0), .window(0.2)])
        b.doorStep(at: Vec3(0, 0, D * 0.5), axis: .x, outwardSign: 1, width: 3)
        b.slab(x0: -8.7, x1: 8.7, z0: -6.7, z1: 6.7, top: 0, thickness: 0.3, floorMat: .linoleum, floorColor: Vec3(0.55, 0.57, 0.6))
        let it: Float = 0.15
        b.wall(axis: .x, fixed: 1.5, from: -8.7, to: 8.7, y0: 0, y1: FH, thickness: it, exterior: false, openings: [.door(0, width: 1.2)])
        b.wall(axis: .z, fixed: -4, from: 1.58, to: 6.7, y0: 0, y1: FH, thickness: it, exterior: false, openings: [.door(4.0, width: 0.95)])
        b.wall(axis: .z, fixed: 4, from: 1.58, to: 6.7, y0: 0, y1: FH, thickness: it, exterior: false, openings: [.door(4.0, width: 0.95)])
        // Back rooms wall with doors.
        b.wall(axis: .x, fixed: -1.0, from: -2.0, to: 8.7, y0: 0, y1: FH, thickness: it, exterior: false,
               openings: [.door(0.5, width: 0.95, style: .metal), .door(5.8, width: 0.95)])
        b.wall(axis: .z, fixed: -2.0, from: -6.7, to: -1.08, y0: 0, y1: FH, thickness: it, exterior: false)
        b.wall(axis: .z, fixed: 3.0, from: -6.7, to: -1.08, y0: 0, y1: FH, thickness: it, exterior: false)
        // Cells: three cells with barred fronts and cell doors.
        let cellEdges: [Float] = [-8.7, -6.47, -4.23, -2.0]
        for i in 0..<3 {
            let c0 = cellEdges[i], c1 = cellEdges[i + 1]
            let mid = (c0 + c1) * 0.5
            cellBars(b, x0: c0 + 0.08, x1: c1 - 0.08, z: -1.0, height: FH, doorCenter: mid)
            if i > 0 { b.wall(axis: .z, fixed: c0, from: -6.7, to: -1.05, y0: 0, y1: FH, thickness: 0.12, exterior: false) }
            b.furnish(Room(x0: c0 + 0.06, x1: c1 - 0.06, z0: -6.7, z1: -1.1, floorY: 0, type: .cell))
        }
        b.furnish(Room(x0: -3.92, x1: 3.92, z0: 1.58, z1: 6.7, floorY: 0, type: .reception), lootOverride: .police)
        b.furnish(Room(x0: -8.7, x1: -4.08, z0: 1.58, z1: 6.7, floorY: 0, type: .office), lootOverride: .police)
        b.furnish(Room(x0: 4.08, x1: 8.7, z0: 1.58, z1: 6.7, floorY: 0, type: .office), lootOverride: .police)
        b.furnish(Room(x0: -1.92, x1: 2.92, z0: -6.7, z1: -1.08, floorY: 0, type: .armory), lootOverride: .police)
        b.furnish(Room(x0: 3.08, x1: 8.7, z0: -6.7, z1: -1.08, floorY: 0, type: .storage), lootOverride: .police)
        b.slab(x0: -8.7, x1: 8.7, z0: -6.7, z1: 6.7, top: FH + 0.25, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.flatRoof(w: W, d: D, baseY: FH + 0.25)
        // Blue sign band above the entrance.
        let m = model.shell
        m.material = .metalPainted
        m.color = Vec3(0.12, 0.2, 0.45)
        m.addBox(min: Vec3(-4, 2.55, 7.0), max: Vec3(4, 3.15, 7.12))
        m.color = Vec3(0.9, 0.9, 0.92)
        for i in 0..<6 {
            let x = -2.6 + Float(i) * 1.05
            m.addBox(min: Vec3(x, 2.68, 7.12), max: Vec3(x + 0.6, 3.02, 7.14))
        }
        model.height = FH + 1
    }

    static func cellBars(_ b: BuildingBuilder, x0: Float, x1: Float, z: Float, height: Float, doorCenter: Float) {
        let m = b.model.interior
        m.material = .metalPainted
        m.color = Vec3(0.25, 0.27, 0.3)
        m.skyVisibility = 0.5
        let doorW: Float = 0.9
        let d0 = doorCenter - doorW * 0.5, d1 = doorCenter + doorW * 0.5
        var x = x0
        while x <= x1 {
            if x < d0 - 0.02 || x > d1 + 0.02 {
                m.addBox(min: Vec3(x - 0.02, 0, z - 0.02), max: Vec3(x + 0.02, height, z + 0.02))
            }
            x += 0.14
        }
        m.addBox(min: Vec3(x0, 2.2, z - 0.04), max: Vec3(x1, 2.3, z + 0.04))
        m.addBox(min: Vec3(x0, height - 0.1, z - 0.04), max: Vec3(x1, height, z + 0.04))
        b.model.addCollider(AABB(min: Vec3(x0, 0, z - 0.05), max: Vec3(d0, height, z + 0.05)), [.solid], .metal)
        b.model.addCollider(AABB(min: Vec3(d1, 0, z - 0.05), max: Vec3(x1, height, z + 0.05)), [.solid], .metal)
        b.model.addCollider(AABB(min: Vec3(d0, 2.2, z - 0.05), max: Vec3(d1, height, z + 0.05)), [.solid], .metal)
        b.model.doors.append(DoorSpec(hinge: Vec3(d0 + 0.02, 0, z), closedYaw: 0, width: doorW - 0.04, height: 2.15,
                                      openSign: -1, exterior: false, style: .cell))
    }

    // MARK: Hospital

    static func hospital(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.3)
        b.style.exteriorMat = .plaster
        b.style.exteriorColor = Vec3(0.9, 0.9, 0.88)
        b.style.tintableExterior = false
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.82, 0.88, 0.86)
        b.style.trimColor = Vec3(0.55, 0.6, 0.62)
        b.style.trimMat = .metalPainted
        let W: Float = 26, D: Float = 16, FH: Float = 3.3
        b.plinth(w: W, d: D)
        let sx0: Float = -3.6, sw: Float = 1.1, zNear: Float = -4.3
        let hole = b.switchbackHole(x0: sx0, zNear: zNear, width: sw)
        let it: Float = 0.15
        for f in 0..<2 {
            let y = Float(f) * FH
            b.exteriorWalls(w: W, d: D, y0: y, y1: y + FH,
                            front: (f == 0 ? [Opening.door(0, width: 2.0, style: .glass)] : [Opening.window(0, width: 2.0)]) +
                                [.window(-10.5), .window(-7.0), .window(-2.5), .window(2.5), .window(7.0), .window(10.5)],
                            back: [.window(-10.5), .window(-7.0), .window(2.5), .window(7.0), .window(10.5)] + (f == 0 ? [Opening.door(-6.0, style: .metal)] : []),
                            left: [.window(4.0), .window(-4.0)],
                            right: [.window(4.0), .window(-4.0)])
            if f == 0 {
                b.slab(x0: -12.7, x1: 12.7, z0: -7.7, z1: 7.7, top: 0, thickness: 0.3, floorMat: .linoleum, floorColor: Vec3(0.7, 0.76, 0.74))
            } else {
                b.facadeBand(w: W, d: D, y: y, color: Vec3(0.55, 0.62, 0.66))
                b.slab(x0: -12.7, x1: 12.7, z0: -7.7, z1: 7.7, top: y, thickness: 0.25, floorMat: .linoleum, floorColor: Vec3(0.7, 0.76, 0.74), holes: [hole])
            }
            b.wall(axis: .x, fixed: 1.0, from: -12.7, to: 12.7, y0: y, y1: y + FH, thickness: it, exterior: false,
                   openings: [.door(-8.3, width: 1.2), .doorway(0, width: f == 0 ? 3.0 : 1.2), .door(8.3, width: 1.0)])
            b.wall(axis: .x, fixed: -1.2, from: -12.7, to: 12.7, y0: y, y1: y + FH, thickness: it, exterior: false,
                   openings: [.door(-8.3, width: 1.2), .doorway(-2.45, width: 1.2), .door(2.5, width: 0.95), .door(8.8, width: 0.95)])
            b.wall(axis: .z, fixed: -4.0, from: 1.08, to: 7.7, y0: y, y1: y + FH, thickness: it, exterior: false)
            b.wall(axis: .z, fixed: 4.0, from: 1.08, to: 7.7, y0: y, y1: y + FH, thickness: it, exterior: false)
            b.wall(axis: .z, fixed: -4.0, from: -7.7, to: -1.28, y0: y, y1: y + FH, thickness: it, exterior: false)
            b.wall(axis: .z, fixed: -0.2, from: -7.7, to: -1.28, y0: y, y1: y + FH, thickness: it, exterior: false)
            b.wall(axis: .z, fixed: 5.0, from: -7.7, to: -1.28, y0: y, y1: y + FH, thickness: it, exterior: false)
            if f == 0 {
                b.switchbackFlight(x0: sx0, zNear: zNear, width: sw, level: 0)
            } else {
                b.railing(from: Vec3(sx0, y, zNear), to: Vec3(sx0 + sw, y, zNear))
                b.railing(from: Vec3(sx0 + sw + 0.05, y, hole.min.z), to: Vec3(sx0 + sw + 0.05, y, zNear))
            }
            b.furnish(Room(x0: -12.7, x1: -4.08, z0: 1.08, z1: 7.7, floorY: y, type: .ward))
            b.furnish(Room(x0: -12.7, x1: -4.08, z0: -7.7, z1: -1.28, floorY: y, type: .ward))
            if f == 0 {
                b.furnish(Room(x0: -3.92, x1: 3.92, z0: 1.08, z1: 7.7, floorY: y, type: .reception), lootOverride: .medical)
                b.furnish(Room(x0: 4.08, x1: 12.7, z0: 1.08, z1: 7.7, floorY: y, type: .pharmacy))
            } else {
                b.furnish(Room(x0: -3.92, x1: 3.92, z0: 1.08, z1: 7.7, floorY: y, type: .office), lootOverride: .medical)
                b.furnish(Room(x0: 4.08, x1: 12.7, z0: 1.08, z1: 7.7, floorY: y, type: .ward))
            }
            b.furnish(Room(x0: -0.12, x1: 4.92, z0: -7.7, z1: -1.28, floorY: y, type: .office), lootOverride: .medical)
            b.furnish(Room(x0: 5.08, x1: 12.7, z0: -7.7, z1: -1.28, floorY: y, type: .storage), lootOverride: .medical)
        }
        b.slab(x0: -12.7, x1: 12.7, z0: -7.7, z1: 7.7, top: 2 * FH, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.45, 0.45, 0.45))
        b.flatRoof(w: W, d: D, baseY: 2 * FH)
        // Red cross sign.
        let m = model.shell
        m.material = .metalPainted
        m.color = Vec3(0.95, 0.95, 0.95)
        m.addBox(min: Vec3(-1.0, 4.4, 8.05), max: Vec3(1.0, 6.0, 8.15))
        m.color = Vec3(0.8, 0.1, 0.1)
        m.addBox(min: Vec3(-0.65, 5.05, 8.15), max: Vec3(0.65, 5.35, 8.18))
        m.addBox(min: Vec3(-0.15, 4.55, 8.15), max: Vec3(0.15, 5.85, 8.18))
        m.color = Vec3(0.55, 0.55, 0.55)
        m.addBox(min: Vec3(-2.2, 2.7, 8.0), max: Vec3(2.2, 2.85, 10.0))
        for x in [Float(-2.0), 2.0] {
            m.addBox(min: Vec3(x - 0.1, -0.3, 9.8), max: Vec3(x + 0.1, 2.7, 10.0))
            model.addCollider(AABB(min: Vec3(x - 0.1, -0.3, 9.8), max: Vec3(x + 0.1, 2.7, 10.0)), .wall, .concrete)
        }
        b.doorStep(at: Vec3(0, 0, D * 0.5), axis: .x, outwardSign: 1, width: 3.5)
        model.height = 2 * FH + 1
    }

    // MARK: Shop

    static func shop(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.4)
        b.style.exteriorMat = .plaster
        b.style.exteriorColor = Vec3(0.86, 0.84, 0.78)
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.88, 0.88, 0.85)
        b.style.trimMat = .metalPainted
        b.style.trimColor = Vec3(0.3, 0.32, 0.35)
        let W: Float = 14, D: Float = 12, FH: Float = 3.4
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [.door(0, width: 1.6, style: .glass), .window(-4.0, width: 3.4, bottom: 0.5, top: 2.7), .window(4.0, width: 3.4, bottom: 0.5, top: 2.7)],
                        back: [.door(-4.0, style: .metal)],
                        left: [.window(2.5)],
                        right: [])
        b.slab(x0: -6.7, x1: 6.7, z0: -5.7, z1: 5.7, top: 0, thickness: 0.3, floorMat: .floorTiles, floorColor: Vec3(0.82, 0.8, 0.76))
        b.wall(axis: .x, fixed: -1.5, from: -6.7, to: 6.7, y0: 0, y1: FH, thickness: 0.15, exterior: false, openings: [.door(4.5, width: 1.0)])
        b.furnish(Room(x0: -6.7, x1: 6.7, z0: -1.42, z1: 5.7, floorY: 0, type: .shopFloor))
        b.furnish(Room(x0: -6.7, x1: 6.7, z0: -5.7, z1: -1.58, floorY: 0, type: .storage), lootOverride: .shop)
        b.slab(x0: -6.7, x1: 6.7, z0: -5.7, z1: 5.7, top: FH + 0.25, thickness: 0.25, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.flatRoof(w: W, d: D, baseY: FH + 0.25, parapet: 0.9)
        // Sign band and awning.
        let m = model.shell
        m.material = .metalPainted
        m.color = Vec3(0.15, 0.45, 0.25)
        m.addBox(min: Vec3(-6.5, 2.95, 6.0), max: Vec3(6.5, 3.6, 6.12))
        m.material = .canvas
        m.color = Vec3(0.2, 0.5, 0.3)
        m.addOrientedTriangle(Vec3(-6.5, 2.9, 6.0), Vec3(6.5, 2.9, 6.0), Vec3(6.5, 2.5, 7.3), want: Vec3(0, 1, 0.5))
        m.addOrientedTriangle(Vec3(-6.5, 2.9, 6.0), Vec3(6.5, 2.5, 7.3), Vec3(-6.5, 2.5, 7.3), want: Vec3(0, 1, 0.5))
        m.addOrientedTriangle(Vec3(-6.5, 2.88, 6.0), Vec3(6.5, 2.48, 7.3), Vec3(6.5, 2.88, 6.0), want: Vec3(0, -1, -0.5))
        m.addOrientedTriangle(Vec3(-6.5, 2.88, 6.0), Vec3(-6.5, 2.48, 7.3), Vec3(6.5, 2.48, 7.3), want: Vec3(0, -1, -0.5))
        b.doorStep(at: Vec3(0, 0, D * 0.5), axis: .x, outwardSign: 1, width: 2.5)
        model.height = FH + 1.2
    }

    // MARK: Warehouse / factory

    static func warehouse(_ model: BuildingModel, _ seed: UInt64, factory: Bool) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: factory ? 8 : 7)
        let W: Float = factory ? 30 : 24, D: Float = factory ? 20 : 18, FH: Float = factory ? 8 : 7
        b.style.exteriorMat = factory ? .brick : .metalCorrugated
        b.style.exteriorColor = factory ? Vec3(0.7, 0.5, 0.42) : Vec3(0.62, 0.66, 0.68)
        b.style.tintableExterior = !factory
        b.style.interiorMat = factory ? .brick : .metalCorrugated
        b.style.interiorColor = factory ? Vec3(0.6, 0.45, 0.38) : Vec3(0.55, 0.58, 0.6)
        b.style.trimMat = .metalPainted
        b.style.trimColor = Vec3(0.3, 0.32, 0.3)
        b.plinth(w: W, d: D)
        let hw = W * 0.5, hd = D * 0.5
        let backDoorX = -W * 0.3
        let highWindows: [Opening] = stride(from: -hw + 3, through: hw - 3, by: 4)
            .filter { abs($0 - backDoorX) > 2.0 }
            .map { Opening.window($0, width: 2.4, bottom: 4.4, top: 5.6) }
        let sideWindows: [Opening] = stride(from: -hd + 3, through: hd - 3, by: 4).map { Opening.window($0, width: 2.4, bottom: 4.4, top: 5.6) }
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, t: 0.3,
                        front: [.wide(-W * 0.2, width: 5, top: 4.5), .door(W * 0.25, style: .metal)],
                        back: highWindows + [Opening.door(backDoorX, style: .metal)],
                        left: sideWindows,
                        right: sideWindows)
        b.slab(x0: -hw + 0.3, x1: hw - 0.3, z0: -hd + 0.3, z1: hd - 0.3, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.55, 0.55, 0.53))
        // Office block in the back-right corner.
        let ox0 = hw - 6.5, oz1 = -hd + 6.0
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.8, 0.8, 0.76)
        b.wall(axis: .x, fixed: oz1, from: ox0, to: hw - 0.3, y0: 0, y1: 3.0, thickness: 0.15, exterior: false, openings: [.door(ox0 + 1.5, width: 0.95), .window(ox0 + 4.0, width: 1.6)])
        b.wall(axis: .z, fixed: ox0, from: -hd + 0.3, to: oz1 + 0.07, y0: 0, y1: 3.0, thickness: 0.15, exterior: false, openings: [.window(-hd + 3.0, width: 1.6)])
        b.slab(x0: ox0, x1: hw - 0.3, z0: -hd + 0.3, z1: oz1 + 0.07, top: 3.2, thickness: 0.2, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.furnish(Room(x0: ox0 + 0.08, x1: hw - 0.3, z0: -hd + 0.3, z1: oz1 - 0.08, floorY: 0, type: .office), lootOverride: .industrial)
        b.furnish(Room(x0: -hw + 0.3, x1: hw - 0.3, z0: oz1 + 0.1, z1: hd - 0.3, floorY: 0, type: .warehouseFloor))
        b.furnish(Room(x0: -hw + 0.3, x1: ox0 - 0.1, z0: -hd + 0.3, z1: oz1 + 0.1, floorY: 0, type: .storage), lootOverride: .industrial)
        // Low-pitch roof with trusses.
        var rr = b.rng
        b.style.exteriorMat = factory ? .brick : .metalCorrugated
        b.style.exteriorColor = factory ? Vec3(0.7, 0.5, 0.42) : Vec3(0.62, 0.66, 0.68)
        let roofCol = factory ? Vec3(0.35, 0.36, 0.38) : Vec3(0.5, 0.52, 0.55)
        _ = rr.next()
        b.gableRoof(w: W, d: D, baseY: FH, ridge: 1.8, color: roofCol, ridgeAlongZ: true)
        b.rng = rr
        let m = model.interior
        m.material = .metalPainted
        m.color = Vec3(0.35, 0.36, 0.38)
        m.skyVisibility = 0.4
        var z = -hd + 2
        while z < hd - 1 {
            m.addBox(min: Vec3(-hw + 0.3, FH - 0.3, z - 0.08), max: Vec3(hw - 0.3, FH - 0.1, z + 0.08))
            z += 4
        }
        // Rolled-up door above the wide opening.
        let s = model.shell
        s.material = .metalCorrugated
        s.color = Vec3(0.45, 0.5, 0.55)
        s.addBox(min: Vec3(-W * 0.2 - 2.6, 4.5, hd - 0.1), max: Vec3(-W * 0.2 + 2.6, 5.1, hd + 0.25))
        if factory {
            // Smokestack.
            s.material = .brick
            s.color = Vec3(0.55, 0.36, 0.3)
            s.addCylinder(center: Vec3(-hw + 3, 0, -hd - 2.0), radiusBottom: 1.4, radiusTop: 0.9, height: 22, segments: 14)
            model.addCollider(AABB(min: Vec3(-hw + 1.6, 0, -hd - 3.4), max: Vec3(-hw + 4.4, 22, -hd - 0.6)), .wall, .concrete)
        }
        model.height = FH + 2
    }

    // MARK: Barracks

    static func barracks(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.0)
        b.style.exteriorMat = .plaster
        b.style.exteriorColor = Vec3(0.55, 0.58, 0.45)
        b.style.tintableExterior = false
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.75, 0.76, 0.68)
        b.style.trimMat = .metalPainted
        b.style.trimColor = Vec3(0.3, 0.33, 0.28)
        let W: Float = 22, D: Float = 9, FH: Float = 3.0
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [.door(0, style: .metal), .window(-8.5), .window(-5.0), .window(5.0), .window(8.5)],
                        back: [.window(-8.5), .window(-5.0), .window(5.0), .window(8.5), .door(-1.0, style: .metal)],
                        left: [.window(0)], right: [.window(0)])
        b.slab(x0: -10.7, x1: 10.7, z0: -4.2, z1: 4.2, top: 0, thickness: 0.3, floorMat: .linoleum, floorColor: Vec3(0.45, 0.48, 0.4))
        b.wall(axis: .z, fixed: -2, from: -4.2, to: 4.2, y0: 0, y1: FH, thickness: 0.15, exterior: false, openings: [.doorway(2.2, width: 1.0)])
        b.wall(axis: .z, fixed: 2, from: -4.2, to: 4.2, y0: 0, y1: FH, thickness: 0.15, exterior: false, openings: [.doorway(2.2, width: 1.0)])
        b.wall(axis: .x, fixed: 0.2, from: -1.92, to: 1.92, y0: 0, y1: FH, thickness: 0.15, exterior: false, openings: [.door(0.6, width: 0.95, style: .metal)])
        b.furnish(Room(x0: -10.7, x1: -2.08, z0: -4.2, z1: 4.2, floorY: 0, type: .barracks))
        b.furnish(Room(x0: 2.08, x1: 10.7, z0: -4.2, z1: 4.2, floorY: 0, type: .barracks))
        b.furnish(Room(x0: -1.92, x1: 1.92, z0: -4.2, z1: 0.12, floorY: 0, type: .armory), lootOverride: .military)
        b.slab(x0: -10.7, x1: 10.7, z0: -4.2, z1: 4.2, top: FH + 0.2, thickness: 0.2, floorMat: .woodPlanks, floorColor: Vec3(0.5, 0.42, 0.33))
        b.gableRoof(w: W, d: D, baseY: FH + 0.2, ridge: 1.8, color: Vec3(0.3, 0.33, 0.28), ridgeAlongZ: false)
        b.doorStep(at: Vec3(0, 0, D * 0.5), axis: .x, outwardSign: 1)
        model.height = FH + 2.2
    }

    // MARK: Small structures

    static func garage(_ model: BuildingModel, _ seed: UInt64, _ variant: Int) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.0)
        b.style.exteriorMat = variant == 0 ? .brick : .plaster
        b.style.exteriorColor = variant == 0 ? Vec3(0.7, 0.55, 0.48) : Vec3(0.8, 0.78, 0.72)
        b.style.interiorMat = .concrete
        b.style.interiorColor = Vec3(0.6, 0.6, 0.58)
        let W: Float = 6, D: Float = 7, FH: Float = 3.0
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, front: [.wide(0, width: 3.0, top: 2.5)], back: [.window(1.5, width: 0.8, bottom: 1.3)],
                        left: [.door(-2.0, style: .metal)], right: [])
        b.slab(x0: -2.7, x1: 2.7, z0: -3.2, z1: 3.2, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.48))
        b.furnish(Room(x0: -2.7, x1: 2.7, z0: -3.2, z1: 3.2, floorY: 0, type: .garage))
        b.slab(x0: -2.7, x1: 2.7, z0: -3.2, z1: 3.2, top: FH + 0.2, thickness: 0.2, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.flatRoof(w: W, d: D, baseY: FH + 0.2, parapet: 0.2)
        let s = model.shell
        s.material = .metalCorrugated
        s.color = Vec3(0.5, 0.52, 0.5)
        s.addBox(min: Vec3(-1.55, 2.5, 3.2), max: Vec3(1.55, 2.95, 3.45))
        model.height = FH + 0.6
    }

    static func barn(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 5.0)
        b.style.exteriorMat = .woodPlanks
        b.style.exteriorColor = Vec3(0.6, 0.22, 0.18)
        b.style.interiorMat = .woodPlanks
        b.style.interiorColor = Vec3(0.5, 0.38, 0.28)
        b.style.trimColor = Vec3(0.9, 0.88, 0.82)
        let W: Float = 12, D: Float = 16, FH: Float = 5.0
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, t: 0.2,
                        front: [.wide(0, width: 3.6, top: 4.0)], back: [.door(3.0)],
                        left: [.window(-3.0, width: 1.0, bottom: 2.6, top: 3.6), .window(3.0, width: 1.0, bottom: 2.6, top: 3.6)],
                        right: [.window(0, width: 1.0, bottom: 2.6, top: 3.6)])
        b.slab(x0: -5.8, x1: 5.8, z0: -7.8, z1: 7.8, top: 0, thickness: 0.3, floorMat: .dirt, floorColor: Vec3(0.55, 0.45, 0.32))
        b.furnish(Room(x0: -5.8, x1: 5.8, z0: -7.8, z1: 7.8, floorY: 0, type: .barn))
        b.gableRoof(w: W, d: D, baseY: FH, ridge: 4.0, color: Vec3(0.35, 0.33, 0.3), ridgeAlongZ: true)
        model.height = FH + 4
    }

    static func gasStation(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 3.2)
        b.style.exteriorMat = .plaster
        b.style.exteriorColor = Vec3(0.92, 0.92, 0.9)
        b.style.tintableExterior = false
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.88, 0.88, 0.86)
        b.style.trimMat = .metalPainted
        b.style.trimColor = Vec3(0.75, 0.15, 0.12)
        // Shop occupies the back of the lot (z in [-10, -2]); canopy in front.
        let W: Float = 10, D: Float = 8, FH: Float = 3.2
        let shopZ: Float = -6
        let shell = model.shell, interior = model.interior
        let savedS = shell.transform, savedI = interior.transform, savedP = model.lodPlugs.transform
        let shift = Mat4.translation(Vec3(0, 0, shopZ))
        shell.setTransform(shift); interior.setTransform(shift); model.lodPlugs.setTransform(shift)
        let before = model.colliders.count, lootBefore = model.lootSpots.count, doorsBefore = model.doors.count
        let indoorBefore = model.indoorVolumes.count
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH,
                        front: [.door(-2.5, width: 1.2, style: .glass), .window(1.5, width: 3.6, bottom: 0.5, top: 2.6)],
                        back: [.door(3.0, style: .metal)], left: [.window(0)], right: [])
        b.slab(x0: -4.7, x1: 4.7, z0: -3.7, z1: 3.7, top: 0, thickness: 0.3, floorMat: .floorTiles, floorColor: Vec3(0.8, 0.8, 0.78))
        b.furnish(Room(x0: -4.7, x1: 4.7, z0: -3.7, z1: 3.7, floorY: 0, type: .shopFloor))
        b.slab(x0: -4.7, x1: 4.7, z0: -3.7, z1: 3.7, top: FH + 0.2, thickness: 0.2, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.flatRoof(w: W, d: D, baseY: FH + 0.2, parapet: 0.5)
        shell.setTransform(savedS); interior.setTransform(savedI); model.lodPlugs.setTransform(savedP)
        // Shift the gameplay data that was produced in shop-local space.
        for i in before..<model.colliders.count { model.colliders[i].box = model.colliders[i].box.transformed(shift) }
        for i in lootBefore..<model.lootSpots.count { model.lootSpots[i].position = shift.transformPoint(model.lootSpots[i].position) }
        for i in doorsBefore..<model.doors.count { model.doors[i].hinge = shift.transformPoint(model.doors[i].hinge) }
        for i in indoorBefore..<model.indoorVolumes.count { model.indoorVolumes[i] = model.indoorVolumes[i].transformed(shift) }
        // Canopy over pumps.
        shell.material = .metalPainted
        shell.color = Vec3(0.92, 0.92, 0.9)
        shell.flags = 0
        shell.addBox(min: Vec3(-6, 4.2, 0.5), max: Vec3(6, 4.9, 8.5))
        shell.color = Vec3(0.75, 0.15, 0.12)
        shell.addBox(min: Vec3(-6.05, 4.25, 0.45), max: Vec3(6.05, 4.6, 8.55), faces: .sides)
        for (x, z) in [(Float(-4.5), Float(2.0)), (4.5, 2.0), (-4.5, 7.0), (4.5, 7.0)] {
            shell.color = Vec3(0.85, 0.85, 0.83)
            shell.addBox(min: Vec3(x - 0.18, -0.2, z - 0.18), max: Vec3(x + 0.18, 4.2, z + 0.18))
            model.addCollider(AABB(min: Vec3(x - 0.18, -0.2, z - 0.18), max: Vec3(x + 0.18, 4.2, z + 0.18)), .wall, .metal)
        }
        // Pump islands.
        for x in [Float(-2.0), 2.0] {
            shell.material = .concrete
            shell.color = Vec3(0.6, 0.6, 0.58)
            shell.addBox(min: Vec3(x - 0.5, -0.2, 2.5), max: Vec3(x + 0.5, 0.15, 6.5))
            shell.material = .metalPainted
            shell.color = Vec3(0.8, 0.18, 0.14)
            shell.addBox(min: Vec3(x - 0.35, 0.15, 3.8), max: Vec3(x + 0.35, 1.8, 4.6))
            shell.color = Vec3(0.15, 0.15, 0.15)
            shell.addBox(min: Vec3(x - 0.3, 1.2, 4.6), max: Vec3(x + 0.3, 1.55, 4.62))
            model.addCollider(AABB(min: Vec3(x - 0.5, -0.2, 2.5), max: Vec3(x + 0.5, 0.15, 6.5)), [.solid], .concrete)
            model.addCollider(AABB(min: Vec3(x - 0.35, 0.15, 3.8), max: Vec3(x + 0.35, 1.8, 4.6)), .furniture, .metal)
            model.addLoot(Vec3(x + 0.8, -0.1, 4.2), .vehicle, large: true)
        }
        model.height = 5
    }

    static func tent(_ model: BuildingModel, _ seed: UInt64, _ variant: Int) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.0)
        b.style.exteriorMat = .canvas
        b.style.exteriorColor = variant == 0 ? Vec3(0.42, 0.45, 0.32) : Vec3(0.5, 0.48, 0.38)
        b.style.tintableExterior = false
        b.style.interiorMat = .canvas
        b.style.interiorColor = Vec3(0.38, 0.4, 0.3)
        b.style.trimMat = .woodPlanks
        b.style.trimColor = Vec3(0.4, 0.36, 0.3)
        let W: Float = 6, D: Float = 8, FH: Float = 1.9
        b.exteriorWalls(w: W, d: D, y0: -0.2, y1: FH, t: 0.08,
                        front: [.wide(0, width: 2.0, top: 1.95)], back: [], left: [.window(1.5, width: 0.8, bottom: 0.9, top: 1.5)], right: [.window(-1.5, width: 0.8, bottom: 0.9, top: 1.5)])
        let m = model.interior
        m.material = .woodPlanks
        m.color = Vec3(0.45, 0.38, 0.3)
        m.skyVisibility = 0.4
        m.addBox(min: Vec3(-2.95, -0.2, -3.95), max: Vec3(2.95, 0.02, 3.95), faces: [.posY])
        model.addCollider(AABB(min: Vec3(-2.95, -0.6, -3.95), max: Vec3(2.95, 0.02, 3.95)), .wall, .wood)
        b.furnish(Room(x0: -2.95, x1: 2.95, z0: -3.95, z1: 3.95, floorY: 0.02, type: variant == 0 ? .barracks : .storage), lootOverride: .military)
        b.gableRoof(w: W, d: D, baseY: FH, ridge: 1.6, color: b.style.exteriorColor * 0.95, ridgeAlongZ: true)
        model.height = FH + 1.6
    }

    static func guardBooth(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.6)
        b.style.exteriorMat = .concrete
        b.style.exteriorColor = Vec3(0.6, 0.62, 0.55)
        b.style.tintableExterior = false
        b.style.interiorMat = .plaster
        b.style.interiorColor = Vec3(0.7, 0.72, 0.66)
        let W: Float = 3, D: Float = 3, FH: Float = 2.6
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, t: 0.2,
                        front: [.window(0, width: 1.6)], back: [.door(0.3, width: 0.9, style: .metal)],
                        left: [.window(0, width: 1.4)], right: [.window(0, width: 1.4)])
        b.slab(x0: -1.3, x1: 1.3, z0: -1.3, z1: 1.3, top: 0, thickness: 0.3, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.48))
        b.placeFurniture(.desk, at: Vec3(0, 0, 0.9), rotation: 2, loot: .military)
        b.placeFurniture(.chair, at: Vec3(0.3, 0, 0.0), rotation: 0, loot: nil)
        b.slab(x0: -1.3, x1: 1.3, z0: -1.3, z1: 1.3, top: FH + 0.2, thickness: 0.2, floorMat: .concrete, floorColor: Vec3(0.5, 0.5, 0.5))
        b.flatRoof(w: W + 0.4, d: D + 0.4, baseY: FH + 0.2, parapet: 0)
        model.height = FH + 0.5
    }

    static func container(_ model: BuildingModel, _ seed: UInt64, _ variant: Int) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.5)
        b.style.exteriorMat = .metalCorrugated
        b.style.exteriorColor = variant == 0 ? Vec3(0.7, 0.25, 0.15) : Vec3(0.2, 0.35, 0.55)
        b.style.tintableExterior = true
        b.style.interiorMat = .metalCorrugated
        b.style.interiorColor = Vec3(0.5, 0.45, 0.42)
        let W: Float = 2.44, D: Float = 6.1, FH: Float = 2.5
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, t: 0.08, front: [.wide(0, width: 2.2, top: 2.35)], back: [], left: [], right: [])
        b.slab(x0: -1.18, x1: 1.18, z0: -3.0, z1: 3.0, top: 0.06, thickness: 0.3, floorMat: .woodPlanks, floorColor: Vec3(0.45, 0.38, 0.3))
        let s = model.shell
        s.material = .metalCorrugated
        s.color = b.style.exteriorColor
        s.flags = 1
        s.addBox(min: Vec3(-1.22, FH, -3.05), max: Vec3(1.22, FH + 0.1, 3.05))
        // Open doors swung against the sides.
        s.addBox(min: Vec3(-1.3, 0.05, 3.05), max: Vec3(-1.25, 2.45, 4.25))
        s.addBox(min: Vec3(1.25, 0.05, 3.05), max: Vec3(1.3, 2.45, 4.25))
        s.flags = 0
        model.addCollider(AABB(min: Vec3(-1.3, 0, 3.05), max: Vec3(-1.25, 2.45, 4.25)), .wall, .metal)
        model.addCollider(AABB(min: Vec3(1.25, 0, 3.05), max: Vec3(1.3, 2.45, 4.25)), .wall, .metal)
        model.addCollider(AABB(min: Vec3(-1.22, FH, -3.05), max: Vec3(1.22, FH + 0.1, 3.05)), .wall, .metal)
        b.furnish(Room(x0: -1.18, x1: 1.18, z0: -3.0, z1: 3.0, floorY: 0.06, type: .storage), lootOverride: .industrial)
        model.height = FH + 0.1
    }

    static func shed(_ model: BuildingModel, _ seed: UInt64) {
        let b = BuildingBuilder(model: model, seed: seed, floorHeight: 2.4)
        b.style.exteriorMat = .woodPlanks
        b.style.exteriorColor = Vec3(0.55, 0.45, 0.33)
        b.style.interiorMat = .woodPlanks
        b.style.interiorColor = Vec3(0.5, 0.4, 0.3)
        let W: Float = 4, D: Float = 4, FH: Float = 2.4
        b.plinth(w: W, d: D)
        b.exteriorWalls(w: W, d: D, y0: 0, y1: FH, t: 0.12, front: [.door(0.6, width: 0.95)], back: [], left: [.window(0, width: 0.6, bottom: 1.2, top: 1.8)], right: [])
        b.slab(x0: -1.88, x1: 1.88, z0: -1.88, z1: 1.88, top: 0, thickness: 0.3, floorMat: .woodPlanks, floorColor: Vec3(0.45, 0.36, 0.28))
        b.furnish(Room(x0: -1.88, x1: 1.88, z0: -1.88, z1: 1.88, floorY: 0, type: .storage), lootOverride: .garage)
        b.gableRoof(w: W, d: D, baseY: FH, ridge: 1.2, color: Vec3(0.3, 0.3, 0.32), ridgeAlongZ: false)
        model.height = FH + 1.2
    }
}
