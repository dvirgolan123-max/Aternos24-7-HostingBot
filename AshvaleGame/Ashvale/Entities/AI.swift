//
//  AI.swift
//  Ashvale
//
//  Infected and hostile survivors: perception (vision with light, stance,
//  fog and line of sight; hearing of footsteps, doors and gunshots), state
//  machines (idle, wander, investigate, chase, attack, search), A* navigation,
//  hit reactions, deaths with physical loot drops, and population management.
//

import Foundation

enum AgentKind: Int, Codable, CaseIterable {
    case civilian, worker, police, soldier, runner, brute, bandit

    var isInfected: Bool { self != .bandit }

    struct Props {
        var health: Float
        var walk: Float
        var run: Float
        var damage: Float
        var attackInterval: Float
        var armor: Float
        var headArmor: Float
        var sight: Float
        var hearing: Float
        var bleedChance: Float
        var legBreakChance: Float
        var scale: Float
        var loot: LootCategory
    }

    var props: Props {
        switch self {
        case .civilian: return Props(health: 90, walk: 1.0, run: 4.5, damage: 9, attackInterval: 1.3, armor: 0, headArmor: 0, sight: 32, hearing: 1, bleedChance: 0.35, legBreakChance: 0, scale: 1, loot: .living)
        case .worker: return Props(health: 110, walk: 1.0, run: 4.3, damage: 11, attackInterval: 1.35, armor: 0.05, headArmor: 0, sight: 30, hearing: 1, bleedChance: 0.35, legBreakChance: 0, scale: 1.03, loot: .industrial)
        case .police: return Props(health: 120, walk: 1.0, run: 4.4, damage: 10, attackInterval: 1.3, armor: 0.25, headArmor: 0, sight: 34, hearing: 1.1, bleedChance: 0.35, legBreakChance: 0, scale: 1.02, loot: .police)
        case .soldier: return Props(health: 140, walk: 1.05, run: 4.7, damage: 12, attackInterval: 1.25, armor: 0.4, headArmor: 0.5, sight: 36, hearing: 1.1, bleedChance: 0.4, legBreakChance: 0, scale: 1.04, loot: .military)
        case .runner: return Props(health: 70, walk: 1.3, run: 5.9, damage: 8, attackInterval: 0.95, armor: 0, headArmor: 0, sight: 38, hearing: 1.3, bleedChance: 0.3, legBreakChance: 0, scale: 0.97, loot: .living)
        case .brute: return Props(health: 280, walk: 0.9, run: 3.9, damage: 24, attackInterval: 2.0, armor: 0.15, headArmor: 0.2, sight: 26, hearing: 0.9, bleedChance: 0.55, legBreakChance: 0.18, scale: 1.16, loot: .industrial)
        case .bandit: return Props(health: 120, walk: 1.4, run: 4.2, damage: 36, attackInterval: 0.13, armor: 0.3, headArmor: 0.3, sight: 75, hearing: 1.2, bleedChance: 0.6, legBreakChance: 0, scale: 1, loot: .military)
        }
    }
}

enum AgentState: Int {
    case idle, wander, investigate, chase, attack, search, dead
}

enum HitZone {
    case head, torso, legs
}

final class Agent {
    let id: Int
    let kind: AgentKind
    let body: MovementBody
    var yaw: Float
    var health: Float
    var state: AgentState = .idle
    var stateTimer: Float = 0
    var home: Vec3
    var target = Vec3(0, 0, 0)
    var lastSeen = Vec3(0, 0, 0)
    var awareness: Float = 0
    var path: [Vec3] = []
    var pathIndex = 0
    var repathTimer: Float = 0
    var attackCooldown: Float = 0
    var attackT: Float = -1
    var attackHitDone = false
    var stagger: Float = 0
    var pose = CharacterPose()
    var joints = CharacterJoints()
    var appearance = Appearance()
    var deathTime: Float = 0
    var soundTimer: Float = Float.random(in: 2...8)
    var thinkTimer: Float = 0
    var locationIndex: Int
    var canSeeTarget = false
    var stuckTimer: Float = 0
    var lastPos = Vec3(0, 0, 0)
    var stairChain: [Vec3] = []
    var stairIndex = 0
    // Bandit weapon state.
    var burstLeft = 0
    var aimTimer: Float = 0
    var magazine = 30
    var reloadTimer: Float = 0

    init(id: Int, kind: AgentKind, position: Vec3, yaw: Float, location: Int) {
        self.id = id
        self.kind = kind
        body = MovementBody(position: position)
        body.radius = 0.28
        self.yaw = yaw
        health = kind.props.health
        home = position
        locationIndex = location
        lastPos = position
    }

    var alive: Bool { state != .dead }
    var position: Vec3 { body.position }
}

struct AITarget {
    var position: Vec3
    var chest: Vec3
    var crouched: Bool
    var sprinting: Bool
    var noiseRadius: Float
    var alive: Bool
    var building: Int?
    var lightLevel: Float
    var visibility: Float
}

enum AIEvent {
    case playerHit(damage: Float, bleedChance: Float, dirty: Bool, legBreak: Float, cause: String, from: Vec3, bullet: Bool)
    case gunshot(from: Vec3, to: Vec3)
    case sound(SoundID, Vec3, Float)
    case died(Agent)
}

final class AIManager {
    let world: World
    let nav: NavGrid
    private(set) var agents: [Agent] = []
    private var nextID = 1
    private var noises: [(pos: Vec3, radius: Float, age: Float)] = []
    var rng = RNG(seed: 4711)
    var populationMultiplier: Float = 1
    var aggression: Float = 1
    private var locationCooldown: [Int: Float] = [:]
    private var killedInLocation: [Int: Int] = [:]
    private var populateTimer: Float = 0
    var maxActive = 40
    var killCount = 0

    init(world: World) {
        self.world = world
        nav = NavGrid(world: world)
    }

    func reset() {
        agents.removeAll()
        noises.removeAll()
        locationCooldown.removeAll()
        killedInLocation.removeAll()
    }

    func noise(at p: Vec3, radius: Float) {
        noises.append((p, radius, 0))
    }

    // MARK: Spawning

    private func appearanceFor(_ kind: AgentKind) -> Appearance {
        var a = Appearance()
        a.infected = kind.isInfected
        a.scale = kind.props.scale * rng.range(0.96, 1.04)
        if kind.isInfected {
            a.skin = rng.pick([Vec3(0.62, 0.66, 0.58), Vec3(0.58, 0.6, 0.55), Vec3(0.66, 0.62, 0.6), Vec3(0.5, 0.52, 0.46)])
        } else {
            a.skin = rng.pick([Vec3(0.86, 0.68, 0.56), Vec3(0.7, 0.52, 0.4), Vec3(0.55, 0.4, 0.3)])
        }
        a.hair = rng.pick([Vec3(0.2, 0.15, 0.1), Vec3(0.35, 0.3, 0.25), Vec3(0.1, 0.1, 0.1), Vec3(0.5, 0.45, 0.4)])
        a.longHair = rng.chance(0.3)
        let dirt: Float = kind.isInfected ? rng.range(0.3, 0.7) : 0.1
        switch kind {
        case .civilian, .runner:
            a.top = Garment(color: rng.pick([Vec3(0.6, 0.2, 0.18), Vec3(0.3, 0.35, 0.5), Vec3(0.7, 0.68, 0.6), Vec3(0.25, 0.4, 0.3), Vec3(0.5, 0.45, 0.4)]),
                            layer: .fabric, bulky: rng.chance(0.4), longSleeves: rng.chance(0.6), dirt: dirt)
            a.pants = Garment(color: rng.pick([Vec3(0.32, 0.4, 0.58), Vec3(0.25, 0.25, 0.27), Vec3(0.45, 0.4, 0.32)]), layer: rng.chance(0.5) ? .denim : .fabric, dirt: dirt)
        case .worker:
            a.top = Garment(color: rng.pick([Vec3(0.85, 0.45, 0.12), Vec3(0.2, 0.3, 0.5), Vec3(0.35, 0.35, 0.3)]), layer: .canvas, bulky: true, longSleeves: true, dirt: dirt)
            a.pants = Garment(color: Vec3(0.3, 0.3, 0.32), layer: .canvas, dirt: dirt)
            a.bootsStyle = true
            a.shoes = Garment(color: Vec3(0.3, 0.22, 0.15), layer: .leather)
            if rng.chance(0.4) { a.head = .beanie; a.headTint = Vec3(0.8, 0.5, 0.1) }
        case .police:
            a.top = Garment(color: Vec3(0.12, 0.15, 0.28), layer: .fabric, bulky: true, longSleeves: true, dirt: dirt)
            a.pants = Garment(color: Vec3(0.1, 0.12, 0.2), layer: .fabric, dirt: dirt)
            a.vest = .vestPolice
            a.vestTint = Vec3(0.15, 0.17, 0.22)
            a.bootsStyle = true
            a.shoes = Garment(color: Vec3(0.1, 0.1, 0.1), layer: .leather)
            if rng.chance(0.5) { a.head = .policeCap; a.headTint = Vec3(0.12, 0.14, 0.25) }
        case .soldier, .bandit:
            a.top = Garment(color: Vec3(0.8, 0.85, 0.75), layer: .camo, bulky: true, longSleeves: true, dirt: dirt)
            a.pants = Garment(color: Vec3(0.8, 0.85, 0.75), layer: .camo, dirt: dirt)
            a.bootsStyle = true
            a.shoes = Garment(color: Vec3(0.12, 0.12, 0.12), layer: .leather)
            a.head = rng.chance(0.7) ? .helmet : .beanie
            a.headTint = Vec3(0.36, 0.4, 0.3)
            a.vest = rng.chance(0.6) ? .plateCarrier : .chestRig
            a.vestTint = Vec3(0.75, 0.78, 0.65)
            if kind == .bandit {
                a.face = .balaclava
                a.faceTint = Vec3(0.12, 0.12, 0.12)
                a.backpack = .backpackHiking
                a.top.color = Vec3(0.35, 0.33, 0.3)
                a.top.layer = .canvas
            }
        case .brute:
            a.top = Garment(color: Vec3(0.4, 0.38, 0.35), layer: .canvas, bulky: true, longSleeves: false, dirt: dirt)
            a.pants = Garment(color: Vec3(0.3, 0.3, 0.28), layer: .denim, dirt: dirt)
            a.bootsStyle = true
            a.shoes = Garment(color: Vec3(0.2, 0.15, 0.1), layer: .leather)
        }
        return a
    }

    @discardableResult
    func spawn(_ kind: AgentKind, at p: Vec3, location: Int) -> Agent {
        let a = Agent(id: nextID, kind: kind, position: p, yaw: rng.range(0, kTwoPi), location: location)
        nextID += 1
        a.appearance = appearanceFor(kind)
        a.state = rng.chance(0.5) ? .idle : .wander
        a.stateTimer = rng.range(2, 8)
        a.pose.phase = rng.range(0, kTwoPi)
        agents.append(a)
        return a
    }

    private func kindFor(location l: Location) -> AgentKind {
        switch l.kind {
        case .military:
            return rng.weightedIndex([1, 0, 0, 6, 1.5, 0.6, 0]).asKind
        case .checkpoint:
            return rng.weightedIndex([2, 0, 1, 4, 1, 0.3, 0]).asKind
        case .industrial:
            return rng.weightedIndex([2, 5, 0, 0, 1.5, 1, 0]).asKind
        case .town:
            return rng.weightedIndex([6, 1.5, 1.5, 0.3, 2, 0.6, 0]).asKind
        default:
            return rng.weightedIndex([6, 1, 0.2, 0.1, 1.5, 0.3, 0]).asKind
        }
    }

    private var locationSpots: [Int: [Int]] = [:]

    private func indoorSpots(_ li: Int, _ l: Location) -> [Int] {
        if let s = locationSpots[li] { return s }
        let s = world.lootSpots.indices.filter { i in
            let sp = world.lootSpots[i]
            return sp.large && vlength2(Vec2(sp.position.x, sp.position.z) - l.center) < l.radius
        }
        locationSpots[li] = s
        return s
    }

    /// Finds a free spawn position inside a location (outdoors or inside buildings on floor level).
    private func spawnPoint(in l: Location, index li: Int, avoid player: Vec3) -> Vec3? {
        let spots = indoorSpots(li, l)
        for _ in 0..<14 {
            if rng.chance(0.35) && !spots.isEmpty {
                let sp = world.lootSpots[spots[rng.int(0, spots.count - 1)]]
                if vdistance(sp.position, player) < 35 { continue }
                let g = world.groundHeight(at: sp.position + Vec3(0, 0.3, 0))
                let p = Vec3(sp.position.x, g.height, sp.position.z)
                if MovementBody(position: p).fits(world: world, at: p, height: 1.8) { return p }
                continue
            }
            let d = rng.unitDisk() * l.radius * 0.85
            let x = l.center.x + d.x, z = l.center.y + d.y
            let th = world.terrain.height(x, z)
            let g = world.groundHeight(at: Vec3(x, th + 1.0, z), radius: 0.3, stepHeight: 0)
            let p = Vec3(x, g.height, z)
            if vdistance(p, player) < 45 { continue }
            if world.isInWater(p) > 0.3 { continue }
            let mb = MovementBody(position: p)
            if mb.fits(world: world, at: p, height: 1.8) { return p }
        }
        return nil
    }

    /// Keeps locations near the player populated and despawns far agents.
    func managePopulation(dt: Float, player: Vec3, force: Bool = false) {
        populateTimer -= dt
        for (k, v) in locationCooldown { locationCooldown[k] = v - dt }
        if !force && populateTimer > 0 { return }
        populateTimer = 3
        // Despawn far agents (dead bodies linger nearby for a while).
        agents.removeAll { a in
            let d = vdistanceXZ(a.position, player)
            if !a.alive { return d > 220 || a.deathTime > 300 }
            return d > 380
        }
        var active = agents.filter { $0.alive }.count
        for (li, l) in world.locations.enumerated() {
            let d = vlength2(Vec2(player.x, player.z) - l.center)
            if d > l.radius + 220 { continue }
            if let cd = locationCooldown[li], cd > 0 { continue }
            let budget = Int((Float(l.infectedBudget) * populationMultiplier).rounded()) - (killedInLocation[li] ?? 0)
            let present = agents.filter { $0.locationIndex == li && $0.alive }.count
            var need = budget - present
            while need > 0 && active < maxActive {
                if let p = spawnPoint(in: l, index: li, avoid: player) {
                    spawn(kindFor(location: l), at: p, location: li)
                    active += 1
                }
                need -= 1
            }
            // Armed survivors hold the military base and the checkpoint.
            if (l.kind == .military || l.kind == .checkpoint) && !agents.contains(where: { $0.kind == .bandit && $0.locationIndex == li }) && rng.chance(0.6) {
                let n = l.kind == .military ? 2 : 1
                for _ in 0..<n {
                    if let p = spawnPoint(in: l, index: li, avoid: player) { spawn(.bandit, at: p, location: li) }
                }
            }
            locationCooldown[li] = 20
        }
        // A few wanderers in the wild.
        let wild = agents.filter { $0.locationIndex < 0 && $0.alive }.count
        if wild < Int(3 * populationMultiplier) && active < maxActive && rng.chance(0.4) {
            let a = rng.range(0, kTwoPi)
            let r = rng.range(90, 160)
            let x = clampf(player.x + cosf(a) * r, 20, World.size - 20), z = clampf(player.z + sinf(a) * r, 20, World.size - 20)
            let th = world.terrain.height(x, z)
            let p = Vec3(x, world.groundHeight(at: Vec3(x, th + 1, z)).height, z)
            if world.isInWater(p) < 0.2 {
                spawn(rng.chance(0.2) ? .runner : .civilian, at: p, location: -1)
            }
        }
    }

    func registerKill(_ a: Agent) {
        killCount += 1
        if a.locationIndex >= 0 {
            killedInLocation[a.locationIndex, default: 0] += 1
        }
    }

    // MARK: Perception

    private func canSee(_ a: Agent, _ t: AITarget, range: Float) -> Bool {
        guard t.alive else { return false }
        let eye = a.position + Vec3(0, 1.6, 0)
        let to = t.chest - eye
        let d = vlength(to)
        if d > range { return false }
        let fwd = flatForward(yaw: a.yaw)
        let dir = to / max(d, 0.001)
        let facing = vdot(Vec3(dir.x, 0, dir.z), fwd)
        if d > 2.5 && facing < 0.3 { return false }
        if world.collision.raycast(origin: eye, direction: dir, maxDistance: d - 0.3, mask: .blocksSight) != nil { return false }
        if d > 25, world.terrain.raycast(origin: eye, direction: dir, maxDist: d) != nil { return false }
        return true
    }

    // MARK: Update

    func update(dt: Float, target t: AITarget, events: inout [AIEvent]) {
        for i in 0..<noises.count { noises[i].age += dt }
        noises.removeAll { $0.age > 1.0 }
        if t.noiseRadius > 1 { noises.append((t.position, t.noiseRadius, 0)) }

        for a in agents {
            if !a.alive {
                a.deathTime += dt
                a.pose.death = min(1, a.deathTime / 0.8)
                if a.deathTime < 2 {
                    _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
                }
                a.pose.position = a.body.position
                if a.deathTime < 3 { a.joints = CharacterAnimator.compute(a.pose, scale: a.appearance.scale) }
                continue
            }
            let dist = vdistance(a.position, t.position)
            // Throttle far agents.
            let lod: Float = dist > 160 ? 0.25 : (dist > 90 ? 0.08 : 0)
            a.thinkTimer -= dt
            let think = a.thinkTimer <= 0
            if think { a.thinkTimer = max(lod, 0.12) }
            if a.kind == .bandit {
                updateBandit(a, dt: dt, target: t, dist: dist, think: think, events: &events)
            } else {
                updateInfected(a, dt: dt, target: t, dist: dist, think: think, events: &events)
            }
            // Animation.
            let hs = vlength2(Vec2(a.body.velocity.x, a.body.velocity.z))
            a.pose.phase += hs / (hs > 3 ? 2.3 : 1.4) * kTwoPi * dt * (a.kind.isInfected ? 0.9 : 1)
            a.pose.speed = hs
            a.pose.position = a.body.position
            a.pose.yaw = a.yaw
            a.pose.infected = a.kind.isInfected
            a.pose.hit = max(0, a.pose.hit - dt * 3)
            a.pose.airborne = damp(a.pose.airborne, a.body.onGround ? 0 : 1, 8, dt)
            if a.attackT >= 0 {
                a.pose.attack = a.attackT
            } else {
                a.pose.attack = -1
            }
            if dist < 200 || think {
                a.joints = CharacterAnimator.compute(a.pose, scale: a.appearance.scale)
            }
        }
    }

    private func moveTowards(_ a: Agent, point: Vec3, speed: Float, dt: Float) {
        var dir = point - a.position
        dir.y = 0
        let d = vlength(dir)
        var wish = Vec3(0, 0, 0)
        if d > 0.15 {
            dir /= d
            wish = dir * speed
            a.yaw = dampAngle(a.yaw, yawFromDirection(dir.x, dir.z), 8, dt)
        }
        // Separation from other agents.
        for o in agents where o !== a && o.alive {
            let off = a.position - o.position
            let od = vlength2(Vec2(off.x, off.z))
            if od < 0.8 && od > 0.001 {
                wish += Vec3(off.x, 0, off.z) / od * (0.8 - od) * 3
            }
        }
        let ev = a.body.update(dt: dt, wish: wish, jump: false, world: world)
        _ = ev
    }

    /// Follows path / stairs / direct line towards a goal.
    private func navigate(_ a: Agent, goal: Vec3, speed: Float, dt: Float, think: Bool, targetBuilding: Int?) {
        // Different floor inside the same building: use the stair chain.
        if abs(goal.y - a.position.y) > 1.5, let bi = targetBuilding ?? world.buildingAt(a.position + Vec3(0, 0.5, 0)),
           let chains = world.buildingStairs[bi], a.stairChain.isEmpty {
            let goingUp = goal.y > a.position.y
            var best: [Vec3]?
            var bestD = Float.greatestFiniteMagnitude
            for c in chains {
                let start = goingUp ? c.first! : c.last!
                if abs(start.y - a.position.y) > 1.2 { continue }
                let d = vdistance(start, a.position)
                if d < bestD { bestD = d; best = goingUp ? c : c.reversed() }
            }
            if let b = best {
                a.stairChain = b
                a.stairIndex = 0
            }
        }
        if !a.stairChain.isEmpty {
            let wp = a.stairChain[a.stairIndex]
            if vdistanceXZ(wp, a.position) < 0.6 && abs(wp.y - a.position.y) < 0.8 {
                a.stairIndex += 1
                if a.stairIndex >= a.stairChain.count {
                    a.stairChain.removeAll()
                }
            }
            if !a.stairChain.isEmpty {
                // Use A* on the ground floor to reach the first waypoint, then walk the chain directly.
                if a.stairIndex == 0 && vdistanceXZ(wp, a.position) > 3 {
                    followPath(a, goal: wp, speed: speed, dt: dt, think: think)
                } else {
                    moveTowards(a, point: wp, speed: speed * 0.8, dt: dt)
                }
                return
            }
        }
        followPath(a, goal: goal, speed: speed, dt: dt, think: think)
    }

    private func followPath(_ a: Agent, goal: Vec3, speed: Float, dt: Float, think: Bool) {
        let d = vdistanceXZ(goal, a.position)
        // Direct line if clear.
        var direct = d < 2.0
        if !direct && think {
            let from = a.position + Vec3(0, 0.6, 0)
            let to = Vec3(goal.x, a.position.y + 0.6, goal.z)
            let dir = to - from
            let len = vlength(dir)
            if len > 0.01 && world.collision.raycast(origin: from, direction: dir / len, maxDistance: len, mask: .solid) == nil {
                let from2 = a.position + Vec3(0, 1.4, 0)
                let to2 = Vec3(goal.x, a.position.y + 1.4, goal.z)
                if world.collision.raycast(origin: from2, direction: (to2 - from2) / len, maxDistance: len, mask: .solid) == nil {
                    direct = true
                    a.path.removeAll()
                }
            }
        }
        if direct || (a.path.isEmpty && !think) {
            if direct || a.path.isEmpty { moveTowards(a, point: goal, speed: speed, dt: dt) }
            return
        }
        a.repathTimer -= dt
        if a.path.isEmpty || a.repathTimer <= 0 || vdistanceXZ(a.path.last ?? goal, goal) > 3 {
            a.repathTimer = 1.4 + rng.range(0, 0.6)
            if let p = nav.findPath(from: a.position, to: goal) {
                a.path = p
                a.pathIndex = 0
            } else {
                a.path = []
            }
        }
        if a.pathIndex < a.path.count {
            var wp = a.path[a.pathIndex]
            wp.y = a.position.y
            if vdistanceXZ(wp, a.position) < 0.7 {
                a.pathIndex += 1
            }
            moveTowards(a, point: wp, speed: speed, dt: dt)
        } else {
            moveTowards(a, point: goal, speed: speed, dt: dt)
        }
    }

    private func updateInfected(_ a: Agent, dt: Float, target t: AITarget, dist: Float, think: Bool, events: inout [AIEvent]) {
        let pr = a.kind.props
        a.stateTimer -= dt
        a.attackCooldown -= dt
        a.soundTimer -= dt
        if a.stagger > 0 {
            a.stagger -= dt
            _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
            return
        }
        // Perception.
        if think {
            let lightFactor = mixf(0.35, 1.0, t.lightLevel)
            var range = pr.sight * lightFactor * t.visibility * aggression
            if t.crouched { range *= 0.55 }
            if t.sprinting { range *= 1.25 }
            a.canSeeTarget = canSee(a, t, range: range)
            if a.canSeeTarget {
                let gain = (2.6 - dist / max(range, 1) * 2.0) * (a.state == .chase ? 3 : 1)
                a.awareness = min(1.5, a.awareness + max(0.4, gain) * a.thinkTimer * 4)
                a.lastSeen = t.position
            } else {
                a.awareness = max(0, a.awareness - 0.15 * a.thinkTimer)
            }
            // Hearing.
            if a.state != .chase && a.state != .attack {
                for n in noises where n.age < 0.35 {
                    let hd = vdistance(n.pos, a.position)
                    if hd < n.radius * pr.hearing {
                        a.state = .investigate
                        a.target = n.pos
                        a.stateTimer = 20
                        a.path.removeAll()
                        if a.soundTimer < 1 || rng.chance(0.3) {
                            events.append(.sound(.infectedAlert, a.position + Vec3(0, 1.6, 0), 0.8))
                            a.soundTimer = rng.range(3, 6)
                        }
                        break
                    }
                }
            }
            if a.awareness >= 1 && a.state != .chase && a.state != .attack {
                a.state = .chase
                events.append(.sound(.infectedAlert, a.position + Vec3(0, 1.6, 0), 1))
                a.soundTimer = rng.range(2, 4)
            }
        }
        if !t.alive && (a.state == .chase || a.state == .attack) {
            a.state = .search
            a.stateTimer = 8
        }
        // Ambient groans.
        if a.soundTimer <= 0 {
            a.soundTimer = rng.range(5, 12)
            if dist < 60 {
                events.append(.sound(a.state == .chase ? .infectedAttack : .infectedIdle, a.position + Vec3(0, 1.6, 0), a.state == .chase ? 1 : 0.6))
            }
        }

        switch a.state {
        case .idle:
            _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
            if a.stateTimer <= 0 {
                a.state = .wander
                let d = rng.unitDisk() * 14
                a.target = a.home + Vec3(d.x, 0, d.y)
                a.stateTimer = rng.range(8, 16)
            }
        case .wander:
            navigate(a, goal: a.target, speed: pr.walk, dt: dt, think: think, targetBuilding: nil)
            if vdistanceXZ(a.target, a.position) < 1 || a.stateTimer <= 0 {
                a.state = .idle
                a.stateTimer = rng.range(3, 9)
            }
        case .investigate:
            navigate(a, goal: a.target, speed: pr.run * 0.55, dt: dt, think: think, targetBuilding: nil)
            if vdistanceXZ(a.target, a.position) < 1.5 || a.stateTimer <= 0 {
                a.state = .search
                a.stateTimer = rng.range(5, 9)
                a.home = a.position
            }
        case .chase:
            if a.canSeeTarget { a.lastSeen = t.position }
            let goal = a.canSeeTarget ? t.position : a.lastSeen
            if dist < 1.35 && abs(t.position.y - a.position.y) < 1.2 && t.alive {
                a.state = .attack
                a.attackT = 0
                a.attackHitDone = false
                break
            }
            navigate(a, goal: goal, speed: pr.run * min(1.2, aggression), dt: dt, think: think, targetBuilding: t.building)
            if !a.canSeeTarget && vdistanceXZ(a.lastSeen, a.position) < 1.5 {
                a.state = .search
                a.stateTimer = rng.range(8, 14)
                a.home = a.position
                a.awareness = 0.4
            }
            // Stuck detection: try a side step.
            if think {
                if vdistance(a.position, a.lastPos) < 0.05 * Float(a.thinkTimer * 10) && dist > 2 {
                    a.stuckTimer += a.thinkTimer
                } else {
                    a.stuckTimer = 0
                }
                a.lastPos = a.position
                if a.stuckTimer > 2.5 {
                    a.stuckTimer = 0
                    a.path.removeAll()
                    a.repathTimer = 0
                    a.stairChain.removeAll()
                }
            }
        case .attack:
            // Face the target and swing.
            let to = t.position - a.position
            a.yaw = dampAngle(a.yaw, yawFromDirection(to.x, to.z), 10, dt)
            _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
            if a.attackT >= 0 {
                a.attackT += dt / 0.75
                if a.attackT > 0.5 && !a.attackHitDone {
                    a.attackHitDone = true
                    let facing = vdot(vnormalize(Vec3(to.x, 0, to.z)), flatForward(yaw: a.yaw))
                    if vdistance(t.position, a.position) < 1.75 && facing > 0.3 && t.alive && abs(t.position.y - a.position.y) < 1.3 {
                        events.append(.playerHit(damage: pr.damage * rng.range(0.8, 1.2), bleedChance: pr.bleedChance, dirty: true,
                                                 legBreak: pr.legBreakChance, cause: "Killed by the infected", from: a.position, bullet: false))
                        events.append(.sound(.hitFlesh, t.chest, 0.9))
                    } else {
                        events.append(.sound(.meleeSwing, a.position + Vec3(0, 1.4, 0), 0.5))
                    }
                }
                if a.attackT >= 1 {
                    a.attackT = -1
                    a.attackCooldown = pr.attackInterval * rng.range(0.6, 1.0)
                }
            } else if a.attackCooldown <= 0 {
                if dist < 1.5 && t.alive {
                    a.attackT = 0
                    a.attackHitDone = false
                    events.append(.sound(.infectedAttack, a.position + Vec3(0, 1.6, 0), 1))
                } else {
                    a.state = .chase
                }
            }
        case .search:
            if a.stateTimer <= 0 {
                a.state = .idle
                a.stateTimer = rng.range(4, 10)
                a.awareness = 0
            } else {
                if vdistanceXZ(a.target, a.position) < 1 || a.path.isEmpty && rng.chance(dt * 0.5) {
                    let d = rng.unitDisk() * 8
                    a.target = a.home + Vec3(d.x, 0, d.y)
                }
                navigate(a, goal: a.target, speed: pr.walk * 1.5, dt: dt, think: think, targetBuilding: nil)
            }
        case .dead:
            break
        }
    }

    // MARK: Hostile survivors

    private func updateBandit(_ a: Agent, dt: Float, target t: AITarget, dist: Float, think: Bool, events: inout [AIEvent]) {
        let pr = a.kind.props
        a.stateTimer -= dt
        a.reloadTimer -= dt
        a.pose.hold = .rifle
        if a.stagger > 0 {
            a.stagger -= dt
            _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
            return
        }
        if think {
            let lightFactor = mixf(0.3, 1.0, t.lightLevel)
            var range = pr.sight * lightFactor * t.visibility
            if t.crouched { range *= 0.6 }
            a.canSeeTarget = canSee(a, t, range: range)
            if a.canSeeTarget {
                a.awareness = min(1.5, a.awareness + a.thinkTimer * 2.2)
                a.lastSeen = t.position
            } else {
                a.awareness = max(0, a.awareness - a.thinkTimer * 0.1)
                for n in noises where n.age < 0.35 && vdistance(n.pos, a.position) < n.radius * pr.hearing && a.state != .chase {
                    a.state = .investigate
                    a.target = n.pos
                    a.stateTimer = 15
                }
            }
            if a.awareness >= 1 { a.state = .chase }
        }
        switch a.state {
        case .chase, .attack:
            a.pose.aim = damp(a.pose.aim, 1, 6, dt)
            let to = t.chest - (a.position + Vec3(0, 1.45, 0))
            a.yaw = dampAngle(a.yaw, yawFromDirection(to.x, to.z), 6, dt)
            a.pose.aimPitch = atan2f(to.y, max(0.1, vlength2(Vec2(to.x, to.z))))
            if a.canSeeTarget && t.alive {
                // Hold position at range, close in when far.
                if dist > 45 {
                    navigate(a, goal: t.position, speed: pr.run * 0.7, dt: dt, think: think, targetBuilding: t.building)
                } else {
                    _ = a.body.update(dt: dt, wish: Vec3(0, 0, 0), jump: false, world: world)
                }
                a.aimTimer += dt
                if a.reloadTimer > 0 { break }
                if a.magazine <= 0 {
                    a.reloadTimer = 3.2
                    a.magazine = 30
                    events.append(.sound(.magOut, a.position + Vec3(0, 1.3, 0), 0.7))
                    break
                }
                if a.aimTimer > 0.9 && a.burstLeft <= 0 && a.attackCooldown <= 0 {
                    a.burstLeft = rng.int(2, 4)
                }
                a.attackCooldown -= dt
                if a.burstLeft > 0 && a.attackCooldown <= 0 {
                    a.burstLeft -= 1
                    a.magazine -= 1
                    a.attackCooldown = a.burstLeft > 0 ? 0.13 : rng.range(0.9, 1.8)
                    fireBandit(a, target: t, dist: dist, events: &events)
                }
            } else {
                a.aimTimer = 0
                navigate(a, goal: a.lastSeen, speed: pr.run * 0.6, dt: dt, think: think, targetBuilding: t.building)
                if vdistanceXZ(a.lastSeen, a.position) < 2 {
                    a.state = .search
                    a.stateTimer = 12
                    a.home = a.position
                }
            }
        case .investigate:
            a.pose.aim = damp(a.pose.aim, 0.6, 4, dt)
            navigate(a, goal: a.target, speed: pr.walk * 1.4, dt: dt, think: think, targetBuilding: nil)
            if vdistanceXZ(a.target, a.position) < 2 || a.stateTimer <= 0 {
                a.state = .search
                a.stateTimer = 10
                a.home = a.position
            }
        default:
            a.pose.aim = damp(a.pose.aim, 0, 3, dt)
            if a.stateTimer <= 0 || vdistanceXZ(a.target, a.position) < 1 {
                let d = rng.unitDisk() * 25
                a.target = a.home + Vec3(d.x, 0, d.y)
                a.stateTimer = rng.range(10, 20)
                a.state = .wander
            }
            navigate(a, goal: a.target, speed: pr.walk, dt: dt, think: think, targetBuilding: nil)
        }
    }

    private func fireBandit(_ a: Agent, target t: AITarget, dist: Float, events: inout [AIEvent]) {
        let muzzle = a.joints.gripTransform.transformPoint(Vec3(0, 0.07, -0.6))
        var spread: Float = 0.035 + dist * 0.0009
        if t.sprinting { spread *= 1.6 }
        if t.crouched { spread *= 1.2 }
        let aimPoint = t.chest + Vec3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) * (spread * dist)
        let dir = vnormalize(aimPoint - muzzle)
        let maxD = vdistance(aimPoint, muzzle) + 2
        var end = muzzle + dir * maxD
        var blocked = false
        if let h = world.collision.raycast(origin: muzzle, direction: dir, maxDistance: maxD, mask: .blocksBullets) {
            end = h.point
            blocked = true
        }
        events.append(.gunshot(from: muzzle, to: end))
        noise(at: a.position, radius: 320)
        if !blocked {
            // Did the bullet pass through the player's body?
            let r = Ray(origin: muzzle, direction: dir)
            let base = t.position
            if rayCapsule(r, a: base + Vec3(0, 0.3, 0), b: base + Vec3(0, t.crouched ? 1.0 : 1.55, 0), radius: 0.3, maxDist: maxD) != nil {
                events.append(.playerHit(damage: a.kind.props.damage * rng.range(0.8, 1.2), bleedChance: 0.75, dirty: false, legBreak: 0,
                                         cause: "Shot by a hostile survivor", from: a.position, bullet: true))
            }
        }
    }

    // MARK: Damage

    /// Ray test against agent hitboxes. Returns nearest hit.
    func hitTest(origin o: Vec3, direction d: Vec3, maxDistance: Float, includeDead: Bool = false) -> (Agent, HitZone, Float)? {
        let ray = Ray(origin: o, direction: d)
        var best: (Agent, HitZone, Float)?
        for a in agents where a.alive || includeDead {
            let j = a.joints
            let c = j.chestCenter
            // Broad phase.
            if raySphere(ray, center: c, radius: 1.4, maxDist: maxDistance) == nil && vdistance(o, c) > 1.4 { continue }
            let maxD = best?.2 ?? maxDistance
            if let t = raySphere(ray, center: j.headCenter, radius: 0.13, maxDist: maxD) {
                best = (a, .head, t)
                continue
            }
            if let t = rayCapsule(ray, a: j.pelvisCenter, b: c + vnormalize(c - j.pelvisCenter) * 0.12, radius: 0.2, maxDist: maxD), t < (best?.2 ?? maxD) + 0.001 {
                best = (a, .torso, t)
                continue
            }
            for (k, an) in [(j.kneeL, j.ankleL), (j.kneeR, j.ankleR)] {
                if let t = rayCapsule(ray, a: j.pelvisCenter, b: k, radius: 0.09, maxDist: maxD), t < (best?.2 ?? maxD) {
                    best = (a, .legs, t)
                }
                if let t = rayCapsule(ray, a: k, b: an, radius: 0.07, maxDist: maxD), t < (best?.2 ?? maxD) {
                    best = (a, .legs, t)
                }
            }
        }
        return best
    }

    /// Applies damage; returns true if the agent died.
    @discardableResult
    func damage(_ a: Agent, amount: Float, zone: HitZone, from: Vec3, bullet: Bool, events: inout [AIEvent]) -> Bool {
        guard a.alive else { return false }
        let pr = a.kind.props
        var dmg = amount
        switch zone {
        case .head:
            dmg *= bullet ? 3.2 : 2.0
            dmg *= 1 - pr.headArmor * (bullet ? 0.6 : 0.4)
        case .torso:
            dmg *= 1 - pr.armor * (bullet ? 0.6 : 0.3)
        case .legs:
            dmg *= 0.6
        }
        a.health -= dmg
        let to = a.position - from
        let facing = vdot(vnormalize(Vec3(to.x, 0, to.z)), flatForward(yaw: a.yaw))
        a.pose.hit = 1
        a.pose.hitDir = facing > 0 ? -1 : 1
        a.stagger = bullet ? 0.25 : 0.45
        if a.kind == .brute { a.stagger *= 0.3 }
        // Being hit always reveals the attacker.
        a.awareness = 1.5
        a.lastSeen = from
        if a.state != .attack { a.state = .chase }
        if a.health <= 0 {
            a.state = .dead
            a.deathTime = 0
            a.pose.death = 0.01
            a.pose.deathForward = facing > 0
            a.body.velocity = Vec3(0, 0, 0)
            registerKill(a)
            events.append(.died(a))
            events.append(.sound(a.kind.isInfected ? .infectedDeath : .playerDeath, a.position + Vec3(0, 1.4, 0), 1))
            return true
        }
        events.append(.sound(a.kind.isInfected ? .infectedHurt : .playerHurt, a.position + Vec3(0, 1.5, 0), 0.8))
        return false
    }

    // MARK: Rendering

    func emit(scene: RenderScene, meshes: CharacterMeshes, camera: Vec3, weaponModel: (Agent) -> Void) {
        for a in agents {
            let d = vdistance(a.position, camera)
            if d > 260 { continue }
            CharacterAnimator.emit(a.joints, a.appearance, meshes: meshes, scene: scene, shadow: d < 70)
            if a.kind == .bandit { weaponModel(a) }
        }
    }
}

private extension Int {
    var asKind: AgentKind { AgentKind(rawValue: self) ?? .civilian }
}
