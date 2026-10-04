//
//  GameItems.swift
//  Ashvale
//
//  Item handling: picking up, dropping and throwing physical items, wearing
//  clothing, hands and quick slots, grid inventory moves, combining items
//  (ammo into magazines, magazines and attachments onto weapons), and timed
//  use actions (eat, drink, open cans, medicine, repairs, filling bottles).
//

import Foundation

struct ItemAction {
    let title: String
    let perform: () -> Void
}

extension Game {

    // MARK: Lookup

    func worldItem(uid: Int) -> WorldItem? {
        items.items.values.first { $0.item.uid == uid }
    }

    func findItem(uid: Int) -> ItemInstance? {
        if let it = equipment.find(uid: uid) { return it }
        return worldItem(uid: uid)?.item
    }

    func isCarried(uid: Int) -> Bool { equipment.find(uid: uid) != nil }

    /// Items lying within reach (for the VICINITY panel).
    func vicinityItems() -> [WorldItem] {
        items.query(center: player.position + Vec3(0, 0.8, 0), radius: 2.4)
            .filter { $0.resting }
            .sorted { vdistance($0.position, player.position) < vdistance($1.position, player.position) }
    }

    /// Removes an item from wherever it is (equipment or world).
    func takeItem(uid: Int) -> ItemInstance? {
        if let it = equipment.remove(uid: uid) {
            return it
        }
        if let wi = worldItem(uid: uid) {
            return items.remove(id: wi.id)
        }
        return nil
    }

    /// Puts an item back on the ground in front of the player.
    func placeOnGround(_ it: ItemInstance, near: Vec3? = nil) {
        let base = near ?? (player.position + flatForward(yaw: player.yaw) * 0.5)
        var p = base + Vec3(rng.range(-0.2, 0.2), 0.5, rng.range(-0.2, 0.2))
        p.y = world.groundHeight(at: p, radius: 0.05, stepHeight: 0).height
        items.add(it, at: p, yaw: rng.range(0, kTwoPi))
    }

    // MARK: Pick up / drop / throw

    func pickUp(worldItemID id: Int) {
        guard let wi = items.items[id] else { return }
        let it = wi.item
        let d = it.def
        var placed = false
        // Clothing goes on if the slot is free.
        if let c = d.clothing, equipment.item(c.slot) == nil {
            _ = items.remove(id: id)
            equipment.slots[c.slot.rawValue] = it
            refreshAppearance()
            placed = true
            message("Equipped \(d.name)")
        } else if (d.isFirearm || d.isMelee) && equipment.hands == nil {
            _ = items.remove(id: id)
            equipment.hands = it
            placed = true
            weapon = WeaponRuntime()
        } else if d.isLong && equipment.item(.shoulder) == nil {
            _ = items.remove(id: id)
            equipment.slots[EquipSlot.shoulder.rawValue] = it
            placed = true
        } else if canFitInCargo(it) {
            _ = items.remove(id: id)
            placed = equipment.addToCargo(it)
            if !placed { placeOnGround(it, near: wi.position) }
        } else if equipment.hands == nil {
            _ = items.remove(id: id)
            equipment.hands = it
            placed = true
        }
        if placed {
            sounds.play(.pickup, at: wi.position, volume: 0.6)
            message("Picked up \(d.name)\(it.quantityText.map { " (\($0))" } ?? "")")
            autoAssignQuickSlot(it)
        } else {
            message("No room for \(d.name). Free your hands or find a bigger container.")
        }
    }

    func canFitInCargo(_ it: ItemInstance) -> Bool {
        for (_, _, c) in equipment.containers {
            if it.def.isStackable && c.items.contains(where: { $0.defID == it.defID && $0.quantity < it.def.stackMax }) { return true }
            if c.findSpace(it) != nil { return true }
        }
        return false
    }

    func dropItem(uid: Int) {
        guard let it = takeItem(uid: uid) else { return }
        if equipment.hands == nil { weapon = WeaponRuntime() }
        placeOnGround(it)
        sounds.play(.drop, at: player.position, volume: 0.5)
        if it.def.clothing != nil { refreshAppearance() }
        clearQuickSlotsFor(uid: uid)
    }

    func throwHeld() {
        guard let it = equipment.hands else { return }
        equipment.hands = nil
        weapon = WeaponRuntime()
        let dir = directionFrom(yaw: camYaw, pitch: camPitch + 0.15)
        let start = player.position + Vec3(0, player.body.eyeHeight - 0.2, 0) + flatForward(yaw: camYaw) * 0.4
        let strength: Float = it.weight > 2 ? 6 : 10
        items.add(it, at: start, yaw: rng.range(0, kTwoPi), velocity: dir * strength + player.body.velocity * 0.5)
        sounds.play(.throwItem, at: start, volume: 0.6)
        player.pose.attack = 0
        clearQuickSlotsFor(uid: it.uid)
        message("Threw \(it.def.name)")
    }

    // MARK: Equipment

    func canEquip(_ it: ItemInstance, to slot: EquipSlot) -> Bool {
        if slot == .shoulder { return it.def.isFirearm || it.def.isMelee }
        return it.def.clothing?.slot == slot
    }

    /// Moves an item into a slot, swapping the previous one to cargo/ground.
    @discardableResult
    func equip(uid: Int, to slot: EquipSlot) -> Bool {
        guard let it = findItem(uid: uid), canEquip(it, to: slot) else { return false }
        if let existing = equipment.item(slot), existing.uid != uid {
            // Swap the old item into the source location if possible.
            _ = takeItem(uid: uid)
            equipment.slots.removeValue(forKey: slot.rawValue)
            equipment.slots[slot.rawValue] = it
            if !equipment.addToCargo(existing) {
                if equipment.hands == nil { equipment.hands = existing } else { placeOnGround(existing) }
            }
        } else {
            _ = takeItem(uid: uid)
            equipment.slots[slot.rawValue] = it
        }
        if equipment.hands == nil { weapon = WeaponRuntime() }
        refreshAppearance()
        sounds.play(.equip, at: player.position, volume: 0.5)
        return true
    }

    @discardableResult
    func toHands(uid: Int) -> Bool {
        guard let it = findItem(uid: uid) else { return false }
        if equipment.hands?.uid == uid { return true }
        if let current = equipment.hands {
            // Put away what is currently held.
            equipment.hands = nil
            if !(stashOnBody(current)) {
                equipment.hands = current
                message("No room to put away \(current.def.name)")
                return false
            }
        }
        guard let taken = takeItem(uid: uid) else { return false }
        _ = it
        equipment.hands = taken
        weapon = WeaponRuntime()
        refreshAppearance()
        sounds.play(.equip, at: player.position, volume: 0.6)
        return true
    }

    /// Puts an item on the body: shoulder for long weapons, otherwise cargo.
    func stashOnBody(_ it: ItemInstance) -> Bool {
        if (it.def.isFirearm || it.def.isMelee) && equipment.item(.shoulder) == nil {
            equipment.slots[EquipSlot.shoulder.rawValue] = it
            return true
        }
        return equipment.addToCargo(it)
    }

    func holsterHands() {
        guard let h = equipment.hands else { return }
        equipment.hands = nil
        if !stashOnBody(h) {
            equipment.hands = h
            message("No room to put away \(h.def.name)")
        } else {
            weapon = WeaponRuntime()
        }
    }

    /// Places an item at an exact grid position in a worn container.
    @discardableResult
    func placeInCargo(uid: Int, slot: EquipSlot, x: Int, y: Int, rotated: Bool) -> Bool {
        guard let holder = equipment.item(slot), let c = holder.cargo, let it = findItem(uid: uid) else { return false }
        if holder.uid == uid { return false }
        // Merge onto a stack of the same item at that cell.
        if it.def.isStackable, let e = c.entries.first(where: { $0.item.defID == it.defID && $0.item.uid != uid && x >= $0.x && x < $0.x + $0.w && y >= $0.y && y < $0.y + $0.h }) {
            let space = it.def.stackMax - e.item.quantity
            if space > 0 {
                let n = min(space, it.quantity)
                e.item.quantity += n
                it.quantity -= n
                if it.quantity <= 0 { _ = takeItem(uid: uid) }
                return true
            }
        }
        if c.contains(uid: uid) {
            return c.place(it, x: x, y: y, rotated: rotated)
        }
        guard c.canPlace(it, x: x, y: y, rotated: rotated) else { return false }
        guard let taken = takeItem(uid: uid) else { return false }
        if !c.place(taken, x: x, y: y, rotated: rotated) {
            placeOnGround(taken)
            return false
        }
        if equipment.hands == nil { weapon = WeaponRuntime() }
        refreshAppearance()
        return true
    }

    @discardableResult
    func stashToCargo(uid: Int) -> Bool {
        guard let it = findItem(uid: uid), canFitInCargo(it) else {
            message("Not enough space")
            return false
        }
        guard let taken = takeItem(uid: uid) else { return false }
        if !equipment.addToCargo(taken) {
            placeOnGround(taken)
            return false
        }
        if equipment.hands == nil { weapon = WeaponRuntime() }
        refreshAppearance()
        return true
    }

    // MARK: Quick slots

    func autoAssignQuickSlot(_ it: ItemInstance) {
        let d = it.def
        guard d.isFirearm || d.isMelee || d.medical == .bandage || d.tool == .flashlight else { return }
        if equipment.quickSlots.contains(where: { $0 == it.uid }) { return }
        if let i = equipment.quickSlots.firstIndex(where: { $0 == nil || findItem(uid: $0!) == nil || !isCarried(uid: $0!) }) {
            equipment.quickSlots[i] = it.uid
        }
    }

    func assignQuickSlot(_ i: Int, uid: Int) {
        guard i >= 0 && i < equipment.quickSlots.count else { return }
        for k in 0..<equipment.quickSlots.count where equipment.quickSlots[k] == uid { equipment.quickSlots[k] = nil }
        equipment.quickSlots[i] = uid
    }

    func clearQuickSlot(_ i: Int) {
        guard i >= 0 && i < equipment.quickSlots.count else { return }
        equipment.quickSlots[i] = nil
        message("Quick slot \(i + 1) cleared")
    }

    func clearQuickSlotsFor(uid: Int) {
        for k in 0..<equipment.quickSlots.count where equipment.quickSlots[k] == uid { equipment.quickSlots[k] = nil }
    }

    func activateQuickSlot(_ i: Int) {
        guard i >= 0 && i < equipment.quickSlots.count, let uid = equipment.quickSlots[i] else { return }
        guard let it = equipment.find(uid: uid) else {
            equipment.quickSlots[i] = nil
            return
        }
        if equipment.hands?.uid == uid {
            holsterHands()
        } else if it.def.category == .medical || it.def.category == .food || it.def.category == .drink {
            useItem(uid: uid)
        } else {
            toHands(uid: uid)
        }
    }

    // MARK: Combining

    /// Result of dropping `uid` onto `target`.
    @discardableResult
    func combine(uid: Int, onto targetUID: Int) -> Bool {
        guard uid != targetUID, let src = findItem(uid: uid), let dst = findItem(uid: targetUID) else { return false }
        let sd = src.def, dd = dst.def
        // Ammo into magazine.
        if let cal = sd.ammo, let mp = dd.magazine {
            guard cal == mp.caliber else {
                message("\(sd.name) doesn't fit in a \(dd.name)")
                return false
            }
            loadRounds(ammoUID: uid, magazineUID: targetUID)
            return true
        }
        // Ammo directly into a weapon (internal magazine / chamber).
        if let cal = sd.ammo, let w = dd.weapon, dd.isFirearm {
            guard w.caliber == cal else {
                message("\(sd.name) doesn't fit the \(dd.name)")
                return false
            }
            if w.internalCapacity > 0 {
                let space = w.internalCapacity - dst.internalRounds
                if space <= 0 { message("\(dd.name) is full"); return false }
                let n = min(space, src.quantity)
                dst.internalRounds += n
                src.quantity -= n
                if src.quantity <= 0 { _ = takeItem(uid: uid) }
                if !dst.chambered && dst.internalRounds > 0 {
                    dst.internalRounds -= 1
                    dst.chambered = true
                }
                sounds.play(.shellInsert, at: player.position, volume: 0.6)
                message("Loaded \(n) shells into \(dd.name)")
                return true
            }
            if !dst.chambered {
                dst.chambered = true
                src.quantity -= 1
                if src.quantity <= 0 { _ = takeItem(uid: uid) }
                sounds.play(.chamber, at: player.position, volume: 0.6)
                message("Chambered a round")
                return true
            }
            message("Load rounds into a magazine first")
            return false
        }
        // Magazine into firearm.
        if sd.magazine != nil, let w = dd.weapon, dd.isFirearm {
            guard w.magazineID == sd.id else {
                message("\(sd.name) doesn't fit the \(dd.name)")
                return false
            }
            guard let mag = takeItem(uid: uid) else { return false }
            if let old = dst.magazine {
                dst.magazine = nil
                if !equipment.addToCargo(old) { placeOnGround(old) }
            }
            dst.magazine = mag
            if !dst.chambered && mag.quantity > 0 && dst.uid == equipment.hands?.uid {
                message("Inserted magazine. Press RELOAD to chamber a round.")
            } else {
                message("Inserted \(sd.name)")
            }
            sounds.play(.magIn, at: player.position, volume: 0.7)
            return true
        }
        // Attachment onto firearm.
        if let ap = sd.attachment, dd.isFirearm, let w = dd.weapon {
            guard w.attachSlots.contains(ap.slot), ap.compatible.contains(dd.id) else {
                message("\(sd.name) is not compatible with the \(dd.name)")
                return false
            }
            guard let att = takeItem(uid: uid) else { return false }
            if let old = dst.attachments[ap.slot.rawValue] {
                if !equipment.addToCargo(old) { placeOnGround(old) }
            }
            dst.attachments[ap.slot.rawValue] = att
            sounds.play(.equip, at: player.position, volume: 0.6)
            message("Attached \(sd.name)")
            return true
        }
        // Battery into a light.
        if sd.tool == .battery && (dd.tool == .flashlight || dd.attachment?.light == true || dst.attachment(.rail) != nil) {
            let light = dd.tool == .flashlight || dd.attachment?.light == true ? dst : dst.attachment(.rail)!
            light.charge = 1
            src.quantity -= 1
            if src.quantity <= 0 { _ = takeItem(uid: uid) }
            message("Replaced the battery")
            return true
        }
        // Repair kits.
        if let t = sd.tool, [.ductTape, .sewingKit, .cleaningKit].contains(t) {
            return repair(target: dst, kit: src)
        }
        // Stack merge.
        if sd.id == dd.id && sd.isStackable {
            let space = dd.stackMax - dst.quantity
            guard space > 0 else { return false }
            let n = min(space, src.quantity)
            dst.quantity += n
            src.quantity -= n
            if src.quantity <= 0 { _ = takeItem(uid: uid) }
            return true
        }
        // Liquid transfer between containers.
        if let fs = sd.food, fs.liquidContainer, let fd = dd.food, fd.liquidContainer {
            let n = min(src.quantity, Int(fd.capacity) - dst.quantity)
            if n > 0 {
                src.quantity -= n
                dst.quantity += n
                dst.dirty = dst.dirty || src.dirty
                message("Poured \(n) ml")
                return true
            }
        }
        return false
    }

    func repair(target: ItemInstance, kit: ItemInstance) -> Bool {
        guard let t = kit.def.tool else { return false }
        let d = target.def
        let ok: Bool
        switch t {
        case .sewingKit: ok = d.clothing != nil
        case .cleaningKit: ok = d.isFirearm
        case .ductTape: ok = d.clothing != nil || d.isMelee || d.isFirearm || d.category == .tool
        default: ok = false
        }
        guard ok else {
            message("\(kit.def.name) can't repair \(d.name)")
            return false
        }
        guard target.condition < 0.99 else {
            message("\(d.name) is already in good condition")
            return false
        }
        let kitUID = kit.uid
        action = TimedAction("Repairing \(d.name)", duration: 5) { [weak self] in
            guard let self = self else { return }
            let gain: Float = t == .cleaningKit ? 0.4 : (t == .sewingKit ? 0.35 : 0.22)
            target.condition = min(1, target.condition + gain)
            if let k = self.findItem(uid: kitUID) {
                k.condition -= 0.25
                if k.condition <= 0 { _ = self.takeItem(uid: kitUID) }
            }
            self.message("Repaired \(d.name) (\(target.conditionLevel.name))")
        }
        return true
    }

    // MARK: Ammunition

    func loadRounds(ammoUID: Int, magazineUID: Int) {
        guard let mag = findItem(uid: magazineUID), let mp = mag.def.magazine else { return }
        guard mag.quantity < mp.capacity else {
            message("\(mag.def.name) is already full")
            return
        }
        let magName = mag.def.name
        let a = TimedAction("Loading \(magName)", duration: 999) { }
        var acc: Float = 0
        a.onTick = { [weak self] dt in
            guard let self = self, let ammo = self.findItem(uid: ammoUID), let m = self.findItem(uid: magazineUID) else { return false }
            acc += dt
            while acc > 0.22 {
                acc -= 0.22
                if m.quantity >= mp.capacity || ammo.quantity <= 0 {
                    if ammo.quantity <= 0 { _ = self.takeItem(uid: ammoUID) }
                    self.message("\(magName): \(m.quantity)/\(mp.capacity)")
                    return false
                }
                m.quantity += 1
                ammo.quantity -= 1
                self.sounds.play(.shellInsert, at: self.player.position, volume: 0.25, pitch: self.rng.range(0.95, 1.1))
                if ammo.quantity <= 0 {
                    _ = self.takeItem(uid: ammoUID)
                    self.message("\(magName): \(m.quantity)/\(mp.capacity)")
                    return false
                }
            }
            return true
        }
        action = a
    }

    func unloadMagazine(uid: Int) {
        guard let mag = findItem(uid: uid), let mp = mag.def.magazine, mag.quantity > 0 else { return }
        let ammoID = ItemDB.ordered.first { $0.ammo == mp.caliber }?.id ?? "ammo_9mm"
        let rounds = mag.quantity
        action = TimedAction("Unloading \(mag.def.name)", duration: 0.1 * Float(rounds) + 0.5) { [weak self] in
            guard let self = self, let m = self.findItem(uid: uid) else { return }
            let n = m.quantity
            m.quantity = 0
            self.giveItem(ItemInstance(defID: ammoID, quantity: n))
            self.message("Unloaded \(n) rounds")
        }
    }

    /// Gives an item to the player (cargo, else hands, else ground).
    func giveItem(_ it: ItemInstance) {
        if equipment.addToCargo(it) { return }
        if equipment.hands == nil {
            equipment.hands = it
            return
        }
        placeOnGround(it)
        message("\(it.def.name) placed on the ground (no space)")
    }

    func detach(uid: Int) {
        guard let it = takeItem(uid: uid) else { return }
        giveItem(it)
        sounds.play(.magOut, at: player.position, volume: 0.6)
        message("Removed \(it.def.name)")
    }

    func unloadWeapon(uid: Int) {
        guard let w = findItem(uid: uid), let wp = w.def.weapon, let cal = wp.caliber else { return }
        let ammoID = ItemDB.ordered.first { $0.ammo == cal }?.id ?? "ammo_9mm"
        var n = w.internalRounds + (w.chambered ? 1 : 0)
        w.internalRounds = 0
        w.chambered = false
        if let m = w.magazine {
            w.magazine = nil
            giveItem(m)
        }
        if n > 0 { giveItem(ItemInstance(defID: ammoID, quantity: n)) }
        n = 0
        sounds.play(.magOut, at: player.position, volume: 0.6)
        message("Unloaded \(w.def.name)")
    }

    // MARK: Using items

    func hasCanTool() -> (Bool, Bool) {
        let opener = equipment.firstItem { $0.def.tool == .canOpener } != nil
        let blade = equipment.firstItem { $0.def.tool == .blade } != nil
        return (opener, blade)
    }

    func useItem(uid: Int) {
        guard let it = findItem(uid: uid), action == nil else { return }
        let d = it.def
        if let f = d.food {
            if f.liquidContainer {
                drinkFromContainer(it)
            } else if f.needsOpening && !it.opened {
                openCan(it)
            } else {
                consume(it)
            }
            return
        }
        if let m = d.medical {
            applyMedical(it, kind: m)
            return
        }
        if d.tool == .flashlight {
            if equipment.hands?.uid != uid { toHands(uid: uid) }
            flashlightOn.toggle()
            message(flashlightOn ? "Flashlight on" : "Flashlight off")
            return
        }
        if let c = d.clothing {
            equip(uid: uid, to: c.slot)
            return
        }
        if d.isFirearm || d.isMelee {
            toHands(uid: uid)
        }
    }

    func openCan(_ it: ItemInstance) {
        let (opener, blade) = hasCanTool()
        let uid = it.uid
        let name = it.def.name
        if opener {
            action = TimedAction("Opening \(name)", duration: 2.5) { [weak self] in
                self?.findItem(uid: uid)?.opened = true
                self?.message("Opened \(name)")
            }
        } else if blade {
            action = TimedAction("Cutting open \(name)", duration: 3.5) { [weak self] in
                guard let c = self?.findItem(uid: uid) else { return }
                c.opened = true
                c.portion *= 0.9
                self?.message("Opened \(name) with a blade")
            }
        } else {
            action = TimedAction("Smashing open \(name)", duration: 4) { [weak self] in
                guard let self = self, let c = self.findItem(uid: uid) else { return }
                c.opened = true
                c.portion *= 0.65
                self.makeNoise(radius: 14)
                self.sounds.play(.hitHard, at: self.player.position, volume: 0.6)
                self.message("You smashed it open and lost some of it", important: false)
            }
        }
    }

    func consume(_ it: ItemInstance) {
        guard let f = it.def.food else { return }
        let uid = it.uid
        let name = it.def.name
        let isDrink = it.def.category == .drink
        action = TimedAction(isDrink ? "Drinking \(name)" : "Eating \(name)", duration: isDrink ? 2.5 : 4, eatAnimation: true) { [weak self] in
            guard let self = self, let c = self.findItem(uid: uid) else { return }
            let p = c.portion
            self.stats.energy = min(SurvivorStats.maxEnergy, self.stats.energy + f.energy * p)
            self.stats.water = max(0, min(SurvivorStats.maxWater, self.stats.water + f.water * p))
            if f.poisonChance > 0 && self.rng.chance(f.poisonChance) {
                self.stats.foodPoisoning = max(self.stats.foodPoisoning, 0.45)
                self.message("That didn't taste right...", important: true)
            }
            _ = self.takeItem(uid: uid)
            self.clearQuickSlotsFor(uid: uid)
            self.message(isDrink ? "You drank the \(name)" : "You ate the \(name)")
        }
        sounds.play(isDrink ? .drink : .eat, at: player.position, volume: 0.5)
    }

    func drinkFromContainer(_ it: ItemInstance) {
        guard it.quantity > 0 else {
            message("\(it.def.name) is empty")
            return
        }
        let uid = it.uid
        action = TimedAction("Drinking from \(it.def.name)", duration: 3, eatAnimation: true) { [weak self] in
            guard let self = self, let c = self.findItem(uid: uid) else { return }
            let amount = min(c.quantity, 500)
            c.quantity -= amount
            self.stats.water = min(SurvivorStats.maxWater, self.stats.water + Float(amount))
            if c.dirty && self.rng.chance(0.3) {
                self.stats.foodPoisoning = max(self.stats.foodPoisoning, 0.4)
                self.message("Your stomach turns. The water was not clean.", important: true)
            }
            if c.quantity <= 0 { c.dirty = false }
            self.message("Drank \(amount) ml")
        }
        sounds.play(.drink, at: player.position, volume: 0.5)
    }

    func drinkOrFill(at pos: Vec3, safe: Bool) {
        if let h = equipment.hands, let f = h.def.food, f.liquidContainer, h.quantity < Int(f.capacity) {
            let uid = h.uid
            action = TimedAction("Filling \(h.def.name)", duration: 3) { [weak self] in
                guard let self = self, let c = self.findItem(uid: uid) else { return }
                c.quantity = Int(f.capacity)
                if !safe { c.dirty = true }
                self.message(safe ? "Filled with clean water" : "Filled with lake water — it may not be safe")
            }
            sounds.play(.footstepWater, at: pos, volume: 0.6)
            return
        }
        action = TimedAction("Drinking", duration: 3, allowMovement: false) { [weak self] in
            guard let self = self else { return }
            self.stats.water = min(SurvivorStats.maxWater, self.stats.water + 450)
            if !safe && self.rng.chance(0.25) {
                self.stats.foodPoisoning = max(self.stats.foodPoisoning, 0.4)
                self.message("The lake water made you feel sick", important: true)
            } else {
                self.message("You drank some water")
            }
        }
        sounds.play(.drink, at: pos, volume: 0.6)
    }

    func applyMedical(_ it: ItemInstance, kind: MedicalKind) {
        let uid = it.uid
        let name = it.def.name
        func useOne() {
            guard let c = findItem(uid: uid) else { return }
            c.quantity -= 1
            if c.quantity <= 0 {
                _ = takeItem(uid: uid)
                clearQuickSlotsFor(uid: uid)
            }
        }
        switch kind {
        case .bandage, .rag:
            guard stats.isBleeding else {
                message("You are not bleeding")
                return
            }
            action = TimedAction(kind == .bandage ? "Bandaging" : "Binding wound with rags", duration: kind == .bandage ? 4 : 5) { [weak self] in
                guard let self = self else { return }
                _ = self.stats.bandage(clean: kind == .bandage)
                useOne()
                self.message(self.stats.isBleeding ? "One wound bandaged. You are still bleeding." : "The bleeding has stopped")
            }
            sounds.play(.bandage, at: player.position, volume: 0.6)
        case .disinfectant:
            action = TimedAction("Disinfecting wounds", duration: 2.5) { [weak self] in
                self?.stats.disinfect()
                useOne()
                self?.message("Wounds disinfected")
            }
            sounds.play(.medicate, at: player.position, volume: 0.5)
        case .antibiotics, .painkillers, .vitamins, .charcoal:
            action = TimedAction("Taking \(name)", duration: 1.8, eatAnimation: true) { [weak self] in
                guard let self = self else { return }
                switch kind {
                case .antibiotics: self.stats.antibiotics += 160
                case .painkillers:
                    self.stats.painkillers += 200
                    self.stats.pain = 0
                case .vitamins: self.stats.vitamins += 300
                default: self.stats.charcoal += 150
                }
                useOne()
                self.message("Took \(name)")
            }
            sounds.play(.medicate, at: player.position, volume: 0.5)
        case .saline:
            action = TimedAction("Administering saline", duration: 8, allowMovement: false) { [weak self] in
                self?.stats.saline += 130
                useOne()
                self?.message("Saline administered — blood volume will recover")
            }
        case .splint:
            guard stats.brokenLeg else {
                message("Your legs are fine")
                return
            }
            action = TimedAction("Applying splint", duration: 6, allowMovement: false) { [weak self] in
                self?.stats.splinted = true
                useOne()
                self?.message("Splint applied. Give it time to heal.")
            }
        case .morphine:
            action = TimedAction("Injecting morphine", duration: 1.5) { [weak self] in
                self?.stats.morphine += 300
                self?.stats.pain = 0
                useOne()
                self?.message("The pain fades away")
            }
            sounds.play(.medicate, at: player.position, volume: 0.6)
        }
    }

    // MARK: Context actions for the inventory UI

    func actions(for it: ItemInstance, inVicinity: Bool) -> [ItemAction] {
        var out: [ItemAction] = []
        let d = it.def
        let uid = it.uid
        if inVicinity {
            out.append(ItemAction(title: "TAKE") { [weak self] in
                if let wi = self?.worldItem(uid: uid) { self?.pickUp(worldItemID: wi.id) }
            })
            out.append(ItemAction(title: "TO HANDS") { [weak self] in self?.toHands(uid: uid) })
            return out
        }
        if let f = d.food {
            if f.liquidContainer {
                if it.quantity > 0 { out.append(ItemAction(title: "DRINK") { [weak self] in self?.useItem(uid: uid) }) }
                if it.quantity > 0 { out.append(ItemAction(title: "EMPTY") { [weak self] in
                    self?.findItem(uid: uid)?.quantity = 0
                    self?.findItem(uid: uid)?.dirty = false
                }) }
            } else if f.needsOpening && !it.opened {
                out.append(ItemAction(title: "OPEN") { [weak self] in self?.useItem(uid: uid) })
            } else {
                out.append(ItemAction(title: d.category == .drink ? "DRINK" : "EAT") { [weak self] in self?.useItem(uid: uid) })
            }
        }
        if d.medical != nil {
            out.append(ItemAction(title: "USE") { [weak self] in self?.useItem(uid: uid) })
        }
        if d.tool == .flashlight {
            out.append(ItemAction(title: flashlightOn && equipment.hands?.uid == uid ? "LIGHT OFF" : "LIGHT ON") { [weak self] in self?.useItem(uid: uid) })
        }
        if let c = d.clothing, equipment.item(c.slot)?.uid != uid {
            out.append(ItemAction(title: "WEAR") { [weak self] in self?.equip(uid: uid, to: c.slot) })
        }
        if d.magazine != nil && it.quantity > 0 {
            out.append(ItemAction(title: "UNLOAD") { [weak self] in self?.unloadMagazine(uid: uid) })
        }
        if let mp = d.magazine, it.quantity < mp.capacity,
           let ammo = equipment.firstItem(where: { $0.def.ammo == mp.caliber }) {
            out.append(ItemAction(title: "LOAD ROUNDS") { [weak self] in self?.loadRounds(ammoUID: ammo.uid, magazineUID: uid) })
        }
        if d.isFirearm {
            if it.roundsLoaded > 0 || it.magazine != nil {
                out.append(ItemAction(title: "UNLOAD") { [weak self] in self?.unloadWeapon(uid: uid) })
            }
            if let magID = d.weapon?.magazineID, it.magazine == nil,
               let mag = equipment.firstItem(where: { $0.defID == magID }) {
                out.append(ItemAction(title: "INSERT MAG") { [weak self] in _ = self?.combine(uid: mag.uid, onto: uid) })
            }
            if !it.chambered, let cal = d.weapon?.caliber, (it.magazine?.quantity ?? 0) == 0 && it.internalRounds == 0,
               let ammo = equipment.firstItem(where: { $0.def.ammo == cal }) {
                out.append(ItemAction(title: d.weapon!.internalCapacity > 0 ? "LOAD SHELLS" : "CHAMBER ROUND") { [weak self] in _ = self?.combine(uid: ammo.uid, onto: uid) })
            }
            for s in AttachSlot.allCases {
                if let a = it.attachment(s) {
                    out.append(ItemAction(title: "REMOVE \(s.title)") { [weak self] in self?.detach(uid: a.uid) })
                }
            }
        }
        if d.attachment != nil, let target = [equipment.hands, equipment.item(.shoulder)].compactMap({ $0 }).first(where: {
            $0.def.isFirearm && d.attachment!.compatible.contains($0.defID)
        }) {
            out.append(ItemAction(title: "ATTACH TO \(target.def.name.uppercased())") { [weak self] in _ = self?.combine(uid: uid, onto: target.uid) })
        }
        if equipment.hands?.uid == uid {
            out.append(ItemAction(title: "PUT AWAY") { [weak self] in self?.holsterHands() })
            out.append(ItemAction(title: "THROW") { [weak self] in self?.throwHeld() })
        } else if d.clothing == nil || !(equipment.slots.values.contains { $0.uid == uid }) {
            out.append(ItemAction(title: "TO HANDS") { [weak self] in self?.toHands(uid: uid) })
        }
        if d.isStackable && it.quantity > 1 {
            out.append(ItemAction(title: "SPLIT") { [weak self] in
                guard let self = self, let s = self.findItem(uid: uid), let half = s.split(count: s.quantity / 2) else { return }
                if !self.equipment.addToCargo(half) {
                    s.quantity += half.quantity
                    self.message("No space to split the stack")
                }
            })
        }
        out.append(ItemAction(title: "DROP") { [weak self] in self?.dropItem(uid: uid) })
        return out
    }
}
