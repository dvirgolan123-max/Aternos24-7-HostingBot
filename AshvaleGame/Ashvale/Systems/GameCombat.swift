//
//  GameCombat.swift
//  Ashvale
//
//  Firearms (chambering, fire modes, bolt/pump cycling, magazine and shell
//  reloads, jams from wear, recoil, bloom, suppressors, optics), melee
//  weapons, unarmed punches, hit detection with head/torso/leg zones and
//  armor, and damage the player receives from infected and gunfire.
//

import Foundation

extension Game {

    // MARK: Per-frame weapon logic

    func updateWeapon(dt: Float) {
        weapon.cooldown = max(0, weapon.cooldown - dt)
        weapon.bloom = max(0, weapon.bloom - dt * 0.08)
        if !input.fireHeld { weapon.triggerReleased = true }

        // Quick slots / fire mode / reload inputs.
        if let q = input.quickSlotPressed { activateQuickSlot(q) }
        if input.fireModePressed { toggleFireMode() }

        // Flashlight battery drain.
        if let h = equipment.hands, h.def.tool == .flashlight, flashlightOn {
            h.charge = max(0, h.charge - dt / 900)
            if h.charge <= 0 {
                flashlightOn = false
                message("The flashlight battery is dead")
            }
        }
        if flashlightActive, let l = equipment.hands?.attachment(.rail) {
            l.charge = max(0, l.charge - dt / 1200)
        }

        // Melee / punch animation progress.
        if weapon.meleeT >= 0 {
            let speed = equipment.hands?.def.weapon?.meleeSpeed ?? 2.2
            weapon.meleeT += dt * speed * 1.2
            if weapon.meleeT > 0.45 && !weapon.meleeHitDone {
                weapon.meleeHitDone = true
                resolveMeleeHit()
            }
            if weapon.meleeT >= 1 { weapon.meleeT = -1 }
        }

        // Reload progress.
        if weapon.reloadT >= 0 {
            weapon.reloadT += dt / weapon.reloadDuration
            if weapon.reloadT >= 1 {
                weapon.reloadT = -1
                finishReload()
            }
        }

        // Bolt / pump cycling.
        if weapon.cycleT >= 0 {
            weapon.cycleT += dt
            if weapon.cycleT > 0.55 {
                weapon.cycleT = -1
                if let h = equipment.hands { chamberFromFeed(h, playSound: true) }
            }
        }

        guard player.alive, action == nil else { return }
        if input.reloadPressed { startReload() }

        guard let h = equipment.hands else {
            // Unarmed: punch.
            if input.firePressed && weapon.meleeT < 0 && stats.stamina > 5 {
                startMelee(punch: true)
            }
            return
        }
        let d = h.def
        if d.isFirearm {
            guard let w = d.weapon else { return }
            let mode = w.modes[min(h.fireModeIndex, w.modes.count - 1)]
            let wantsShot: Bool
            switch mode {
            case .auto: wantsShot = input.fireHeld
            default: wantsShot = input.fireHeld && weapon.triggerReleased
            }
            if wantsShot && weapon.cooldown <= 0 && weapon.reloadT < 0 && weapon.cycleT < 0 {
                weapon.triggerReleased = false
                fire(h, w: w, mode: mode)
            }
        } else if d.isMelee {
            if input.firePressed && weapon.meleeT < 0 && stats.stamina > 8 {
                startMelee(punch: false)
            }
        } else if d.tool == .flashlight {
            if input.firePressed {
                flashlightOn.toggle()
                sounds.play(.uiClick, at: player.position, volume: 0.4)
            }
        } else if input.firePressed {
            // Anything else in hands gets thrown.
            throwHeld()
        }
    }

    func toggleFireMode() {
        guard let h = equipment.hands, let w = h.def.weapon, w.modes.count > 1 else { return }
        h.fireModeIndex = (h.fireModeIndex + 1) % w.modes.count
        sounds.play(.uiClick, at: player.position, volume: 0.5)
        message("Fire mode: \(w.modes[h.fireModeIndex].name)")
    }

    // MARK: Firing

    func fire(_ h: ItemInstance, w: WeaponProps, mode: FireMode) {
        if h.isRuined {
            message("\(h.def.name) is ruined and can't fire")
            return
        }
        guard h.chambered && !weapon.jammed else {
            sounds.play(.dryFire, at: player.position, volume: 0.7)
            weapon.cooldown = 0.25
            if weapon.jammed { message("Weapon jammed! Press RELOAD to clear it.", important: true) } else if h.roundsLoaded > 0 { message("No round chambered. Press RELOAD.") }
            return
        }
        h.chambered = false
        record.shotsFired += 1
        // Wear and jams.
        let wear: Float = (w.weaponClass == .sniper || w.weaponClass == .shotgun) ? 0.002 : 0.0009
        h.condition = max(0, h.condition - wear)
        if h.condition < 0.3 && rng.chance(0.04 + (0.3 - h.condition) * 0.2) {
            weapon.jammed = true
            sounds.play(.dryFire, at: player.position, volume: 0.8)
            message("Weapon jammed! Press RELOAD to clear it.", important: true)
            return
        }
        let suppressor = h.attachment(.muzzle)?.def.attachment
        let suppressed = suppressor != nil
        let noise = w.noise * (suppressor?.noiseMultiplier ?? 1)
        sounds.play(suppressed ? .gunSuppressed : w.sound, at: player.position, volume: 1, pitch: rng.range(0.96, 1.04))
        ai.noise(at: player.position, radius: noise)
        makeNoise(radius: noise)
        weapon.cooldown = 60 / w.rpm

        // Muzzle position.
        let muzzleLocal = ItemVisuals.geometry(h.def.model).muzzle + (suppressed ? Vec3(0, 0, -0.16) : Vec3(0, 0, 0))
        let weaponM = firstPerson ? viewModelTransform() : player.joints.gripTransform
        let muzzle = weaponM.transformPoint(muzzleLocal)
        let muzzleDir = vnormalize(weaponM.transformDirection(Vec3(0, 0, -1)))
        particles.muzzleFlash(at: muzzle, dir: muzzleDir, suppressed: suppressed)

        // Accuracy.
        let hs = vlength2(Vec2(player.body.velocity.x, player.body.velocity.z))
        var spread = w.spread + weapon.bloom
        spread *= isAiming ? 1 : 3.2
        spread *= 1 + hs * 0.25
        if player.body.stance == .crouched { spread *= 0.75 }
        spread *= mixf(1, stats.aimSway, 0.5)
        let ray = aimRay
        for _ in 0..<max(1, w.pellets) {
            let jitter = Vec3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) * spread
            let dir = vnormalize(ray.dir + jitter)
            traceBullet(origin: ray.origin, dir: dir, muzzle: muzzle, weapon: w, damage: w.damage)
        }
        // Recoil.
        let gripMult = h.attachment(.grip)?.def.attachment?.recoilMultiplier ?? 1
        let stanceMult: Float = player.body.stance == .crouched ? 0.8 : 1
        let kick = w.recoil * gripMult * stanceMult * (isAiming ? 1 : 1.3)
        recoilPitch += kick
        recoilYaw += rng.range(-0.4, 0.4) * kick
        camPitch += kick * 0.35
        weapon.bloom = min(0.05, weapon.bloom + w.spread * 0.6 + kick * 0.15)
        cameraShake = max(cameraShake, w.weaponClass == .shotgun || w.weaponClass == .sniper ? 0.35 : 0.12)

        // Feed the next round.
        switch mode {
        case .bolt, .pump:
            if h.roundsLoaded > 0 || (h.magazine?.quantity ?? 0) > 0 || h.internalRounds > 0 {
                weapon.cycleT = 0
            }
        default:
            chamberFromFeed(h, playSound: false)
        }
    }

    /// Moves a round from the magazine (or internal tube) into the chamber.
    @discardableResult
    func chamberFromFeed(_ h: ItemInstance, playSound: Bool) -> Bool {
        if h.chambered { return true }
        if let m = h.magazine, m.quantity > 0 {
            m.quantity -= 1
            h.chambered = true
        } else if h.internalRounds > 0 {
            h.internalRounds -= 1
            h.chambered = true
        }
        if playSound && h.chambered {
            let pump = h.def.weapon?.modes.first == .pump
            sounds.play(pump ? .boltCycle : .boltCycle, at: player.position, volume: 0.6, pitch: pump ? 0.8 : 1.1)
        }
        return h.chambered
    }

    /// Hitscan with world and agent hit tests. Damage falls off beyond effective range.
    func traceBullet(origin: Vec3, dir: Vec3, muzzle: Vec3, weapon w: WeaponProps, damage: Float) {
        let maxRange = min(1000, w.range * 3)
        var worldDist = maxRange
        var worldHit: RayHit?
        if let h = world.collision.raycast(origin: origin, direction: dir, maxDistance: maxRange, mask: .blocksBullets) {
            worldDist = h.distance
            worldHit = h
        }
        if let t = world.terrain.raycast(origin: origin, direction: dir, maxDist: worldDist), t < worldDist {
            worldDist = t
            let p = origin + dir * t
            worldHit = RayHit(distance: t, point: p, normal: world.terrain.normal(p.x, p.z), collider: -1, surface: .dirt)
        }
        // Ignore anything between the camera and the player (third person camera behind walls).
        let skip = firstPerson ? 0 : max(0, vdot(player.eyePosition - origin, dir) - 0.3)
        let agentHit = ai.hitTest(origin: origin + dir * skip, direction: dir, maxDistance: worldDist - skip)
        var endPoint = origin + dir * worldDist
        if let hit = agentHit {
            let (agent, zone, t) = hit
            let dist = t + skip
            endPoint = origin + dir * dist
            // The shot must also be possible from the muzzle.
            let fromMuzzle = endPoint - muzzle
            let ml = vlength(fromMuzzle)
            if ml > 0.3, let blocker = world.collision.raycast(origin: muzzle, direction: fromMuzzle / ml, maxDistance: ml - 0.2, mask: .blocksBullets) {
                particles.impact(at: blocker.point, normal: blocker.normal, surface: blocker.surface)
                return
            }
            let falloff = clampf(1 - (dist - w.range) / (w.range * 2), 0.35, 1)
            var events: [AIEvent] = []
            ai.damage(agent, amount: damage * falloff, zone: zone, from: player.position, bullet: true, events: &events)
            aiEvents.append(contentsOf: events)
            handleAIEvents()
            particles.blood(at: endPoint, dir: -dir, amount: zone == .head ? 14 : 8)
            hud.hitMarker = 1
            sounds.play(.hitFlesh, at: endPoint, volume: 0.8)
        } else if let h = worldHit {
            particles.impact(at: h.point, normal: h.normal, surface: h.surface)
            sounds.play(.bulletImpact, at: h.point, volume: 0.5, pitch: rng.range(0.8, 1.2))
            ai.noise(at: h.point, radius: 12)
        }
        if w.weaponClass != .pistol && rng.chance(0.35) {
            particles.tracer(from: muzzle, to: endPoint)
        }
    }

    // MARK: Reload

    func startReload() {
        guard let h = equipment.hands, h.def.isFirearm, let w = h.def.weapon, weapon.reloadT < 0, weapon.meleeT < 0 else { return }
        // Clear a jam / rack the slide.
        if weapon.jammed {
            weapon.jammed = false
            weapon.reloadDuration = 1.0
            weapon.reloadMagUID = nil
            weapon.shellReload = false
            weapon.reloadT = 0
            sounds.play(.boltCycle, at: player.position, volume: 0.7)
            message("Clearing the jam")
            return
        }
        if w.internalCapacity > 0 {
            // Shell by shell.
            guard let cal = w.caliber, h.internalRounds < w.internalCapacity,
                  equipment.firstItem(where: { $0.def.ammo == cal }) != nil else {
                if !h.chambered && h.internalRounds > 0 {
                    weapon.cycleT = 0
                } else if h.internalRounds >= w.internalCapacity {
                    message("\(h.def.name) is fully loaded")
                } else {
                    message("No \(w.caliber?.name ?? "") ammunition")
                }
                return
            }
            weapon.shellReload = true
            weapon.reloadDuration = w.reloadTime
            weapon.reloadT = 0
            sounds.play(.shellInsert, at: player.position, volume: 0.6)
            return
        }
        guard let magID = w.magazineID else { return }
        // Best loaded compatible magazine in the inventory.
        let mags = equipment.allItems.filter { $0.defID == magID && $0.uid != h.magazine?.uid }
        if let best = mags.max(by: { $0.quantity < $1.quantity }), best.quantity > 0 {
            weapon.reloadMagUID = best.uid
            weapon.shellReload = false
            weapon.reloadDuration = w.reloadTime + (h.chambered ? 0 : 0.4)
            weapon.reloadT = 0
            sounds.play(.magOut, at: player.position, volume: 0.7)
            makeNoise(radius: 6)
            return
        }
        if !h.chambered, let m = h.magazine, m.quantity > 0 {
            weapon.reloadMagUID = nil
            weapon.shellReload = false
            weapon.reloadDuration = 0.7
            weapon.reloadT = 0
            sounds.play(.boltCycle, at: player.position, volume: 0.6)
            return
        }
        // No loaded spare: top up a magazine from loose rounds (the one in the weapon first).
        if let cal = w.caliber, let ammo = equipment.firstItem(where: { $0.def.ammo == cal }) {
            if let m = h.magazine, let mp = m.def.magazine, m.quantity < mp.capacity {
                loadRounds(ammoUID: ammo.uid, magazineUID: m.uid)
                return
            }
            if let spare = mags.first(where: { $0.quantity < ($0.def.magazine?.capacity ?? 0) }) {
                loadRounds(ammoUID: ammo.uid, magazineUID: spare.uid)
                return
            }
        }
        let magName = ItemDB.get(magID)?.name ?? "magazine"
        if mags.isEmpty && h.magazine == nil {
            message("You need a \(magName)")
        } else {
            message("No loaded \(magName). Load rounds into it from the inventory.")
        }
    }

    func finishReload() {
        guard let h = equipment.hands, let w = h.def.weapon else { return }
        if weapon.shellReload {
            guard let cal = w.caliber, let ammo = equipment.firstItem(where: { $0.def.ammo == cal }) else { return }
            ammo.quantity -= 1
            if ammo.quantity <= 0 { _ = takeItem(uid: ammo.uid) }
            h.internalRounds += 1
            sounds.play(.shellInsert, at: player.position, volume: 0.6)
            // Keep loading while there are shells and space (and the player does not fire).
            if h.internalRounds < w.internalCapacity, equipment.firstItem(where: { $0.def.ammo == cal }) != nil, !input.fireHeld {
                weapon.reloadT = 0
                weapon.reloadDuration = w.reloadTime
            } else if !h.chambered {
                weapon.cycleT = 0
            }
            return
        }
        if let uid = weapon.reloadMagUID, let newMag = takeItem(uid: uid) {
            if let old = h.magazine {
                h.magazine = nil
                if !equipment.addToCargo(old) { placeOnGround(old) }
            }
            h.magazine = newMag
            sounds.play(.magIn, at: player.position, volume: 0.7)
        }
        weapon.reloadMagUID = nil
        if !h.chambered {
            chamberFromFeed(h, playSound: true)
        }
    }

    // MARK: Melee

    func startMelee(punch: Bool) {
        weapon.meleeT = 0
        weapon.meleeHitDone = false
        weapon.punchSide = -weapon.punchSide
        stats.stamina = max(0, stats.stamina - (punch ? 5 : 9))
        sounds.play(punch ? .punchSwing : .meleeSwing, at: player.position, volume: 0.6, pitch: rng.range(0.9, 1.1))
        makeNoise(radius: 5)
    }

    func resolveMeleeHit() {
        let h = equipment.hands
        let w = h?.def.weapon
        let isPunch = h == nil
        let range: Float = isPunch ? 1.35 : (w?.meleeRange ?? 1.5)
        var dmg: Float = isPunch ? 9 : (w?.meleeDamage ?? 15)
        if let it = h { dmg *= 0.6 + 0.4 * max(it.condition, 0.2) }
        let ray = aimRay
        let eye = player.eyePosition
        var target: (Agent, HitZone)?
        // Precise: ray from the eye along the aim direction.
        if let hit = ai.hitTest(origin: eye, direction: ray.dir, maxDistance: range + 0.3) {
            target = (hit.0, hit.1)
        } else {
            // Forgiving cone in front of the player.
            var bestD = Float.greatestFiniteMagnitude
            for a in ai.agents where a.alive {
                let to = a.joints.chestCenter - eye
                let d = vlength(to)
                if d > range + 0.4 { continue }
                let f = vdot(vnormalize(Vec3(to.x, 0, to.z)), flatForward(yaw: camYaw))
                if f > 0.7 && d < bestD && abs(a.position.y - player.position.y) < 1.2 {
                    bestD = d
                    target = (a, .torso)
                }
            }
        }
        guard let tg = target else { return }
        let (agent, zone) = tg
        var events: [AIEvent] = []
        let died = ai.damage(agent, amount: dmg, zone: zone, from: player.position, bullet: false, events: &events)
        aiEvents.append(contentsOf: events)
        handleAIEvents()
        let p = zone == .head ? agent.joints.headCenter : agent.joints.chestCenter
        let blade = h?.def.tool == .blade
        particles.blood(at: p, dir: -ray.dir, amount: blade ? 10 : 4)
        sounds.play(blade ? .hitFlesh : .hitHard, at: p, volume: 0.9)
        hud.hitMarker = 1
        if let it = h { it.condition = max(0, it.condition - 0.006) }
        // Pushback on the agent.
        if !died {
            let push = vnormalize(Vec3(ray.dir.x, 0, ray.dir.z)) * (isPunch ? 1.2 : 2.0)
            agent.body.velocity += push
        }
    }

    // MARK: AI events

    func handleAIEvents() {
        guard !aiEvents.isEmpty else { return }
        let evs = aiEvents
        aiEvents.removeAll()
        for e in evs {
            switch e {
            case .playerHit(let damage, let bleedChance, let dirty, let legBreak, let cause, let from, let bullet):
                playerHit(damage: damage, bleedChance: bleedChance, dirty: dirty, legBreak: legBreak, cause: cause, from: from, bullet: bullet)
            case .gunshot(let from, let to):
                sounds.play(.gunRifle, at: from, volume: 1, pitch: rng.range(0.9, 1.0))
                particles.muzzleFlash(at: from, dir: vnormalize(to - from), suppressed: false)
                particles.tracer(from: from, to: to)
                if let h = world.collision.raycast(origin: from, direction: vnormalize(to - from), maxDistance: vdistance(from, to) + 0.1, mask: .blocksBullets) {
                    particles.impact(at: h.point, normal: h.normal, surface: h.surface)
                }
            case .sound(let id, let p, let v):
                sounds.play(id, at: p, volume: v, pitch: rng.range(0.85, 1.15))
            case .died(let a):
                dropAgentLoot(a)
                record.kills += a.kind.isInfected ? 1 : 0
            }
        }
    }

    func dropAgentLoot(_ a: Agent) {
        var r = rng
        if a.kind == .bandit {
            let gun = ItemInstance(defID: "vanta", condition: r.range(0.3, 0.7))
            let mag = ItemInstance(defID: "mag_vanta", condition: r.range(0.4, 0.9))
            mag.quantity = r.int(3, 14)
            gun.magazine = mag
            items.add(gun, at: a.position + Vec3(0.4, 0.02, 0.2), yaw: r.range(0, kTwoPi))
            if r.chance(0.6) {
                items.add(ItemInstance(defID: "ammo_762", quantity: r.int(8, 25)), at: a.position + Vec3(-0.3, 0.02, 0.3), yaw: r.range(0, kTwoPi))
            }
            if r.chance(0.4) {
                items.add(ItemInstance(defID: "bandage", quantity: r.int(1, 2)), at: a.position + Vec3(0.1, 0.02, -0.4), yaw: 0)
            }
        } else {
            let n = r.weightedIndex([3, 2.5, 1])
            for i in 0..<n {
                if let d = LootSpawner.pick(a.kind.props.loot, large: false, rng: &r) {
                    let it = LootSpawner.makeInstance(d, rng: &r)
                    let ang = Float(i) * 2.1 + r.range(0, 1)
                    var p = a.position + Vec3(cosf(ang) * 0.5, 0.3, sinf(ang) * 0.5)
                    p.y = world.groundHeight(at: p).height
                    items.add(it, at: p, yaw: r.range(0, kTwoPi))
                }
            }
        }
        rng = r
    }

    /// Damage to the player with armor, bleeding, infection risk and broken bones.
    func playerHit(damage: Float, bleedChance: Float, dirty: Bool, legBreak: Float, cause: String, from: Vec3, bullet: Bool) {
        guard player.alive else { return }
        var dmg = damage
        // Armor: helmet (head) or vest (torso) by chance of where the hit lands.
        let headHit = bullet ? rng.chance(0.15) : rng.chance(0.25)
        let armorItem = headHit ? equipment.item(.head) : equipment.item(.vest)
        var armored = false
        if let a = armorItem, let armor = a.def.clothing?.armor, armor > 0, a.condition > 0 {
            dmg *= 1 - armor * (bullet ? 0.75 : 0.6) * (0.5 + 0.5 * a.condition)
            a.condition = max(0, a.condition - (bullet ? 0.08 : 0.02))
            armored = true
        }
        if headHit && bullet && !armored { dmg *= 2.2 }
        // Clothing takes wear too.
        if let t = equipment.item(.torso) { t.condition = max(0, t.condition - 0.01) }
        stats.damage(health: dmg, blood: bullet ? dmg * 8 : dmg * 4, cause: cause)
        if rng.chance(bleedChance * (armored ? 0.4 : 1)) {
            stats.addBleed(rate: bullet ? rng.range(6, 12) : rng.range(3, 7), dirty: dirty)
            message("You are bleeding!", important: true)
        }
        if rng.chance(legBreak) && !stats.brokenLeg {
            stats.brokenLeg = true
            message("Your leg snapped under the blow", important: true)
        }
        hud.damageFlash = min(1, hud.damageFlash + 0.35 + dmg / 50)
        cameraShake = max(cameraShake, 0.4)
        player.pose.hit = 1
        let to = player.position - from
        player.pose.hitDir = vdot(vnormalize(Vec3(to.x, 0, to.z)), flatForward(yaw: player.yaw)) > 0 ? -1 : 1
        player.body.velocity += vnormalize(Vec3(to.x, 0, to.z)) * (bullet ? 0.5 : 1.2)
        sounds.play(.playerHurt, at: player.position, volume: 0.9, pitch: rng.range(0.9, 1.1))
        particles.blood(at: player.position + Vec3(0, 1.2, 0), dir: vnormalize(to), amount: 6)
        // Interrupt actions.
        if let a = action {
            message("\(a.label) interrupted")
            action = nil
        }
        weapon.reloadT = -1
        if stats.health <= 0 { die(cause: cause) }
    }
}
