//
//  PlayerController.swift
//  Ashvale
//
//  Character movement physics shared by the player (and reused by AI):
//  capsule vs world colliders, stairs/step-up, slopes, gravity, jumping,
//  crouching, vaulting over low obstacles and through windows, swimming.
//

import Foundation

enum Stance {
    case standing, crouched
}

struct MovementEvents {
    var landed = false
    var fallDistance: Float = 0
    var vaulted = false
    var footstep = false
    var jumped = false
    var surface: SurfaceKind = .grass
}

final class MovementBody {
    var position: Vec3
    var velocity = Vec3(0, 0, 0)
    var onGround = true
    var stance: Stance = .standing
    var radius: Float = 0.3
    var stepHeight: Float = 0.42
    var groundSurface: SurfaceKind = .grass
    var swimming = false
    var waterDepth: Float = 0

    // Vault state.
    var vaultT: Float = -1
    var vaultDuration: Float = 0.7
    var vaultStart = Vec3(0, 0, 0)
    var vaultEnd = Vec3(0, 0, 0)
    var vaultApex: Float = 0
    var vaultCrouchAfter = false

    private var highestY: Float
    private var stepAccumulator: Float = 0

    init(position: Vec3) {
        self.position = position
        highestY = position.y
    }

    var height: Float { stance == .crouched ? 1.1 : 1.8 }
    var eyeHeight: Float { stance == .crouched ? 1.02 : 1.64 }
    var isVaulting: Bool { vaultT >= 0 }

    /// Pushes the body's circle out of blocking boxes. Returns true if any collision occurred.
    @discardableResult
    func resolveCollisions(world: World, iterations: Int = 3) -> Bool {
        var collided = false
        for _ in 0..<iterations {
            var moved = false
            let feet = position.y
            let q = AABB(min: Vec3(position.x - radius - 0.05, feet + stepHeight, position.z - radius - 0.05),
                         max: Vec3(position.x + radius + 0.05, feet + height, position.z + radius + 0.05))
            var push = Vec2(0, 0)
            world.collision.forEach(in: q) { _, c in
                guard c.flags.contains(.solid) else { return }
                let b = c.box
                // Ignore surfaces we can step onto.
                if b.max.y <= feet + stepHeight { return }
                if b.min.y >= feet + height { return }
                let px = position.x + push.x, pz = position.z + push.y
                let cx = clampf(px, b.min.x, b.max.x)
                let cz = clampf(pz, b.min.z, b.max.z)
                var dx = px - cx, dz = pz - cz
                let d2 = dx * dx + dz * dz
                if d2 >= radius * radius { return }
                if d2 < 1e-8 {
                    // Center inside the box: push out along the smallest axis.
                    let left = px - b.min.x, right = b.max.x - px
                    let back = pz - b.min.z, front = b.max.z - pz
                    let m = min(min(left, right), min(back, front))
                    if m == left {
                        push.x -= left + radius
                    } else if m == right {
                        push.x += right + radius
                    } else if m == back {
                        push.y -= back + radius
                    } else {
                        push.y += front + radius
                    }
                } else {
                    let d = sqrtf(d2)
                    let pen = radius - d
                    push += Vec2(dx / d * pen, dz / d * pen)
                }
                moved = true
            }
            if moved {
                position.x += push.x
                position.z += push.y
                collided = true
                // Remove velocity into the obstacle.
                let n = vnormalize2(push)
                let vn = velocity.x * n.x + velocity.z * n.y
                if vn < 0 {
                    velocity.x -= n.x * vn
                    velocity.z -= n.y * vn
                }
            } else {
                break
            }
        }
        return collided
    }

    /// True if the body would fit (no blocking overlap) at `p` with the given height.
    func fits(world: World, at p: Vec3, height h: Float) -> Bool {
        var free = true
        let q = AABB(min: Vec3(p.x - radius + 0.04, p.y + 0.3, p.z - radius + 0.04), max: Vec3(p.x + radius - 0.04, p.y + h, p.z + radius - 0.04))
        world.collision.forEach(in: q) { _, c in
            if c.flags.contains(.solid) { free = false }
        }
        return free
    }

    func tryStand(world: World) -> Bool {
        if stance == .standing { return true }
        let q = AABB(min: Vec3(position.x - radius + 0.05, position.y + 1.0, position.z - radius + 0.05),
                     max: Vec3(position.x + radius - 0.05, position.y + 1.8, position.z + radius - 0.05))
        var blocked = false
        world.collision.forEach(in: q) { _, c in
            if c.flags.contains(.solid) && c.box.min.y > position.y + 0.5 { blocked = true }
        }
        if !blocked { stance = .standing }
        return !blocked
    }

    /// Attempts to start a vault in `dir` (unit XZ). Returns true when a vault begins.
    func tryVault(world: World, dir: Vec3) -> Bool {
        guard onGround, !isVaulting else { return false }
        let origin = position + Vec3(0, 0.45, 0)
        guard let hit = world.collision.raycast(origin: origin, direction: dir, maxDistance: radius + 0.75, mask: .solid) else { return false }
        let c = world.collision.colliders[Int(hit.collider)]
        let top = c.box.max.y
        let rel = top - position.y
        guard rel > 0.3 && rel < 1.6 else { return false }
        // Distance through the obstacle along dir.
        let ray = Ray(origin: hit.point + dir * 0.01, direction: dir)
        var tExit: Float = 0.4
        let t1 = (c.box.min - ray.origin) * ray.invDir
        let t2 = (c.box.max - ray.origin) * ray.invDir
        let tFar = pointwiseMax(t1, t2)
        tExit = min(min(abs(dir.x) > 1e-4 ? tFar.x : 99, abs(dir.z) > 1e-4 ? tFar.z : 99), 2.5)
        if tExit > 2.2 { return false }
        // Clearance above the obstacle (crouch-sized body).
        let mid = hit.point + dir * (tExit * 0.5)
        var blocked = false
        let clear = AABB(min: Vec3(mid.x - 0.18, top + 0.05, mid.z - 0.18), max: Vec3(mid.x + 0.18, top + 0.95, mid.z + 0.18))
        world.collision.forEach(in: clear) { idx, cc in
            if cc.flags.contains(.solid) && idx != Int(hit.collider) { blocked = true }
        }
        if blocked { return false }
        // Landing spot.
        var land = hit.point + dir * (tExit + radius + 0.2)
        land.y = top + 0.2
        let g = world.groundHeight(at: land, radius: 0.15, stepHeight: 0.0)
        land.y = g.height
        if land.y < top - 4.5 { return false }
        let standFree = fits(world: world, at: land, height: 1.8)
        let crouchFree = standFree || fits(world: world, at: land, height: 1.1)
        if !crouchFree { return false }
        vaultCrouchAfter = !standFree
        vaultStart = position
        vaultEnd = land
        vaultApex = top + 0.1
        vaultDuration = 0.45 + rel * 0.35
        vaultT = 0
        velocity = Vec3(0, 0, 0)
        return true
    }

    /// Integrates movement. `wish` is the desired horizontal velocity.
    func update(dt: Float, wish: Vec3, jump: Bool, world: World) -> MovementEvents {
        var ev = MovementEvents()
        // Vault animation overrides physics.
        if vaultT >= 0 {
            vaultT += dt / vaultDuration
            let t = min(vaultT, 1)
            var p = vlerp(vaultStart, vaultEnd, smoothstepf(0, 1, t))
            let lift = sinf(t * kPi)
            let baseY = mixf(vaultStart.y, vaultEnd.y, t)
            p.y = max(baseY, mixf(baseY, vaultApex, lift)) + lift * 0.05
            position = p
            if vaultT >= 1 {
                vaultT = -1
                position = vaultEnd
                onGround = true
                if vaultCrouchAfter { stance = .crouched }
                ev.vaulted = true
                highestY = position.y
            }
            return ev
        }

        let depth = world.isInWater(position + Vec3(0, 0.1, 0))
        waterDepth = depth
        swimming = depth > 1.25

        // Horizontal acceleration.
        let accel: Float = onGround ? 14 : 2.5
        let target = swimming ? wish * 0.45 : wish
        velocity.x = mixf(velocity.x, target.x, 1 - expf(-accel * dt))
        velocity.z = mixf(velocity.z, target.z, 1 - expf(-accel * dt))

        if swimming {
            // Float at the surface.
            let surfaceFeet = position.y + depth - 1.3
            velocity.y = (surfaceFeet - position.y) * 3
            onGround = false
        } else if onGround && jump {
            velocity.y = 4.3
            onGround = false
            ev.jumped = true
        } else if !onGround {
            velocity.y -= 15.5 * dt
            velocity.y = max(velocity.y, -40)
        }

        // Integrate with sub-steps for fast motion.
        let steps = max(1, Int(ceilf(vlength(velocity) * dt / 0.15)))
        let sdt = dt / Float(steps)
        let wasOnGround = onGround
        for _ in 0..<steps {
            position.x += velocity.x * sdt
            position.z += velocity.z * sdt
            resolveCollisions(world: world)
            position.y += velocity.y * sdt
            // Ceiling.
            if velocity.y > 0 {
                let head = AABB(min: Vec3(position.x - radius * 0.7, position.y + height - 0.1, position.z - radius * 0.7),
                                max: Vec3(position.x + radius * 0.7, position.y + height + 0.05, position.z + radius * 0.7))
                var hitCeiling = false
                world.collision.forEach(in: head) { _, c in if c.flags.contains(.solid) && c.box.min.y > position.y + 1.0 { hitCeiling = true } }
                if hitCeiling { velocity.y = min(velocity.y, 0) }
            }
            // Ground.
            let g = world.groundHeight(at: position, radius: 0.16, stepHeight: stepHeight)
            ev.surface = g.surface
            groundSurface = g.surface
            if swimming {
                if position.y < g.height { position.y = g.height }
                continue
            }
            if position.y <= g.height + 0.001 {
                position.y = g.height
                if velocity.y <= 0 { velocity.y = 0; onGround = true }
            } else if onGround && velocity.y <= 0 && position.y - g.height < 0.5 {
                // Stick to slopes and stairs going down.
                position.y = g.height
                velocity.y = 0
            } else {
                onGround = false
            }
        }
        // Clamp to map.
        position.x = clampf(position.x, 4, World.size - 4)
        position.z = clampf(position.z, 4, World.size - 4)

        if !onGround {
            highestY = max(highestY, position.y)
        } else {
            if !wasOnGround {
                ev.landed = true
                ev.fallDistance = max(0, highestY - position.y)
            }
            highestY = position.y
        }
        if swimming { highestY = position.y }

        // Footsteps.
        let hs = sqrtf(velocity.x * velocity.x + velocity.z * velocity.z)
        if onGround && hs > 0.3 {
            stepAccumulator += hs * dt
            let stride: Float = stance == .crouched ? 0.6 : (hs > 5 ? 1.25 : 0.85)
            if stepAccumulator > stride {
                stepAccumulator = 0
                ev.footstep = true
            }
        }
        return ev
    }
}
