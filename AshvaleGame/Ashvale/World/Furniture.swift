//
//  Furniture.swift
//  Ashvale
//
//  Procedural furniture pieces with collision and physical loot spots, and the
//  room furnishing logic that arranges them along walls.
//

import Foundation

enum FurnitureKind: CaseIterable {
    case table, chair, counter, stove, sinkCounter, fridge, upperCabinet
    case sofa, armchair, coffeeTable, tvStand, bookshelf, rug
    case doubleBed, singleBed, wardrobe, nightstand, desk, dresser
    case toilet, washbasin, bathtub
    case filingCabinet, locker, shelfUnit, palletRack, crate, barrel, pallet
    case hospitalBed, ivStand, medCabinet, curtainScreen
    case bunkBed, footLocker, weaponRack, workbench, receptionDesk, cellBench, hayBale, checkout, tire, radiator, coatRack, fridgeUnit

    /// Footprint (width along local X, depth along local Z) and height.
    var size: Vec3 {
        switch self {
        case .table: return Vec3(1.4, 0.76, 0.85)
        case .chair: return Vec3(0.45, 0.9, 0.45)
        case .counter: return Vec3(1.2, 0.92, 0.62)
        case .stove: return Vec3(0.6, 0.92, 0.62)
        case .sinkCounter: return Vec3(1.0, 0.92, 0.62)
        case .fridge: return Vec3(0.7, 1.8, 0.68)
        case .upperCabinet: return Vec3(1.2, 0.7, 0.35)
        case .sofa: return Vec3(2.0, 0.85, 0.9)
        case .armchair: return Vec3(0.9, 0.85, 0.85)
        case .coffeeTable: return Vec3(1.0, 0.42, 0.55)
        case .tvStand: return Vec3(1.3, 1.1, 0.45)
        case .bookshelf: return Vec3(1.0, 1.9, 0.35)
        case .rug: return Vec3(2.2, 0.01, 1.5)
        case .doubleBed: return Vec3(1.6, 0.9, 2.1)
        case .singleBed: return Vec3(0.95, 0.85, 2.0)
        case .wardrobe: return Vec3(1.2, 2.0, 0.6)
        case .nightstand: return Vec3(0.45, 0.55, 0.4)
        case .desk: return Vec3(1.3, 0.76, 0.7)
        case .dresser: return Vec3(1.1, 0.9, 0.5)
        case .toilet: return Vec3(0.45, 0.8, 0.7)
        case .washbasin: return Vec3(0.6, 0.9, 0.48)
        case .bathtub: return Vec3(1.7, 0.6, 0.78)
        case .filingCabinet: return Vec3(0.5, 1.3, 0.62)
        case .locker: return Vec3(0.9, 1.9, 0.5)
        case .shelfUnit: return Vec3(1.8, 1.8, 0.55)
        case .palletRack: return Vec3(2.7, 4.2, 1.1)
        case .crate: return Vec3(1.0, 0.8, 0.8)
        case .barrel: return Vec3(0.6, 0.9, 0.6)
        case .pallet: return Vec3(1.2, 0.9, 1.0)
        case .hospitalBed: return Vec3(1.0, 0.95, 2.1)
        case .ivStand: return Vec3(0.4, 1.8, 0.4)
        case .medCabinet: return Vec3(1.0, 1.9, 0.42)
        case .curtainScreen: return Vec3(0.05, 1.9, 2.0)
        case .bunkBed: return Vec3(1.0, 1.75, 2.0)
        case .footLocker: return Vec3(0.8, 0.45, 0.45)
        case .weaponRack: return Vec3(1.6, 1.6, 0.4)
        case .workbench: return Vec3(1.8, 0.95, 0.75)
        case .receptionDesk: return Vec3(2.4, 1.1, 0.8)
        case .cellBench: return Vec3(1.9, 0.5, 0.7)
        case .hayBale: return Vec3(1.2, 0.8, 0.6)
        case .checkout: return Vec3(1.8, 0.95, 0.8)
        case .tire: return Vec3(0.7, 0.75, 0.7)
        case .radiator: return Vec3(0.9, 0.6, 0.12)
        case .coatRack: return Vec3(0.9, 1.7, 0.3)
        case .fridgeUnit: return Vec3(1.6, 2.0, 0.8)
        }
    }

    var isTall: Bool { size.y > 1.0 }
}

struct FurnitureWriter {
    let model: BuildingModel
    let transform: Mat4
    var rng: RNG
    let lootCategory: LootCategory?

    var mesh: MeshBuilder { model.interior }

    func box(_ a: Vec3, _ b: Vec3, _ mat: Mat, _ color: Vec3, faces: Faces = .all, uv: Float = 1.0) {
        mesh.material = mat
        mesh.color = color
        mesh.uvScale = uv
        mesh.addBox(min: Vec3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)), max: Vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)), faces: faces)
    }

    func cylinder(_ c: Vec3, _ r0: Float, _ r1: Float, _ h: Float, _ mat: Mat, _ color: Vec3, seg: Int = 10) {
        mesh.material = mat
        mesh.color = color
        mesh.uvScale = 1
        mesh.addCylinder(center: c, radiusBottom: r0, radiusTop: r1, height: h, segments: seg)
    }

    func collider(_ a: Vec3, _ b: Vec3, _ flags: ColliderFlags = .furniture, _ surface: SurfaceKind = .wood) {
        let box = AABB(min: Vec3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)), max: Vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
        model.addCollider(box.transformed(transform), flags, surface)
    }

    func loot(_ p: Vec3, large: Bool = false, category: LootCategory? = nil) {
        guard let cat = category ?? lootCategory else { return }
        model.addLoot(transform.transformPoint(p), cat, large: large)
    }
}

extension BuildingBuilder {

    /// Places a furniture piece with its local origin (center of footprint, floor level) at `p`, rotated by k * 90 degrees.
    func placeFurniture(_ kind: FurnitureKind, at p: Vec3, rotation k: Int, loot: LootCategory?) {
        let m = Mat4.translation(p) * Mat4.rotationY(Float(k) * kPi * 0.5)
        let mesh = model.interior
        let saved = mesh.transform
        mesh.setTransform(saved * m)
        mesh.skyVisibility = 0.45
        mesh.flags = 0
        let w = FurnitureWriter(model: model, transform: m, rng: RNG(seed: UInt64(rng.next() & 0xFFFFFF)), lootCategory: loot)
        buildFurniture(kind, w)
        mesh.setTransform(saved)
    }

    private func woodColor(_ r: inout RNG) -> Vec3 {
        return r.pick([Vec3(0.55, 0.38, 0.24), Vec3(0.42, 0.3, 0.2), Vec3(0.68, 0.52, 0.36), Vec3(0.3, 0.22, 0.16)])
    }

    private func fabricColor(_ r: inout RNG) -> Vec3 {
        return r.pick([Vec3(0.45, 0.2, 0.18), Vec3(0.25, 0.3, 0.42), Vec3(0.4, 0.42, 0.3), Vec3(0.55, 0.5, 0.42), Vec3(0.3, 0.3, 0.3), Vec3(0.5, 0.35, 0.25)])
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func buildFurniture(_ kind: FurnitureKind, _ fw: FurnitureWriter) {
        var r = fw.rng
        let s = kind.size
        let hw = s.x * 0.5, hd = s.z * 0.5
        switch kind {
        case .table:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, s.y - 0.05, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            for (lx, lz) in [(-hw + 0.06, -hd + 0.06), (hw - 0.06, -hd + 0.06), (-hw + 0.06, hd - 0.06), (hw - 0.06, hd - 0.06)] {
                fw.box(Vec3(lx - 0.035, 0, lz - 0.035), Vec3(lx + 0.035, s.y - 0.05, lz + 0.035), .woodDark, c * 0.85)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .wood)
            fw.loot(Vec3(-0.3, s.y, 0)); fw.loot(Vec3(0.35, s.y, 0.1))
        case .chair:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0.43, -hd), Vec3(hw, 0.47, hd), .woodDark, c)
            fw.box(Vec3(-hw, 0.47, -hd), Vec3(hw, 0.9, -hd + 0.04), .woodDark, c)
            for (lx, lz) in [(-hw + 0.03, -hd + 0.03), (hw - 0.03, -hd + 0.03), (-hw + 0.03, hd - 0.03), (hw - 0.03, hd - 0.03)] {
                fw.box(Vec3(lx - 0.02, 0, lz - 0.02), Vec3(lx + 0.02, 0.43, lz + 0.02), .woodDark, c * 0.8)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.47, hd), [.solid], .wood)
        case .counter, .sinkCounter, .stove:
            let body = r.pick([Vec3(0.85, 0.84, 0.8), Vec3(0.55, 0.42, 0.3), Vec3(0.4, 0.48, 0.42), Vec3(0.75, 0.72, 0.62)])
            fw.box(Vec3(-hw, 0.1, -hd), Vec3(hw, s.y - 0.04, hd - 0.02), kind == .stove ? .metalPainted : .woodPlanks, kind == .stove ? Vec3(0.8, 0.8, 0.78) : body)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.1, hd - 0.08), .plastic, Vec3(0.15, 0.15, 0.15))
            fw.box(Vec3(-hw, s.y - 0.04, -hd), Vec3(hw, s.y, hd + 0.02), .concrete, Vec3(0.5, 0.48, 0.45), uv: 2)
            // Door seams / handles.
            let doors = max(1, Int(s.x / 0.5))
            for i in 0..<doors {
                let x = -hw + (Float(i) + 0.5) * (s.x / Float(doors))
                fw.box(Vec3(x - 0.08, s.y - 0.2, hd - 0.02), Vec3(x + 0.08, s.y - 0.18, hd + 0.01), .metalPainted, Vec3(0.7, 0.7, 0.7))
            }
            if kind == .stove {
                for (bx, bz) in [(-0.14, -0.14), (0.14, -0.14), (-0.14, 0.14), (0.14, 0.14)] as [(Float, Float)] {
                    fw.cylinder(Vec3(bx, s.y, bz), 0.09, 0.09, 0.01, .gunMetal, Vec3(0.1, 0.1, 0.1), seg: 8)
                }
            }
            if kind == .sinkCounter {
                fw.box(Vec3(-0.3, s.y - 0.01, -0.2), Vec3(0.3, s.y + 0.005, 0.18), .sheetMetal, Vec3(0.75, 0.76, 0.78))
                fw.box(Vec3(-0.02, s.y, -0.27), Vec3(0.02, s.y + 0.3, -0.23), .sheetMetal, Vec3(0.75, 0.76, 0.78))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable, .blocksBullets], .wood)
            if kind != .stove { fw.loot(Vec3(0, s.y, 0)) }
        case .fridge:
            let c = r.pick([Vec3(0.9, 0.9, 0.88), Vec3(0.75, 0.76, 0.78), Vec3(0.85, 0.82, 0.7)])
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, c)
            fw.box(Vec3(-hw, 1.15, hd), Vec3(hw, 1.17, hd + 0.005), .plastic, Vec3(0.3, 0.3, 0.3))
            fw.box(Vec3(hw - 0.08, 0.8, hd), Vec3(hw - 0.05, 1.1, hd + 0.04), .sheetMetal, Vec3(0.6, 0.6, 0.6))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
            fw.loot(Vec3(0, 0, hd + 0.25))
        case .upperCabinet:
            let c = r.pick([Vec3(0.85, 0.84, 0.8), Vec3(0.55, 0.42, 0.3)])
            fw.box(Vec3(-hw, 1.45, -hd), Vec3(hw, 2.15, hd), .woodPlanks, c)
        case .sofa, .armchair:
            let c = fabricColor(&r)
            fw.box(Vec3(-hw, 0.1, -hd), Vec3(hw, 0.45, hd), .fabric, c)
            fw.box(Vec3(-hw, 0.45, -hd), Vec3(hw, s.y, -hd + 0.22), .fabric, c * 0.92)
            fw.box(Vec3(-hw, 0.45, -hd + 0.22), Vec3(-hw + 0.16, 0.65, hd), .fabric, c * 0.95)
            fw.box(Vec3(hw - 0.16, 0.45, -hd + 0.22), Vec3(hw, 0.65, hd), .fabric, c * 0.95)
            fw.box(Vec3(-hw + 0.16, 0.45, -hd + 0.22), Vec3(hw - 0.16, 0.52, hd - 0.02), .fabric, c * 1.05)
            fw.box(Vec3(-hw + 0.05, 0, -hd + 0.05), Vec3(hw - 0.05, 0.1, hd - 0.05), .woodDark, Vec3(0.2, 0.15, 0.1))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.52, hd), [.solid, .vaultable], .fabric)
            fw.collider(Vec3(-hw, 0.52, -hd), Vec3(hw, s.y, -hd + 0.22), [.solid], .fabric)
            fw.loot(Vec3(kind == .sofa ? 0.4 : 0, 0.52, 0.1))
        case .coffeeTable:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, s.y - 0.04, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            fw.box(Vec3(-hw + 0.05, 0.08, -hd + 0.05), Vec3(hw - 0.05, 0.1, hd - 0.05), .woodDark, c * 0.9)
            for (lx, lz) in [(-hw + 0.04, -hd + 0.04), (hw - 0.04, -hd + 0.04), (-hw + 0.04, hd - 0.04), (hw - 0.04, hd - 0.04)] {
                fw.box(Vec3(lx - 0.025, 0, lz - 0.025), Vec3(lx + 0.025, s.y - 0.04, lz + 0.025), .woodDark, c * 0.8)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid], .wood)
            fw.loot(Vec3(0.1, s.y, 0))
        case .tvStand:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.5, hd), .woodDark, c)
            fw.box(Vec3(-0.5, 0.55, -0.05), Vec3(0.5, 1.1, 0.0), .plastic, Vec3(0.05, 0.05, 0.06))
            fw.box(Vec3(-0.08, 0.5, -0.1), Vec3(0.08, 0.56, 0.05), .plastic, Vec3(0.08, 0.08, 0.08))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.5, hd), [.solid, .vaultable], .wood)
            fw.loot(Vec3(0.45, 0.5, 0.1))
        case .bookshelf:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0, -hd), Vec3(-hw + 0.03, s.y, hd), .woodDark, c)
            fw.box(Vec3(hw - 0.03, 0, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.02), .woodDark, c * 0.8)
            for i in 0..<5 {
                let y = Float(i) * 0.45
                fw.box(Vec3(-hw, y, -hd), Vec3(hw, y + 0.03, hd), .woodDark, c)
                if i < 4 {
                    // Books.
                    var x = -hw + 0.05
                    while x < hw - 0.12 {
                        let bw = r.range(0.03, 0.07)
                        if r.chance(0.8) {
                            let bh = r.range(0.2, 0.32)
                            fw.box(Vec3(x, y + 0.03, -hd + 0.03), Vec3(x + bw, y + 0.03 + bh, hd - 0.05), .paper,
                                   r.pick([Vec3(0.6, 0.15, 0.12), Vec3(0.15, 0.25, 0.5), Vec3(0.2, 0.4, 0.22), Vec3(0.75, 0.7, 0.55), Vec3(0.3, 0.3, 0.3)]))
                        }
                        x += bw + 0.005
                    }
                }
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .wood)
            fw.loot(Vec3(-0.2, 0.93, 0.02)); fw.loot(Vec3(0.25, 1.38, 0.02))
        case .rug:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.012, hd), .carpet, fabricColor(&r), faces: [.posY])
        case .doubleBed, .singleBed:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0.1, -hd), Vec3(hw, 0.38, hd), .woodDark, c)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.06), .woodDark, c * 0.9)
            fw.box(Vec3(-hw + 0.04, 0.38, -hd + 0.06), Vec3(hw - 0.04, 0.55, hd - 0.03), .fabric, Vec3(0.88, 0.86, 0.82))
            let blanket = fabricColor(&r)
            fw.box(Vec3(-hw + 0.02, 0.5, -hd + 0.6), Vec3(hw - 0.02, 0.58, hd - 0.01), .fabric, blanket)
            let pillows = kind == .doubleBed ? 2 : 1
            for i in 0..<pillows {
                let px: Float = pillows == 1 ? 0 : (i == 0 ? -0.38 : 0.38)
                fw.box(Vec3(px - 0.3, 0.55, -hd + 0.12), Vec3(px + 0.3, 0.66, -hd + 0.5), .fabric, Vec3(0.92, 0.92, 0.9))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.58, hd), [.solid, .vaultable], .fabric)
            fw.loot(Vec3(0, 0.58, 0.3), large: true)
        case .wardrobe:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            fw.box(Vec3(-0.01, 0.1, hd), Vec3(0.01, s.y - 0.1, hd + 0.005), .woodDark, c * 0.6)
            fw.box(Vec3(-0.06, 1.0, hd), Vec3(-0.04, 1.2, hd + 0.03), .sheetMetal, Vec3(0.7, 0.7, 0.6))
            fw.box(Vec3(0.04, 1.0, hd), Vec3(0.06, 1.2, hd + 0.03), .sheetMetal, Vec3(0.7, 0.7, 0.6))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .wood)
            fw.loot(Vec3(0.2, 0, hd + 0.25), large: true)
        case .nightstand, .dresser:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            let drawers = kind == .dresser ? 3 : 2
            for i in 0..<drawers {
                let y = 0.1 + Float(i) * (s.y - 0.15) / Float(drawers)
                fw.box(Vec3(-hw + 0.04, y + 0.02, hd), Vec3(hw - 0.04, y + 0.03, hd + 0.005), .woodDark, c * 0.6)
                fw.box(Vec3(-0.05, y + 0.1, hd), Vec3(0.05, y + 0.12, hd + 0.025), .sheetMetal, Vec3(0.7, 0.68, 0.6))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .wood)
            fw.loot(Vec3(0, s.y, 0))
        case .desk:
            let c = woodColor(&r)
            fw.box(Vec3(-hw, s.y - 0.04, -hd), Vec3(hw, s.y, hd), .woodDark, c)
            fw.box(Vec3(-hw, 0, -hd), Vec3(-hw + 0.45, s.y - 0.04, hd), .woodDark, c * 0.9)
            fw.box(Vec3(hw - 0.04, 0, -hd), Vec3(hw, s.y - 0.04, hd), .woodDark, c * 0.9)
            if r.chance(0.5) {
                // Monitor / lamp.
                fw.box(Vec3(0.1, s.y, -hd + 0.05), Vec3(0.6, s.y + 0.35, -hd + 0.09), .plastic, Vec3(0.08, 0.08, 0.08))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .wood)
            fw.loot(Vec3(-0.25, s.y, 0.1))
        case .toilet:
            fw.box(Vec3(-0.18, 0, -0.1), Vec3(0.18, 0.4, 0.3), .plastic, Vec3(0.93, 0.93, 0.92))
            fw.box(Vec3(-0.2, 0.4, -0.12), Vec3(0.2, 0.44, 0.33), .plastic, Vec3(0.95, 0.95, 0.94))
            fw.box(Vec3(-0.2, 0.4, -hd), Vec3(0.2, 0.8, -hd + 0.18), .plastic, Vec3(0.93, 0.93, 0.92))
            fw.collider(Vec3(-0.2, 0, -hd), Vec3(0.2, 0.44, 0.33), [.solid], .concrete)
        case .washbasin:
            fw.box(Vec3(-hw, 0.75, -hd), Vec3(hw, 0.9, hd), .plastic, Vec3(0.94, 0.94, 0.93))
            fw.box(Vec3(-0.06, 0, -hd), Vec3(0.06, 0.75, -hd + 0.15), .plastic, Vec3(0.9, 0.9, 0.9))
            fw.box(Vec3(-0.25, 1.15, -hd), Vec3(0.25, 1.75, -hd + 0.12), .glass, Vec3(0.7, 0.75, 0.78))
            fw.collider(Vec3(-hw, 0.0, -hd), Vec3(hw, 0.9, hd), [.solid], .concrete)
            fw.loot(Vec3(0.15, 0.9, -0.05))
        case .bathtub:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.06), .plastic, Vec3(0.95, 0.95, 0.94))
            fw.box(Vec3(-hw, 0, hd - 0.06), Vec3(hw, s.y, hd), .plastic, Vec3(0.95, 0.95, 0.94))
            fw.box(Vec3(-hw, 0, -hd + 0.06), Vec3(-hw + 0.06, s.y, hd - 0.06), .plastic, Vec3(0.95, 0.95, 0.94))
            fw.box(Vec3(hw - 0.06, 0, -hd + 0.06), Vec3(hw, s.y, hd - 0.06), .plastic, Vec3(0.95, 0.95, 0.94))
            fw.box(Vec3(-hw + 0.06, 0, -hd + 0.06), Vec3(hw - 0.06, 0.12, hd - 0.06), .plastic, Vec3(0.9, 0.9, 0.9))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .concrete)
            fw.loot(Vec3(0.3, 0.12, 0))
        case .filingCabinet:
            let c = r.pick([Vec3(0.55, 0.57, 0.55), Vec3(0.35, 0.38, 0.42), Vec3(0.6, 0.55, 0.45)])
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, c)
            for i in 0..<4 {
                let y = 0.05 + Float(i) * 0.32
                fw.box(Vec3(-hw + 0.03, y + 0.29, hd), Vec3(hw - 0.03, y + 0.3, hd + 0.005), .metalPainted, c * 0.6)
                fw.box(Vec3(-0.07, y + 0.2, hd), Vec3(0.07, y + 0.22, hd + 0.025), .sheetMetal, Vec3(0.7, 0.7, 0.7))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
            fw.loot(Vec3(0, s.y, 0))
        case .locker:
            let c = r.pick([Vec3(0.3, 0.38, 0.32), Vec3(0.4, 0.45, 0.5), Vec3(0.55, 0.55, 0.52)])
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, c)
            for i in 0..<3 {
                let x = -hw + Float(i) * 0.3
                fw.box(Vec3(x + 0.005, 0.05, hd), Vec3(x + 0.015, s.y - 0.05, hd + 0.005), .metalPainted, c * 0.5)
                for j in 0..<4 {
                    fw.box(Vec3(x + 0.08, 1.55 + Float(j) * 0.04, hd), Vec3(x + 0.22, 1.565 + Float(j) * 0.04, hd + 0.005), .metalPainted, c * 0.4)
                }
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
            fw.loot(Vec3(0, 0, hd + 0.25), large: true)
        case .shelfUnit:
            let c = r.pick([Vec3(0.6, 0.62, 0.62), Vec3(0.75, 0.75, 0.72), Vec3(0.35, 0.4, 0.5)])
            for (px, pz) in [(-hw, -hd), (hw - 0.04, -hd), (-hw, hd - 0.04), (hw - 0.04, hd - 0.04)] {
                fw.box(Vec3(px, 0, pz), Vec3(px + 0.04, s.y, pz + 0.04), .metalPainted, c * 0.8)
            }
            for i in 0..<4 {
                let y = 0.08 + Float(i) * 0.55
                fw.box(Vec3(-hw, y, -hd), Vec3(hw, y + 0.03, hd), .metalPainted, c)
                // Some boxed goods.
                var x = -hw + 0.08
                while x < hw - 0.25 {
                    if r.chance(0.45) {
                        let bw = r.range(0.15, 0.3)
                        fw.box(Vec3(x, y + 0.03, -hd + 0.05), Vec3(x + bw, y + 0.03 + r.range(0.12, 0.3), -hd + 0.05 + r.range(0.15, 0.3)), .paper,
                               r.pick([Vec3(0.7, 0.6, 0.42), Vec3(0.6, 0.2, 0.15), Vec3(0.2, 0.35, 0.6), Vec3(0.85, 0.8, 0.3)]))
                        x += bw + 0.05
                    } else { x += 0.25 }
                }
                fw.loot(Vec3(r.range(-0.5, 0.5), y + 0.03, 0.08))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid], .metal)
        case .palletRack:
            let c = Vec3(0.2, 0.32, 0.6)
            for px in [-hw, hw - 0.08] {
                for pz in [-hd, hd - 0.08] {
                    fw.box(Vec3(px, 0, pz), Vec3(px + 0.08, s.y, pz + 0.08), .metalPainted, c)
                }
            }
            for i in 0..<3 {
                let y = 0.15 + Float(i) * 1.4
                fw.box(Vec3(-hw, y, -hd), Vec3(hw, y + 0.1, -hd + 0.08), .metalPainted, Vec3(0.9, 0.45, 0.1))
                fw.box(Vec3(-hw, y, hd - 0.08), Vec3(hw, y + 0.1, hd), .metalPainted, Vec3(0.9, 0.45, 0.1))
                fw.box(Vec3(-hw + 0.1, y + 0.1, -hd + 0.05), Vec3(hw - 0.1, y + 0.16, hd - 0.05), .woodPlanks, Vec3(0.65, 0.55, 0.4))
                if r.chance(0.7) {
                    fw.box(Vec3(-hw + 0.2, y + 0.16, -hd + 0.1), Vec3(-0.1, y + 0.16 + r.range(0.4, 0.9), hd - 0.1), .paper, Vec3(0.66, 0.54, 0.38))
                }
                if r.chance(0.6) {
                    fw.box(Vec3(0.15, y + 0.16, -hd + 0.15), Vec3(hw - 0.2, y + 0.16 + r.range(0.3, 0.8), hd - 0.15), .paper, Vec3(0.62, 0.5, 0.35))
                }
                fw.loot(Vec3(0, y + 0.16, hd - 0.2), large: true)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
        case .crate:
            let c = Vec3(0.55, 0.45, 0.32)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .woodPlanks, c, uv: 1.2)
            fw.box(Vec3(-hw - 0.01, 0.05, -hd - 0.01), Vec3(hw + 0.01, 0.12, hd + 0.01), .woodPlanks, c * 0.8)
            fw.box(Vec3(-hw - 0.01, s.y - 0.12, -hd - 0.01), Vec3(hw + 0.01, s.y - 0.05, hd + 0.01), .woodPlanks, c * 0.8)
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable, .blocksBullets], .wood)
            fw.loot(Vec3(0, s.y, 0))
        case .barrel:
            let c = r.pick([Vec3(0.2, 0.32, 0.55), Vec3(0.55, 0.15, 0.1), Vec3(0.3, 0.35, 0.25)])
            fw.cylinder(Vec3(0, 0, 0), 0.29, 0.29, s.y, .metalPainted, c, seg: 12)
            fw.cylinder(Vec3(0, 0.3, 0), 0.3, 0.3, 0.04, .metalPainted, c * 0.7, seg: 12)
            fw.cylinder(Vec3(0, 0.6, 0), 0.3, 0.3, 0.04, .metalPainted, c * 0.7, seg: 12)
            fw.collider(Vec3(-0.28, 0, -0.28), Vec3(0.28, s.y, 0.28), [.solid, .vaultable, .blocksBullets], .metal)
        case .pallet:
            fw.box(Vec3(-0.6, 0, -0.5), Vec3(0.6, 0.14, 0.5), .woodPlanks, Vec3(0.66, 0.56, 0.4))
            let h = r.range(0.3, 0.75)
            fw.box(Vec3(-0.55, 0.14, -0.45), Vec3(0.55, 0.14 + h, 0.45), .paper, Vec3(0.66, 0.54, 0.38), uv: 1.5)
            fw.collider(Vec3(-0.6, 0, -0.5), Vec3(0.6, 0.14 + h, 0.5), [.solid, .vaultable, .blocksBullets], .wood)
            fw.loot(Vec3(0, 0.14 + h, 0))
        case .hospitalBed:
            fw.box(Vec3(-hw, 0.5, -hd), Vec3(hw, 0.6, hd), .metalPainted, Vec3(0.8, 0.82, 0.84))
            fw.box(Vec3(-hw + 0.03, 0.6, -hd + 0.03), Vec3(hw - 0.03, 0.72, hd - 0.03), .fabric, Vec3(0.75, 0.82, 0.85))
            fw.box(Vec3(-hw, 0.5, -hd), Vec3(hw, 1.05, -hd + 0.04), .metalPainted, Vec3(0.85, 0.86, 0.88))
            fw.box(Vec3(-hw - 0.02, 0.72, -0.4), Vec3(-hw + 0.01, 0.95, 0.5), .sheetMetal, Vec3(0.7, 0.7, 0.72))
            fw.box(Vec3(hw - 0.01, 0.72, -0.4), Vec3(hw + 0.02, 0.95, 0.5), .sheetMetal, Vec3(0.7, 0.7, 0.72))
            for (lx, lz) in [(-hw + 0.05, -hd + 0.05), (hw - 0.05, -hd + 0.05), (-hw + 0.05, hd - 0.05), (hw - 0.05, hd - 0.05)] {
                fw.box(Vec3(lx - 0.02, 0.08, lz - 0.02), Vec3(lx + 0.02, 0.5, lz + 0.02), .sheetMetal, Vec3(0.7, 0.7, 0.72))
                fw.cylinder(Vec3(lx, 0, lz), 0.05, 0.05, 0.08, .rubber, Vec3(0.1, 0.1, 0.1), seg: 6)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.72, hd), [.solid, .vaultable], .metal)
            fw.loot(Vec3(0, 0.72, 0.4), large: true)
        case .ivStand:
            fw.cylinder(Vec3(0, 0, 0), 0.18, 0.02, 0.06, .sheetMetal, Vec3(0.7, 0.7, 0.72), seg: 6)
            fw.cylinder(Vec3(0, 0.06, 0), 0.015, 0.015, 1.7, .sheetMetal, Vec3(0.8, 0.8, 0.82), seg: 6)
            fw.box(Vec3(-0.08, 1.45, -0.03), Vec3(0.08, 1.7, 0.03), .plastic, Vec3(0.85, 0.9, 0.95))
            fw.collider(Vec3(-0.1, 0, -0.1), Vec3(0.1, 1.7, 0.1), [.solid], .metal)
        case .medCabinet:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.03), .metalPainted, Vec3(0.92, 0.93, 0.94))
            fw.box(Vec3(-hw, 0, -hd), Vec3(-hw + 0.03, s.y, hd), .metalPainted, Vec3(0.92, 0.93, 0.94))
            fw.box(Vec3(hw - 0.03, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, Vec3(0.92, 0.93, 0.94))
            for i in 0..<5 {
                let y = Float(i) * 0.45
                fw.box(Vec3(-hw, y, -hd), Vec3(hw, y + 0.03, hd), .metalPainted, Vec3(0.9, 0.9, 0.92))
                if i > 0 && i < 4 {
                    var x = -hw + 0.06
                    while x < hw - 0.1 {
                        if r.chance(0.6) {
                            fw.box(Vec3(x, y + 0.03, -hd + 0.06), Vec3(x + 0.06, y + 0.03 + r.range(0.06, 0.14), -hd + 0.14), .plastic,
                                   r.pick([Vec3(0.95, 0.95, 0.95), Vec3(0.3, 0.5, 0.8), Vec3(0.85, 0.3, 0.25), Vec3(0.95, 0.8, 0.3)]))
                        }
                        x += 0.09
                    }
                    fw.loot(Vec3(r.range(-0.3, 0.3), y + 0.03, 0.05))
                }
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
        case .curtainScreen:
            fw.box(Vec3(-0.02, 1.85, -hd), Vec3(0.02, 1.9, hd), .sheetMetal, Vec3(0.7, 0.7, 0.7))
            fw.box(Vec3(-0.015, 0.25, -hd), Vec3(0.015, 1.85, hd), .fabric, Vec3(0.55, 0.7, 0.68))
            fw.collider(Vec3(-0.03, 0, -hd), Vec3(0.03, 1.9, hd), [.solid, .blocksSight], .fabric)
        case .bunkBed:
            let c = Vec3(0.3, 0.36, 0.28)
            for (px, pz) in [(-hw, -hd), (hw - 0.05, -hd), (-hw, hd - 0.05), (hw - 0.05, hd - 0.05)] {
                fw.box(Vec3(px, 0, pz), Vec3(px + 0.05, s.y, pz + 0.05), .metalPainted, c)
            }
            for y in [Float(0.35), 1.35] {
                fw.box(Vec3(-hw, y, -hd), Vec3(hw, y + 0.06, hd), .metalPainted, c)
                fw.box(Vec3(-hw + 0.05, y + 0.06, -hd + 0.05), Vec3(hw - 0.05, y + 0.18, hd - 0.05), .fabric, Vec3(0.42, 0.45, 0.35))
                fw.box(Vec3(-0.3, y + 0.18, -hd + 0.08), Vec3(0.3, y + 0.26, -hd + 0.42), .fabric, Vec3(0.8, 0.8, 0.75))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.53, hd), [.solid, .vaultable], .metal)
            fw.collider(Vec3(-hw, 1.35, -hd), Vec3(hw, 1.55, hd), [.solid], .metal)
            fw.loot(Vec3(0, 0.53, 0.3), large: true)
            fw.loot(Vec3(0, 1.53, 0.2))
        case .footLocker:
            let c = Vec3(0.28, 0.33, 0.24)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, c)
            fw.box(Vec3(-hw - 0.01, s.y - 0.08, -hd - 0.01), Vec3(hw + 0.01, s.y - 0.06, hd + 0.01), .metalPainted, c * 0.7)
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .metal)
            fw.loot(Vec3(0, s.y, 0))
        case .weaponRack:
            let c = Vec3(0.25, 0.25, 0.27)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.12, hd), .metalPainted, c)
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.05), .metalPainted, c * 0.9)
            fw.box(Vec3(-hw, 1.1, -hd), Vec3(hw, 1.16, hd), .metalPainted, c)
            for i in 0..<7 {
                let x = -hw + 0.15 + Float(i) * 0.22
                fw.box(Vec3(x - 0.015, 1.1, hd - 0.1), Vec3(x + 0.015, 1.25, hd - 0.05), .metalPainted, c * 0.7)
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
            fw.loot(Vec3(-0.4, 0.12, 0.05), large: true)
            fw.loot(Vec3(0.4, 0.12, 0.05), large: true)
            fw.loot(Vec3(0, 1.16, 0.0))
        case .workbench:
            let c = Vec3(0.5, 0.4, 0.3)
            fw.box(Vec3(-hw, s.y - 0.06, -hd), Vec3(hw, s.y, hd), .woodPlanks, c)
            fw.box(Vec3(-hw, 0.15, -hd + 0.05), Vec3(hw, 0.19, hd - 0.05), .woodPlanks, c * 0.8)
            for (lx, lz) in [(-hw + 0.05, -hd + 0.05), (hw - 0.05, -hd + 0.05), (-hw + 0.05, hd - 0.05), (hw - 0.05, hd - 0.05)] {
                fw.box(Vec3(lx - 0.04, 0, lz - 0.04), Vec3(lx + 0.04, s.y - 0.06, lz + 0.04), .metalPainted, Vec3(0.3, 0.3, 0.3))
            }
            fw.box(Vec3(-hw, s.y, -hd), Vec3(hw, s.y + 0.9, -hd + 0.03), .woodPlanks, Vec3(0.6, 0.5, 0.38))
            fw.box(Vec3(hw - 0.35, s.y, -0.1), Vec3(hw - 0.1, s.y + 0.15, 0.1), .gunMetal, Vec3(0.25, 0.3, 0.45))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .wood)
            fw.loot(Vec3(-0.4, s.y, 0.1)); fw.loot(Vec3(0.3, 0.19, 0.0))
        case .receptionDesk:
            let c = r.pick([Vec3(0.5, 0.4, 0.3), Vec3(0.8, 0.8, 0.78)])
            fw.box(Vec3(-hw, 0, hd - 0.1), Vec3(hw, s.y, hd), .woodPlanks, c)
            fw.box(Vec3(-hw, 0.75, -hd), Vec3(hw, 0.79, hd), .woodDark, c * 0.8)
            fw.box(Vec3(-hw, s.y - 0.03, hd - 0.35), Vec3(hw, s.y, hd), .woodDark, c * 0.85)
            fw.box(Vec3(-hw, 0, -hd), Vec3(-hw + 0.08, 0.75, hd - 0.1), .woodPlanks, c)
            fw.box(Vec3(-0.3, 0.79, -hd + 0.1), Vec3(0.15, 1.1, -hd + 0.14), .plastic, Vec3(0.08, 0.08, 0.08))
            fw.collider(Vec3(-hw, 0, hd - 0.35), Vec3(hw, s.y, hd), [.solid, .vaultable, .blocksBullets], .wood)
            fw.loot(Vec3(0.6, 0.79, -0.1)); fw.loot(Vec3(-0.6, s.y, hd - 0.18))
        case .cellBench:
            fw.box(Vec3(-hw, 0.4, -hd), Vec3(hw, 0.48, hd), .concrete, Vec3(0.6, 0.6, 0.6))
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.4, -hd + 0.1), .concrete, Vec3(0.55, 0.55, 0.55))
            fw.box(Vec3(-hw + 0.05, 0.48, -hd + 0.05), Vec3(hw - 0.3, 0.55, hd - 0.05), .fabric, Vec3(0.35, 0.38, 0.3))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, 0.55, hd), [.solid, .vaultable], .concrete)
            fw.loot(Vec3(0.5, 0.55, 0))
        case .hayBale:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .burlap, Vec3(0.85, 0.72, 0.4), uv: 2)
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable], .fabric)
        case .checkout:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, Vec3(0.75, 0.75, 0.72))
            fw.box(Vec3(-hw, s.y, -hd), Vec3(hw, s.y + 0.03, hd), .plastic, Vec3(0.15, 0.15, 0.15))
            fw.box(Vec3(0.4, s.y + 0.03, -0.2), Vec3(0.75, s.y + 0.25, 0.15), .plastic, Vec3(0.2, 0.2, 0.22))
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), [.solid, .vaultable, .blocksBullets], .metal)
            fw.loot(Vec3(-0.4, s.y + 0.03, 0))
        case .tire:
            fw.mesh.material = .rubber
            fw.mesh.color = Vec3(0.12, 0.12, 0.12)
            fw.mesh.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.35, radiusTop: 0.35, height: 0.25, segments: 12)
            fw.cylinder(Vec3(0, 0.25, 0), 0.2, 0.2, 0.01, .gunMetal, Vec3(0.4, 0.4, 0.42), seg: 10)
            fw.collider(Vec3(-0.35, 0, -0.35), Vec3(0.35, 0.25, 0.35), [.solid], .dirt)
        case .radiator:
            for i in 0..<9 {
                let x = -hw + 0.05 + Float(i) * 0.1
                fw.box(Vec3(x - 0.03, 0.12, -hd), Vec3(x + 0.03, 0.12 + 0.5, hd), .metalPainted, Vec3(0.88, 0.88, 0.86))
            }
        case .coatRack:
            fw.box(Vec3(-hw, 1.55, -hd), Vec3(hw, 1.62, -hd + 0.05), .woodDark, Vec3(0.4, 0.3, 0.2))
            if r.chance(0.6) {
                fw.box(Vec3(-0.25, 0.9, -hd + 0.03), Vec3(0.15, 1.55, -hd + 0.2), .fabric, fabricColor(&r))
            }
            fw.loot(Vec3(0, 0, 0.2))
        case .fridgeUnit:
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, s.y, -hd + 0.06), .metalPainted, Vec3(0.85, 0.86, 0.88))
            fw.box(Vec3(-hw, 0, -hd), Vec3(-hw + 0.06, s.y, hd), .metalPainted, Vec3(0.85, 0.86, 0.88))
            fw.box(Vec3(hw - 0.06, 0, -hd), Vec3(hw, s.y, hd), .metalPainted, Vec3(0.85, 0.86, 0.88))
            fw.box(Vec3(-hw, s.y - 0.1, -hd), Vec3(hw, s.y, hd), .metalPainted, Vec3(0.85, 0.86, 0.88))
            fw.box(Vec3(-hw, 0, -hd), Vec3(hw, 0.15, hd), .metalPainted, Vec3(0.2, 0.2, 0.22))
            for i in 0..<4 {
                let y = 0.15 + Float(i) * 0.42
                fw.box(Vec3(-hw + 0.06, y, -hd + 0.06), Vec3(hw - 0.06, y + 0.02, hd - 0.05), .sheetMetal, Vec3(0.7, 0.7, 0.72))
                var x = -hw + 0.1
                while x < hw - 0.15 {
                    if r.chance(0.5) {
                        fw.cylinder(Vec3(x + 0.04, y + 0.02, 0), 0.035, 0.03, 0.22, .plastic,
                                    r.pick([Vec3(0.2, 0.5, 0.8), Vec3(0.8, 0.2, 0.15), Vec3(0.2, 0.6, 0.25), Vec3(0.9, 0.6, 0.1)]), seg: 6)
                    }
                    x += 0.1
                }
                fw.loot(Vec3(r.range(-0.5, 0.5), y + 0.02, 0.05))
            }
            fw.collider(Vec3(-hw, 0, -hd), Vec3(hw, s.y, hd), .furniture, .metal)
        }
    }
}

// MARK: - Rooms

enum RoomType {
    case kitchen, living, bedroom, bathroom, hallway, office, storage, ward, pharmacy, shopFloor
    case warehouseFloor, barracks, cell, armory, reception, garage, barn, empty, stairwell
}

/// A rectangular room in building-local space used for furnishing.
struct Room {
    var x0: Float, x1: Float, z0: Float, z1: Float
    var floorY: Float
    var type: RoomType
    /// Blocked intervals per side for any furniture: 0 = north (z0), 1 = south (z1), 2 = west (x0), 3 = east (x1).
    var blockedAll: [[(Float, Float)]] = [[], [], [], []]
    /// Blocked for tall furniture only (windows).
    var blockedTall: [[(Float, Float)]] = [[], [], [], []]
    var occupied: [(Float, Float, Float, Float)] = []

    init(x0: Float, x1: Float, z0: Float, z1: Float, floorY: Float, type: RoomType) {
        self.x0 = x0; self.x1 = x1; self.z0 = z0; self.z1 = z1; self.floorY = floorY; self.type = type
    }

    var width: Float { x1 - x0 }
    var depth: Float { z1 - z0 }
    var center: Vec3 { Vec3((x0 + x1) * 0.5, floorY, (z0 + z1) * 0.5) }
}

extension BuildingBuilder {

    /// Registers door/window intervals that intersect the room's walls (from the openings log) and
    /// reserves clear space in front of doorways.
    func prepareRoom(_ room: inout Room) {
        let eps: Float = 0.35
        for entry in openingsLog {
            let o = entry.o
            if abs(entry.y0 - room.floorY) > 0.5 { continue }
            let a0 = o.center - o.width * 0.5 - 0.15, a1 = o.center + o.width * 0.5 + 0.15
            var side = -1
            switch entry.axis {
            case .x:
                if a1 < room.x0 || a0 > room.x1 { continue }
                if abs(entry.fixed - room.z0) < eps { side = 0 } else if abs(entry.fixed - room.z1) < eps { side = 1 }
            case .z:
                if a1 < room.z0 || a0 > room.z1 { continue }
                if abs(entry.fixed - room.x0) < eps { side = 2 } else if abs(entry.fixed - room.x1) < eps { side = 3 }
            }
            if side < 0 { continue }
            switch o.kind {
            case .window:
                room.blockedTall[side].append((a0, a1))
            default:
                room.blockedAll[side].append((a0 - 0.1, a1 + 0.1))
                // Keep the approach clear.
                switch side {
                case 0: room.occupied.append((a0, a1, room.z0, room.z0 + 1.1))
                case 1: room.occupied.append((a0, a1, room.z1 - 1.1, room.z1))
                case 2: room.occupied.append((room.x0, room.x0 + 1.1, a0, a1))
                default: room.occupied.append((room.x1 - 1.1, room.x1, a0, a1))
                }
            }
        }
    }

    /// Tries to place a piece against a wall. Returns true on success.
    @discardableResult
    func placeAgainstWall(_ kind: FurnitureKind, room: inout Room, side preferred: Int? = nil, loot: LootCategory?, offsetFromWall: Float = 0.02) -> Bool {
        let sz = kind.size
        let sides: [Int]
        if let p = preferred { sides = [p] } else { sides = [0, 1, 2, 3].shuffledDeterministic(&rng) }
        for side in sides {
            let along0: Float, along1: Float
            switch side {
            case 0, 1: along0 = room.x0; along1 = room.x1
            default: along0 = room.z0; along1 = room.z1
            }
            let half = sz.x * 0.5
            let lo = along0 + half + 0.05, hi = along1 - half - 0.05
            if lo > hi { continue }
            var candidates: [Float] = []
            var a = lo
            while a <= hi { candidates.append(a); a += 0.15 }
            candidates = candidates.shuffledDeterministic(&rng)
            for c in candidates {
                let i0 = c - half, i1 = c + half
                var ok = true
                for b in room.blockedAll[side] where i1 > b.0 && i0 < b.1 { ok = false; break }
                if ok && kind.isTall {
                    for b in room.blockedTall[side] where i1 > b.0 && i0 < b.1 { ok = false; break }
                }
                if !ok { continue }
                // Footprint rect in room space.
                let d = sz.z + offsetFromWall
                let rect: (Float, Float, Float, Float)
                let pos: Vec3
                let rot: Int
                switch side {
                case 0:
                    rect = (i0, i1, room.z0, room.z0 + d)
                    pos = Vec3(c, room.floorY, room.z0 + offsetFromWall + sz.z * 0.5); rot = 0
                case 1:
                    rect = (i0, i1, room.z1 - d, room.z1)
                    pos = Vec3(c, room.floorY, room.z1 - offsetFromWall - sz.z * 0.5); rot = 2
                case 2:
                    rect = (room.x0, room.x0 + d, i0, i1)
                    pos = Vec3(room.x0 + offsetFromWall + sz.z * 0.5, room.floorY, c); rot = 1
                default:
                    rect = (room.x1 - d, room.x1, i0, i1)
                    pos = Vec3(room.x1 - offsetFromWall - sz.z * 0.5, room.floorY, c); rot = 3
                }
                var overlap = false
                for o in room.occupied where rect.1 > o.0 && rect.0 < o.1 && rect.3 > o.2 && rect.2 < o.3 { overlap = true; break }
                if overlap { continue }
                room.occupied.append(rect)
                room.blockedAll[side].append((i0, i1))
                placeFurniture(kind, at: pos, rotation: rot, loot: loot)
                return true
            }
        }
        return false
    }

    /// Places a free-standing piece near the room center.
    @discardableResult
    func placeCentered(_ kind: FurnitureKind, room: inout Room, rotation: Int = 0, offset: Vec2 = Vec2(0, 0), loot: LootCategory?) -> Bool {
        let sz = kind.size
        let w = rotation % 2 == 0 ? sz.x : sz.z
        let d = rotation % 2 == 0 ? sz.z : sz.x
        let c = room.center + Vec3(offset.x, 0, offset.y)
        let rect = (c.x - w * 0.5 - 0.3, c.x + w * 0.5 + 0.3, c.z - d * 0.5 - 0.3, c.z + d * 0.5 + 0.3)
        if rect.0 < room.x0 + 0.1 || rect.1 > room.x1 - 0.1 || rect.2 < room.z0 + 0.1 || rect.3 > room.z1 - 0.1 { return false }
        for o in room.occupied where rect.1 > o.0 && rect.0 < o.1 && rect.3 > o.2 && rect.2 < o.3 { return false }
        room.occupied.append(rect)
        placeFurniture(kind, at: c, rotation: rotation, loot: loot)
        return true
    }

    /// Fills a room with type-appropriate furniture and loot spots.
    func furnish(_ roomIn: Room, lootOverride: LootCategory? = nil) {
        var room = roomIn
        prepareRoom(&room)
        let L = lootOverride
        switch room.type {
        case .kitchen:
            let cat = L ?? .kitchen
            placeAgainstWall(.fridge, room: &room, loot: cat)
            placeAgainstWall(.stove, room: &room, side: 0, loot: nil)
            placeAgainstWall(.sinkCounter, room: &room, side: 0, loot: cat)
            placeAgainstWall(.counter, room: &room, side: 0, loot: cat)
            placeAgainstWall(.counter, room: &room, loot: cat)
            if room.width > 2.6 && room.depth > 2.6 {
                placeCentered(.table, room: &room, loot: cat)
                placeCentered(.chair, room: &room, rotation: 2, offset: Vec2(-0.35, -0.65), loot: nil)
                placeCentered(.chair, room: &room, rotation: 0, offset: Vec2(0.35, 0.65), loot: nil)
            }
            room.floorLoot(self, cat)
        case .living:
            let cat = L ?? .living
            if room.width > 3 && room.depth > 3 && placeCentered(.rug, room: &room, loot: nil) {
                room.occupied.removeLast()
            }
            placeAgainstWall(.sofa, room: &room, loot: cat)
            placeAgainstWall(.tvStand, room: &room, loot: cat)
            placeAgainstWall(.bookshelf, room: &room, loot: cat)
            placeAgainstWall(.armchair, room: &room, loot: cat)
            placeAgainstWall(.radiator, room: &room, loot: nil)
            placeCentered(.coffeeTable, room: &room, loot: cat)
            room.floorLoot(self, cat)
        case .bedroom:
            let cat = L ?? .bedroom
            if room.width > 3 && room.depth > 3 {
                placeAgainstWall(.doubleBed, room: &room, loot: cat)
            } else {
                placeAgainstWall(.singleBed, room: &room, loot: cat)
            }
            placeAgainstWall(.wardrobe, room: &room, loot: cat)
            placeAgainstWall(.nightstand, room: &room, loot: cat)
            placeAgainstWall(.dresser, room: &room, loot: cat)
            if rng.chance(0.5) { placeAgainstWall(.desk, room: &room, loot: cat) }
        case .bathroom:
            let cat = L ?? .bathroom
            placeAgainstWall(.bathtub, room: &room, loot: cat)
            placeAgainstWall(.toilet, room: &room, loot: nil)
            placeAgainstWall(.washbasin, room: &room, loot: cat)
            room.floorLoot(self, cat)
        case .hallway:
            placeAgainstWall(.coatRack, room: &room, loot: L ?? .living)
            if rng.chance(0.5) { placeAgainstWall(.dresser, room: &room, loot: L ?? .living) }
        case .office:
            let cat = L ?? .office
            placeAgainstWall(.desk, room: &room, loot: cat)
            placeAgainstWall(.desk, room: &room, loot: cat)
            placeAgainstWall(.filingCabinet, room: &room, loot: cat)
            placeAgainstWall(.filingCabinet, room: &room, loot: cat)
            placeAgainstWall(.bookshelf, room: &room, loot: cat)
            placeCentered(.chair, room: &room, loot: nil)
        case .storage:
            let cat = L ?? .garage
            placeAgainstWall(.shelfUnit, room: &room, loot: cat)
            placeAgainstWall(.shelfUnit, room: &room, loot: cat)
            placeAgainstWall(.crate, room: &room, loot: cat)
            placeAgainstWall(.barrel, room: &room, loot: nil)
            room.floorLoot(self, cat)
        case .ward:
            let cat = L ?? .medical
            var n = 0
            while n < 6 && placeAgainstWall(.hospitalBed, room: &room, side: n % 2 == 0 ? 0 : 1, loot: cat) {
                n += 1
            }
            placeAgainstWall(.ivStand, room: &room, loot: nil)
            placeAgainstWall(.medCabinet, room: &room, loot: cat)
            placeAgainstWall(.nightstand, room: &room, loot: cat)
            room.floorLoot(self, cat)
        case .pharmacy:
            let cat = L ?? .medical
            placeAgainstWall(.medCabinet, room: &room, loot: cat)
            placeAgainstWall(.medCabinet, room: &room, loot: cat)
            placeAgainstWall(.medCabinet, room: &room, loot: cat)
            placeAgainstWall(.counter, room: &room, loot: cat)
            placeAgainstWall(.filingCabinet, room: &room, loot: cat)
        case .shopFloor:
            let cat = L ?? .shop
            placeAgainstWall(.fridgeUnit, room: &room, side: 0, loot: cat)
            placeAgainstWall(.fridgeUnit, room: &room, side: 0, loot: cat)
            placeAgainstWall(.shelfUnit, room: &room, side: 2, loot: cat)
            placeAgainstWall(.shelfUnit, room: &room, side: 3, loot: cat)
            // Aisles of back-to-back shelving.
            let rows = max(1, Int((room.width - 3) / 2.4))
            for i in 0..<rows {
                let x = room.x0 + 2.0 + Float(i) * 2.4
                for z in [room.center.z - 1.1, room.center.z + 0.9] {
                    let rect = (x - 0.4, x + 0.4, z - 1.0, z + 1.0)
                    var ok = rect.0 > room.x0 + 1 && rect.1 < room.x1 - 1
                    for o in room.occupied where rect.1 > o.0 && rect.0 < o.1 && rect.3 > o.2 && rect.2 < o.3 { ok = false }
                    if ok {
                        room.occupied.append(rect)
                        placeFurniture(.shelfUnit, at: Vec3(x, room.floorY, z), rotation: 1, loot: cat)
                    }
                }
            }
            placeAgainstWall(.checkout, room: &room, side: 1, loot: cat)
            room.floorLoot(self, cat)
        case .warehouseFloor:
            let cat = L ?? .industrial
            for _ in 0..<4 { placeAgainstWall(.palletRack, room: &room, loot: cat) }
            for _ in 0..<5 {
                let p = Vec2(rng.range(-room.width * 0.3, room.width * 0.3), rng.range(-room.depth * 0.3, room.depth * 0.3))
                placeCentered(rng.chance(0.6) ? .pallet : .crate, room: &room, rotation: rng.int(0, 1), offset: p, loot: cat)
            }
            for _ in 0..<3 {
                let p = Vec2(rng.range(-room.width * 0.35, room.width * 0.35), rng.range(-room.depth * 0.35, room.depth * 0.35))
                placeCentered(.barrel, room: &room, offset: p, loot: nil)
            }
            room.floorLoot(self, cat)
        case .barracks:
            let cat = L ?? .military
            var n = 0
            while n < 8 && placeAgainstWall(.bunkBed, room: &room, side: n % 2 == 0 ? 0 : 1, loot: cat) {
                n += 1
            }
            for _ in 0..<3 { placeAgainstWall(.locker, room: &room, loot: cat) }
            for _ in 0..<2 { placeCentered(.footLocker, room: &room, offset: Vec2(rng.range(-1.5, 1.5), 0), loot: cat) }
            room.floorLoot(self, cat)
        case .cell:
            placeAgainstWall(.cellBench, room: &room, loot: L ?? .police)
            placeAgainstWall(.toilet, room: &room, loot: nil)
        case .armory:
            let cat = L ?? .police
            placeAgainstWall(.weaponRack, room: &room, loot: cat)
            placeAgainstWall(.weaponRack, room: &room, loot: cat)
            placeAgainstWall(.locker, room: &room, loot: cat)
            placeAgainstWall(.shelfUnit, room: &room, loot: cat)
            placeCentered(.crate, room: &room, loot: cat)
        case .reception:
            let cat = L ?? .office
            placeCentered(.receptionDesk, room: &room, rotation: 0, offset: Vec2(0, -room.depth * 0.1), loot: cat)
            placeAgainstWall(.chair, room: &room, loot: nil)
            placeAgainstWall(.chair, room: &room, loot: nil)
            placeAgainstWall(.filingCabinet, room: &room, loot: cat)
        case .garage:
            let cat = L ?? .garage
            placeAgainstWall(.workbench, room: &room, side: 0, loot: cat)
            placeAgainstWall(.shelfUnit, room: &room, loot: cat)
            placeAgainstWall(.tire, room: &room, loot: nil)
            placeAgainstWall(.barrel, room: &room, loot: nil)
            room.floorLoot(self, cat)
        case .barn:
            let cat = L ?? .farm
            for _ in 0..<6 { placeAgainstWall(.hayBale, room: &room, loot: nil) }
            placeAgainstWall(.workbench, room: &room, loot: cat)
            placeAgainstWall(.crate, room: &room, loot: cat)
            placeAgainstWall(.crate, room: &room, loot: cat)
            placeAgainstWall(.barrel, room: &room, loot: nil)
            room.floorLoot(self, cat)
        case .empty, .stairwell:
            break
        }
    }
}

extension Room {
    /// Adds a couple of floor loot spots in free space.
    func floorLoot(_ b: BuildingBuilder, _ cat: LootCategory) {
        let count = b.rng.int(1, 2)
        for _ in 0..<count {
            for _ in 0..<6 {
                let x = b.rng.range(x0 + 0.5, x1 - 0.5)
                let z = b.rng.range(z0 + 0.5, z1 - 0.5)
                var free = true
                for o in occupied where x > o.0 - 0.2 && x < o.1 + 0.2 && z > o.2 - 0.2 && z < o.3 + 0.2 { free = false; break }
                if free {
                    b.model.addLoot(Vec3(x, floorY, z), cat, large: true)
                    break
                }
            }
        }
    }
}

extension Array {
    func shuffledDeterministic(_ rng: inout RNG) -> [Element] {
        var a = self
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = rng.int(0, i)
            a.swapAt(i, j)
        }
        return a
    }
}
