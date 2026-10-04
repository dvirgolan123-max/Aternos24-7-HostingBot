// Randomized long-play soak test: drives the full game loop with random input,
// teleports, item actions, combining, dropping, throwing, saving/loading and
// deaths. Any Swift runtime trap (index out of range, force unwrap, overflow)
// aborts the process, so finishing means no crash was found.
import Foundation

func runSoak(world: World, registry: MeshRegistry, minutes: Float) {
    print("== Soak test (\(Int(minutes)) simulated minutes)")
    ItemVisuals.registerAll(registry: registry)
    let cm = CharacterMeshes.build(registry: registry)
    let g = Game(world: world, registry: registry, characterMeshes: cm, seed: 31)
    g.configure(server: ServerProfile.byID("hardcore"))
    g.startNewGame()
    g.populateInfected()
    var rng = RNG(seed: 4242)
    let scene = RenderScene()
    let frames = Int(minutes * 60 * 60)
    var counts: [String: Int] = [:]
    func count(_ k: String) { counts[k, default: 0] += 1 }
    var input = InputState()
    var deaths = 0, saves = 0, maxAgents = 0, maxItems = 0
    let wall0 = Date()
    // Hand out gear periodically so weapon paths get exercised.
    let loadouts: [[String]] = [
        ["kestrel", "mag_kestrel", "ammo_556", "reddot", "supp_rifle"],
        ["warden", "mag_warden", "ammo_9mm", "supp_pistol", "weaponlight"],
        ["brennan", "ammo_12ga"],
        ["longreach", "mag_longreach", "ammo_308", "scope4x"],
        ["wasp", "mag_wasp", "ammo_45", "vgrip"],
        ["fireaxe", "bandage", "beans", "waterbottle", "canopener", "rag", "splint", "flashlight", "battery"],
        ["hollis", "mag_hollis", "ammo_45", "vanta", "mag_vanta", "ammo_762", "platecarrier", "helmet"],
    ]
    for f in 0..<frames {
        // Random input that changes every ~0.5 s.
        if f % 30 == 0 {
            input = InputState()
            input.move = Vec2(rng.range(-1, 1), rng.range(-0.3, 1))
            input.sprintToggled = rng.chance(0.3)
            input.crouchToggled = rng.chance(0.15)
            input.aimToggled = rng.chance(0.25)
            input.fireHeld = rng.chance(0.2)
        }
        input.look = Vec2(rng.range(-0.04, 0.04), rng.range(-0.02, 0.02))
        input.firePressed = input.fireHeld && rng.chance(0.1)
        input.jumpPressed = rng.chance(0.004)
        input.reloadPressed = rng.chance(0.004)
        input.interactPressed = rng.chance(0.02)
        input.fireModePressed = rng.chance(0.001)
        input.cameraTogglePressed = rng.chance(0.001)
        input.holsterPressed = rng.chance(0.001)
        input.quickSlotPressed = rng.chance(0.003) ? rng.int(0, 4) : nil
        g.input = input
        g.update(dt: 1.0 / 60.0)
        g.buildScene(scene, dt: 1.0 / 60.0)
        _ = g.sounds.drain()
        maxAgents = max(maxAgents, g.ai.agents.count)
        maxItems = max(maxItems, g.items.count)

        // Teleport somewhere new every ~40 s (towns, military, forest, lake shore).
        if f % 2400 == 0 {
            let l = world.locations[rng.int(0, world.locations.count - 1)]
            let p = Vec3(l.center.x + rng.range(-40, 40), 0, l.center.y + rng.range(-40, 40))
            g.player.position = Vec3(p.x, world.groundHeight(at: Vec3(p.x, 400, p.z)).height + 0.05, p.z)
            g.player.body.velocity = Vec3(0, 0, 0)
            count("teleport")
        }
        // Gear handouts.
        if f % 1800 == 900 {
            for id in loadouts[rng.int(0, loadouts.count - 1)] {
                let it = ItemInstance(defID: id)
                if it.def.magazine != nil { it.quantity = 0 }
                if !g.equipment.addToCargo(it) {
                    g.items.add(it, at: g.player.position + Vec3(rng.range(-1, 1), 0.3, rng.range(-1, 1)), yaw: 0)
                }
            }
            if g.equipment.item(.backpack) == nil {
                let pack = ItemInstance(defID: "rucksack")
                g.items.add(pack, at: g.player.position, yaw: 0)
                _ = g.equip(uid: pack.uid, to: .backpack)
            }
            count("loadout")
        }
        // Random inventory activity a few times per second.
        if f % 20 == 7 {
            let carried = g.equipment.allItems
            let near = g.vicinityItems()
            switch rng.int(0, 9) {
            case 0, 1:
                if let it = carried.randomElement(using: &rng) {
                    let acts = g.actions(for: it, inVicinity: false)
                    if let a = acts.randomElement(using: &rng) { a.perform(); count("action:" + a.title) }
                }
            case 2:
                if let w = near.randomElement(using: &rng) {
                    let acts = g.actions(for: w.item, inVicinity: true)
                    if let a = acts.randomElement(using: &rng) { a.perform(); count("vicinity:" + a.title) }
                }
            case 3:
                if let a = carried.randomElement(using: &rng), let b = carried.randomElement(using: &rng), a.uid != b.uid {
                    if g.combine(uid: a.uid, onto: b.uid) { count("combine") }
                }
            case 4:
                if let a = carried.randomElement(using: &rng) { _ = g.toHands(uid: a.uid); count("toHands") }
            case 5:
                if let a = carried.randomElement(using: &rng) { g.dropItem(uid: a.uid); count("drop") }
            case 6:
                if g.equipment.hands != nil && rng.chance(0.3) { g.throwHeld(); count("throw") }
            case 7:
                if let a = carried.randomElement(using: &rng) {
                    let slots = g.equipment.containers
                    if let s = slots.randomElement(using: &rng) {
                        _ = g.placeInCargo(uid: a.uid, slot: s.0, x: rng.int(0, max(0, s.2.width - 1)), y: rng.int(0, max(0, s.2.height - 1)), rotated: rng.chance(0.5))
                        count("place")
                    }
                }
            case 8:
                if let a = carried.randomElement(using: &rng) { g.assignQuickSlot(rng.int(0, 4), uid: a.uid); count("quickslot") }
            default:
                if let a = carried.randomElement(using: &rng), let slot = EquipSlot.allCases.randomElement(using: &rng) {
                    _ = g.equip(uid: a.uid, to: slot); count("equip")
                }
            }
        }
        // Weather and time jumps.
        if f % 3000 == 1500 {
            g.env.forceWeather(WeatherKind.allCases.randomElement(using: &rng) ?? .rain)
            g.env.hour = rng.range(0, 24)
            count("weather")
        }
        // Save/load round trip.
        if f % 6000 == 3000 && g.player.alive {
            let snap = SaveSystem.makeSnapshot(g, serverID: "soak", copy: true)
            if let data = try? JSONEncoder().encode(snap), let back = try? JSONDecoder().decode(SaveData.self, from: data) {
                g.restore(from: back)
                g.populateInfected()
                saves += 1
            }
        }
        // Occasionally get hurt badly to exercise bleeding/death/respawn.
        if f % 4000 == 2000 { g.stats.addBleed(rate: 25, dirty: rng.chance(0.5)) }
        if !g.player.alive {
            deaths += 1
            if deaths % 2 == 0 { g.respawn() } else {
                // Linger on the death screen for a moment first.
                for _ in 0..<150 { g.update(dt: 1.0 / 60.0); g.buildScene(scene, dt: 1.0 / 60.0) }
                g.respawn()
            }
            g.populateInfected()
        }
        if f % 18000 == 0 && f > 0 {
            print(String(format: "  %5.1f min  agents %d  items %d  deaths %d  kills %d", Float(f) / 3600, g.ai.agents.count, g.items.count, deaths, g.record.kills))
        }
    }
    // Combat phase: keep a loaded rifle in hands and engage the nearest infected in a town.
    let town = world.locations.first { $0.kind == .town } ?? world.locations[0]
    let tp = Vec3(town.center.x, 0, town.center.y)
    g.respawn()
    g.player.position = Vec3(tp.x, world.groundHeight(at: Vec3(tp.x, 400, tp.z)).height + 0.05, tp.z)
    g.populateInfected()
    let killsBefore = g.record.kills
    let shotsBefore = g.record.shotsFired
    var shots = 0
    var debugT = 0
    for f in 0..<(5 * 3600) {
        if !g.player.alive { g.respawn(); g.player.position = Vec3(tp.x, world.groundHeight(at: Vec3(tp.x, 400, tp.z)).height + 0.05, tp.z); g.populateInfected() }
        if g.equipment.hands?.defID != "kestrel" {
            let rifle = ItemInstance(defID: "kestrel")
            rifle.magazine = ItemInstance(defID: "mag_kestrel", quantity: 30)
            rifle.chambered = true
            g.equipment.hands = rifle
        }
        if g.equipment.firstItem(where: { $0.defID == "ammo_556" }) == nil {
            _ = g.equipment.addToCargo(ItemInstance(defID: "ammo_556", quantity: 60))
        }
        var inp = InputState()
        if let target = g.ai.agents.filter({ $0.alive }).min(by: { vdistance($0.position, g.player.position) < vdistance($1.position, g.player.position) }) {
            let aimAt = target.position + Vec3(0, 1.3, 0)
            let d = aimAt - g.camPos
            let wantYaw = yawFromDirection(d.x, d.z)
            let wantPitch = atan2f(d.y, sqrtf(d.x * d.x + d.z * d.z))
            g.camYaw = wantYaw
            g.camPitch = wantPitch
            inp.aimToggled = true
            let dist = vdistance(target.position, g.player.position)
            // Tap the trigger (semi-auto needs a release between shots).
            inp.firePressed = dist < 60 && f % 9 == 0 && g.action == nil && g.weapon.reloadT < 0
            inp.fireHeld = inp.firePressed
            if inp.firePressed { shots += 1 }
            inp.move = dist > 40 ? Vec2(0, 1) : Vec2(0, 0)
        } else {
            inp.move = Vec2(rng.range(-1, 1), 1)
        }
        if let m = g.equipment.hands?.magazine, m.quantity == 0 { inp.reloadPressed = true }
        if g.equipment.hands?.magazine == nil { inp.reloadPressed = f % 30 == 0 }
        if g.weapon.jammed && g.action == nil { inp.reloadPressed = true }
        g.input = inp
        g.update(dt: 1.0 / 60.0)
        g.buildScene(scene, dt: 1.0 / 60.0)
        _ = g.sounds.drain()
        debugT += 1
        if ProcessInfo.processInfo.environment["DEBUG_COMBAT"] != nil && debugT % 600 == 0 {
            let alive = g.ai.agents.filter { $0.alive }
            let near = alive.min(by: { vdistance($0.position, g.player.position) < vdistance($1.position, g.player.position) })
            let h = g.equipment.hands
            print("    t=\(debugT / 60)s alive=\(alive.count) nearest=\(near.map { String(format: "%.1fm hp %.0f state \\($0.state) indoors \\(world.isIndoors($0.position + Vec3(0, 0.5, 0)))", vdistance($0.position, g.player.position), $0.health) } ?? "-") mag=\(h?.magazine?.quantity ?? -1) ch=\(h?.chambered ?? false) jam=\(g.weapon.jammed) reloadT=\(g.weapon.reloadT) action=\(g.action?.label ?? "-") fired=\(g.record.shotsFired - shotsBefore) aim=\(g.aimBlend)")
        }
    }
    print("  combat phase: \(shots) trigger pulls, \(g.record.shotsFired - shotsBefore) rounds fired, \(g.record.kills - killsBefore) kills, world items \(g.items.count)")
    check(g.record.kills > killsBefore, "combat soak killed infected (\(g.record.kills - killsBefore))")
    let secs = Date().timeIntervalSince(wall0)
    print(String(format: "  finished %d frames in %.1fs (%.2f ms/frame); deaths %d, save/load %d, max agents %d, max world items %d",
                 frames, secs, secs / Double(frames) * 1000, deaths, saves, maxAgents, maxItems))
    print("  activity: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    check(g.items.count < 20000, "world item count stays bounded (\(g.items.count))")
}

/// Aimed single shots at a stationary infected in the open at several ranges.
func runAccuracy(world: World, registry: MeshRegistry) {
    print("== Aimed fire accuracy")
    ItemVisuals.registerAll(registry: registry)
    let cm = CharacterMeshes.build(registry: registry)
    let g = Game(world: world, registry: registry, characterMeshes: cm, seed: 77)
    g.configure(server: ServerProfile.byID("regular"))
    g.startNewGame()
    g.ai.populationMultiplier = 0
    g.ai.reset()
    // Find a spot with a clear 60 m line of fire towards -Z (no colliders, no terrain crest).
    var base = Vec3(1000, 0, 1100)
    search: for gx in stride(from: Float(300), to: 1800, by: 37) {
        for gz in stride(from: Float(300), to: 1800, by: 41) {
            let gy = world.terrain.height(gx, gz)
            let o = Vec3(gx, gy + 1.5, gz)
            let far = Vec3(gx, world.terrain.height(gx, gz - 60) + 1.2, gz - 60)
            let d = far - o
            let len = vlength(d)
            if world.isInWater(o) > 0 || world.isIndoors(o) { continue }
            if world.collision.raycast(origin: o, direction: d / len, maxDistance: len, mask: .blocksBullets) != nil { continue }
            if let t = world.terrain.raycast(origin: o, direction: d / len, maxDist: len), t < len - 0.5 { continue }
            base = Vec3(gx, 0, gz)
            break search
        }
    }
    g.player.position = Vec3(base.x, world.groundHeight(at: base + Vec3(0, 300, 0)).height, base.z)
    g.firstPerson = true
    for (defID, magID) in [("kestrel", "mag_kestrel"), ("warden", "mag_warden")] {
        for range: Float in [10, 25, 50] {
            var hits = 0, shots = 0
            for _ in 0..<12 {
                let gun = ItemInstance(defID: defID)
                gun.magazine = ItemInstance(defID: magID, quantity: 10)
                gun.chambered = true
                g.equipment.hands = gun
                g.weapon = WeaponRuntime()
                g.ai.reset()
                let tp = g.player.position + flatForward(yaw: 0) * range
                let inf = g.ai.spawn(.civilian, at: Vec3(tp.x, world.groundHeight(at: tp + Vec3(0, 3, 0)).height, tp.z), location: -1)
                inf.yaw = kPi
                g.input = InputState()
                g.input.aimToggled = true
                for _ in 0..<40 { g.update(dt: 1.0 / 60.0); g.buildScene(RenderScene(), dt: 1.0 / 60.0); inf.body.position = Vec3(tp.x, inf.body.position.y, tp.z) }
                let aim = inf.joints.chestCenter - g.camPos
                g.camYaw = yawFromDirection(aim.x, aim.z)
                g.camPitch = atan2f(aim.y, vlength2(Vec2(aim.x, aim.z)))
                let hp0 = inf.health
                if ProcessInfo.processInfo.environment["DEBUG_COMBAT"] != nil && shots == 0 {
                    let ray = g.aimRay
                    let wh = world.collision.raycast(origin: ray.origin, direction: ray.dir, maxDistance: 600, mask: .blocksBullets)
                    let th = world.terrain.raycast(origin: ray.origin, direction: ray.dir, maxDist: 600)
                    let ah = g.ai.hitTest(origin: ray.origin, direction: ray.dir, maxDistance: 600)
                    print("    dbg range \(range): cam \(g.camPos) chest \(inf.joints.chestCenter) agentPos \(inf.position) world \(wh.map { "\($0.distance)" } ?? "-") terrain \(th.map { "\($0)" } ?? "-") agent \(ah.map { "\($0.2) \($0.1)" } ?? "-") recoil \(g.recoilPitch) \(g.recoilYaw)")
                }
                g.input.fireHeld = true
                g.input.firePressed = true
                g.update(dt: 1.0 / 60.0)
                g.input.fireHeld = false
                g.input.firePressed = false
                for _ in 0..<5 { g.update(dt: 1.0 / 60.0) }
                shots += 1
                if inf.health < hp0 || !inf.alive { hits += 1 }
            }
            print("  \(defID) at \(Int(range)) m: \(hits)/\(shots) hits")
            if range == 10 { check(hits >= 10, "\(defID) hits reliably at 10 m (\(hits)/\(shots))") }
            if range == 50 && defID == "kestrel" { check(hits >= 10, "aimed rifle hits at 50 m (\(hits)/\(shots))") }
        }
    }
}
