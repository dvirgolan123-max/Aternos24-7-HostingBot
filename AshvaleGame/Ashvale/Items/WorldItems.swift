//
//  WorldItems.swift
//  Ashvale
//
//  Every item that is not carried exists physically in the world: on floors,
//  shelves, tables, beds, next to vehicles. Items can be picked up, dropped
//  and thrown (with gravity, bouncing and settling).
//

import Foundation

final class WorldItem {
    let id: Int
    var item: ItemInstance
    var position: Vec3
    var yaw: Float
    var velocity = Vec3(0, 0, 0)
    var spin = Vec3(0, 0, 0)
    var tilt = Vec3(0, 0, 0)      // tumbling rotation while airborne (pitch, roll, unused)
    var resting = true
    var lootSpot: Int = -1

    init(id: Int, item: ItemInstance, position: Vec3, yaw: Float) {
        self.id = id
        self.item = item
        self.position = position
        self.yaw = yaw
    }
}

final class WorldItemSystem {
    private(set) var items: [Int: WorldItem] = [:]
    private var cells: [Int: [Int]] = [:]
    private var nextID = 1
    private let cellSize: Float = 8
    /// Loot spot indices that have been looted (or spawned) – persisted with the save.
    var spawnedSpots = Set<Int>()

    @inline(__always) private func cellKey(_ p: Vec3) -> Int {
        let cx = Int(floorf(p.x / cellSize)), cz = Int(floorf(p.z / cellSize))
        return cz * 1024 + cx
    }

    func removeAll() {
        items.removeAll()
        cells.removeAll()
        spawnedSpots.removeAll()
    }

    @discardableResult
    func add(_ item: ItemInstance, at p: Vec3, yaw: Float, velocity: Vec3? = nil, lootSpot: Int = -1) -> WorldItem {
        let wi = WorldItem(id: nextID, item: item, position: p, yaw: yaw)
        nextID += 1
        wi.lootSpot = lootSpot
        if let v = velocity {
            wi.velocity = v
            wi.resting = false
            wi.spin = Vec3(Float.random(in: -8...8), Float.random(in: -5...5), Float.random(in: -8...8))
        }
        items[wi.id] = wi
        cells[cellKey(p), default: []].append(wi.id)
        return wi
    }

    @discardableResult
    func remove(id: Int) -> ItemInstance? {
        guard let wi = items.removeValue(forKey: id) else { return nil }
        let k = cellKey(wi.position)
        cells[k]?.removeAll { $0 == id }
        return wi.item
    }

    private func move(_ wi: WorldItem, to p: Vec3) {
        let a = cellKey(wi.position), b = cellKey(p)
        wi.position = p
        if a != b {
            cells[a]?.removeAll { $0 == wi.id }
            cells[b, default: []].append(wi.id)
        }
    }

    func query(center c: Vec3, radius r: Float) -> [WorldItem] {
        var out: [WorldItem] = []
        let x0 = Int(floorf((c.x - r) / cellSize)), x1 = Int(floorf((c.x + r) / cellSize))
        let z0 = Int(floorf((c.z - r) / cellSize)), z1 = Int(floorf((c.z + r) / cellSize))
        for cz in z0...z1 {
            for cx in x0...x1 {
                guard let list = cells[cz * 1024 + cx] else { continue }
                for id in list {
                    if let wi = items[id], vdistance(wi.position, c) <= r { out.append(wi) }
                }
            }
        }
        return out
    }

    /// Simulates airborne (dropped / thrown) items.
    func update(dt: Float, world: World, onImpact: (WorldItem, Float) -> Void) {
        for wi in items.values where !wi.resting {
            let old = wi.position
            wi.velocity.y -= 9.81 * dt
            var p = old + wi.velocity * dt
            wi.tilt += wi.spin * dt
            // Collide with world geometry along the path.
            let delta = p - old
            let len = vlength(delta)
            if len > 1e-5 {
                let dir = delta / len
                if let hit = world.collision.raycast(origin: old, direction: dir, maxDistance: len + 0.05, mask: .solid) {
                    p = hit.point - dir * 0.03
                    let n = hit.normal
                    let vn = vdot(wi.velocity, n)
                    wi.velocity = (wi.velocity - n * (vn * 1.45)) * 0.55
                    wi.spin *= 0.5
                    onImpact(wi, abs(vn))
                }
            }
            // Ground.
            let g = world.groundHeight(at: p, radius: 0.05, stepHeight: 0.05)
            if p.y <= g.height {
                p.y = g.height
                let impact = abs(wi.velocity.y)
                if impact > 1.5 { onImpact(wi, impact) }
                wi.velocity.y = -wi.velocity.y * 0.3
                wi.velocity.x *= 0.6
                wi.velocity.z *= 0.6
                wi.spin *= 0.6
                if vlength(wi.velocity) < 0.6 {
                    wi.resting = true
                    wi.velocity = Vec3(0, 0, 0)
                    wi.tilt = Vec3(0, 0, 0)
                    wi.yaw += wi.spin.y * 0.1
                }
            }
            if p.y < world.terrain.height(p.x, p.z) - 0.5 {
                p.y = world.terrain.height(p.x, p.z)
                wi.resting = true
            }
            move(wi, to: p)
        }
    }

    var count: Int { items.count }

    func maxUID() -> Int {
        var m = 0
        for wi in items.values { m = max(m, wi.item.maxUID()) }
        return m
    }
}

// MARK: - Loot generation

enum LootSpawner {
    private static var tables: [LootCategory: [(ItemDef, Float)]] = [:]

    private static func table(_ c: LootCategory) -> [(ItemDef, Float)] {
        if let t = tables[c] { return t }
        let t = ItemDB.ordered.compactMap { d -> (ItemDef, Float)? in
            guard let w = d.loot[c], w > 0 else { return nil }
            return (d, w)
        }
        tables[c] = t
        return t
    }

    static func pick(_ c: LootCategory, large: Bool, rng: inout RNG) -> ItemDef? {
        let t = table(c).filter { large || !$0.0.largeLoot }
        guard !t.isEmpty else { return nil }
        let i = rng.weightedIndex(t.map { $0.1 })
        return t[i].0
    }

    static func randomCondition(_ rng: inout RNG) -> Float {
        let r = rng.float()
        if r < 0.25 { return rng.range(0.82, 1.0) }
        if r < 0.7 { return rng.range(0.56, 0.8) }
        if r < 0.92 { return rng.range(0.31, 0.55) }
        return rng.range(0.08, 0.3)
    }

    /// Builds an item instance with randomized but plausible state.
    static func makeInstance(_ d: ItemDef, rng: inout RNG) -> ItemInstance {
        let it = ItemInstance(defID: d.id, condition: randomCondition(&rng))
        if d.isStackable {
            if d.ammo != nil {
                it.quantity = rng.int(4, min(d.stackMax, 24))
            } else {
                it.quantity = rng.int(1, max(1, d.stackMax / 2))
            }
        }
        if let m = d.magazine {
            it.quantity = rng.chance(0.4) ? 0 : rng.int(1, max(1, m.capacity * 2 / 3))
        }
        if let f = d.food {
            if f.liquidContainer {
                it.quantity = rng.chance(0.35) ? 0 : Int(f.capacity * rng.range(0.2, 1.0))
            } else if rng.chance(0.15) && !f.needsOpening {
                it.portion = rng.range(0.4, 0.9)
            }
        }
        if d.medical != nil && d.medicalUses > 1 {
            it.quantity = rng.int(max(1, d.medicalUses / 3), d.medicalUses)
        }
        if let w = d.weapon, d.isFirearm {
            if let magID = w.magazineID, rng.chance(0.35), let md = ItemDB.get(magID), let mp = md.magazine {
                let m = ItemInstance(defID: magID, condition: randomCondition(&rng))
                m.quantity = rng.int(0, mp.capacity / 2)
                it.magazine = m
            }
            if w.internalCapacity > 0 && rng.chance(0.4) {
                it.internalRounds = rng.int(1, w.internalCapacity / 2)
            }
            // Rare factory attachments.
            for s in w.attachSlots where rng.chance(0.12) {
                if let ad = ItemDB.ordered.first(where: { $0.attachment?.slot == s && $0.attachment!.compatible.contains(d.id) }) {
                    it.attachments[s.rawValue] = ItemInstance(defID: ad.id, condition: randomCondition(&rng))
                }
            }
        }
        if let t = d.tool, t == .flashlight {
            it.charge = rng.range(0.1, 1)
        }
        if d.id == "weaponlight" { it.charge = rng.range(0.2, 1) }
        if d.clothing?.cargo != nil, rng.chance(0.15), let c = it.cargo {
            // Something left in a pocket.
            if let extra = pick(.living, large: false, rng: &rng), extra.clothing == nil {
                c.add(makeInstance(extra, rng: &rng))
            }
        }
        return it
    }

    /// Fills the world's loot spots.
    static func populate(world: World, items: WorldItemSystem, rng: inout RNG, lootMultiplier: Float) {
        for (i, spot) in world.lootSpots.enumerated() {
            var chance: Float = 0.42
            switch spot.category {
            case .military: chance = 0.5
            case .police, .medical: chance = 0.55
            case .vehicle: chance = 0.45
            case .kitchen, .shop: chance = 0.5
            default: break
            }
            chance = min(0.95, chance * lootMultiplier)
            items.spawnedSpots.insert(i)
            guard rng.chance(chance), let d = pick(spot.category, large: spot.large, rng: &rng) else { continue }
            let inst = makeInstance(d, rng: &rng)
            items.add(inst, at: spot.position + Vec3(0, 0.005, 0), yaw: spot.yaw + rng.range(-0.4, 0.4), lootSpot: i)
        }
    }
}
