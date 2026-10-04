//
//  Game.swift
//  Ashvale
//
//  The gameplay simulation. Platform independent: driven by InputState,
//  produces a RenderScene, sound events and HUD state. Item, combat and
//  persistence logic live in extensions (GameItems, GameCombat, SaveSystem).
//

import Foundation

enum InteractionTarget: Equatable {
    case door(Int)
    case item(Int)
    case water(Vec3, Bool)

    static func == (a: InteractionTarget, b: InteractionTarget) -> Bool {
        switch (a, b) {
        case (.door(let x), .door(let y)): return x == y
        case (.item(let x), .item(let y)): return x == y
        case (.water(let p, _), .water(let q, _)): return vdistance(p, q) < 0.01
        default: return false
        }
    }
}

struct HUDMessage {
    var text: String
    var time: Float
    var important: Bool
}

struct HUDState {
    var prompt: String?
    var locationBanner: String?
    var locationTimer: Float = 0
    var messages: [HUDMessage] = []
    var hitMarker: Float = 0
    var damageFlash: Float = 0
    var showScope = false
    var showRedDot = false
    var actionLabel: String?
    var actionProgress: Float = 0
}

/// Per-life statistics.
struct LifeRecord: Codable {
    var kills = 0
    var distanceTravelled: Float = 0
    var shotsFired = 0
}

/// A timed action such as eating, drinking, bandaging or loading rounds.
final class TimedAction {
    let label: String
    let duration: Float
    var elapsed: Float = 0
    let allowMovement: Bool
    let animation: Bool
    let onComplete: () -> Void
    var onTick: ((Float) -> Bool)?

    init(_ label: String, duration: Float, allowMovement: Bool = true, eatAnimation: Bool = false, onComplete: @escaping () -> Void) {
        self.label = label
        self.duration = duration
        self.allowMovement = allowMovement
        self.animation = eatAnimation
        self.onComplete = onComplete
    }
}

/// Runtime state of the weapon in hands (not persisted).
struct WeaponRuntime {
    var cooldown: Float = 0
    var reloadT: Float = -1
    var reloadDuration: Float = 1
    var reloadMagUID: Int?
    var shellReload = false
    var cycleT: Float = -1
    var triggerReleased = true
    var bloom: Float = 0
    var meleeT: Float = -1
    var meleeHitDone = false
    var punchSide: Float = 1
    var jammed = false
}

struct PlayerCorpse {
    var joints: CharacterJoints
    var appearance: Appearance
    var position: Vec3
    var age: Float
}

final class Game {
    let world: World
    let registry: MeshRegistry
    let characterMeshes: CharacterMeshes
    let env: Environment
    let sounds = SoundQueue()
    let items = WorldItemSystem()
    let ai: AIManager
    let particles = ParticleSystem()
    var input = InputState()
    var hud = HUDState()
    var rng: RNG
    var player: Player
    var server = ServerProfile.byID("regular")

    // Survivor state.
    var equipment = Equipment()
    var stats = SurvivorStats()
    var record = LifeRecord()
    var deathCause = ""
    var action: TimedAction?
    var weapon = WeaponRuntime()
    var flashlightOn = false
    var corpses: [PlayerCorpse] = []
    private var lastPosForDistance = Vec3(0, 0, 0)
    var aiEvents: [AIEvent] = []

    // Camera.
    var camYaw: Float = 0
    var camPitch: Float = -0.1
    var firstPerson = false
    var aimBlend: Float = 0
    var camPos = Vec3(0, 0, 0)
    var camSmoothY: Float = 0
    var fovBase: Float = 70
    var lookSensitivity: Float = 1
    var aimSensitivity: Float = 0.6
    var invertY = false
    var recoilPitch: Float = 0
    var recoilYaw: Float = 0
    var cameraShake: Float = 0
    var swayTime: Float = 0

    var gameTime: Float = 0
    var interaction: InteractionTarget?
    private var lastLocation: String?
    var interactCooldown: Float = 0
    var survivalTick: Float = 0

    init(world: World, registry: MeshRegistry, characterMeshes: CharacterMeshes, seed: UInt64) {
        ItemDB.load()
        self.world = world
        self.registry = registry
        self.characterMeshes = characterMeshes
        self.env = Environment(seed: seed)
        ai = AIManager(world: world)
        rng = RNG(seed: seed &+ UInt64(Date().timeIntervalSince1970))
        let sp = world.spawnPoints.first ?? SpawnPoint(position: Vec3(1024, 50, 1024), yaw: 0)
        player = Player(position: sp.position, yaw: sp.yaw)
        camYaw = sp.yaw
        applySettings()
    }

    func applySettings() {
        let s = GameSettings.shared
        fovBase = s.fieldOfView
        lookSensitivity = s.lookSensitivity
        aimSensitivity = s.aimSensitivity
        invertY = s.invertY
        env.dayLengthMinutes = s.dayLengthMinutes
    }

    func configure(server p: ServerProfile) {
        server = p
        ai.populationMultiplier = p.infectedMultiplier
        ai.aggression = p.infectedAggression
        if p.firstPersonOnly { firstPerson = true }
    }

    // MARK: Life cycle

    /// Fresh world state: new loot, morning, new survivor with basic clothing only.
    func startNewGame() {
        items.removeAll()
        ai.reset()
        corpses.removeAll()
        // Doors back to their generated state.
        var drng = RNG(seed: 555)
        for i in 0..<world.doors.count {
            world.setDoor(i, open: drng.chance(0.35), immediate: true)
        }
        var lrng = RNG(seed: UInt64(Date().timeIntervalSince1970))
        LootSpawner.populate(world: world, items: items, rng: &lrng, lootMultiplier: server.lootMultiplier)
        env.hour = server.startHour
        env.day = 1
        env.forceWeather(.clear)
        env.cloud = 0.2
        env.rain = 0
        env.wetness = 0
        spawnFreshPlayer()
    }

    /// Places a brand new survivor at a random spawn point with basic clothing only.
    func spawnFreshPlayer() {
        let sp = world.randomSpawn(&rng)
        player = Player(position: sp.position, yaw: sp.yaw)
        player.appearance = Player.freshAppearance(&rng)
        camYaw = sp.yaw
        camPitch = -0.12
        camSmoothY = sp.position.y
        firstPerson = server.firstPersonOnly || GameSettings.shared.firstPersonDefault
        hud.messages.removeAll()
        hud.locationBanner = nil
        lastLocation = nil
        stats = SurvivorStats()
        record = LifeRecord()
        deathCause = ""
        action = nil
        weapon = WeaponRuntime()
        flashlightOn = false
        input = InputState()
        equipment = Equipment()
        // Basic clothing only: no weapon, ammo, backpack, vest, food, water or medicine.
        equipment.slots[EquipSlot.torso.rawValue] = ItemInstance(defID: "tshirt", condition: rng.range(0.55, 0.85))
        equipment.slots[EquipSlot.legs.rawValue] = ItemInstance(defID: "jeans", condition: rng.range(0.55, 0.85))
        equipment.slots[EquipSlot.feet.rawValue] = ItemInstance(defID: "sneakers", condition: rng.range(0.55, 0.85))
        refreshAppearance()
        lastPosForDistance = player.position
    }

    func respawn() {
        spawnFreshPlayer()
        message("You wake up somewhere unfamiliar. Your old body is where you left it.", important: true)
    }

    func populateInfected() {
        ai.nav.prepare(around: player.position, radius: 1)
        ai.managePopulation(dt: 0, player: player.position, force: true)
    }

    /// Updates the character look from worn clothing.
    func refreshAppearance() {
        var a = player.appearance
        a.top = Garment(color: Vec3(0.55, 0.5, 0.45), layer: .skin, bulky: false, longSleeves: false)
        a.top.color = a.skin
        a.pants = Garment(color: Vec3(0.2, 0.2, 0.22), layer: .fabric)
        a.shoes = Garment(color: a.skin, layer: .skin)
        a.bootsStyle = false
        a.head = nil
        a.face = nil
        a.vest = nil
        a.backpack = nil
        if let t = equipment.item(.torso), let c = t.def.clothing {
            a.top = Garment(color: c.color, layer: c.layer, bulky: c.bulky, longSleeves: c.longSleeves, dirt: (1 - t.condition) * 0.4)
        }
        if let l = equipment.item(.legs), let c = l.def.clothing {
            a.pants = Garment(color: c.color, layer: c.layer, dirt: (1 - l.condition) * 0.4)
        }
        if let f = equipment.item(.feet), let c = f.def.clothing {
            a.shoes = Garment(color: c.color, layer: c.layer)
            a.bootsStyle = c.boots
        }
        if let h = equipment.item(.head), let c = h.def.clothing { a.head = c.gear; a.headTint = c.color }
        if let f = equipment.item(.face), let c = f.def.clothing { a.face = c.gear; a.faceTint = c.color }
        if let v = equipment.item(.vest), let c = v.def.clothing { a.vest = c.gear; a.vestTint = c.color }
        if let b = equipment.item(.backpack), let c = b.def.clothing { a.backpack = c.gear; a.backpackTint = c.color }
        player.appearance = a
    }

    // MARK: Messages

    func message(_ text: String, important: Bool = false) {
        if let last = hud.messages.last, last.text == text, last.time > 1.5 { return }
        hud.messages.append(HUDMessage(text: text, time: important ? 5 : 3.5, important: important))
        if hud.messages.count > 5 { hud.messages.removeFirst() }
    }

    // MARK: Update

    func update(dt rawDt: Float) {
        let dt = min(rawDt, 1.0 / 20.0)
        gameTime += dt
        swayTime += dt
        env.update(dt: dt)
        updateCamera(dt: dt)
        updatePlayer(dt: dt)
        world.updateDoors(dt: dt, focus: player.position)
        items.update(dt: dt, world: world) { [weak self] wi, impact in
            guard let self = self else { return }
            if impact > 2 {
                self.sounds.play(.drop, at: wi.position, volume: min(1, impact / 8))
                self.ai.noise(at: wi.position, radius: min(25, impact * 3))
            }
        }
        updateAI(dt: dt)
        particles.update(dt: dt)
        updateInteraction(dt: dt)
        updateHUD(dt: dt)
        for i in 0..<corpses.count { corpses[i].age += dt }
        input.clearEdges()
    }

    func updateCamera(dt: Float) {
        let sens = mixf(lookSensitivity, lookSensitivity * aimSensitivity, aimBlend) * (hud.showScope ? 0.35 : 1)
        camYaw -= input.look.x * sens
        camPitch += input.look.y * sens * (invertY ? -1 : 1)
        camPitch = clampf(camPitch, -1.35, 1.3)
        camYaw = wrapAngle(camYaw)
        if input.cameraTogglePressed {
            if server.firstPersonOnly {
                message("This server is first person only")
            } else {
                firstPerson.toggle()
            }
        }
        aimBlend = damp(aimBlend, isAiming ? 1 : 0, 12, dt)
        recoilPitch = damp(recoilPitch, 0, 6, dt)
        recoilYaw = damp(recoilYaw, 0, 6, dt)
        cameraShake = max(0, cameraShake - dt * 3)
    }

    var isAiming: Bool { input.aimToggled && player.alive && !player.body.swimming }

    func movementSpeed(magnitude m: Float) -> Float {
        let body = player.body
        if m < 0.12 { return 0 }
        let crouched = body.stance == .crouched
        var speed: Float
        if m < 0.6 {
            speed = (crouched ? 1.1 : 1.7) * (m / 0.6)
        } else {
            speed = crouched ? 2.1 : 4.1
            if player.sprinting && !crouched { speed = 6.2 }
        }
        if isAiming { speed = min(speed, crouched ? 1.0 : 1.9) }
        if let a = action, !a.allowMovement { speed = 0 } else if action != nil { speed = min(speed, 1.4) }
        // Carried weight slows you down.
        let w = equipment.totalWeight
        if w > 25 { speed *= max(0.6, 1 - (w - 25) * 0.02) }
        return speed * stats.movementMultiplier
    }

    func updatePlayer(dt: Float) {
        let p = player
        p.timeAlive += p.alive ? dt : 0
        p.vaultCooldown = max(0, p.vaultCooldown - dt)
        p.hitFlash = max(0, p.hitFlash - dt * 2)
        guard p.alive else {
            p.deathTimer += dt
            p.pose.death = min(1, p.deathTimer / 0.9)
            p.pose.speed = 0
            p.pose.hold = .none
            _ = p.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
            p.pose.position = p.body.position
            p.joints = CharacterAnimator.compute(p.pose, scale: p.appearance.scale)
            return
        }
        // Stance.
        if input.crouchToggled && p.body.stance == .standing {
            p.body.stance = .crouched
        } else if !input.crouchToggled && p.body.stance == .crouched {
            if !p.body.tryStand(world: world) { input.crouchToggled = true }
        }
        // Movement intent (camera relative).
        let fwd = flatForward(yaw: camYaw), right = flatRight(yaw: camYaw)
        var mv = input.move
        let mag = min(vlength2(mv), 1)
        if mag > 0.001 { mv = mv / max(vlength2(mv), 1) }
        p.sprinting = input.sprintToggled && mag > 0.5 && stats.canSprint && p.body.stance == .standing && !isAiming && action == nil
        if input.sprintToggled && mag < 0.1 { input.sprintToggled = false }
        let speed = movementSpeed(magnitude: mag)
        var wishDir = fwd * mv.y + right * mv.x
        if vlength(wishDir) > 0.001 { wishDir = vnormalize(wishDir) }
        let wish = wishDir * speed
        if p.sprinting { stats.stamina = max(0, stats.stamina - 9 * dt) }

        // Jump / vault.
        var jump = false
        if input.jumpPressed && p.vaultCooldown <= 0 && action == nil {
            let dir = vlength(wishDir) > 0.1 ? wishDir : flatForward(yaw: firstPerson ? camYaw : p.yaw)
            if stats.canJump && p.body.tryVault(world: world, dir: dir) {
                sounds.play(.vault, at: p.position, volume: 0.7)
                p.vaultCooldown = 0.4
                stats.stamina = max(0, stats.stamina - 10)
                makeNoise(radius: 10)
            } else if p.body.stance == .standing && stats.canJump {
                jump = true
                stats.stamina = max(0, stats.stamina - 12)
            } else if p.body.stance == .crouched {
                input.crouchToggled = false
                _ = p.body.tryStand(world: world)
            } else if !stats.canJump {
                message(stats.brokenLeg ? "You can't jump with a broken leg" : "You are too exhausted to jump")
            }
        }
        let ev = p.body.update(dt: dt, wish: wish, jump: jump, world: world)
        if ev.jumped { makeNoise(radius: 6) }
        if ev.landed {
            if ev.fallDistance > 0.8 {
                sounds.play(.jumpLand, at: p.position, volume: min(1, ev.fallDistance / 3))
                makeNoise(radius: 6 + ev.fallDistance * 2)
            }
            applyFallDamage(ev.fallDistance)
        }
        if ev.footstep {
            let s: SoundID
            if p.body.swimming || p.body.waterDepth > 0.2 {
                s = .footstepWater
            } else {
                switch ev.surface {
                case .concrete: s = .footstepConcrete
                case .wood: s = .footstepWood
                case .metal: s = .footstepMetal
                default: s = .footstepGrass
                }
            }
            let hs = vlength2(Vec2(p.body.velocity.x, p.body.velocity.z))
            let loud: Float = p.body.stance == .crouched ? 0.25 : (hs > 5 ? 1.0 : (hs > 3 ? 0.7 : 0.4))
            sounds.play(s, at: p.position, volume: loud, pitch: rng.range(0.9, 1.1))
            makeNoise(radius: p.body.stance == .crouched ? 2.5 : (hs > 5 ? 18 : (hs > 3 ? 10 : 5)))
        }
        record.distanceTravelled += vdistanceXZ(p.position, lastPosForDistance)
        lastPosForDistance = p.position

        // Facing.
        let hs = vlength2(Vec2(p.body.velocity.x, p.body.velocity.z))
        if firstPerson || isAiming || weapon.meleeT >= 0 || p.pose.attack >= 0 {
            p.yaw = dampAngle(p.yaw, camYaw, 18, dt)
        } else if hs > 0.4 && vlength(wishDir) > 0.1 {
            p.yaw = dampAngle(p.yaw, yawFromDirection(wishDir.x, wishDir.z), 9, dt)
        }

        // Timed actions.
        if let a = action {
            if p.sprinting || (!a.allowMovement && hs > 0.5) || input.firePressed {
                message("\(a.label) interrupted")
                action = nil
            } else {
                a.elapsed += dt
                if let tick = a.onTick, !tick(dt) {
                    action = nil
                } else if a.elapsed >= a.duration {
                    action = nil
                    a.onComplete()
                }
            }
        }
        hud.actionLabel = action?.label
        hud.actionProgress = action.map { $0.elapsed / $0.duration } ?? 0

        updateWeapon(dt: dt)

        // Survival simulation.
        let insul = clothingInsulation()
        let ctx = SurvivalContext(dt: dt, airTemp: env.airTemperature(altitude: p.position.y), indoors: world.isIndoors(p.eyePosition),
                                  rain: env.rain, wind: env.windStrength, swimming: p.body.swimming, sprinting: p.sprinting,
                                  moving: hs > 0.5, insulation: insul.0, waterproof: insul.1, drain: server.survivalDrain)
        let sev = stats.update(ctx)
        for (m, imp) in sev.messages { message(m, important: imp) }
        if sev.vomited {
            sounds.play(.vomit, at: p.position, volume: 0.8)
            makeNoise(radius: 12)
        }
        if sev.coughed {
            sounds.play(.cough, at: p.position, volume: 0.7)
            makeNoise(radius: 15)
        }
        if sev.sneezed {
            sounds.play(.sneeze, at: p.position, volume: 0.8)
            makeNoise(radius: 18)
        }
        stats.stamina = min(stats.stamina, stats.maxStamina(weight: equipment.totalWeight))
        if let cause = sev.deathCause { die(cause: cause) }
        if p.body.swimming { stats.stamina = max(0, stats.stamina - dt * 3) }

        // Animation state.
        let cycle: Float = hs > 5 ? 2.6 : (hs > 2.5 ? 2.2 : 1.5)
        p.pose.phase += hs / cycle * kTwoPi * dt
        if p.pose.phase > kTwoPi * 100 { p.pose.phase -= kTwoPi * 100 }
        p.pose.speed = hs
        p.pose.position = p.body.position
        p.pose.yaw = p.yaw
        p.pose.crouch = damp(p.pose.crouch, p.body.stance == .crouched ? 1 : 0, 10, dt)
        p.pose.airborne = damp(p.pose.airborne, p.body.onGround || p.body.swimming ? 0 : 1, 8, dt)
        p.pose.aim = aimBlend
        p.pose.aimPitch = camPitch + recoilPitch
        p.pose.vault = p.body.isVaulting ? min(p.body.vaultT, 1) : -1
        p.pose.hit = max(0, p.pose.hit - dt * 4)
        p.pose.hold = holdStyle()
        p.pose.reload = weapon.reloadT
        p.pose.attack = weapon.meleeT
        p.pose.punchSide = weapon.punchSide
        p.pose.eat = (action?.animation ?? false) ? fmodf(action!.elapsed, 1.2) / 1.2 : -1
        p.joints = CharacterAnimator.compute(p.pose, scale: p.appearance.scale)
    }

    func holdStyle() -> HoldStyle {
        guard let h = equipment.hands else { return .none }
        let d = h.def
        if let w = d.weapon {
            switch w.weaponClass {
            case .pistol: return .pistol
            case .melee: return w.twoHanded ? .twoHandMelee : .melee
            default: return .rifle
            }
        }
        return .item
    }

    /// Total (insulation, waterproofing) from worn clothes.
    func clothingInsulation() -> (Float, Float) {
        var ins: Float = 0
        var wp: Float = 0
        var n: Float = 0
        for s in [EquipSlot.head, .face, .torso, .vest, .legs, .feet] {
            if let it = equipment.item(s), let c = it.def.clothing {
                ins += c.insulation * (0.5 + 0.5 * it.condition)
                if s == .torso || s == .legs || s == .feet || s == .head {
                    wp += c.waterproof
                    n += 1
                }
            }
        }
        if equipment.item(.backpack) != nil { ins += 0.05 }
        return (min(1.6, ins), n > 0 ? wp / 4 : 0)
    }

    func applyFallDamage(_ d: Float) {
        guard d > 3.2 else { return }
        let dmg = (d - 3.2) * 16
        stats.damage(health: dmg, cause: "Fell to their death")
        hud.damageFlash = min(1, hud.damageFlash + dmg / 40)
        cameraShake = 0.6
        sounds.play(.playerHurt, at: player.position, volume: 1)
        if d > 4.5 && rng.chance(min(0.9, (d - 4.5) * 0.3)) && !stats.brokenLeg {
            stats.brokenLeg = true
            message("You broke your leg", important: true)
        }
        if stats.health <= 0 { die(cause: "Fell to their death") }
    }

    func die(cause: String) {
        guard player.alive else { return }
        player.alive = false
        player.deathTimer = 0
        deathCause = cause
        action = nil
        sounds.play(.playerDeath, at: player.position, volume: 1)
        dropEverythingOnDeath()
    }

    /// The body stays; all gear falls to the ground around it as physical items.
    func dropEverythingOnDeath() {
        let p = player.position
        var all: [ItemInstance] = []
        if let h = equipment.hands { all.append(h) }
        for s in EquipSlot.allCases { if let it = equipment.slots[s.rawValue] { all.append(it) } }
        equipment = Equipment()
        for (i, it) in all.enumerated() {
            let a = Float(i) / Float(max(all.count, 1)) * kTwoPi + rng.range(-0.3, 0.3)
            let r = rng.range(0.5, 1.1)
            var pos = p + Vec3(cosf(a) * r, 0.4, sinf(a) * r)
            pos.y = world.groundHeight(at: pos).height
            items.add(it, at: pos, yaw: rng.range(0, kTwoPi))
        }
        var a = player.appearance
        a.top = Garment(color: Vec3(0.7, 0.7, 0.68), layer: .fabric, bulky: false, longSleeves: false, dirt: 0.4)
        a.pants = Garment(color: Vec3(0.25, 0.25, 0.27), layer: .fabric, dirt: 0.4)
        a.head = nil
        a.face = nil
        a.vest = nil
        a.backpack = nil
        player.appearance = a
        corpses.append(PlayerCorpse(joints: player.joints, appearance: a, position: p, age: 0))
        if corpses.count > 4 { corpses.removeFirst() }
    }

    func makeNoise(radius: Float) {
        player.lastNoiseRadius = max(player.lastNoiseRadius, radius)
    }

    // MARK: AI

    func updateAI(dt: Float) {
        let p = player
        ai.managePopulation(dt: dt, player: p.position)
        ai.nav.beginFrame()
        ai.nav.warm(around: p.position)
        let target = AITarget(position: p.position, chest: p.position + Vec3(0, p.body.stance == .crouched ? 0.8 : 1.3, 0),
                              crouched: p.body.stance == .crouched, sprinting: p.sprinting, noiseRadius: p.lastNoiseRadius,
                              alive: p.alive, building: world.buildingAt(p.position + Vec3(0, 0.5, 0)),
                              lightLevel: max(env.lightLevel, flashlightActive ? 0.8 : 0), visibility: env.visibilityFactor)
        aiEvents.removeAll(keepingCapacity: true)
        ai.update(dt: dt, target: target, events: &aiEvents)
        handleAIEvents()
    }

    var flashlightActive: Bool {
        if let h = equipment.hands {
            if h.def.tool == .flashlight && flashlightOn && h.charge > 0 { return true }
            if let l = h.attachment(.rail), l.def.attachment?.light == true, l.charge > 0, isAiming, env.daylight < 0.45 { return true }
        }
        return false
    }

    // MARK: Interaction

    /// Ray from the camera through the crosshair.
    var aimRay: (origin: Vec3, dir: Vec3) {
        let dir = directionFrom(yaw: camYaw + recoilYaw, pitch: camPitch + recoilPitch)
        return (camPos, dir)
    }

    func updateInteraction(dt: Float) {
        interactCooldown = max(0, interactCooldown - dt)
        guard player.alive else {
            interaction = nil
            hud.prompt = nil
            return
        }
        interaction = findInteraction()
        hud.prompt = interaction.map { promptText(for: $0) }
        if input.interactPressed, let target = interaction, interactCooldown <= 0, action == nil {
            interactCooldown = 0.25
            performInteraction(target)
        }
    }

    func findInteraction() -> InteractionTarget? {
        let eye = player.eyePosition
        let ray = aimRay
        let bodyFwd = flatForward(yaw: firstPerson ? camYaw : player.yaw)
        var best: InteractionTarget?
        var bestScore: Float = -10
        // Items on the ground / shelves.
        for wi in items.query(center: eye, radius: 2.6) where wi.resting {
            let c = wi.position + Vec3(0, 0.05, 0)
            let to = c - eye
            let d = vlength(to)
            if d > 2.5 { continue }
            let facing = vdot(to / max(d, 0.01), ray.dir)
            let flat = vnormalize(Vec3(to.x, 0, to.z))
            let bodyFacing = vdot(flat, bodyFwd)
            if facing < 0.75 && !(d < 1.6 && bodyFacing > 0.5) { continue }
            // Must not be behind a wall.
            if world.collision.raycast(origin: eye, direction: to / max(d, 0.01), maxDistance: max(0, d - 0.12), mask: .blocksSight) != nil { continue }
            let score = facing * 2 - d * 0.35 + 0.3
            if score > bestScore {
                bestScore = score
                best = .item(wi.id)
            }
        }
        // Doors.
        for di in world.doorsNear(eye, radius: 2.6) {
            let c = world.doors[di].center
            let to = c - eye
            let d = vlength(to)
            if d > 2.3 { continue }
            let facing = vdot(vnormalize(to), ray.dir)
            let bodyFacing = vdot(vnormalize(Vec3(to.x, 0, to.z)), bodyFwd)
            let score = max(facing, bodyFacing * 0.8) * 1.5 - d * 0.2
            if (facing > 0.55 || bodyFacing > 0.6) && score > bestScore {
                bestScore = score
                best = .door(di)
            }
        }
        // Water sources.
        if best == nil, let ws = world.nearestWaterSource(to: player.position, maxDistance: 2.2) {
            best = .water(ws.position, ws.safe)
        }
        return best
    }

    func promptText(for t: InteractionTarget) -> String {
        switch t {
        case .door(let i):
            return world.doors[i].isOpen ? "Close Door" : "Open Door"
        case .item(let id):
            guard let wi = items.items[id] else { return "" }
            var s = "Pick up \(wi.item.displayName)"
            if let q = wi.item.quantityText { s += " (\(q))" }
            return s
        case .water(_, let safe):
            if let h = equipment.hands, let f = h.def.food, f.liquidContainer, h.quantity < Int(f.capacity) {
                return "Fill \(h.def.name)"
            }
            return safe ? "Drink Water" : "Drink Lake Water"
        }
    }

    func performInteraction(_ t: InteractionTarget) {
        switch t {
        case .door(let i):
            world.toggleDoor(i)
            sounds.play(world.doors[i].isOpen ? .doorOpen : .doorClose, at: world.doors[i].center, volume: 0.8)
            makeNoise(radius: 8)
        case .item(let id):
            pickUp(worldItemID: id)
        case .water(let pos, let safe):
            drinkOrFill(at: pos, safe: safe)
        }
    }

    // MARK: HUD

    func updateHUD(dt: Float) {
        for i in 0..<hud.messages.count { hud.messages[i].time -= dt }
        hud.messages.removeAll { $0.time <= 0 }
        hud.hitMarker = max(0, hud.hitMarker - dt * 4)
        hud.damageFlash = max(0, hud.damageFlash - dt * 1.2)
        hud.locationTimer = max(0, hud.locationTimer - dt)
        if Int(gameTime * 2) % 2 == 0 {
            let loc = world.location(at: player.position)?.name
            if loc != lastLocation {
                if let l = loc {
                    hud.locationBanner = l
                    hud.locationTimer = 4
                }
                lastLocation = loc
            }
        }
        player.lastNoiseRadius = max(0, player.lastNoiseRadius - dt * 25)
        let optic = equipment.hands?.attachment(.optic)?.def.attachment
        hud.showScope = optic?.scope == true && aimBlend > 0.85 && firstPerson && equipment.hands?.def.isFirearm == true && weapon.reloadT < 0
        hud.showRedDot = optic?.redDot == true && aimBlend > 0.6 && equipment.hands?.def.isFirearm == true && weapon.reloadT < 0
    }

    // MARK: Rendering

    var currentFOV: Float {
        var aimFov = fovBase * 0.72
        if let h = equipment.hands, h.def.isFirearm, let o = h.attachment(.optic)?.def.attachment, o.zoomFOV > 0 {
            aimFov = (o.scope && !firstPerson) ? 30 : o.zoomFOV
        }
        return mixf(fovBase, aimFov, aimBlend) * kDegToRad
    }

    /// Camera transform with collision against the world.
    func computeCamera(dt: Float) -> (eye: Vec3, view: Mat4) {
        let p = player
        let dir = directionFrom(yaw: camYaw + recoilYaw, pitch: camPitch + recoilPitch)
        var eye: Vec3
        if firstPerson && p.alive {
            camSmoothY = damp(camSmoothY, p.body.position.y, 20, dt)
            let head = p.joints.headCenter
            eye = Vec3(head.x, camSmoothY + (head.y - p.body.position.y) + 0.04, head.z) + flatForward(yaw: camYaw) * 0.1
        } else {
            camSmoothY = damp(camSmoothY, p.body.position.y, p.body.onGround ? 14 : 30, dt)
            let eyeH = p.alive ? p.body.eyeHeight - 0.08 : 0.8
            let base = Vec3(p.body.position.x, camSmoothY + eyeH, p.body.position.z)
            let right = flatRight(yaw: camYaw)
            let shoulder = mixf(0.42, 0.55, aimBlend)
            var dist = mixf(2.6, 1.15, aimBlend)
            if p.sprinting { dist += 0.35 }
            if !p.alive { dist = 3.2 }
            var pivot = base + right * shoulder
            if let h = world.collision.raycast(origin: base, direction: right, maxDistance: shoulder + 0.2, mask: .blocksSight) {
                pivot = base + right * max(0, h.distance - 0.25)
            }
            let back = -dir
            var d = dist
            if let h = world.collision.raycast(origin: pivot, direction: back, maxDistance: dist + 0.25, mask: .blocksSight) {
                d = max(0.25, h.distance - 0.25)
            }
            if let t = world.terrain.raycast(origin: pivot, direction: back, maxDist: d + 0.3) {
                d = max(0.25, min(d, t - 0.3))
            }
            eye = pivot + back * d
            let groundAtEye = world.terrain.height(eye.x, eye.z) + 0.25
            if eye.y < groundAtEye { eye.y = groundAtEye }
        }
        if cameraShake > 0 {
            eye += Vec3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) * (cameraShake * 0.03)
        }
        camPos = eye
        let view = Mat4.lookAt(eye: eye, target: eye + dir, up: Vec3(0, 1, 0))
        return (eye, view)
    }

    func buildScene(_ scene: RenderScene, dt: Float) {
        scene.beginFrame()
        let cam = computeCamera(dt: dt)
        scene.cameraPos = cam.eye
        scene.view = cam.view
        scene.fovY = currentFOV
        scene.time = gameTime
        let indoors = world.isIndoors(cam.eye)
        env.fill(&scene.uniforms, indoors: indoors)
        scene.rainIntensity = env.rain
        scene.drawRain = !indoors
        scene.uniforms.grade.z = hud.damageFlash
        scene.uniforms.grade.x = stats.saturation
        scene.uniforms.grade.y = 0.35 + hud.damageFlash * 0.4 + (stats.health < 30 ? 0.4 : 0)
        scene.uniforms.flashlightPos = Vec4(0, 0, 0, 0)
        scene.uniforms.pointLight = Vec4(0, 0, 0, 0)
        if flashlightActive {
            let d = directionFrom(yaw: camYaw, pitch: camPitch)
            let origin = firstPerson ? cam.eye + Vec3(0, -0.15, 0) : player.joints.gripTransform.translationPart
            scene.uniforms.flashlightPos = Vec4(origin.x, origin.y, origin.z, 1)
            scene.uniforms.flashlightDir = Vec4(d.x, d.y, d.z, 0.9)
        }
        // Player body.
        CharacterAnimator.emit(player.joints, player.appearance, meshes: characterMeshes, scene: scene, hideHead: firstPerson && player.alive)
        emitHeldItem(scene: scene)
        // Previous lives.
        for c in corpses where vdistance(c.position, cam.eye) < 200 {
            CharacterAnimator.emit(c.joints, c.appearance, meshes: characterMeshes, scene: scene)
        }
        // World items within range.
        for wi in items.query(center: cam.eye, radius: 60) {
            let model = wi.item.def.model
            let rest = ItemVisuals.restTransforms[model.rawValue] ?? .identity
            var m = Mat4.translation(wi.position) * Mat4.rotationY(wi.yaw)
            if !wi.resting { m = m * Mat4.rotationX(wi.tilt.x) * Mat4.rotationZ(wi.tilt.z) }
            m = m * rest
            let highlight: Float = interaction == .item(wi.id) ? 1 : 0
            ItemVisuals.emit(wi.item, transform: m, scene: scene, highlight: highlight, castsShadow: vdistance(wi.position, cam.eye) < 25)
        }
        // Agents.
        ai.emit(scene: scene, meshes: characterMeshes, camera: cam.eye) { a in
            // Hostile survivors carry a Vanta-47.
            let grip = a.joints.gripTransform
            scene.add(ItemVisuals.mesh(.rifleVanta), InstanceData(model: grip), castsShadow: true)
            scene.add(ItemVisuals.mesh(.magVanta), InstanceData(model: grip * Mat4.translation(ItemVisuals.geometry(.rifleVanta).magwell)), castsShadow: false)
        }
        particles.fill(scene)
    }

    /// Draws the item in hands: on the body in third person, as a view model in first person.
    func emitHeldItem(scene: RenderScene) {
        guard let h = equipment.hands, player.alive else { return }
        let magOffset = Vec3(0, -0.25 * max(0, sinf(max(weapon.reloadT, 0) * kPi)), 0)
        if firstPerson {
            let m = viewModelTransform()
            ItemVisuals.emit(h, transform: m, scene: scene, viewModel: true, magazineOffset: magOffset)
            // Arms holding it.
            let cm = characterMeshes
            let j = player.joints
            scene.addViewModel(cm.part(.forearm), InstanceData(model: j.forearmR, tint: armColor(), layer: Float(armLayer().rawValue)))
            scene.addViewModel(cm.part(.forearm), InstanceData(model: j.forearmL, tint: armColor(), layer: Float(armLayer().rawValue)))
            scene.addViewModel(cm.part(.hand), InstanceData(model: j.handR, tint: player.appearance.skin, layer: Float(Mat.skin.rawValue)))
            scene.addViewModel(cm.part(.hand), InstanceData(model: j.handL, tint: player.appearance.skin, layer: Float(Mat.skin.rawValue)))
        } else {
            var m = player.joints.gripTransform
            if !h.def.isFirearm && !h.def.isMelee && h.def.tool != .flashlight {
                // Small items rest in the palm.
                let rest = ItemVisuals.restTransforms[h.def.model.rawValue] ?? .identity
                m = m * Mat4.translation(Vec3(0, -0.03, -0.02)) * rest
            }
            ItemVisuals.emit(h, transform: m, scene: scene, magazineOffset: magOffset)
        }
    }

    func armColor() -> Vec3 {
        if let t = equipment.item(.torso), let c = t.def.clothing, c.longSleeves { return c.color }
        return player.appearance.skin
    }

    func armLayer() -> Mat {
        if let t = equipment.item(.torso), let c = t.def.clothing, c.longSleeves { return c.layer }
        return .skin
    }

    /// First-person weapon placement (world space) including ADS alignment, sway and recoil.
    func viewModelTransform() -> Mat4 {
        let dir = directionFrom(yaw: camYaw + recoilYaw, pitch: camPitch + recoilPitch)
        var right = vcross(dir, Vec3(0, 1, 0))
        if vlengthSq(right) < 1e-5 { right = Vec3(1, 0, 0) }
        right = vnormalize(right)
        let up = vcross(right, dir)
        let camBasis = Mat4.basis(right: right, up: up, back: -dir, origin: camPos)
        var sightH: Float = 0.11
        var isFirearm = false
        if let h = equipment.hands, h.def.isFirearm {
            isFirearm = true
            let g = ItemVisuals.geometry(h.def.model)
            sightH = g.sightHeight
            if let o = h.attachment(.optic) { sightH = g.optic.y + ItemVisuals.opticHeight(o.def.model) }
        }
        let a = aimBlend
        let bob = sinf(player.pose.phase) * 0.008 * min(player.pose.speed / 4, 1) * (1 - a)
        let sway = Vec3(sinf(swayTime * 1.1), sinf(swayTime * 1.7) * 0.6, 0) * (0.004 * stats.aimSway * (1 - a * 0.6))
        let hip = Vec3(0.17, -0.17 + bob, -0.36)
        let ads = Vec3(0, -sightH, isFirearm ? -0.3 : -0.36)
        var local = vlerp(hip, ads, isFirearm ? a : a * 0.4) + sway
        if weapon.reloadT >= 0 { local += Vec3(0.02, -0.06, 0.04) * sinf(weapon.reloadT * kPi) }
        if weapon.meleeT >= 0 {
            let t = weapon.meleeT
            local += Vec3(-0.12 * sinf(t * kPi), 0.05 * sinf(t * kTwoPi), -0.15 * sinf(t * kPi))
        }
        local.z += recoilPitch * 0.4
        var m = camBasis * Mat4.translation(local)
        if weapon.reloadT >= 0 { m = m * Mat4.rotationZ(0.5 * sinf(weapon.reloadT * kPi)) }
        if weapon.meleeT >= 0 { m = m * Mat4.rotationX(-0.9 * sinf(weapon.meleeT * kPi)) }
        // Place arms (via the body rig) on the view model.
        let g = ItemVisuals.geometry(equipment.hands?.def.model ?? .bat)
        let handR = m.transformPoint(Vec3(0, -0.02, 0.02))
        let handL = m.transformPoint(isFirearm ? g.support : Vec3(-0.05, -0.04, 0.05))
        let shR = camBasis.transformPoint(Vec3(0.2, -0.32, 0.05)), shL = camBasis.transformPoint(Vec3(-0.2, -0.32, 0.05))
        let pole = -up * 0.8 + right * 0.3
        let (eR, hR) = CharacterAnimator.solveElbow(shoulder: shR, hand: handR, l1: 0.27, l2: 0.25, pole: pole + right * 0.4)
        let (eL, hL) = CharacterAnimator.solveElbow(shoulder: shL, hand: handL, l1: 0.27, l2: 0.25, pole: pole - right * 0.6)
        player.joints.forearmR = CharacterAnimator.segment(eR, hR, hint: dir)
        player.joints.forearmL = CharacterAnimator.segment(eL, hL, hint: dir)
        player.joints.handR = CharacterAnimator.segment(hR, hR + (hR - eR), hint: dir)
        player.joints.handL = CharacterAnimator.segment(hL, hL + (hL - eL), hint: dir)
        return m
    }
}
