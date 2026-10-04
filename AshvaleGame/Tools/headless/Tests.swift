// Headless gameplay/system tests.
import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok   \(msg)") } else { print("  FAIL \(msg)"); failures += 1 }
}

func runTests(world: World, registry: MeshRegistry) {
    print("== GPU data layout (must match Shaders.metal and the vertex descriptor)")
    check(MemoryLayout<Vertex>.stride == 44, "Vertex stride 44 (\(MemoryLayout<Vertex>.stride))")
    check(MemoryLayout<Vertex>.offset(of: \Vertex.nx) == 12 && MemoryLayout<Vertex>.offset(of: \Vertex.u) == 24
          && MemoryLayout<Vertex>.offset(of: \Vertex.color) == 32 && MemoryLayout<Vertex>.offset(of: \Vertex.material) == 36
          && MemoryLayout<Vertex>.offset(of: \Vertex.weights) == 40, "Vertex attribute offsets 0/12/24/32/36/40")
    check(MemoryLayout<FrameUniforms>.stride == 5 * 64 + 16 * 16, "FrameUniforms size 576 (\(MemoryLayout<FrameUniforms>.stride))")
    check(MemoryLayout<InstanceData>.stride == 96, "InstanceData size 96 (\(MemoryLayout<InstanceData>.stride))")
    check(MemoryLayout<ParticleInstance>.stride == 48, "ParticleInstance size 48 (\(MemoryLayout<ParticleInstance>.stride))")
    print("== Math")
    let m = Mat4.rotationY(0.7) * Mat4.translation(Vec3(1, 2, 3))
    let p = Vec3(0.3, -1, 2)
    let back = m.inverse.transformPoint(m.transformPoint(p))
    check(vlength(back - p) < 1e-4, "matrix inverse round trip")
    let fwd = flatForward(yaw: 0.9)
    check(abs(yawFromDirection(fwd.x, fwd.z) - 0.9) < 1e-4, "yaw from direction")
    let proj = Mat4.perspectiveReverseZ(fovY: 1.0, aspect: 1.5, near: 0.1)
    let view = Mat4.lookAt(eye: Vec3(0, 0, 0), target: Vec3(0, 0, -10), up: Vec3(0, 1, 0))
    let clip = (proj * view).mulVec(Vec4(0, 0, -10, 1))
    check(abs(clip.x / clip.w) < 1e-5 && clip.z / clip.w > 0 && clip.z / clip.w < 1, "projection maps point ahead into NDC")
    let clipNear = (proj * view).mulVec(Vec4(0, 0, -0.1, 1))
    check(abs(clipNear.z / clipNear.w - 1) < 1e-4, "reverse-Z near plane maps to 1")

    print("== World")
    check(world.buildings.count > 150, "enough buildings (\(world.buildings.count))")
    check(world.doors.count > 300, "doors exist")
    check(world.lootSpots.count > 2000, "loot spots exist")
    // Every building has at least one door or wide opening reachable.
    var doorless = 0
    for (bi, b) in world.buildings.enumerated() {
        let hasDoor = world.doors.contains { $0.building == bi }
        if !hasDoor && ![.garage, .barn, .tent, .container, .warehouse, .factory].contains(b.type) { doorless += 1 }
    }
    check(doorless == 0, "all closed buildings have doors (\(doorless) without)")

    // Ground query inside a building returns the floor, not the terrain.
    if let b = world.buildings.first(where: { $0.type == .houseSmall }) {
        let inside = b.transform.transformPoint(Vec3(-2, 0.5, 2))
        let g = world.groundHeight(at: inside)
        check(g.height >= b.position.y - 0.01 && g.height < b.position.y + 0.9, "floor/furniture height inside house (\(g.height - b.position.y))")
        check(world.isIndoors(inside + Vec3(0, 0.5, 0)), "indoor detection")
    }
    // Upper floor of a two story house is walkable.
    if let b = world.buildings.first(where: { $0.type == .houseTwoStory }) {
        let up = b.transform.transformPoint(Vec3(-2, 2.9 + 0.3, 2))
        let g = world.groundHeight(at: up)
        check(g.height >= b.position.y + 2.89 && g.height < b.position.y + 3.8, "upper floor height (\(g.height - b.position.y))")
    }
    // Raycast hits a wall.
    if let b = world.buildings.first(where: { $0.type == .police }) {
        let o = b.transform.transformPoint(Vec3(-8, 1.5, 20))
        let target = b.transform.transformPoint(Vec3(-8, 1.5, 0))
        let dir = vnormalize(target - o)
        let hit = world.collision.raycast(origin: o, direction: dir, maxDistance: 40, mask: .blocksBullets)
        check(hit != nil && abs(hit!.distance - 13) < 0.5, "raycast hits police front wall (\(hit?.distance ?? -1))")
    }
    print("Tests finished with \(failures) failure(s)")
}

/// Drives the real Game simulation with synthetic input.
func runGameTests(world: World, registry: MeshRegistry) {
    print("== Gameplay")
    let cm = CharacterMeshes.build(registry: registry)
    let game = Game(world: world, registry: registry, characterMeshes: cm, seed: 99)
    game.spawnFreshPlayer()
    let scene = RenderScene()
    func sim(_ seconds: Float, move: Vec2, yaw: Float, jumpAt: Float? = nil) {
        var t: Float = 0
        game.camYaw = yaw
        var jumped = false
        while t < seconds {
            game.input.move = move
            if let j = jumpAt, !jumped, t >= j { game.input.jumpPressed = true; jumped = true }
            game.update(dt: 1.0 / 60.0)
            game.buildScene(scene, dt: 1.0 / 60.0)
            t += 1.0 / 60.0
        }
    }
    // 1. Walk through the front door of a two story house.
    guard let bi = world.buildings.firstIndex(where: { $0.type == .houseTwoStory && $0.area == .town }) else { check(false, "found house"); return }
    let b = world.buildings[bi]
    let m = b.transform
    for (di, d) in world.doors.enumerated() where d.building == bi { world.setDoor(di, open: true, immediate: true) }
    let outside = m.transformPoint(Vec3(3.6, 0, 6.5))
    game.player.position = Vec3(outside.x, world.groundHeight(at: outside + Vec3(0, 2, 0)).height, outside.z)
    let inward = vnormalize(m.transformDirection(Vec3(0, 0, -1)))
    let yawIn = yawFromDirection(inward.x, inward.z)
    sim(2.2, move: Vec2(0, 0.5), yaw: yawIn)
    let local1 = m.inverse.transformPoint(game.player.position)
    check(world.isIndoors(game.player.position + Vec3(0, 0.5, 0)), "walked through the front door (local \(local1))")
    // 2. Climb the stairs: stairs start at local z 2.6 going -Z inside x 3.07..4.2.
    let stairBottom = m.transformPoint(Vec3(3.62, 0, 3.4))
    game.player.position = Vec3(stairBottom.x, b.position.y, stairBottom.z)
    game.player.body.velocity = Vec3(0, 0, 0)
    sim(4.5, move: Vec2(0, 0.5), yaw: yawIn)
    let rel = game.player.position.y - b.position.y
    check(rel > 2.7, "climbed stairs to the upper floor (height \(rel))")
    // 3. Wall collision: walk into the back wall from inside the kitchen.
    let kitchen = m.transformPoint(Vec3(-1.5, 0, -2.0))
    game.player.position = Vec3(kitchen.x, b.position.y + 0.05, kitchen.z)
    sim(3, move: Vec2(0, 1), yaw: yawIn)
    let l3 = m.inverse.transformPoint(game.player.position)
    check(l3.z > -4.75, "blocked by exterior wall (local z \(l3.z))")
    // 4. Vault a wooden fence.
    if let fi = world.props.firstIndex(where: { $0.type == .woodFence }) {
        let f = world.props[fi]
        let n = flatRight(yaw: f.yaw) // fence spans local Z, so its normal is local X
        let start = f.position - n * 1.5
        game.player.position = Vec3(start.x, world.terrain.height(start.x, start.z), start.z)
        game.player.body.stance = .standing
        game.input.crouchToggled = false
        let y = yawFromDirection(n.x, n.z)
        sim(2.0, move: Vec2(0, 0.7), yaw: y, jumpAt: 0.6)
        let side = vdot(game.player.position - f.position, n)
        check(side > 0.2, "vaulted over fence (side \(side))")
    }
    // 5. Infected navigation: chase through the open front door, blocked by a closed one.
    do {
        game.ai.reset()
        game.ai.populationMultiplier = 0
        let inside = m.transformPoint(Vec3(-1.5, 0, -2.0))
        func runChase(seconds: Float) -> (reached: Bool, indoors: Bool) {
            game.player.position = Vec3(inside.x, b.position.y + 0.05, inside.z)
            game.player.body.velocity = Vec3(0, 0, 0)
            game.stats.health = 100
            game.stats.blood = SurvivorStats.maxBlood
            game.stats.bleeds.removeAll()
            let out = m.transformPoint(Vec3(3.6, 0, 16))
            let a = game.ai.spawn(.civilian, at: Vec3(out.x, world.groundHeight(at: out + Vec3(0, 3, 0)).height, out.z), location: 0)
            a.state = .chase
            a.awareness = 1.5
            a.lastSeen = game.player.position
            var t: Float = 0
            var reached = false
            while t < seconds && a.alive {
                game.input.move = Vec2(0, 0)
                game.update(dt: 1.0 / 60.0)
                game.player.position = Vec3(inside.x, game.player.position.y, inside.z)
                a.awareness = 1.5
                a.lastSeen = game.player.position
                if vdistanceXZ(a.position, game.player.position) < 1.8 { reached = true }
                if ProcessInfo.processInfo.environment["DEBUG_NAV"] != nil && Int(t * 60) % 60 == 0 {
                    let lp = m.inverse.transformPoint(a.position)
                    print(String(format: "    t=%.0f local=(%.1f, %.2f, %.1f) state=\(a.state) path=\(a.path.count) idx=\(a.pathIndex) aware=%.2f", t, lp.x, lp.y, lp.z, a.awareness))
                }
                t += 1.0 / 60.0
            }
            let indoors = world.isIndoors(a.position + Vec3(0, 0.5, 0))
            game.ai.reset()
            return (reached, indoors)
        }
        for (di, d) in world.doors.enumerated() where d.building == bi { world.setDoor(di, open: true, immediate: true) }
        let open = runChase(seconds: 16)
        check(open.reached, "infected pathed through the open door to the player")
        for (di, d) in world.doors.enumerated() where d.building == bi { world.setDoor(di, open: false, immediate: true) }
        let closed = runChase(seconds: 10)
        check(!closed.reached && !closed.indoors, "closed doors keep the infected out")
        for (di, d) in world.doors.enumerated() where d.building == bi { world.setDoor(di, open: true, immediate: true) }
        game.ai.populationMultiplier = 1
        game.stats.health = 100
    }
    // 6. Day/night: advance time.
    game.env.hour = 23.5
    game.buildScene(scene, dt: 0.016)
    check(scene.uniforms.sunDir.w < 0.5 && scene.uniforms.moonDir.w > 0.5, "night lighting uses the moon")
    print("Gameplay tests done, failures so far: \(failures)")
}

func runSystemTests(world: World, registry: MeshRegistry) {
    print("== Items, combat, survival, save")
    ItemVisuals.registerAll(registry: registry)
    let cm = CharacterMeshes.build(registry: registry)
    let g = Game(world: world, registry: registry, characterMeshes: cm, seed: 7)
    g.configure(server: ServerProfile.byID("regular"))
    g.ai.populationMultiplier = 0
    g.ai.maxActive = 4
    let t0 = Date()
    g.startNewGame()
    print("  new game setup \(String(format: "%.2f", Date().timeIntervalSince(t0)))s, world items: \(g.items.count)")
    check(g.items.count > 1500, "loot physically spawned in the world (\(g.items.count))")
    let worn = EquipSlot.allCases.compactMap { g.equipment.item($0)?.defID }.sorted()
    check(worn == ["jeans", "sneakers", "tshirt"], "starts with basic clothing only (\(worn))")
    check(g.equipment.hands == nil && g.equipment.item(.backpack) == nil && g.equipment.item(.vest) == nil, "no weapon/backpack/vest at start")
    let carried = g.equipment.containers.flatMap { $0.2.items }
    check(carried.isEmpty, "no food/water/medicine/ammo at start")
    let scene = RenderScene()
    func step(_ s: Float) {
        var t: Float = 0
        while t < s { g.update(dt: 1.0 / 60.0); g.buildScene(scene, dt: 1.0 / 60.0); t += 1.0 / 60.0 }
    }
    // Move to an open area and place items in front of the player.
    let base = Vec3(1000, world.terrain.height(1000, 1100), 1100)
    g.player.position = Vec3(base.x, world.groundHeight(at: base + Vec3(0, 2, 0)).height, base.z)
    g.camYaw = 0; g.camPitch = -0.6; g.player.yaw = 0
    let front = g.player.position + flatForward(yaw: 0) * 1.0
    let pack = ItemInstance(defID: "rucksack")
    g.items.add(pack, at: Vec3(front.x, world.groundHeight(at: front + Vec3(0, 1, 0)).height, front.z), yaw: 0)
    step(0.2)
    g.input.interactPressed = true
    step(0.1)
    check(g.equipment.item(.backpack)?.uid == pack.uid, "picked up and wore the rucksack via interaction")
    // Weapon, magazine and ammo.
    let rifle = ItemInstance(defID: "kestrel")
    let mag = ItemInstance(defID: "mag_kestrel", quantity: 0)
    let ammo = ItemInstance(defID: "ammo_556", quantity: 40)
    let wrongMag = ItemInstance(defID: "mag_vanta", quantity: 10)
    check(g.equipment.addToCargo(mag) && g.equipment.addToCargo(ammo) && g.equipment.addToCargo(wrongMag), "items stored in cargo grid")
    g.equipment.hands = rifle
    check(!g.combine(uid: wrongMag.uid, onto: rifle.uid), "incompatible magazine rejected")
    check(g.combine(uid: ammo.uid, onto: mag.uid), "loading rounds into magazine starts")
    step(8)
    check(mag.quantity == 30 && ammo.quantity == 10, "magazine loaded round by round (\(mag.quantity), ammo left \(ammo.quantity))")
    g.input.reloadPressed = true
    step(3.5)
    check(rifle.magazine?.uid == mag.uid && rifle.chambered, "reload inserted magazine and chambered a round")
    // Spawn an infected in front and shoot it.
    let target = g.player.position + flatForward(yaw: 0) * 8
    let inf = g.ai.spawn(.civilian, at: Vec3(target.x, world.groundHeight(at: target + Vec3(0, 2, 0)).height, target.z), location: -1)
    inf.yaw = kPi
    step(0.1)
    let aimAt = inf.joints.chestCenter - g.camPos
    g.camYaw = yawFromDirection(aimAt.x, aimAt.z)
    g.camPitch = atan2f(aimAt.y, vlength2(Vec2(aimAt.x, aimAt.z)))
    g.input.aimToggled = true
    step(0.3)
    let hp0 = inf.health
    let aimAt2 = inf.joints.chestCenter - g.camPos
    g.camYaw = yawFromDirection(aimAt2.x, aimAt2.z)
    g.camPitch = atan2f(aimAt2.y, vlength2(Vec2(aimAt2.x, aimAt2.z)))
    g.input.fireHeld = true
    g.input.firePressed = true
    g.update(dt: 1.0 / 60.0)
    g.input.fireHeld = false
    check(inf.health < hp0 || !inf.alive, "bullet hit the infected (hp \(hp0) -> \(inf.health))")
    check(mag.quantity == 28 && rifle.chambered, "firing consumed a round and chambered the next (\(mag.quantity))")
    g.input.aimToggled = false
    // Let infected attack the player.
    g.equipment.hands = nil
    let attacker = g.ai.spawn(.brute, at: g.player.position + Vec3(1.2, 0, 0), location: -1)
    attacker.awareness = 2
    attacker.state = .chase
    let h0 = g.stats.health
    step(4)
    check(g.stats.health < h0, "infected attacks damage the player (\(h0) -> \(g.stats.health))")
    attacker.health = 0
    attacker.state = .dead
    g.ai.reset()
    g.stats.health = 100
    // Bleeding and bandage.
    g.stats.bleeds.removeAll()
    g.stats.addBleed(rate: 6, dirty: true)
    let bandage = ItemInstance(defID: "bandage", quantity: 2)
    _ = g.equipment.addToCargo(bandage)
    g.useItem(uid: bandage.uid)
    step(5)
    check(!g.stats.isBleeding && bandage.quantity == 1, "bandage stopped the bleeding")
    // Food that needs opening.
    let beans = ItemInstance(defID: "beans")
    _ = g.equipment.addToCargo(beans)
    let e0 = g.stats.energy
    g.useItem(uid: beans.uid)
    step(4.5)
    check(beans.opened, "can opened (without a tool it was smashed)")
    g.useItem(uid: beans.uid)
    step(4.5)
    check(g.stats.energy > e0 + 200, "eating restored energy (\(e0) -> \(g.stats.energy))")
    // Drop and throw keep items physical.
    let soda = ItemInstance(defID: "soda")
    g.equipment.hands = soda
    let countBefore = g.items.count
    g.throwHeld()
    step(3)
    let thrown = g.items.items.values.first { $0.item.uid == soda.uid }
    check(thrown != nil && thrown!.resting && g.items.count == countBefore + 1, "thrown item lands and rests in the world")
    // Save / load round trip.
    let dir = FileManager.default.temporaryDirectory
    _ = dir
    let snap = SaveSystem.makeSnapshot(g, serverID: "test")
    let t1 = Date()
    let data = try! JSONEncoder().encode(snap)
    print("  save encode \(String(format: "%.3f", Date().timeIntervalSince(t1)))s, \(data.count / 1024) KB")
    let decoded = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game(world: world, registry: registry, characterMeshes: cm, seed: 8)
    g2.restore(from: decoded)
    check(vdistance(g2.player.position, g.player.position) < 0.01, "save restores player position")
    check(g2.items.count == g.items.count, "save restores world items (\(g2.items.count))")
    check(g2.equipment.item(.backpack)?.defID == "rucksack" && g2.equipment.containers.flatMap { $0.2.items }.count == g.equipment.containers.flatMap { $0.2.items }.count,
          "save restores worn clothing and cargo")
    check(abs(g2.env.hour - g.env.hour) < 0.001, "save restores time of day")
    // Death and respawn.
    g.stats.health = 0
    step(0.2)
    check(!g.player.alive, "player dies at zero health (cause: \(g.deathCause))")
    let near = g.items.query(center: g.player.position, radius: 3).count
    check(near >= 4, "gear dropped physically around the body (\(near) items)")
    g.respawn()
    check(g.player.alive && g.equipment.item(.torso)?.defID == "tshirt" && g.equipment.hands == nil, "respawn with basic clothing")
    print("System tests done, failures so far: \(failures)")
}
