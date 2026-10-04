//
//  BuildingKit.swift
//  Ashvale
//
//  Shared types and construction helpers for procedural, fully enterable
//  buildings: layered walls with real door/window openings, floor slabs with
//  stair holes, straight and switchback stairs, doors and loot spots.
//

import Foundation

// MARK: - Shared world types

struct ColliderFlags: OptionSet {
    let rawValue: UInt16
    static let solid = ColliderFlags(rawValue: 1 << 0)
    static let blocksSight = ColliderFlags(rawValue: 1 << 1)
    static let blocksBullets = ColliderFlags(rawValue: 1 << 2)
    static let vaultable = ColliderFlags(rawValue: 1 << 3)
    static let door = ColliderFlags(rawValue: 1 << 4)
    static let foliage = ColliderFlags(rawValue: 1 << 5)
    static let thin = ColliderFlags(rawValue: 1 << 6)

    static let wall: ColliderFlags = [.solid, .blocksSight, .blocksBullets]
    static let furniture: ColliderFlags = [.solid, .blocksBullets]
    static let lowCover: ColliderFlags = [.solid, .blocksBullets, .vaultable]
    static let fence: ColliderFlags = [.solid, .vaultable]
}

enum SurfaceKind: UInt8 {
    case concrete = 0, wood, metal, dirt, grass, glass, flesh, fabric, water
}

struct LocalCollider {
    var box: AABB
    var flags: ColliderFlags
    var surface: SurfaceKind
}

enum LootCategory: Int, Codable, CaseIterable {
    case kitchen, bathroom, bedroom, living, garage, shop, police, medical, military, farm, vehicle, industrial, office
}

struct LootSpotSpec {
    var position: Vec3
    var category: LootCategory
    /// Random yaw for spawned items.
    var yaw: Float
    /// Large spots can hold long items (rifles, backpacks).
    var large: Bool
}

/// A floor-level opening people can walk through (door, doorway, wide opening), for AI navigation.
struct NavPassageSpec {
    var center: Vec3
    /// Unit direction through the opening (wall normal).
    var across: Vec3
    var width: Float
    /// Index into the model's doors, or -1 for an open doorway.
    var door: Int
}

struct DoorSpec {
    /// Hinge position at the bottom of the door.
    var hinge: Vec3
    /// Yaw of the closed door leaf; leaf extends along local +X of this yaw.
    var closedYaw: Float
    var width: Float
    var height: Float
    /// Opening direction sign (+1 or -1 rotation).
    var openSign: Float
    var exterior: Bool
    var style: DoorStyle
}

enum DoorStyle: UInt8 {
    case wood = 0, metal, glass, cell
}

/// Static geometry and gameplay data for one building design, in local space
/// (footprint centered at origin, ground floor at y = 0, front facing +Z).
final class BuildingModel {
    let shell = MeshBuilder()
    let interior = MeshBuilder()
    let lodPlugs = MeshBuilder()
    var colliders: [LocalCollider] = []
    var doors: [DoorSpec] = []
    var lootSpots: [LootSpotSpec] = []
    var indoorVolumes: [AABB] = []
    var waterPoints: [Vec3] = []
    /// Stair waypoint chains (bottom -> ... -> top) used by AI navigation.
    var stairs: [[Vec3]] = []
    var passages: [NavPassageSpec] = []
    var footprint = Vec2(10, 10)
    var height: Float = 6

    func addCollider(_ box: AABB, _ flags: ColliderFlags = .wall, _ surface: SurfaceKind = .concrete) {
        colliders.append(LocalCollider(box: box, flags: flags, surface: surface))
    }

    func addLoot(_ p: Vec3, _ cat: LootCategory, large: Bool = false, yaw: Float? = nil) {
        let h = hash32(UInt32(bitPattern: Int32(p.x * 100)) ^ hash32(UInt32(bitPattern: Int32(p.z * 100))) ^ UInt32(lootSpots.count))
        lootSpots.append(LootSpotSpec(position: p, category: cat, yaw: yaw ?? Float(h % 628) / 100, large: large))
    }
}

// MARK: - Openings & walls

enum OpeningKind {
    case door(DoorStyle)
    case doorway
    case window
    case wideOpening
}

struct Opening {
    var center: Float
    var width: Float
    var bottom: Float
    var top: Float
    var kind: OpeningKind

    static func door(_ c: Float, width: Float = 1.0, style: DoorStyle = .wood) -> Opening {
        Opening(center: c, width: width, bottom: 0, top: 2.15, kind: .door(style))
    }
    static func doorway(_ c: Float, width: Float = 0.95) -> Opening {
        Opening(center: c, width: width, bottom: 0, top: 2.15, kind: .doorway)
    }
    static func window(_ c: Float, width: Float = 1.2, bottom: Float = 0.9, top: Float = 2.1) -> Opening {
        Opening(center: c, width: width, bottom: bottom, top: top, kind: .window)
    }
    static func wide(_ c: Float, width: Float, top: Float) -> Opening {
        Opening(center: c, width: width, bottom: 0, top: top, kind: .wideOpening)
    }
}

enum WallAxis { case x, z }

struct WallStyle {
    var exteriorMat: Mat = .plaster
    var exteriorColor: Vec3 = Vec3(0.85, 0.82, 0.76)
    var interiorMat: Mat = .wallpaper
    var interiorColor: Vec3 = Vec3(0.86, 0.84, 0.8)
    var trimColor: Vec3 = Vec3(0.92, 0.92, 0.9)
    var trimMat: Mat = .woodPlanks
    var tintableExterior = true
}

final class BuildingBuilder {
    let model: BuildingModel
    var rng: RNG
    var style = WallStyle()
    let floorHeight: Float
    var openingsLog: [(axis: WallAxis, fixed: Float, o: Opening, y0: Float)] = []

    init(model: BuildingModel, seed: UInt64, floorHeight: Float = 3.0) {
        self.model = model
        self.rng = RNG(seed: seed)
        self.floorHeight = floorHeight
    }

    // MARK: Walls

    /// Builds a wall segment. For `.x` axis walls `fixed` is the z coordinate and the wall spans x in [from, to].
    /// For `.z` axis walls `fixed` is the x coordinate and it spans z in [from, to].
    /// `outsideSign` gives which side (+1 / -1 along the wall normal) faces outdoors for exterior walls.
    func wall(axis: WallAxis, fixed: Float, from: Float, to: Float, y0: Float, y1: Float,
              thickness t: Float, exterior: Bool, outsideSign: Float = 1,
              innerFrom: Float? = nil, innerTo: Float? = nil, openings: [Opening] = []) {
        let ops = openings.sorted { $0.center < $1.center }
        for o in ops { openingsLog.append((axis, fixed, o, y0)) }

        func emitPieces(rangeFrom: Float, rangeTo: Float, n0: Float, n1: Float, mesh: MeshBuilder, mat: Mat, color: Vec3, tint: Bool, sky: Float) {
            mesh.material = mat
            mesh.color = color
            mesh.flags = tint ? 1 : 0
            mesh.skyVisibility = sky
            mesh.uvScale = 0.5
            var s = rangeFrom
            func piece(_ a0: Float, _ a1: Float, _ b0: Float, _ b1: Float) {
                if a1 - a0 < 0.005 || b1 - b0 < 0.005 { return }
                let box = makeBox(axis: axis, a0: a0, a1: a1, n0: n0, n1: n1, y0: b0, y1: b1)
                mesh.addBox(min: box.min, max: box.max)
            }
            for o in ops {
                let o0 = max(rangeFrom, o.center - o.width * 0.5), o1 = min(rangeTo, o.center + o.width * 0.5)
                if o1 <= rangeFrom || o0 >= rangeTo { continue }
                piece(s, o0, y0, y1)
                if o.bottom > 0.001 { piece(o0, o1, y0, y0 + o.bottom) }
                if y0 + o.top < y1 - 0.001 { piece(o0, o1, y0 + o.top, y1) }
                s = o1
            }
            piece(s, rangeTo, y0, y1)
            mesh.flags = 0
        }

        // Normal-axis extents of the full wall.
        let n0 = fixed - t * 0.5, n1 = fixed + t * 0.5
        if exterior {
            let outerN0 = outsideSign > 0 ? fixed : n0
            let outerN1 = outsideSign > 0 ? n1 : fixed
            let innerN0 = outsideSign > 0 ? n0 : fixed
            let innerN1 = outsideSign > 0 ? fixed : n1
            emitPieces(rangeFrom: from, rangeTo: to, n0: outerN0, n1: outerN1, mesh: model.shell,
                       mat: style.exteriorMat, color: style.exteriorColor, tint: style.tintableExterior, sky: 1)
            emitPieces(rangeFrom: innerFrom ?? from, rangeTo: innerTo ?? to, n0: innerN0, n1: innerN1, mesh: model.interior,
                       mat: style.interiorMat, color: style.interiorColor, tint: false, sky: 0.45)
        } else {
            emitPieces(rangeFrom: from, rangeTo: to, n0: n0, n1: n1, mesh: model.interior,
                       mat: style.interiorMat, color: style.interiorColor, tint: false, sky: 0.45)
        }

        // Colliders for the solid parts (full thickness).
        var s = from
        func colliderPiece(_ a0: Float, _ a1: Float, _ b0: Float, _ b1: Float, _ flags: ColliderFlags) {
            if a1 - a0 < 0.01 || b1 - b0 < 0.01 { return }
            model.addCollider(makeBox(axis: axis, a0: a0, a1: a1, n0: n0, n1: n1, y0: b0, y1: b1), flags, .concrete)
        }
        for o in ops {
            let o0 = o.center - o.width * 0.5, o1 = o.center + o.width * 0.5
            colliderPiece(s, o0, y0, y1, .wall)
            if o.bottom > 0.001 { colliderPiece(o0, o1, y0, y0 + o.bottom, [.solid, .blocksBullets, .blocksSight, .vaultable]) }
            if y0 + o.top < y1 - 0.001 { colliderPiece(o0, o1, y0 + o.top, y1, .wall) }
            s = o1
        }
        colliderPiece(s, to, y0, y1, .wall)

        // Frames, doors, plugs.
        for o in ops {
            let center = axis == .x ? Vec3(o.center, y0, fixed) : Vec3(fixed, y0, o.center)
            let across = axis == .x ? Vec3(0, 0, 1) : Vec3(1, 0, 0)
            switch o.kind {
            case .window:
                addWindowFrame(axis: axis, fixed: fixed, thickness: t, o: o, y0: y0, exterior: exterior, outsideSign: outsideSign)
            case .door(let ds):
                addDoorFrame(axis: axis, fixed: fixed, thickness: t, o: o, y0: y0)
                addDoor(axis: axis, fixed: fixed, o: o, y0: y0, exterior: exterior, outsideSign: outsideSign, style: ds)
                model.passages.append(NavPassageSpec(center: center, across: across, width: o.width, door: model.doors.count - 1))
            case .doorway:
                addDoorFrame(axis: axis, fixed: fixed, thickness: t, o: o, y0: y0)
                model.passages.append(NavPassageSpec(center: center, across: across, width: o.width, door: -1))
            case .wideOpening:
                model.passages.append(NavPassageSpec(center: center, across: across, width: o.width, door: -1))
            }
        }
    }

    func makeBox(axis: WallAxis, a0: Float, a1: Float, n0: Float, n1: Float, y0: Float, y1: Float) -> AABB {
        switch axis {
        case .x: return AABB(min: Vec3(a0, y0, n0), max: Vec3(a1, y1, n1))
        case .z: return AABB(min: Vec3(n0, y0, a0), max: Vec3(n1, y1, a1))
        }
    }

    private func addWindowFrame(axis: WallAxis, fixed: Float, thickness t: Float, o: Opening, y0: Float, exterior: Bool, outsideSign: Float) {
        let m = model.shell
        m.material = style.trimMat
        m.color = style.trimColor
        m.skyVisibility = 0.9
        m.uvScale = 1
        let fw: Float = 0.07
        let a0 = o.center - o.width * 0.5, a1 = o.center + o.width * 0.5
        let b0 = y0 + o.bottom, b1 = y0 + o.top
        let n0 = fixed - t * 0.5 - 0.03, n1 = fixed + t * 0.5 + 0.03
        // Frame posts and rails.
        m.addBox(min: makeBox(axis: axis, a0: a0, a1: a0 + fw, n0: n0, n1: n1, y0: b0, y1: b1).min,
                 max: makeBox(axis: axis, a0: a0, a1: a0 + fw, n0: n0, n1: n1, y0: b0, y1: b1).max)
        let bR = makeBox(axis: axis, a0: a1 - fw, a1: a1, n0: n0, n1: n1, y0: b0, y1: b1)
        m.addBox(min: bR.min, max: bR.max)
        let bT = makeBox(axis: axis, a0: a0, a1: a1, n0: n0, n1: n1, y0: b1 - fw, y1: b1)
        m.addBox(min: bT.min, max: bT.max)
        // Sill ledge protruding outside.
        let sillOut = outsideSign > 0 ? n1 + 0.06 : n1
        let sillIn = outsideSign > 0 ? n0 : n0 - 0.06
        let bS = makeBox(axis: axis, a0: a0 - 0.05, a1: a1 + 0.05, n0: sillIn, n1: sillOut, y0: b0 - 0.05, y1: b0 + 0.02)
        m.addBox(min: bS.min, max: bS.max)
        // Shattered pane remnant: a thin dark glass strip in the top of the frame on some windows.
        if rng.chance(0.5) {
            m.material = .glass
            m.color = Vec3(0.55, 0.62, 0.66)
            m.flags = 16
            let gh = rng.range(0.15, 0.45)
            let bG = makeBox(axis: axis, a0: a0 + fw, a1: a1 - fw, n0: fixed - 0.01, n1: fixed + 0.01, y0: b1 - fw - gh, y1: b1 - fw)
            m.addBox(min: bG.min, max: bG.max)
            m.flags = 0
        }
        // LOD plug: dark pane used only when interiors are not drawn.
        if exterior {
            let p = model.lodPlugs
            p.material = .glass
            p.color = Vec3(0.18, 0.2, 0.22)
            p.skyVisibility = 0.6
            p.flags = 16
            let bP = makeBox(axis: axis, a0: a0, a1: a1, n0: fixed - 0.02, n1: fixed + 0.02, y0: b0, y1: b1)
            p.addBox(min: bP.min, max: bP.max)
            p.flags = 0
        }
        // Curtains inside on some windows.
        if exterior && rng.chance(0.35) {
            let im = model.interior
            im.material = .fabric
            im.color = rng.pick([Vec3(0.55, 0.2, 0.18), Vec3(0.3, 0.35, 0.5), Vec3(0.7, 0.66, 0.5), Vec3(0.35, 0.45, 0.32)])
            im.skyVisibility = 0.5
            let inner = outsideSign > 0 ? fixed - t * 0.5 - 0.06 : fixed + t * 0.5 + 0.06
            let cb = makeBox(axis: axis, a0: a0 - 0.15, a1: a0 + 0.2, n0: inner - 0.03, n1: inner + 0.03, y0: b0 - 0.1, y1: b1 + 0.1)
            im.addBox(min: cb.min, max: cb.max)
            let cb2 = makeBox(axis: axis, a0: a1 - 0.2, a1: a1 + 0.15, n0: inner - 0.03, n1: inner + 0.03, y0: b0 - 0.1, y1: b1 + 0.1)
            im.addBox(min: cb2.min, max: cb2.max)
        }
    }

    private func addDoorFrame(axis: WallAxis, fixed: Float, thickness t: Float, o: Opening, y0: Float) {
        let m = model.interior
        m.material = style.trimMat
        m.color = style.trimColor * 0.9
        m.skyVisibility = 0.7
        m.uvScale = 1
        let fw: Float = 0.06
        let a0 = o.center - o.width * 0.5, a1 = o.center + o.width * 0.5
        let n0 = fixed - t * 0.5 - 0.02, n1 = fixed + t * 0.5 + 0.02
        let top = y0 + o.top
        for b in [makeBox(axis: axis, a0: a0 - fw, a1: a0, n0: n0, n1: n1, y0: y0, y1: top + fw),
                  makeBox(axis: axis, a0: a1, a1: a1 + fw, n0: n0, n1: n1, y0: y0, y1: top + fw),
                  makeBox(axis: axis, a0: a0, a1: a1, n0: n0, n1: n1, y0: top, y1: top + fw)] {
            m.addBox(min: b.min, max: b.max)
        }
    }

    private func addDoor(axis: WallAxis, fixed: Float, o: Opening, y0: Float, exterior: Bool, outsideSign: Float, style ds: DoorStyle) {
        let leafWidth = o.width - 0.04
        // Hinge at the "from" side of the opening.
        let a0 = o.center - o.width * 0.5 + 0.02
        let hinge: Vec3
        let closedYaw: Float
        switch axis {
        case .x:
            hinge = Vec3(a0, y0, fixed)
            closedYaw = 0 // leaf extends along +X
        case .z:
            hinge = Vec3(fixed, y0, a0)
            closedYaw = -kPi * 0.5 // leaf extends along +Z (rotationY(-90°) maps +X to +Z)
        }
        // Exterior doors swing inwards.
        var openSign: Float = rng.chance(0.5) ? 1 : -1
        if exterior {
            // Rotating the leaf by +90° (about Y) moves its tip from +X towards -Z (for .x walls).
            // Inwards means away from outside.
            switch axis {
            case .x: openSign = outsideSign > 0 ? 1 : -1
            case .z: openSign = outsideSign > 0 ? -1 : 1
            }
        }
        model.doors.append(DoorSpec(hinge: hinge, closedYaw: closedYaw, width: leafWidth, height: o.top - 0.03,
                                    openSign: openSign, exterior: exterior, style: ds))
    }

    // MARK: Slabs

    /// Floor slab covering rect [x0,x1]x[z0,z1] with top at y, minus rectangular holes.
    func slab(x0: Float, x1: Float, z0: Float, z1: Float, top y: Float, thickness: Float = 0.25,
              floorMat: Mat, floorColor: Vec3, holes: [AABB] = [], ceilingColor: Vec3 = Vec3(0.88, 0.87, 0.84), collider: Bool = true) {
        // Split rect into pieces avoiding holes (holes given as XZ rect via min/max x,z).
        var rects: [(Float, Float, Float, Float)] = [(x0, x1, z0, z1)]
        for h in holes {
            var next: [(Float, Float, Float, Float)] = []
            for r in rects {
                let hx0 = max(r.0, h.min.x), hx1 = min(r.1, h.max.x)
                let hz0 = max(r.2, h.min.z), hz1 = min(r.3, h.max.z)
                if hx0 >= hx1 || hz0 >= hz1 { next.append(r); continue }
                if r.2 < hz0 { next.append((r.0, r.1, r.2, hz0)) }
                if hz1 < r.3 { next.append((r.0, r.1, hz1, r.3)) }
                if r.0 < hx0 { next.append((r.0, hx0, hz0, hz1)) }
                if hx1 < r.1 { next.append((hx1, r.1, hz0, hz1)) }
            }
            rects = next
        }
        let m = model.interior
        for r in rects {
            // Finish layer.
            m.material = floorMat
            m.color = floorColor
            m.skyVisibility = 0.5
            m.uvScale = floorMat == .floorTiles ? 1.0 : 0.5
            m.addBox(min: Vec3(r.0, y - 0.03, r.2), max: Vec3(r.1, y, r.3), faces: [.posY, .posX, .negX, .posZ, .negZ])
            // Structural slab with plaster ceiling below.
            m.material = .plaster
            m.color = ceilingColor
            m.skyVisibility = 0.4
            m.uvScale = 0.5
            m.addBox(min: Vec3(r.0, y - thickness, r.2), max: Vec3(r.1, y - 0.03, r.3), faces: [.negY, .posX, .negX, .posZ, .negZ])
            if collider {
                model.addCollider(AABB(min: Vec3(r.0, y - thickness, r.2), max: Vec3(r.1, y, r.3)), .wall, .concrete)
            }
        }
    }

    // MARK: Stairs

    /// Straight stair run along Z. Steps occupy x in [x0,x1], starting at zStart going in direction `dir` (+1/-1).
    func straightStairs(x0: Float, x1: Float, zStart: Float, dir: Float, fromY: Float, toY: Float,
                        mat: Mat = .woodPlanks, color: Vec3 = Vec3(0.6, 0.45, 0.3), solidBelow: Bool = true) {
        let rise: Float = 0.2
        let steps = max(1, Int(((toY - fromY) / rise).rounded()))
        let r = (toY - fromY) / Float(steps)
        let run: Float = 0.27
        let m = model.interior
        m.material = mat
        m.color = color
        m.skyVisibility = 0.5
        m.uvScale = 1
        for i in 0..<steps {
            let za = zStart + dir * Float(i) * run
            let zb = za + dir * run
            let top = fromY + r * Float(i + 1)
            let bottom = solidBelow ? fromY : max(fromY, top - 0.35)
            let box = AABB(min: Vec3(x0, bottom, min(za, zb)), max: Vec3(x1, top, max(za, zb)))
            m.addBox(min: Vec3(x0, top - 0.06, box.min.z), max: Vec3(x1, top, box.max.z))
            // Riser block below the tread.
            m.color = color * 0.85
            m.addBox(min: Vec3(x0 + 0.02, bottom, box.min.z), max: Vec3(x1 - 0.02, top - 0.06, box.max.z),
                     faces: solidBelow ? [.posX, .negX, .posZ, .negZ] : .all)
            m.color = color
            model.addCollider(box, .furniture, .wood)
        }
        if !solidBelow {
            // Sloped soffit under the run.
            let zEnd = zStart + dir * Float(steps) * run
            m.color = color * 0.75
            let a = Vec3(x0, fromY - 0.15, zStart), b = Vec3(x1, fromY - 0.15, zStart)
            let c = Vec3(x1, toY - 0.35, zEnd), d = Vec3(x0, toY - 0.35, zEnd)
            m.addOrientedTriangle(a, b, c, want: Vec3(0, -1, 0))
            m.addOrientedTriangle(a, c, d, want: Vec3(0, -1, 0))
            m.color = color
        }
    }

    /// Length of a straight run for a given height.
    func stairRunLength(height: Float) -> Float {
        let steps = max(1, Int((height / 0.2).rounded()))
        return Float(steps) * 0.27
    }

    /// Switchback stairwell between floor `level` and `level+1`. Runs go along -Z from zNear.
    /// Left run (x in [x0, x0+w]) rises half a floor to a landing; right run comes back up.
    func switchbackFlight(x0: Float, zNear: Float, width w: Float, level: Int, mat: Mat = .concrete, color: Vec3 = Vec3(0.6, 0.6, 0.58)) {
        let fh = floorHeight
        let baseY = Float(level) * fh
        let half = fh * 0.5
        let runLen = stairRunLength(height: half)
        // Left run going -Z.
        straightStairs(x0: x0, x1: x0 + w, zStart: zNear, dir: -1, fromY: baseY, toY: baseY + half, mat: mat, color: color, solidBelow: false)
        let runLenAI = stairRunLength(height: half)
        model.stairs.append([Vec3(x0 + w * 0.5, baseY, zNear + 0.5), Vec3(x0 + w * 0.5, baseY + half, zNear - runLenAI - 0.55),
                             Vec3(x0 + w * 1.5 + 0.1, baseY + half, zNear - runLenAI - 0.55), Vec3(x0 + w * 1.5 + 0.1, baseY + fh, zNear + 0.5)])
        // Landing at far end.
        let lz0 = zNear - runLen - 1.1, lz1 = zNear - runLen
        let m = model.interior
        m.material = mat
        m.color = color
        m.skyVisibility = 0.5
        m.addBox(min: Vec3(x0, baseY + half - 0.2, lz0), max: Vec3(x0 + 2 * w + 0.1, baseY + half, lz1))
        model.addCollider(AABB(min: Vec3(x0, baseY + half - 0.3, lz0), max: Vec3(x0 + 2 * w + 0.1, baseY + half, lz1)), .furniture, .concrete)
        // Right run coming back +Z from the landing up to the next floor.
        straightStairs(x0: x0 + w + 0.1, x1: x0 + 2 * w + 0.1, zStart: lz1, dir: 1, fromY: baseY + half, toY: baseY + fh, mat: mat, color: color, solidBelow: false)
        // On the ground floor the space under the right run is closed off (upper levels keep the
        // void open because the previous flight's right run arrives there).
        if level == 0 {
            m.color = color * 0.8
            m.addBox(min: Vec3(x0 + w + 0.12, baseY, lz1), max: Vec3(x0 + 2 * w + 0.08, baseY + half, zNear), faces: .sides)
            model.addCollider(AABB(min: Vec3(x0 + w + 0.1, baseY, lz1), max: Vec3(x0 + 2 * w + 0.1, baseY + half, zNear)), .furniture, .concrete)
        }
        // Spine wall between runs.
        m.material = .plaster
        m.color = Vec3(0.8, 0.79, 0.76)
        m.addBox(min: Vec3(x0 + w, baseY, lz1), max: Vec3(x0 + w + 0.1, baseY + fh - 0.3, zNear))
        model.addCollider(AABB(min: Vec3(x0 + w, baseY, lz1), max: Vec3(x0 + w + 0.1, baseY + fh - 0.3, zNear)), .wall, .concrete)
    }

    /// Hole rect (XZ) needed above a switchback flight.
    func switchbackHole(x0: Float, zNear: Float, width w: Float) -> AABB {
        let runLen = stairRunLength(height: floorHeight * 0.5)
        return AABB(min: Vec3(x0 - 0.01, -100, zNear - runLen - 1.1), max: Vec3(x0 + 2 * w + 0.11, 100, zNear + 0.01))
    }

    /// Railing (low wall) used around stair holes.
    func railing(from a: Vec3, to b: Vec3) {
        let m = model.interior
        m.material = .metalPainted
        m.color = Vec3(0.3, 0.3, 0.32)
        m.skyVisibility = 0.5
        let minP = Vec3(min(a.x, b.x) - 0.03, a.y, min(a.z, b.z) - 0.03)
        let maxP = Vec3(max(a.x, b.x) + 0.03, a.y + 1.0, max(a.z, b.z) + 0.03)
        m.addBox(min: Vec3(minP.x, maxP.y - 0.06, minP.z), max: maxP)
        let len = max(maxP.x - minP.x, maxP.z - minP.z)
        let n = max(2, Int(len / 0.6))
        for i in 0...n {
            let t = Float(i) / Float(n)
            let p = vlerp(a, b, t)
            m.addBox(min: Vec3(p.x - 0.025, a.y, p.z - 0.025), max: Vec3(p.x + 0.025, a.y + 1.0, p.z + 0.025))
        }
        model.addCollider(AABB(min: minP, max: maxP), [.solid], .metal)
    }

    // MARK: Roofs & exterior details

    func gableRoof(w: Float, d: Float, baseY: Float, ridge: Float, color: Vec3, ridgeAlongZ: Bool = true) {
        let m = model.shell
        m.material = .roofTiles
        m.color = color
        m.skyVisibility = 1
        m.uvScale = 0.8
        m.flags = 0
        if ridgeAlongZ {
            m.addGableRoof(minX: -w * 0.5, maxX: w * 0.5, minZ: -d * 0.5, maxZ: d * 0.5, baseY: baseY, ridgeHeight: ridge, overhang: 0.4, thickness: 0.12)
            m.material = style.exteriorMat
            m.color = style.exteriorColor
            m.flags = style.tintableExterior ? 1 : 0
            m.addGableTriangle(x0: -w * 0.5, x1: w * 0.5, z: d * 0.5, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: true)
            m.addGableTriangle(x0: -w * 0.5, x1: w * 0.5, z: -d * 0.5, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: false)
            // Inner faces of gables (attic).
            m.material = .woodPlanks
            m.color = Vec3(0.45, 0.36, 0.28)
            m.flags = 0
            m.addGableTriangle(x0: -w * 0.5, x1: w * 0.5, z: d * 0.5 - 0.01, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: false)
            m.addGableTriangle(x0: -w * 0.5, x1: w * 0.5, z: -d * 0.5 + 0.01, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: true)
        } else {
            // Ridge along X: build rotated.
            let saved = m.transform
            m.setTransform(saved * Mat4.rotationY(kPi * 0.5))
            m.addGableRoof(minX: -d * 0.5, maxX: d * 0.5, minZ: -w * 0.5, maxZ: w * 0.5, baseY: baseY, ridgeHeight: ridge, overhang: 0.4, thickness: 0.12)
            m.material = style.exteriorMat
            m.color = style.exteriorColor
            m.flags = style.tintableExterior ? 1 : 0
            m.addGableTriangle(x0: -d * 0.5, x1: d * 0.5, z: w * 0.5, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: true)
            m.addGableTriangle(x0: -d * 0.5, x1: d * 0.5, z: -w * 0.5, baseY: baseY, ridgeHeight: ridge, facingPositiveZ: false)
            m.flags = 0
            m.setTransform(saved)
        }
        m.flags = 0
    }

    func flatRoof(w: Float, d: Float, baseY: Float, parapet: Float = 0.6) {
        let m = model.shell
        m.material = .concrete
        m.color = Vec3(0.5, 0.5, 0.5)
        m.skyVisibility = 1
        m.flags = 0
        m.uvScale = 0.4
        m.addBox(min: Vec3(-w * 0.5, baseY, -d * 0.5), max: Vec3(w * 0.5, baseY + 0.25, d * 0.5))
        if parapet > 0 {
            m.material = style.exteriorMat
            m.color = style.exteriorColor
            m.flags = style.tintableExterior ? 1 : 0
            let t: Float = 0.25
            m.addBox(min: Vec3(-w * 0.5, baseY + 0.25, -d * 0.5), max: Vec3(w * 0.5, baseY + 0.25 + parapet, -d * 0.5 + t))
            m.addBox(min: Vec3(-w * 0.5, baseY + 0.25, d * 0.5 - t), max: Vec3(w * 0.5, baseY + 0.25 + parapet, d * 0.5))
            m.addBox(min: Vec3(-w * 0.5, baseY + 0.25, -d * 0.5 + t), max: Vec3(-w * 0.5 + t, baseY + 0.25 + parapet, d * 0.5 - t))
            m.addBox(min: Vec3(w * 0.5 - t, baseY + 0.25, -d * 0.5 + t), max: Vec3(w * 0.5, baseY + 0.25 + parapet, d * 0.5 - t))
            m.flags = 0
        }
    }

    /// Concrete plinth around the footprint hiding terrain gaps.
    func plinth(w: Float, d: Float) {
        let m = model.shell
        m.material = .concrete
        m.color = Vec3(0.55, 0.54, 0.52)
        m.skyVisibility = 1
        m.flags = 0
        m.uvScale = 0.5
        m.addBox(min: Vec3(-w * 0.5 - 0.06, -1.6, -d * 0.5 - 0.06), max: Vec3(w * 0.5 + 0.06, 0.0, d * 0.5 + 0.06), faces: .sides)
        model.addCollider(AABB(min: Vec3(-w * 0.5, -1.6, -d * 0.5), max: Vec3(w * 0.5, 0, d * 0.5)), .wall, .concrete)
    }

    /// Small concrete step in front of an exterior door.
    func doorStep(at p: Vec3, axis: WallAxis, outwardSign: Float, width: Float = 1.4) {
        let m = model.shell
        m.material = .concrete
        m.color = Vec3(0.6, 0.6, 0.58)
        m.flags = 0
        let depth: Float = 0.7
        let b: AABB
        switch axis {
        case .x:
            let z0 = outwardSign > 0 ? p.z : p.z - depth
            b = AABB(min: Vec3(p.x - width * 0.5, -0.5, z0), max: Vec3(p.x + width * 0.5, -0.12, z0 + depth))
        case .z:
            let x0 = outwardSign > 0 ? p.x : p.x - depth
            b = AABB(min: Vec3(x0, -0.5, p.z - width * 0.5), max: Vec3(x0 + depth, -0.12, p.z + width * 0.5))
        }
        m.addBox(min: b.min, max: b.max)
        model.addCollider(b, [.solid], .concrete)
    }

    /// Horizontal facade band between floors.
    func facadeBand(w: Float, d: Float, y: Float, color: Vec3) {
        let m = model.shell
        m.material = .concrete
        m.color = color
        m.flags = 0
        let o: Float = 0.05
        m.addBox(min: Vec3(-w * 0.5 - o, y - 0.12, -d * 0.5 - o), max: Vec3(w * 0.5 + o, y + 0.05, d * 0.5 + o), faces: [.posX, .negX, .posZ, .negZ, .posY, .negY])
    }

    /// Standard four exterior walls for one floor. Openings arrays are in each wall's own axis coordinate.
    func exteriorWalls(w: Float, d: Float, y0: Float, y1: Float, t: Float = 0.3,
                       front: [Opening], back: [Opening], left: [Opening], right: [Opening]) {
        let hw = w * 0.5, hd = d * 0.5
        // Front (+Z) and back (-Z): span full width.
        wall(axis: .x, fixed: hd - t * 0.5, from: -hw, to: hw, y0: y0, y1: y1, thickness: t, exterior: true, outsideSign: 1,
             innerFrom: -hw + t * 0.5, innerTo: hw - t * 0.5, openings: front)
        wall(axis: .x, fixed: -hd + t * 0.5, from: -hw, to: hw, y0: y0, y1: y1, thickness: t, exterior: true, outsideSign: -1,
             innerFrom: -hw + t * 0.5, innerTo: hw - t * 0.5, openings: back)
        // Sides (-X left, +X right).
        wall(axis: .z, fixed: -hw + t * 0.5, from: -hd + t * 0.5, to: hd - t * 0.5, y0: y0, y1: y1, thickness: t, exterior: true, outsideSign: -1,
             innerFrom: -hd + t, innerTo: hd - t, openings: left)
        wall(axis: .z, fixed: hw - t * 0.5, from: -hd + t * 0.5, to: hd - t * 0.5, y0: y0, y1: y1, thickness: t, exterior: true, outsideSign: 1,
             innerFrom: -hd + t, innerTo: hd - t, openings: right)
        model.indoorVolumes.append(AABB(min: Vec3(-hw + t, y0, -hd + t), max: Vec3(hw - t, y1, hd - t)))
    }
}
