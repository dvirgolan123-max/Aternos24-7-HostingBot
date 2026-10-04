//
//  ItemVisuals.swift
//  Ashvale
//
//  Procedural 3D models for every item, weapon mount points (muzzle, optic,
//  rail, grip, magazine well, support hand) and helpers that emit a weapon
//  with its magazine and attachments physically placed on it.
//

import Foundation

struct WeaponGeometry {
    var muzzle: Vec3
    var optic: Vec3
    var rail: Vec3
    var grip: Vec3
    var magwell: Vec3
    var support: Vec3      // left hand position
    var sightHeight: Float // iron sight line height above grip origin
}

enum ItemVisuals {
    static private(set) var meshIDs: [Int: MeshID] = [:]
    static private(set) var restTransforms: [Int: Mat4] = [:]
    static private(set) var bounds: [Int: AABB] = [:]

    static func registerAll(registry: MeshRegistry) {
        ItemDB.load()
        for m in ItemModel.allCases {
            let b = build(m)
            let id = registry.add("item-\(m.rawValue)", b)
            meshIDs[m.rawValue] = id
            bounds[m.rawValue] = b.bounds
            restTransforms[m.rawValue] = restTransform(m, b.bounds)
        }
    }

    static func mesh(_ m: ItemModel) -> MeshID { meshIDs[m.rawValue] ?? .none }

    static func isWeaponModel(_ m: ItemModel) -> Bool {
        switch m {
        case .pistolWarden, .pistolHollis, .smgWasp, .rifleKestrel, .rifleVanta, .shotgunBrennan, .sniperLongreach,
             .kitchenKnife, .huntingKnife, .machete, .axe, .crowbar, .bat, .wrench, .flashlight:
            return true
        default:
            return false
        }
    }

    /// Transform that lays a model naturally on the ground (weapons on their side).
    static func restTransform(_ m: ItemModel, _ b: AABB) -> Mat4 {
        guard b.isValid else { return .identity }
        if isWeaponModel(m) || m == .magKestrel || m == .magVanta || m == .magSMG || m == .scope || m == .suppressorPistol || m == .suppressorRifle {
            let rot = Mat4.rotationZ(kPi * 0.5)
            let rb = b.transformed(rot)
            let c = rb.center
            return Mat4.translation(Vec3(-c.x, -rb.min.y, -c.z)) * rot
        }
        return Mat4.translation(Vec3(-b.center.x, -b.min.y, -b.center.z))
    }

    static func geometry(_ m: ItemModel) -> WeaponGeometry {
        switch m {
        case .pistolWarden, .pistolHollis:
            return WeaponGeometry(muzzle: Vec3(0, 0.085, -0.17), optic: Vec3(0, 0.11, -0.04), rail: Vec3(0, 0.045, -0.1), grip: Vec3(0, 0.03, -0.1),
                                  magwell: Vec3(0, 0.03, 0.01), support: Vec3(-0.01, -0.02, 0.005), sightHeight: 0.115)
        case .smgWasp:
            return WeaponGeometry(muzzle: Vec3(0, 0.07, -0.33), optic: Vec3(0, 0.115, -0.06), rail: Vec3(0.03, 0.06, -0.22), grip: Vec3(0, 0.02, -0.2),
                                  magwell: Vec3(0, 0.03, -0.08), support: Vec3(0, 0.0, -0.2), sightHeight: 0.13)
        case .rifleKestrel:
            return WeaponGeometry(muzzle: Vec3(0, 0.075, -0.6), optic: Vec3(0, 0.125, -0.07), rail: Vec3(0.04, 0.07, -0.33), grip: Vec3(0, 0.02, -0.3),
                                  magwell: Vec3(0, 0.035, -0.11), support: Vec3(0, 0.02, -0.3), sightHeight: 0.15)
        case .rifleVanta:
            return WeaponGeometry(muzzle: Vec3(0, 0.07, -0.6), optic: Vec3(0, 0.12, -0.02), rail: Vec3(0.04, 0.06, -0.3), grip: Vec3(0, 0.02, -0.3),
                                  magwell: Vec3(0, 0.03, -0.1), support: Vec3(0, 0.02, -0.3), sightHeight: 0.13)
        case .shotgunBrennan:
            return WeaponGeometry(muzzle: Vec3(0, 0.075, -0.72), optic: Vec3(0, 0.11, -0.05), rail: Vec3(0.04, 0.05, -0.35), grip: Vec3(0, 0.03, -0.35),
                                  magwell: Vec3(0, 0.03, -0.1), support: Vec3(0, 0.01, -0.36), sightHeight: 0.11)
        case .sniperLongreach:
            return WeaponGeometry(muzzle: Vec3(0, 0.07, -0.78), optic: Vec3(0, 0.12, -0.08), rail: Vec3(0.04, 0.05, -0.35), grip: Vec3(0, 0.02, -0.32),
                                  magwell: Vec3(0, 0.03, -0.1), support: Vec3(0, 0.02, -0.33), sightHeight: 0.12)
        default:
            return WeaponGeometry(muzzle: Vec3(0, 0, -0.4), optic: Vec3(0, 0.1, 0), rail: Vec3(0, 0, -0.2), grip: Vec3(0, 0, -0.2),
                                  magwell: Vec3(0, 0, 0), support: Vec3(0, 0, -0.25), sightHeight: 0.1)
        }
    }

    /// Height of an optic's sight line above its mount point.
    static func opticHeight(_ m: ItemModel) -> Float {
        switch m {
        case .redDot: return 0.045
        case .scope: return 0.055
        default: return 0
        }
    }

    /// Emits a full weapon/item (with magazine and attachments) at `m`.
    static func emit(_ item: ItemInstance, transform m: Mat4, scene: RenderScene, viewModel: Bool = false, highlight: Float = 0,
                     magazineOffset: Vec3 = Vec3(0, 0, 0), castsShadow: Bool = true) {
        let d = item.def
        let model = d.model
        let tintLayer: Float = -1
        func put(_ mesh: MeshID, _ t: Mat4, tint: Vec3 = Vec3(1, 1, 1)) {
            let inst = InstanceData(model: t, tint: tint, layer: tintLayer, highlight: highlight, dirt: item.condition < 0.3 ? 0.35 : 0)
            if viewModel { scene.addViewModel(mesh, inst) } else { scene.add(mesh, inst, castsShadow: castsShadow) }
        }
        put(mesh(model), m, tint: d.tint)
        guard d.isFirearm else { return }
        let g = geometry(model)
        if let mag = item.magazine {
            put(mesh(mag.def.model), m * Mat4.translation(g.magwell + magazineOffset))
        }
        for (k, a) in item.attachments {
            guard let slot = AttachSlot(rawValue: k) else { continue }
            let p: Vec3
            switch slot {
            case .optic: p = g.optic
            case .muzzle: p = g.muzzle
            case .rail: p = g.rail
            case .grip: p = g.grip
            }
            put(mesh(a.def.model), m * Mat4.translation(p))
        }
    }

    // MARK: - Builders

    private static func mb() -> MeshBuilder {
        let m = MeshBuilder()
        m.skyVisibility = 1
        m.uvScale = 4
        m.flags = 0
        return m
    }

    private static func box(_ m: MeshBuilder, _ a: Vec3, _ b: Vec3, _ mat: Mat, _ c: Vec3) {
        m.material = mat
        m.color = c
        m.addBox(min: Vec3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)), max: Vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    }

    private static func cyl(_ m: MeshBuilder, _ c: Vec3, _ r0: Float, _ r1: Float, _ h: Float, _ mat: Mat, _ col: Vec3, seg: Int = 12) {
        m.material = mat
        m.color = col
        m.addCylinder(center: c, radiusBottom: r0, radiusTop: r1, height: h, segments: seg)
    }

    /// Cylinder along -Z (barrels): starts at `start` and extends `length` forward.
    private static func barrel(_ m: MeshBuilder, _ start: Vec3, _ r: Float, _ length: Float, _ mat: Mat, _ col: Vec3, seg: Int = 10) {
        m.withTransform(Mat4.translation(start) * Mat4.rotationX(-kPi * 0.5)) {
            m.material = mat
            m.color = col
            m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: r, radiusTop: r, height: length, segments: seg)
        }
    }

    /// Side-profile prism (points in Z/Y plane given as (z, y)), extruded along X with half width w.
    private static func profile(_ m: MeshBuilder, _ pts: [(Float, Float)], halfWidth w: Float, _ mat: Mat, _ col: Vec3) {
        m.material = mat
        m.color = col
        // addPrismZ extrudes XY polygons along Z; build in a rotated frame so the profile lies in ZY.
        m.withTransform(Mat4.rotationY(kPi * 0.5)) {
            // In this frame local X maps to world -Z, local Z maps to world +X.
            m.addPrismZ(pts.map { Vec2(-$0.0, $0.1) }, z0: -w, z1: w)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func build(_ model: ItemModel) -> MeshBuilder {
        let m = mb()
        let metal = Vec3(0.22, 0.22, 0.24), dark = Vec3(0.12, 0.12, 0.13), polymer = Vec3(0.16, 0.16, 0.15)
        switch model {
        // MARK: Food
        case .can:
            cyl(m, Vec3(0, 0, 0), 0.037, 0.037, 0.11, .sheetMetal, Vec3(0.75, 0.75, 0.78))
            m.flags = VertexFlag.tintable
            cyl(m, Vec3(0, 0.015, 0), 0.0375, 0.0375, 0.08, .paper, Vec3(1, 1, 1))
            m.flags = 0
        case .canTall:
            cyl(m, Vec3(0, 0, 0), 0.042, 0.042, 0.13, .sheetMetal, Vec3(0.75, 0.75, 0.78))
            m.flags = VertexFlag.tintable
            cyl(m, Vec3(0, 0.015, 0), 0.0425, 0.0425, 0.1, .paper, Vec3(1, 1, 1))
            m.flags = 0
        case .sodaCan:
            m.flags = VertexFlag.tintable | VertexFlag.glossy
            cyl(m, Vec3(0, 0.01, 0), 0.033, 0.033, 0.1, .sheetMetal, Vec3(1, 1, 1))
            m.flags = 0
            cyl(m, Vec3(0, 0, 0), 0.028, 0.033, 0.01, .sheetMetal, Vec3(0.8, 0.8, 0.82))
            cyl(m, Vec3(0, 0.11, 0), 0.033, 0.027, 0.012, .sheetMetal, Vec3(0.8, 0.8, 0.82))
        case .waterBottle:
            m.flags = VertexFlag.glossy
            cyl(m, Vec3(0, 0, 0), 0.036, 0.036, 0.17, .plastic, Vec3(0.75, 0.88, 0.95))
            cyl(m, Vec3(0, 0.17, 0), 0.036, 0.014, 0.04, .plastic, Vec3(0.75, 0.88, 0.95))
            m.flags = 0
            cyl(m, Vec3(0, 0.21, 0), 0.015, 0.015, 0.02, .plastic, Vec3(0.2, 0.4, 0.8))
            m.flags = VertexFlag.tintable
            cyl(m, Vec3(0, 0.06, 0), 0.0365, 0.0365, 0.05, .paper, Vec3(1, 1, 1))
            m.flags = 0
        case .canteen:
            m.withTransform(Mat4.translation(Vec3(0, 0.1, -0.04)) * Mat4.rotationX(kPi * 0.5)) {
                cyl(m, Vec3(0, 0, 0), 0.1, 0.1, 0.08, .canvas, Vec3(0.38, 0.42, 0.3), seg: 14)
            }
            cyl(m, Vec3(0, 0.19, 0), 0.018, 0.018, 0.03, .gunMetal, metal)
        case .cerealBox:
            m.flags = VertexFlag.tintable
            box(m, Vec3(-0.1, 0, -0.03), Vec3(0.1, 0.28, 0.03), .paper, Vec3(1, 1, 1))
            m.flags = 0
            box(m, Vec3(-0.06, 0.12, -0.0305), Vec3(0.06, 0.22, -0.031), .paper, Vec3(0.95, 0.9, 0.5))
        case .crackers:
            m.flags = VertexFlag.tintable
            box(m, Vec3(-0.11, 0, -0.04), Vec3(0.11, 0.06, 0.04), .paper, Vec3(1, 1, 1))
            m.flags = 0
        case .bar:
            m.flags = VertexFlag.tintable
            box(m, Vec3(-0.06, 0, -0.02), Vec3(0.06, 0.015, 0.02), .plastic, Vec3(1, 1, 1))
            m.flags = 0
        case .apple:
            m.flags = VertexFlag.tintable | VertexFlag.glossy
            m.material = .plastic
            m.color = Vec3(1, 1, 1)
            m.addEllipsoid(center: Vec3(0, 0.04, 0), radii: Vec3(0.04, 0.038, 0.04), rings: 8, segments: 10)
            m.flags = 0
            cyl(m, Vec3(0, 0.075, 0), 0.003, 0.002, 0.02, .bark, Vec3(0.3, 0.2, 0.1), seg: 4)
        case .potato:
            m.material = .dirt
            m.color = Vec3(0.9, 0.8, 0.6)
            m.addEllipsoid(center: Vec3(0, 0.03, 0), radii: Vec3(0.05, 0.03, 0.035), rings: 6, segments: 9, jitter: 0.2, seed: 3)
        case .juiceBox:
            m.flags = VertexFlag.tintable
            box(m, Vec3(-0.03, 0, -0.02), Vec3(0.03, 0.1, 0.02), .paper, Vec3(1, 1, 1))
            m.flags = 0
            cyl(m, Vec3(0.015, 0.1, 0), 0.003, 0.003, 0.04, .plastic, Vec3(0.9, 0.9, 0.9), seg: 4)
        case .jerky:
            m.flags = VertexFlag.tintable
            box(m, Vec3(-0.07, 0, -0.05), Vec3(0.07, 0.02, 0.05), .plastic, Vec3(1, 1, 1))
            m.flags = 0

        // MARK: Medical
        case .bandage:
            m.withTransform(Mat4.translation(Vec3(0, 0.035, -0.03)) * Mat4.rotationX(kPi * 0.5)) {
                cyl(m, Vec3(0, 0, 0), 0.035, 0.035, 0.06, .fabric, Vec3(0.95, 0.95, 0.92), seg: 12)
            }
        case .rag:
            m.material = .fabric
            m.color = Vec3(0.7, 0.66, 0.58)
            m.addBeveledBox(min: Vec3(-0.07, 0, -0.05), max: Vec3(0.07, 0.03, 0.05), bevel: 0.02)
        case .spray:
            cyl(m, Vec3(0, 0, 0), 0.03, 0.03, 0.15, .sheetMetal, Vec3(0.92, 0.92, 0.95))
            m.flags = VertexFlag.tintable
            cyl(m, Vec3(0, 0.03, 0), 0.0305, 0.0305, 0.08, .paper, Vec3(1, 1, 1))
            m.flags = 0
            cyl(m, Vec3(0, 0.15, 0), 0.02, 0.016, 0.03, .plastic, Vec3(0.9, 0.9, 0.9))
        case .pillBottle:
            cyl(m, Vec3(0, 0, 0), 0.022, 0.022, 0.065, .plastic, Vec3(0.85, 0.5, 0.2))
            m.flags = VertexFlag.tintable
            cyl(m, Vec3(0, 0.065, 0), 0.024, 0.024, 0.018, .plastic, Vec3(1, 1, 1))
            m.flags = 0
            cyl(m, Vec3(0, 0.015, 0), 0.0225, 0.0225, 0.035, .paper, Vec3(0.95, 0.95, 0.95))
        case .salineBag:
            m.flags = VertexFlag.glossy
            m.material = .plastic
            m.color = Vec3(0.85, 0.92, 0.95)
            m.addBeveledBox(min: Vec3(-0.08, 0, -0.12), max: Vec3(0.08, 0.035, 0.12), bevel: 0.03)
            m.flags = 0
            cyl(m, Vec3(0, 0.01, 0.12), 0.006, 0.006, 0.01, .plastic, Vec3(0.3, 0.6, 0.9), seg: 6)
        case .splint:
            box(m, Vec3(-0.04, 0, -0.18), Vec3(0.04, 0.012, 0.18), .metalPainted, Vec3(0.85, 0.55, 0.2))
            box(m, Vec3(-0.035, 0.012, -0.17), Vec3(0.035, 0.03, 0.17), .fabric, Vec3(0.25, 0.25, 0.28))
        case .injector:
            cyl(m, Vec3(0, 0.0, 0), 0.012, 0.012, 0.14, .plastic, Vec3(0.3, 0.5, 0.3), seg: 8)
            cyl(m, Vec3(0, 0.14, 0), 0.012, 0.008, 0.02, .plastic, Vec3(0.9, 0.7, 0.1), seg: 8)

        // MARK: Clothing
        case .foldedShirt, .foldedJacket, .foldedPants:
            let h: Float = model == .foldedShirt ? 0.04 : (model == .foldedJacket ? 0.08 : 0.06)
            let w: Float = model == .foldedPants ? 0.15 : 0.2
            m.flags = VertexFlag.tintable
            m.material = .fabric
            m.color = Vec3(1, 1, 1)
            m.addBeveledBox(min: Vec3(-w, 0, -0.14), max: Vec3(w, h, 0.14), bevel: 0.03)
            m.addBeveledBox(min: Vec3(-w * 0.9, h, -0.12), max: Vec3(w * 0.9, h + 0.015, 0.1), bevel: 0.02)
            m.flags = 0
        case .boots, .sneakers:
            for x in [Float(-0.06), 0.06] {
                m.flags = VertexFlag.tintable
                m.material = model == .boots ? .leather : .fabric
                m.color = Vec3(1, 1, 1)
                m.addBeveledBox(min: Vec3(x - 0.045, 0.01, -0.14), max: Vec3(x + 0.045, model == .boots ? 0.08 : 0.06, 0.12), bevel: 0.03)
                if model == .boots { m.addCylinder(center: Vec3(x, 0.06, 0.07), radiusBottom: 0.048, radiusTop: 0.046, height: 0.12, segments: 10) }
                m.flags = 0
                box(m, Vec3(x - 0.048, 0, -0.145), Vec3(x + 0.048, 0.015, 0.125), .rubber, model == .boots ? Vec3(0.1, 0.1, 0.1) : Vec3(0.92, 0.92, 0.9))
            }
        case .capItem, .beanieItem, .helmetItem, .policeCapItem, .motoHelmetItem, .bandanaItem, .surgicalMaskItem, .gasMaskItem, .balaclavaItem,
             .vestHuntingItem, .vestPoliceItem, .plateCarrierItem, .chestRigItem, .backpackSchoolItem, .backpackHikingItem, .backpackMilitaryItem:
            let gear: GearMesh
            switch model {
            case .capItem: gear = .cap
            case .beanieItem: gear = .beanie
            case .helmetItem: gear = .helmet
            case .policeCapItem: gear = .policeCap
            case .motoHelmetItem: gear = .motoHelmet
            case .bandanaItem: gear = .bandana
            case .surgicalMaskItem: gear = .surgicalMask
            case .gasMaskItem: gear = .gasMask
            case .balaclavaItem: gear = .balaclava
            case .vestHuntingItem: gear = .vestHunting
            case .vestPoliceItem: gear = .vestPolice
            case .plateCarrierItem: gear = .plateCarrier
            case .chestRigItem: gear = .chestRig
            case .backpackSchoolItem: gear = .backpackSchool
            case .backpackHikingItem: gear = .backpackHiking
            default: gear = .backpackMilitary
            }
            let g = CharacterMeshes.makeGear(gear)
            // Vests and packs lie flat on their back.
            if [.vestHuntingItem, .vestPoliceItem, .plateCarrierItem, .chestRigItem, .backpackSchoolItem, .backpackHikingItem, .backpackMilitaryItem].contains(model) {
                m.append(g, transform: Mat4.rotationX(-kPi * 0.5))
            } else {
                m.append(g)
            }

        // MARK: Firearms (grip at origin, barrel towards -Z)
        case .pistolWarden, .pistolHollis:
            let slideCol = model == .pistolWarden ? dark : Vec3(0.35, 0.35, 0.37)
            let len: Float = model == .pistolWarden ? 0.19 : 0.2
            box(m, Vec3(-0.014, 0.06, -len + 0.03), Vec3(0.014, 0.1, 0.035), .gunMetal, slideCol)
            box(m, Vec3(-0.013, 0.035, -len + 0.04), Vec3(0.013, 0.062, 0.025), .plastic, polymer)
            profile(m, [(0.02, 0.04), (-0.01, 0.04), (-0.025, -0.07), (0.012, -0.075), (0.03, -0.01)], halfWidth: 0.0145, .plastic, polymer)
            barrel(m, Vec3(0, 0.085, -len + 0.03), 0.007, 0.012, .gunMetal, dark, seg: 8)
            box(m, Vec3(-0.002, 0.1, -len + 0.04), Vec3(0.002, 0.108, -len + 0.05), .gunMetal, dark)
            box(m, Vec3(-0.01, 0.1, 0.02), Vec3(0.01, 0.108, 0.03), .gunMetal, dark)
            // Trigger guard.
            box(m, Vec3(-0.004, 0.025, -0.06), Vec3(0.004, 0.03, 0.0), .plastic, polymer)
            box(m, Vec3(-0.004, 0.03, -0.062), Vec3(0.004, 0.04, -0.056), .plastic, polymer)
        case .smgWasp:
            box(m, Vec3(-0.022, 0.035, -0.26), Vec3(0.022, 0.1, 0.06), .gunMetal, dark)
            box(m, Vec3(-0.018, 0.1, -0.2), Vec3(0.018, 0.108, 0.02), .gunMetal, metal)
            barrel(m, Vec3(0, 0.07, -0.26), 0.012, 0.07, .gunMetal, dark)
            profile(m, [(0.0, 0.035), (-0.03, 0.035), (-0.045, -0.06), (-0.01, -0.065), (0.01, 0.0)], halfWidth: 0.018, .plastic, polymer)
            // Folding stock.
            box(m, Vec3(-0.01, 0.07, 0.06), Vec3(0.01, 0.085, 0.26), .gunMetal, metal)
            box(m, Vec3(-0.012, 0.02, 0.24), Vec3(0.012, 0.09, 0.27), .gunMetal, metal)
            box(m, Vec3(-0.02, 0.03, -0.13), Vec3(0.02, 0.04, -0.03), .plastic, polymer)
        case .rifleKestrel:
            // Upper / lower receiver.
            box(m, Vec3(-0.024, 0.04, -0.16), Vec3(0.024, 0.11, 0.06), .gunMetal, dark)
            box(m, Vec3(-0.012, 0.11, -0.16), Vec3(0.012, 0.125, 0.05), .gunMetal, metal)   // top rail
            // Handguard.
            box(m, Vec3(-0.026, 0.035, -0.45), Vec3(0.026, 0.1, -0.16), .plastic, polymer)
            for z in stride(from: Float(-0.43), through: -0.19, by: 0.04) {
                box(m, Vec3(-0.027, 0.06, z), Vec3(0.027, 0.075, z + 0.02), .gunMetal, dark)
            }
            barrel(m, Vec3(0, 0.075, -0.45), 0.009, 0.15, .gunMetal, dark)
            // Front sight post.
            box(m, Vec3(-0.004, 0.1, -0.44), Vec3(0.004, 0.14, -0.43), .gunMetal, dark)
            box(m, Vec3(-0.008, 0.125, 0.02), Vec3(0.008, 0.145, 0.04), .gunMetal, dark)   // rear sight
            // Pistol grip.
            profile(m, [(0.02, 0.04), (-0.015, 0.04), (-0.005, -0.08), (0.03, -0.085), (0.04, 0.0)], halfWidth: 0.016, .plastic, polymer)
            // Buffer tube and stock.
            barrel(m, Vec3(0, 0.08, 0.3), 0.016, 0.24, .gunMetal, dark)
            profile(m, [(0.17, 0.11), (0.33, 0.11), (0.34, -0.02), (0.29, -0.025), (0.17, 0.05)], halfWidth: 0.022, .plastic, polymer)
            box(m, Vec3(-0.004, 0.025, -0.07), Vec3(0.004, 0.03, 0.0), .gunMetal, dark)
        case .rifleVanta:
            box(m, Vec3(-0.024, 0.035, -0.17), Vec3(0.024, 0.1, 0.08), .gunMetal, Vec3(0.2, 0.2, 0.21))
            box(m, Vec3(-0.022, 0.1, -0.12), Vec3(0.022, 0.112, 0.07), .gunMetal, Vec3(0.24, 0.24, 0.25))
            // Wood handguard.
            box(m, Vec3(-0.027, 0.04, -0.42), Vec3(0.027, 0.095, -0.17), .woodDark, Vec3(0.55, 0.32, 0.18))
            box(m, Vec3(-0.018, 0.095, -0.36), Vec3(0.018, 0.112, -0.2), .woodDark, Vec3(0.55, 0.32, 0.18))
            barrel(m, Vec3(0, 0.07, -0.42), 0.009, 0.18, .gunMetal, dark)
            barrel(m, Vec3(0, 0.1, -0.36), 0.008, 0.18, .gunMetal, dark)   // gas tube
            box(m, Vec3(-0.004, 0.09, -0.56), Vec3(0.004, 0.13, -0.545), .gunMetal, dark)
            box(m, Vec3(-0.007, 0.112, -0.06), Vec3(0.007, 0.13, -0.04), .gunMetal, dark)
            profile(m, [(0.025, 0.035), (-0.01, 0.035), (0.0, -0.085), (0.035, -0.088), (0.045, 0.0)], halfWidth: 0.015, .woodDark, Vec3(0.45, 0.28, 0.16))
            profile(m, [(0.08, 0.1), (0.36, 0.06), (0.37, -0.06), (0.32, -0.065), (0.08, 0.035)], halfWidth: 0.02, .woodDark, Vec3(0.55, 0.32, 0.18))
        case .shotgunBrennan:
            box(m, Vec3(-0.024, 0.04, -0.12), Vec3(0.024, 0.11, 0.08), .gunMetal, dark)
            barrel(m, Vec3(0, 0.09, -0.12), 0.012, 0.6, .gunMetal, dark)
            barrel(m, Vec3(0, 0.06, -0.12), 0.012, 0.5, .gunMetal, metal)   // tube magazine
            box(m, Vec3(-0.03, 0.04, -0.46), Vec3(0.03, 0.08, -0.26), .woodDark, Vec3(0.5, 0.3, 0.18))  // pump
            for z in stride(from: Float(-0.45), through: -0.28, by: 0.025) {
                box(m, Vec3(-0.031, 0.045, z), Vec3(0.031, 0.075, z + 0.008), .woodDark, Vec3(0.4, 0.24, 0.14))
            }
            box(m, Vec3(-0.004, 0.1, -0.715), Vec3(0.004, 0.11, -0.705), .gunMetal, Vec3(0.85, 0.85, 0.85))
            profile(m, [(0.08, 0.1), (0.4, 0.07), (0.41, -0.06), (0.36, -0.07), (0.1, -0.02), (0.06, -0.06), (0.03, -0.065), (0.06, 0.04)],
                    halfWidth: 0.02, .woodDark, Vec3(0.5, 0.3, 0.18))
            box(m, Vec3(-0.004, 0.025, -0.06), Vec3(0.004, 0.03, 0.02), .gunMetal, dark)
        case .sniperLongreach:
            box(m, Vec3(-0.022, 0.045, -0.2), Vec3(0.022, 0.11, 0.08), .gunMetal, dark)
            barrel(m, Vec3(0, 0.075, -0.2), 0.011, 0.58, .gunMetal, dark)
            // Bolt handle.
            box(m, Vec3(0.022, 0.08, 0.02), Vec3(0.06, 0.09, 0.035), .gunMetal, metal)
            cyl(m, Vec3(0.06, 0.075, 0.028), 0.01, 0.01, 0.02, .gunMetal, metal, seg: 8)
            // Synthetic stock.
            profile(m, [(-0.42, 0.06), (-0.42, 0.035), (-0.2, 0.03), (-0.05, 0.025), (0.0, -0.08), (0.04, -0.085), (0.06, 0.0), (0.12, 0.0),
                        (0.42, 0.0), (0.43, -0.09), (0.38, -0.1), (0.15, -0.035), (0.08, 0.045), (-0.2, 0.06)],
                    halfWidth: 0.025, .plastic, Vec3(0.32, 0.34, 0.28))
            box(m, Vec3(-0.012, 0.11, -0.16), Vec3(0.012, 0.12, 0.05), .gunMetal, metal)

        // MARK: Magazines (origin at the top where they seat)
        case .magPistol, .magPistolShort:
            let h: Float = model == .magPistol ? 0.11 : 0.09
            box(m, Vec3(-0.011, -h, -0.016), Vec3(0.011, 0.0, 0.016), .gunMetal, dark)
            box(m, Vec3(-0.014, -h - 0.01, -0.02), Vec3(0.014, -h, 0.02), .plastic, polymer)
        case .magSMG:
            box(m, Vec3(-0.012, -0.21, -0.018), Vec3(0.012, 0.0, 0.018), .gunMetal, dark)
            box(m, Vec3(-0.015, -0.22, -0.021), Vec3(0.015, -0.21, 0.021), .plastic, polymer)
        case .magKestrel:
            profile(m, [(0.03, 0.0), (-0.03, 0.0), (-0.045, -0.18), (0.012, -0.19)], halfWidth: 0.012, .gunMetal, Vec3(0.18, 0.18, 0.17))
            box(m, Vec3(-0.015, -0.2, -0.05), Vec3(0.015, -0.185, 0.016), .plastic, polymer)
        case .magVanta:
            profile(m, [(0.035, 0.0), (-0.035, 0.0), (-0.09, -0.19), (-0.03, -0.205)], halfWidth: 0.013, .rust, Vec3(0.75, 0.45, 0.25))
        case .magSniper:
            box(m, Vec3(-0.018, -0.07, -0.045), Vec3(0.018, 0.0, 0.045), .gunMetal, dark)

        // MARK: Ammo
        case .ammoPistol, .ammoRifle:
            let len: Float = model == .ammoPistol ? 0.03 : 0.055
            let r: Float = model == .ammoPistol ? 0.0048 : 0.0055
            for i in 0..<6 {
                let x = Float(i % 3) * 0.013 - 0.013, z = Float(i / 3) * 0.013 - 0.006
                cyl(m, Vec3(x, 0, z), r, r, len * 0.65, .sheetMetal, Vec3(0.8, 0.6, 0.25), seg: 6)
                cyl(m, Vec3(x, len * 0.65, z), r * 0.9, r * 0.35, len * 0.35, .sheetMetal, Vec3(0.7, 0.45, 0.25), seg: 6)
            }
        case .ammoShells:
            for i in 0..<4 {
                let x = Float(i % 2) * 0.022 - 0.011, z = Float(i / 2) * 0.022 - 0.011
                cyl(m, Vec3(x, 0, z), 0.0105, 0.0105, 0.012, .sheetMetal, Vec3(0.8, 0.65, 0.3), seg: 8)
                cyl(m, Vec3(x, 0.012, z), 0.0102, 0.0102, 0.055, .plastic, Vec3(0.75, 0.12, 0.1), seg: 8)
            }

        // MARK: Attachments (origin at mount point)
        case .redDot:
            box(m, Vec3(-0.015, 0, -0.03), Vec3(0.015, 0.02, 0.03), .gunMetal, dark)
            m.withTransform(Mat4.translation(Vec3(0, 0.045, -0.025)) * Mat4.rotationX(-kPi * 0.5)) {
                cyl(m, Vec3(0, 0, 0), 0.018, 0.018, 0.05, .gunMetal, dark, seg: 12)
            }
            m.flags = VertexFlag.glossy
            box(m, Vec3(-0.013, 0.033, -0.026), Vec3(0.013, 0.058, -0.024), .glass, Vec3(0.4, 0.55, 0.45))
            m.flags = 0
        case .scope:
            box(m, Vec3(-0.012, 0, -0.04), Vec3(0.012, 0.03, 0.04), .gunMetal, dark)
            m.withTransform(Mat4.translation(Vec3(0, 0.055, 0.12)) * Mat4.rotationX(-kPi * 0.5)) {
                cyl(m, Vec3(0, 0, 0), 0.02, 0.02, 0.28, .gunMetal, dark, seg: 14)
                cyl(m, Vec3(0, 0.2, 0), 0.02, 0.028, 0.08, .gunMetal, dark, seg: 14)
                cyl(m, Vec3(0, -0.04, 0), 0.026, 0.02, 0.05, .gunMetal, dark, seg: 14)
            }
            cyl(m, Vec3(0, 0.07, 0.0), 0.012, 0.012, 0.02, .gunMetal, dark, seg: 8)
        case .suppressorPistol, .suppressorRifle:
            let r: Float = model == .suppressorPistol ? 0.016 : 0.02
            let l: Float = model == .suppressorPistol ? 0.14 : 0.18
            barrel(m, Vec3(0, 0, 0), r, l, .gunMetal, Vec3(0.15, 0.15, 0.16), seg: 14)
        case .flashlightAttach:
            m.withTransform(Mat4.rotationX(-kPi * 0.5)) {
                cyl(m, Vec3(0, -0.04, 0), 0.016, 0.016, 0.09, .gunMetal, dark, seg: 12)
                cyl(m, Vec3(0, 0.05, 0), 0.016, 0.02, 0.025, .gunMetal, dark, seg: 12)
            }
            m.flags = VertexFlag.emissive
            box(m, Vec3(-0.015, -0.015, -0.077), Vec3(0.015, 0.015, -0.075), .glass, Vec3(0.9, 0.9, 0.8))
            m.flags = 0
        case .verticalGrip:
            cyl(m, Vec3(0, -0.1, 0), 0.016, 0.017, 0.1, .plastic, polymer, seg: 10)
            box(m, Vec3(-0.015, -0.005, -0.03), Vec3(0.015, 0.0, 0.03), .plastic, polymer)

        // MARK: Melee (handle at origin, blade/head towards -Z)
        case .kitchenKnife, .huntingKnife:
            let bl: Float = model == .kitchenKnife ? 0.18 : 0.15
            box(m, Vec3(-0.009, -0.015, -0.01), Vec3(0.009, 0.015, 0.1), model == .kitchenKnife ? .plastic : .woodDark,
                model == .kitchenKnife ? Vec3(0.1, 0.1, 0.1) : Vec3(0.4, 0.25, 0.15))
            profile(m, [(-0.01, 0.02), (-0.01, -0.012), (-bl, -0.012), (-bl - 0.02, 0.0), (-bl, 0.02)], halfWidth: 0.0015, .sheetMetal, Vec3(0.85, 0.85, 0.88))
        case .machete:
            box(m, Vec3(-0.012, -0.018, -0.01), Vec3(0.012, 0.018, 0.13), .plastic, dark)
            profile(m, [(-0.01, 0.022), (-0.01, -0.02), (-0.42, -0.03), (-0.5, 0.0), (-0.48, 0.03)], halfWidth: 0.002, .sheetMetal, Vec3(0.7, 0.7, 0.72))
        case .axe:
            barrel(m, Vec3(0, 0, 0.25), 0.016, 0.85, .woodDark, Vec3(0.6, 0.42, 0.25))
            box(m, Vec3(-0.012, -0.05, -0.62), Vec3(0.012, 0.04, -0.52), .metalPainted, Vec3(0.75, 0.12, 0.1))
            profile(m, [(-0.62, -0.05), (-0.52, -0.05), (-0.5, -0.17), (-0.66, -0.17)], halfWidth: 0.006, .sheetMetal, Vec3(0.8, 0.8, 0.82))
            profile(m, [(-0.6, 0.04), (-0.54, 0.04), (-0.565, 0.11)], halfWidth: 0.012, .metalPainted, Vec3(0.75, 0.12, 0.1))
        case .crowbar:
            barrel(m, Vec3(0, 0, 0.2), 0.011, 0.6, .metalPainted, Vec3(0.15, 0.15, 0.2), seg: 6)
            box(m, Vec3(-0.011, -0.08, -0.43), Vec3(0.011, 0.0, -0.4), .metalPainted, Vec3(0.15, 0.15, 0.2))
        case .bat:
            m.withTransform(Mat4.translation(Vec3(0, 0, 0.2)) * Mat4.rotationX(-kPi * 0.5)) {
                cyl(m, Vec3(0, 0, 0), 0.016, 0.018, 0.3, .woodPlanks, Vec3(0.75, 0.6, 0.42), seg: 12)
                cyl(m, Vec3(0, 0.3, 0), 0.018, 0.034, 0.45, .woodPlanks, Vec3(0.75, 0.6, 0.42), seg: 12)
                cyl(m, Vec3(0, -0.01, 0), 0.022, 0.022, 0.012, .woodPlanks, Vec3(0.7, 0.55, 0.38), seg: 12)
            }
        case .wrench:
            box(m, Vec3(-0.012, -0.015, -0.3), Vec3(0.012, 0.015, 0.08), .metalPainted, Vec3(0.75, 0.15, 0.12))
            box(m, Vec3(-0.018, -0.02, -0.38), Vec3(0.018, 0.06, -0.3), .gunMetal, metal)

        // MARK: Tools
        case .canOpener:
            box(m, Vec3(-0.01, 0, -0.08), Vec3(0.01, 0.012, 0.06), .sheetMetal, Vec3(0.8, 0.8, 0.82))
            cyl(m, Vec3(0, 0, -0.07), 0.018, 0.018, 0.015, .sheetMetal, Vec3(0.7, 0.7, 0.72), seg: 10)
        case .matches:
            box(m, Vec3(-0.025, 0, -0.018), Vec3(0.025, 0.015, 0.018), .paper, Vec3(0.85, 0.2, 0.15))
            box(m, Vec3(-0.0255, 0.003, -0.012), Vec3(-0.025, 0.012, 0.012), .paper, Vec3(0.3, 0.2, 0.15))
        case .ductTape:
            cyl(m, Vec3(0, 0, 0), 0.05, 0.05, 0.05, .plastic, Vec3(0.6, 0.6, 0.62), seg: 14)
        case .sewingKit:
            box(m, Vec3(-0.05, 0, -0.035), Vec3(0.05, 0.03, 0.035), .plastic, Vec3(0.75, 0.35, 0.45))
        case .cleaningKit:
            box(m, Vec3(-0.09, 0, -0.05), Vec3(0.09, 0.045, 0.05), .plastic, Vec3(0.2, 0.25, 0.2))
            box(m, Vec3(-0.08, 0.045, -0.04), Vec3(0.08, 0.05, 0.04), .metalPainted, Vec3(0.3, 0.3, 0.3))
        case .battery:
            box(m, Vec3(-0.013, 0, -0.008), Vec3(0.013, 0.048, 0.008), .plastic, Vec3(0.2, 0.2, 0.2))
            box(m, Vec3(-0.0132, 0.02, -0.0082), Vec3(0.0132, 0.04, 0.0082), .plastic, Vec3(0.85, 0.65, 0.15))
        case .flashlight:
            barrel(m, Vec3(0, 0, 0.1), 0.017, 0.15, .gunMetal, Vec3(0.12, 0.12, 0.13))
            barrel(m, Vec3(0, 0, -0.05), 0.024, 0.04, .gunMetal, Vec3(0.12, 0.12, 0.13))
            m.flags = VertexFlag.emissive
            box(m, Vec3(-0.018, -0.018, -0.092), Vec3(0.018, 0.018, -0.09), .glass, Vec3(0.9, 0.9, 0.8))
            m.flags = 0
        case .compass:
            cyl(m, Vec3(0, 0, 0), 0.03, 0.03, 0.012, .gunMetal, Vec3(0.35, 0.38, 0.3), seg: 14)
            cyl(m, Vec3(0, 0.012, 0), 0.026, 0.026, 0.001, .paper, Vec3(0.9, 0.9, 0.85), seg: 14)
            box(m, Vec3(-0.002, 0.013, -0.02), Vec3(0.002, 0.015, 0.0), .plastic, Vec3(0.8, 0.1, 0.1))
        }
        return m
    }
}
