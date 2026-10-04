//
//  Inventory.swift
//  Ashvale
//
//  Item instances (state: quantity, condition, contents, attachments,
//  chambered rounds), grid containers and the survivor's equipment.
//

import Foundation

enum ItemCondition: Int {
    case pristine, worn, damaged, badlyDamaged, ruined

    init(_ v: Float) {
        if v > 0.8 { self = .pristine } else if v > 0.55 { self = .worn } else if v > 0.3 { self = .damaged } else if v > 0.0 { self = .badlyDamaged } else { self = .ruined }
    }

    var name: String {
        switch self {
        case .pristine: return "Pristine"
        case .worn: return "Worn"
        case .damaged: return "Damaged"
        case .badlyDamaged: return "Badly Damaged"
        case .ruined: return "Ruined"
        }
    }
}

final class ItemInstance: Codable {
    private static var nextUID = 1
    static func makeUID() -> Int {
        nextUID += 1
        return nextUID
    }
    static func reserveUIDs(above v: Int) { nextUID = max(nextUID, v + 1) }

    let uid: Int
    let defID: String
    /// Stack count, rounds in a magazine/ammo stack, ml in a liquid container, uses for medicine.
    var quantity: Int
    var condition: Float
    var cargo: Container?
    var attachments: [Int: ItemInstance] = [:]   // AttachSlot raw -> attachment
    var magazine: ItemInstance?
    var chambered = false
    var internalRounds = 0
    var fireModeIndex = 0
    var opened = false
    var wetness: Float = 0
    var lightOn = false
    var charge: Float = 1
    /// For food: fraction remaining 0..1.
    var portion: Float = 1
    var dirty = false

    init(defID: String, quantity: Int? = nil, condition: Float = 1) {
        uid = ItemInstance.makeUID()
        self.defID = defID
        let d = ItemDB.get(defID)
        // Defaults: magazines and refillable bottles start empty, everything else is a single unit.
        let empty = d?.magazine != nil || d?.food?.liquidContainer == true
        self.quantity = quantity ?? (empty ? 0 : (d?.medicalUses ?? 1))
        self.condition = condition
        if let c = d?.clothing?.cargo {
            cargo = Container(width: c.w, height: c.h)
        }
    }

    var def: ItemDef { ItemDB.get(defID)! }
    var conditionLevel: ItemCondition { ItemCondition(condition) }
    var isRuined: Bool { condition <= 0 }

    /// Display name including stack counts.
    var displayName: String { def.name }

    var quantityText: String? {
        let d = def
        if d.isStackable { return "\(quantity)" }
        if d.magazine != nil { return "\(quantity)/\(d.magazine!.capacity)" }
        if let f = d.food, f.liquidContainer { return "\(quantity)ml" }
        if d.medical != nil && d.medicalUses > 1 { return "×\(quantity)" }
        if d.category == .food, portion < 0.99 { return "\(Int(portion * 100))%" }
        if d.isFirearm {
            let w = d.weapon!
            let rounds = (magazine?.quantity ?? 0) + internalRounds + (chambered ? 1 : 0)
            if w.magazineID != nil || w.internalCapacity > 0 { return "\(rounds)" }
        }
        return nil
    }

    var weight: Float {
        let d = def
        var w = d.weight
        if d.isStackable { w *= Float(quantity) }
        if let f = d.food, f.liquidContainer { w += Float(quantity) / 1000 }
        if let c = cargo { w += c.totalWeight }
        for a in attachments.values { w += a.weight }
        if let m = magazine { w += m.weight }
        if d.magazine != nil { w += Float(quantity) * 0.012 }
        return w
    }

    func attachment(_ s: AttachSlot) -> ItemInstance? { attachments[s.rawValue] }

    /// Total rounds ready to fire.
    var roundsLoaded: Int { (magazine?.quantity ?? 0) + internalRounds + (chambered ? 1 : 0) }

    func findNested(uid: Int) -> ItemInstance? {
        if self.uid == uid { return self }
        if let m = magazine, m.uid == uid { return m }
        for a in attachments.values where a.uid == uid { return a }
        if let c = cargo { return c.find(uid: uid) }
        return nil
    }

    func maxUID() -> Int {
        var m = uid
        if let mg = magazine { m = max(m, mg.maxUID()) }
        for a in attachments.values { m = max(m, a.maxUID()) }
        if let c = cargo { for e in c.entries { m = max(m, e.item.maxUID()) } }
        return m
    }

    /// Deep copy keeping uids (used for background saving).
    func clone() -> ItemInstance {
        let c = ItemInstance(uid: uid, defID: defID)
        c.quantity = quantity
        c.condition = condition
        c.cargo = cargo?.clone()
        c.attachments = attachments.mapValues { $0.clone() }
        c.magazine = magazine?.clone()
        c.chambered = chambered
        c.internalRounds = internalRounds
        c.fireModeIndex = fireModeIndex
        c.opened = opened
        c.wetness = wetness
        c.lightOn = lightOn
        c.charge = charge
        c.portion = portion
        c.dirty = dirty
        return c
    }

    private init(uid: Int, defID: String) {
        self.uid = uid
        self.defID = defID
        quantity = 1
        condition = 1
    }

    /// Creates a copy with a new uid (used when splitting stacks).
    func split(count: Int) -> ItemInstance? {
        guard def.isStackable, count > 0, count < quantity else { return nil }
        let n = ItemInstance(defID: defID, quantity: count, condition: condition)
        quantity -= count
        return n
    }
}

struct GridEntry: Codable {
    var item: ItemInstance
    var x: Int
    var y: Int
    var rotated: Bool

    var w: Int { rotated ? item.def.size.h : item.def.size.w }
    var h: Int { rotated ? item.def.size.w : item.def.size.h }
}

final class Container: Codable {
    let width: Int
    let height: Int
    private(set) var entries: [GridEntry] = []

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var totalWeight: Float { entries.reduce(0) { $0 + $1.item.weight } }
    var items: [ItemInstance] { entries.map { $0.item } }
    var isEmpty: Bool { entries.isEmpty }

    func fits(_ item: ItemInstance) -> Bool {
        let s = item.def.size
        return (s.w <= width && s.h <= height) || (s.h <= width && s.w <= height)
    }

    func canPlace(_ item: ItemInstance, x: Int, y: Int, rotated: Bool, ignoring: Int? = nil) -> Bool {
        let w = rotated ? item.def.size.h : item.def.size.w
        let h = rotated ? item.def.size.w : item.def.size.h
        if x < 0 || y < 0 || x + w > width || y + h > height { return false }
        for e in entries where e.item.uid != ignoring && e.item.uid != item.uid {
            if x < e.x + e.w && x + w > e.x && y < e.y + e.h && y + h > e.y { return false }
        }
        return true
    }

    func findSpace(_ item: ItemInstance) -> (Int, Int, Bool)? {
        for rot in [false, true] {
            for y in 0..<height {
                for x in 0..<width where canPlace(item, x: x, y: y, rotated: rot) {
                    return (x, y, rot)
                }
            }
        }
        return nil
    }

    /// Merges into existing stacks first, then places in free space. Returns false if it did not fit.
    @discardableResult
    func add(_ item: ItemInstance) -> Bool {
        if item.def.isStackable {
            for e in entries where e.item.defID == item.defID && e.item.quantity < item.def.stackMax {
                let space = item.def.stackMax - e.item.quantity
                let n = min(space, item.quantity)
                e.item.quantity += n
                item.quantity -= n
                if item.quantity <= 0 { return true }
            }
        }
        guard let spot = findSpace(item) else { return false }
        entries.append(GridEntry(item: item, x: spot.0, y: spot.1, rotated: spot.2))
        return true
    }

    func place(_ item: ItemInstance, x: Int, y: Int, rotated: Bool) -> Bool {
        guard canPlace(item, x: x, y: y, rotated: rotated) else { return false }
        entries.removeAll { $0.item.uid == item.uid }
        entries.append(GridEntry(item: item, x: x, y: y, rotated: rotated))
        return true
    }

    @discardableResult
    func remove(uid: Int) -> ItemInstance? {
        guard let i = entries.firstIndex(where: { $0.item.uid == uid }) else { return nil }
        return entries.remove(at: i).item
    }

    func entry(uid: Int) -> GridEntry? { entries.first { $0.item.uid == uid } }

    func find(uid: Int) -> ItemInstance? {
        for e in entries {
            if let f = e.item.findNested(uid: uid) { return f }
        }
        return nil
    }

    func contains(uid: Int) -> Bool { entries.contains { $0.item.uid == uid } }

    func clone() -> Container {
        let c = Container(width: width, height: height)
        c.entries = entries.map { GridEntry(item: $0.item.clone(), x: $0.x, y: $0.y, rotated: $0.rotated) }
        return c
    }
}

/// What the survivor wears and holds.
final class Equipment: Codable {
    var slots: [Int: ItemInstance] = [:]    // EquipSlot raw -> item
    var hands: ItemInstance?
    var quickSlots: [Int?] = [nil, nil, nil, nil, nil]

    init() {}

    func item(_ s: EquipSlot) -> ItemInstance? { slots[s.rawValue] }

    /// Worn containers in display order.
    var containers: [(EquipSlot, ItemInstance, Container)] {
        var out: [(EquipSlot, ItemInstance, Container)] = []
        for s in [EquipSlot.torso, .legs, .vest, .backpack] {
            if let it = slots[s.rawValue], let c = it.cargo { out.append((s, it, c)) }
        }
        return out
    }

    var allItems: [ItemInstance] {
        var out: [ItemInstance] = []
        if let h = hands { out.append(h) }
        for s in EquipSlot.allCases { if let i = slots[s.rawValue] { out.append(i) } }
        for (_, _, c) in containers { out.append(contentsOf: c.items) }
        return out
    }

    var totalWeight: Float {
        var w: Float = hands?.weight ?? 0
        for i in slots.values { w += i.weight }
        return w
    }

    enum Location {
        case hands
        case slot(EquipSlot)
        case cargo(EquipSlot, Container)
        case nested(ItemInstance)   // attachment or magazine inside another item
    }

    func locate(uid: Int) -> Location? {
        if hands?.uid == uid { return .hands }
        for (k, v) in slots where v.uid == uid { return .slot(EquipSlot(rawValue: k)!) }
        for (s, _, c) in containers where c.contains(uid: uid) { return .cargo(s, c) }
        if let h = hands, h.uid != uid, h.findNested(uid: uid) != nil { return .nested(h) }
        for v in slots.values where v.findNested(uid: uid) != nil && v.uid != uid { return .nested(v) }
        return nil
    }

    func find(uid: Int) -> ItemInstance? {
        if let h = hands, let f = h.findNested(uid: uid) { return f }
        for v in slots.values { if let f = v.findNested(uid: uid) { return f } }
        return nil
    }

    /// Removes an item wherever it is (hands, slot, cargo, weapon attachment/magazine).
    @discardableResult
    func remove(uid: Int) -> ItemInstance? {
        if let h = hands, h.uid == uid {
            hands = nil
            return h
        }
        for (k, v) in slots where v.uid == uid {
            slots.removeValue(forKey: k)
            return v
        }
        for (_, _, c) in containers {
            if let r = c.remove(uid: uid) { return r }
        }
        // Nested in a weapon.
        let holders = [hands].compactMap { $0 } + Array(slots.values) + containers.flatMap { $0.2.items }
        for hItem in holders {
            if let m = hItem.magazine, m.uid == uid {
                hItem.magazine = nil
                return m
            }
            for (k, a) in hItem.attachments where a.uid == uid {
                hItem.attachments.removeValue(forKey: k)
                return a
            }
        }
        return nil
    }

    /// Tries to put an item into any worn container.
    func addToCargo(_ item: ItemInstance) -> Bool {
        for (_, _, c) in containers where c.add(item) { return true }
        return false
    }

    func count(where pred: (ItemInstance) -> Bool) -> Int {
        allItems.filter(pred).count
    }

    func firstItem(where pred: (ItemInstance) -> Bool) -> ItemInstance? {
        if let h = hands, pred(h) { return h }
        for (_, _, c) in containers {
            if let f = c.items.first(where: pred) { return f }
        }
        for v in slots.values where pred(v) { return v }
        return nil
    }

    func maxUID() -> Int {
        var m = hands?.maxUID() ?? 0
        for v in slots.values { m = max(m, v.maxUID()) }
        return m
    }

    func clone() -> Equipment {
        let e = Equipment()
        e.slots = slots.mapValues { $0.clone() }
        e.hands = hands?.clone()
        e.quickSlots = quickSlots
        return e
    }
}
