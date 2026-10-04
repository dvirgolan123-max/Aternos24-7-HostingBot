//
//  CharacterRig.swift
//  Ashvale
//
//  Procedural human character: part meshes, clothing appearance, a joint
//  hierarchy driven by procedural animation (FK for legs/spine, two-bone IK
//  for arms) and emission of render instances.
//

import Foundation

enum CharPart: Int, CaseIterable {
    case head, hairShort, hairLong, neck, chest, chestBulky, abdomen, pelvis
    case upperArm, upperArmBulky, forearm, forearmBulky, hand, thigh, thighBulky, shin, foot, boot
    case eyes
}

enum GearMesh: Int, CaseIterable {
    case cap, beanie, helmet, policeCap, motoHelmet
    case bandana, surgicalMask, gasMask, balaclava
    case vestHunting, vestPolice, plateCarrier, chestRig
    case backpackSchool, backpackHiking, backpackMilitary
}

struct Garment {
    var color: Vec3
    var layer: Mat
    var bulky = false
    var longSleeves = true
    var dirt: Float = 0
}

struct Appearance {
    var skin = Vec3(0.86, 0.68, 0.56)
    var hair = Vec3(0.25, 0.18, 0.12)
    var longHair = false
    var top = Garment(color: Vec3(0.75, 0.75, 0.72), layer: .fabric, bulky: false, longSleeves: false)
    var pants = Garment(color: Vec3(0.3, 0.38, 0.55), layer: .denim)
    var shoes = Garment(color: Vec3(0.85, 0.85, 0.85), layer: .fabric)
    var bootsStyle = false
    var head: GearMesh?
    var headTint = Vec3(0.3, 0.3, 0.3)
    var face: GearMesh?
    var faceTint = Vec3(0.8, 0.8, 0.8)
    var vest: GearMesh?
    var vestTint = Vec3(0.3, 0.32, 0.25)
    var backpack: GearMesh?
    var backpackTint = Vec3(0.3, 0.35, 0.3)
    var infected = false
    var scale: Float = 1
}

/// Registered mesh ids for character parts and gear.
final class CharacterMeshes {
    var parts: [MeshID] = []
    var gear: [MeshID] = []

    func part(_ p: CharPart) -> MeshID { parts[p.rawValue] }
    func gear(_ g: GearMesh) -> MeshID { gear[g.rawValue] }

    static func build(registry: MeshRegistry) -> CharacterMeshes {
        let cm = CharacterMeshes()
        for p in CharPart.allCases {
            cm.parts.append(registry.add("char-\(p.rawValue)", makePart(p)))
        }
        for g in GearMesh.allCases {
            cm.gear.append(registry.add("gear-\(g.rawValue)", makeGear(g)))
        }
        return cm
    }

    private static func base() -> MeshBuilder {
        let m = MeshBuilder()
        m.material = .fabric
        m.color = Vec3(1, 1, 1)
        m.flags = VertexFlag.tintable
        m.skyVisibility = 1
        m.uvScale = 2
        return m
    }

    /// Part meshes are built in joint-local space. Limb segments extend along +Y from the joint.
    static func makePart(_ p: CharPart) -> MeshBuilder {
        let m = base()
        switch p {
        case .head:
            m.flags = VertexFlag.tintable | VertexFlag.skin
            m.addEllipsoid(center: Vec3(0, 0.11, 0.0), radii: Vec3(0.085, 0.115, 0.1), rings: 10, segments: 14)
            // Jaw and chin.
            m.addEllipsoid(center: Vec3(0, 0.05, -0.03), radii: Vec3(0.07, 0.06, 0.07), rings: 6, segments: 10)
            // Nose.
            m.addEllipsoid(center: Vec3(0, 0.1, -0.098), radii: Vec3(0.016, 0.028, 0.02), rings: 4, segments: 6)
            // Ears.
            m.addEllipsoid(center: Vec3(-0.086, 0.11, 0.0), radii: Vec3(0.012, 0.03, 0.02), rings: 4, segments: 6)
            m.addEllipsoid(center: Vec3(0.086, 0.11, 0.0), radii: Vec3(0.012, 0.03, 0.02), rings: 4, segments: 6)
            // Brow ridge.
            m.addEllipsoid(center: Vec3(0, 0.135, -0.075), radii: Vec3(0.065, 0.018, 0.03), rings: 4, segments: 8)
        case .eyes:
            m.flags = 0
            m.material = .plastic
            m.color = Vec3(0.06, 0.06, 0.07)
            m.addEllipsoid(center: Vec3(-0.032, 0.118, -0.088), radii: Vec3(0.013, 0.009, 0.006), rings: 3, segments: 6)
            m.addEllipsoid(center: Vec3(0.032, 0.118, -0.088), radii: Vec3(0.013, 0.009, 0.006), rings: 3, segments: 6)
        case .hairShort:
            m.material = .hair
            m.addEllipsoid(center: Vec3(0, 0.14, 0.012), radii: Vec3(0.091, 0.1, 0.104), rings: 8, segments: 12)
        case .hairLong:
            m.material = .hair
            m.addEllipsoid(center: Vec3(0, 0.14, 0.015), radii: Vec3(0.094, 0.104, 0.107), rings: 8, segments: 12)
            m.addBeveledBox(min: Vec3(-0.09, -0.05, 0.0), max: Vec3(0.09, 0.15, 0.1), bevel: 0.04)
        case .neck:
            m.flags = VertexFlag.tintable | VertexFlag.skin
            m.addCapsule(from: Vec3(0, 0, 0), to: Vec3(0, 0.1, 0), radiusA: 0.052, radiusB: 0.048, segments: 10, rings: 2)
        case .chest, .chestBulky:
            // Chest from waist joint (y=0) up to shoulders (y=0.32).
            let b: Float = p == .chestBulky ? 1.12 : 1.0
            m.addEllipsoid(center: Vec3(0, 0.2, 0.0), radii: Vec3(0.17 * b, 0.17, 0.11 * b), rings: 8, segments: 14)
            m.addCapsule(from: Vec3(-0.15, 0.27, 0), to: Vec3(0.15, 0.27, 0), radiusA: 0.07 * b, radiusB: 0.07 * b, segments: 10, rings: 2)
            m.addEllipsoid(center: Vec3(0, 0.08, 0.0), radii: Vec3(0.15 * b, 0.12, 0.1 * b), rings: 6, segments: 12)
            if p == .chestBulky {
                // Collar.
                m.addCylinder(center: Vec3(0, 0.3, 0.0), radiusBottom: 0.075, radiusTop: 0.07, height: 0.07, segments: 12)
            }
        case .abdomen:
            m.addEllipsoid(center: Vec3(0, 0.07, 0.0), radii: Vec3(0.145, 0.11, 0.095), rings: 6, segments: 12)
        case .pelvis:
            m.addEllipsoid(center: Vec3(0, -0.02, 0.0), radii: Vec3(0.165, 0.1, 0.105), rings: 6, segments: 12)
            // Belt.
            m.flags = 0
            m.material = .leather
            m.color = Vec3(0.18, 0.13, 0.1)
            m.addCylinder(center: Vec3(0, 0.03, 0), radiusBottom: 0.155, radiusTop: 0.155, height: 0.035, segments: 14, capTop: false, capBottom: false)
        case .upperArm, .upperArmBulky:
            let b: Float = p == .upperArmBulky ? 1.25 : 1.0
            m.addCapsule(from: Vec3(0, 0, 0), to: Vec3(0, 0.27, 0), radiusA: 0.052 * b, radiusB: 0.044 * b, segments: 9, rings: 2)
        case .forearm, .forearmBulky:
            let b: Float = p == .forearmBulky ? 1.2 : 1.0
            m.addCapsule(from: Vec3(0, 0, 0), to: Vec3(0, 0.25, 0), radiusA: 0.042 * b, radiusB: 0.034 * b, segments: 9, rings: 2)
        case .hand:
            m.flags = VertexFlag.tintable | VertexFlag.skin
            m.addEllipsoid(center: Vec3(0, 0.045, 0.0), radii: Vec3(0.042, 0.055, 0.02), rings: 5, segments: 8)
            // Thumb.
            m.addCapsule(from: Vec3(0.03, 0.02, -0.01), to: Vec3(0.05, 0.07, -0.025), radiusA: 0.012, radiusB: 0.01, segments: 6, rings: 1)
            // Fingers curled.
            m.addCapsule(from: Vec3(0, 0.09, 0), to: Vec3(0, 0.11, -0.03), radiusA: 0.022, radiusB: 0.018, segments: 6, rings: 1)
        case .thigh, .thighBulky:
            let b: Float = p == .thighBulky ? 1.1 : 1.0
            m.addCapsule(from: Vec3(0, 0, 0), to: Vec3(0, 0.43, 0), radiusA: 0.078 * b, radiusB: 0.058 * b, segments: 10, rings: 2)
        case .shin:
            m.addCapsule(from: Vec3(0, 0, 0), to: Vec3(0, 0.42, 0), radiusA: 0.054, radiusB: 0.046, segments: 10, rings: 2)
        case .foot:
            // Sneaker: joint at ankle, sole at y=-0.08, toe towards -Z.
            m.addBeveledBox(min: Vec3(-0.045, -0.085, -0.17), max: Vec3(0.045, -0.02, 0.06), bevel: 0.03)
            m.flags = 0
            m.material = .rubber
            m.color = Vec3(0.9, 0.9, 0.88)
            m.addBox(min: Vec3(-0.048, -0.095, -0.175), max: Vec3(0.048, -0.075, 0.065))
        case .boot:
            m.material = .leather
            m.addBeveledBox(min: Vec3(-0.05, -0.085, -0.18), max: Vec3(0.05, 0.0, 0.065), bevel: 0.03)
            m.addCylinder(center: Vec3(0, -0.02, 0.0), radiusBottom: 0.055, radiusTop: 0.052, height: 0.16, segments: 10)
            m.flags = 0
            m.material = .rubber
            m.color = Vec3(0.12, 0.12, 0.12)
            m.addBox(min: Vec3(-0.053, -0.1, -0.185), max: Vec3(0.053, -0.075, 0.07))
        }
        return m
    }

    /// Gear meshes in head-joint space (head/face) or chest-joint space (vests, backpacks).
    static func makeGear(_ g: GearMesh) -> MeshBuilder {
        let m = base()
        switch g {
        case .cap:
            m.addEllipsoid(center: Vec3(0, 0.155, 0.01), radii: Vec3(0.097, 0.075, 0.108), rings: 6, segments: 12)
            m.addBox(min: Vec3(-0.07, 0.155, -0.2), max: Vec3(0.07, 0.165, -0.08))
        case .beanie:
            m.material = .fabric
            m.addEllipsoid(center: Vec3(0, 0.16, 0.01), radii: Vec3(0.098, 0.095, 0.108), rings: 7, segments: 12)
            m.addCylinder(center: Vec3(0, 0.1, 0.01), radiusBottom: 0.1, radiusTop: 0.1, height: 0.04, segments: 12, capTop: false, capBottom: false)
        case .helmet:
            m.material = .camo
            m.addEllipsoid(center: Vec3(0, 0.15, 0.01), radii: Vec3(0.12, 0.11, 0.13), rings: 7, segments: 14)
            m.material = .plastic
            m.flags = 0
            m.color = Vec3(0.15, 0.15, 0.15)
            m.addCylinder(center: Vec3(0, 0.1, 0.01), radiusBottom: 0.123, radiusTop: 0.123, height: 0.02, segments: 14, capTop: false, capBottom: false)
        case .policeCap:
            m.addCylinder(center: Vec3(0, 0.16, 0.01), radiusBottom: 0.1, radiusTop: 0.115, height: 0.08, segments: 12)
            m.flags = 0
            m.material = .plastic
            m.color = Vec3(0.05, 0.05, 0.05)
            m.addBox(min: Vec3(-0.07, 0.155, -0.17), max: Vec3(0.07, 0.165, -0.08))
            m.material = .metalPainted
            m.color = Vec3(0.8, 0.7, 0.3)
            m.addBox(min: Vec3(-0.02, 0.19, -0.108), max: Vec3(0.02, 0.22, -0.1))
        case .motoHelmet:
            m.material = .plastic
            m.addEllipsoid(center: Vec3(0, 0.12, 0.0), radii: Vec3(0.13, 0.15, 0.14), rings: 8, segments: 14)
            m.flags = VertexFlag.glossy
            m.material = .glass
            m.color = Vec3(0.15, 0.17, 0.2)
            m.addEllipsoid(center: Vec3(0, 0.12, -0.06), radii: Vec3(0.1, 0.06, 0.09), rings: 5, segments: 10)
        case .bandana:
            m.addEllipsoid(center: Vec3(0, 0.06, -0.03), radii: Vec3(0.09, 0.065, 0.085), rings: 5, segments: 10)
        case .surgicalMask:
            m.addEllipsoid(center: Vec3(0, 0.075, -0.06), radii: Vec3(0.07, 0.045, 0.05), rings: 5, segments: 10)
        case .gasMask:
            m.material = .rubber
            m.addEllipsoid(center: Vec3(0, 0.095, -0.05), radii: Vec3(0.09, 0.1, 0.07), rings: 6, segments: 12)
            m.flags = 0
            m.material = .glass
            m.color = Vec3(0.2, 0.25, 0.25)
            m.addEllipsoid(center: Vec3(-0.033, 0.12, -0.105), radii: Vec3(0.025, 0.025, 0.012), rings: 4, segments: 8)
            m.addEllipsoid(center: Vec3(0.033, 0.12, -0.105), radii: Vec3(0.025, 0.025, 0.012), rings: 4, segments: 8)
            m.material = .metalPainted
            m.color = Vec3(0.25, 0.27, 0.25)
            m.withTransform(Mat4.translation(Vec3(0, 0.05, -0.1)) * Mat4.rotationX(kPi * 0.5)) {
                m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.035, radiusTop: 0.035, height: 0.07, segments: 10)
            }
        case .balaclava:
            m.addEllipsoid(center: Vec3(0, 0.1, 0.0), radii: Vec3(0.091, 0.122, 0.106), rings: 8, segments: 12)
        case .vestHunting, .vestPolice, .plateCarrier, .chestRig:
            // Chest-joint space: torso spans y 0..0.32.
            let depth: Float = g == .plateCarrier ? 0.15 : 0.13
            m.material = g == .vestHunting ? .canvas : (g == .chestRig ? .canvas : .fabric)
            m.addBeveledBox(min: Vec3(-0.17, 0.03, -depth), max: Vec3(0.17, 0.3, depth), bevel: 0.06)
            if g == .chestRig || g == .plateCarrier || g == .vestHunting {
                // Pouches.
                for x in [Float(-0.1), 0, 0.1] {
                    m.addBox(min: Vec3(x - 0.045, 0.06, -depth - 0.05), max: Vec3(x + 0.045, 0.17, -depth + 0.01))
                }
            }
            if g == .vestPolice {
                m.flags = 0
                m.material = .plastic
                m.color = Vec3(0.85, 0.85, 0.3)
                m.addBox(min: Vec3(-0.12, 0.18, -depth - 0.005), max: Vec3(0.12, 0.23, -depth + 0.01))
            }
        case .backpackSchool, .backpackHiking, .backpackMilitary:
            let w: Float, h: Float, d: Float
            switch g {
            case .backpackSchool: w = 0.15; h = 0.38; d = 0.13
            case .backpackHiking: w = 0.17; h = 0.55; d = 0.17
            default: w = 0.2; h = 0.58; d = 0.2
            }
            m.material = g == .backpackMilitary ? .camo : .canvas
            m.addBeveledBox(min: Vec3(-w, 0.32 - h, 0.12), max: Vec3(w, 0.32, 0.12 + d * 2), bevel: 0.05)
            m.addBox(min: Vec3(-w * 0.8, 0.32 - h * 0.8, 0.12 + d * 2), max: Vec3(w * 0.8, 0.32 - h * 0.35, 0.12 + d * 2 + 0.06))
            // Straps.
            m.flags = 0
            m.material = .leather
            m.color = Vec3(0.15, 0.15, 0.13)
            m.addBox(min: Vec3(-0.12, 0.0, -0.11), max: Vec3(-0.08, 0.31, 0.13))
            m.addBox(min: Vec3(0.08, 0.0, -0.11), max: Vec3(0.12, 0.31, 0.13))
            if g != .backpackSchool {
                m.material = .canvas
                m.color = Vec3(0.3, 0.3, 0.28)
                m.withTransform(Mat4.translation(Vec3(-w, 0.34, 0.12 + d)) * Mat4.rotationZ(-kPi * 0.5)) {
                    m.addCylinder(center: Vec3(0, 0, 0), radiusBottom: 0.07, radiusTop: 0.07, height: w * 2, segments: 10)
                }
            }
        }
        return m
    }
}

// MARK: - Pose & animation

enum HoldStyle {
    case none, rifle, pistol, melee, twoHandMelee, item
}

/// Procedural animation inputs for a character.
struct CharacterPose {
    var position = Vec3(0, 0, 0)
    var yaw: Float = 0
    var speed: Float = 0          // horizontal m/s
    var phase: Float = 0          // locomotion cycle phase (radians)
    var crouch: Float = 0         // 0..1
    var aim: Float = 0            // 0..1 weapon raised
    var aimPitch: Float = 0       // radians
    var airborne: Float = 0       // 0..1
    var hold: HoldStyle = .none
    var attack: Float = -1        // melee swing 0..1, <0 none
    var punchSide: Float = 1
    var reload: Float = -1        // 0..1, <0 none
    var hit: Float = 0            // hit reaction 1 -> 0
    var hitDir: Float = 1
    var death: Float = 0          // 0 alive .. 1 lying
    var deathForward: Bool = false
    var infected = false
    var lean: Float = 0
    var vault: Float = -1
    var eat: Float = -1           // consuming animation 0..1
}

struct CharacterJoints {
    var root: Mat4 = .identity
    var pelvis: Mat4 = .identity
    var chest: Mat4 = .identity
    var neck: Mat4 = .identity
    var head: Mat4 = .identity
    var shoulderL = Vec3(0, 0, 0)
    var shoulderR = Vec3(0, 0, 0)
    var upperArmL: Mat4 = .identity
    var upperArmR: Mat4 = .identity
    var forearmL: Mat4 = .identity
    var forearmR: Mat4 = .identity
    var handL: Mat4 = .identity
    var handR: Mat4 = .identity
    var thighL: Mat4 = .identity
    var thighR: Mat4 = .identity
    var shinL: Mat4 = .identity
    var shinR: Mat4 = .identity
    var footL: Mat4 = .identity
    var footR: Mat4 = .identity
    /// Points used for hit detection.
    var headCenter = Vec3(0, 0, 0)
    var chestCenter = Vec3(0, 0, 0)
    var pelvisCenter = Vec3(0, 0, 0)
    var kneeL = Vec3(0, 0, 0)
    var kneeR = Vec3(0, 0, 0)
    var ankleL = Vec3(0, 0, 0)
    var ankleR = Vec3(0, 0, 0)
    /// Weapon/item anchor (right hand grip) with forward = -Z.
    var gripTransform: Mat4 = .identity
}

enum CharacterAnimator {
    static let upperArmLen: Float = 0.27
    static let forearmLen: Float = 0.25

    /// Builds an orthonormal transform whose +Y axis points from a to b.
    static func segment(_ a: Vec3, _ b: Vec3, hint: Vec3) -> Mat4 {
        let y = vnormalize(b - a)
        var x = vcross(y, hint)
        if vlengthSq(x) < 1e-6 { x = vcross(y, Vec3(0, 0, 1)) }
        x = vnormalize(x)
        let z = vcross(x, y)
        return Mat4.basis(right: x, up: y, back: z, origin: a)
    }

    /// Analytic two-bone IK: returns elbow position.
    static func solveElbow(shoulder s: Vec3, hand h: Vec3, l1: Float, l2: Float, pole: Vec3) -> (elbow: Vec3, hand: Vec3) {
        var toH = h - s
        var d = vlength(toH)
        let maxD = (l1 + l2) * 0.999
        var hand = h
        if d > maxD {
            toH = toH / d * maxD
            hand = s + toH
            d = maxD
        }
        d = max(d, abs(l1 - l2) + 0.01)
        let dir = vnormalize(toH)
        let a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        let hgt = sqrtf(max(0, l1 * l1 - a * a))
        var bend = pole - dir * vdot(pole, dir)
        if vlengthSq(bend) < 1e-6 { bend = Vec3(0, -1, 0) }
        bend = vnormalize(bend)
        return (s + dir * a + bend * hgt, hand)
    }

    static func compute(_ p: CharacterPose, scale: Float = 1) -> CharacterJoints {
        var j = CharacterJoints()
        let moveAmt = min(p.speed / 5.5, 1)
        let walkAmp = min(p.speed / 1.6, 1) * (0.42 + moveAmt * 0.25)
        let ph = p.phase
        let crouch = p.crouch
        // Root: yaw + optional death fall rotation.
        var root = Mat4.translation(p.position) * Mat4.rotationY(p.yaw) * Mat4.scale(Vec3(repeating: scale))
        if p.death > 0 {
            let t = smoothstepf(0, 1, p.death)
            let fall = (p.deathForward ? -1 : 1) * t * kPi * 0.5
            // Pivot around the feet, then lower so the body lies on the ground.
            root = root * Mat4.translation(Vec3(0, 0.12 * t, 0)) * Mat4.rotationX(fall)
        }
        j.root = root

        // Pelvis height with bob and crouch.
        let bob = abs(sinf(ph)) * 0.035 * moveAmt
        var pelvisY: Float = 0.96 - crouch * 0.38 + bob - p.airborne * 0.05
        if p.infected { pelvisY -= 0.04 }
        var spinePitch: Float = -0.04 - moveAmt * 0.12 - crouch * 0.35
        if p.infected { spinePitch -= 0.28 }
        if p.hit > 0 { spinePitch += p.hit * 0.35 * p.hitDir }
        // Aiming leans the torso with the aim pitch.
        spinePitch += p.aimPitch * 0.45 * p.aim
        let twist = sinf(ph) * 0.12 * moveAmt * (1 - p.aim)
        let vaultLean: Float = p.vault >= 0 ? sinf(p.vault * kPi) * 0.6 : 0
        if p.vault >= 0 { pelvisY += sinf(p.vault * kPi) * 0.25 }

        let pelvis = root * Mat4.translation(Vec3(0, pelvisY, 0)) * Mat4.rotationY(twist * 0.5) * Mat4.rotationZ(sinf(ph) * 0.04 * moveAmt)
        j.pelvis = pelvis
        let chest = pelvis * Mat4.translation(Vec3(0, 0.08, 0)) * Mat4.rotationX(spinePitch - vaultLean) * Mat4.rotationY(-twist) * Mat4.rotationZ(p.lean)
        j.chest = chest
        let neck = chest * Mat4.translation(Vec3(0, 0.33, 0))
        j.neck = neck
        var headPitch = -spinePitch * 0.6 + p.aimPitch * (1 - p.aim * 0.45)
        if p.infected { headPitch = 0.25 + sinf(ph * 0.5) * 0.1 }
        if p.hit > 0 { headPitch += p.hit * 0.4 * p.hitDir }
        let head = neck * Mat4.translation(Vec3(0, 0.09, 0)) * Mat4.rotationX(clampf(headPitch, -0.9, 0.9))
        j.head = head
        j.headCenter = head.transformPoint(Vec3(0, 0.1, 0))
        j.chestCenter = chest.transformPoint(Vec3(0, 0.18, 0))
        j.pelvisCenter = pelvis.transformPoint(Vec3(0, 0, 0))

        // Legs (FK).
        func leg(_ side: Float) -> (Mat4, Mat4, Mat4, Vec3, Vec3) {
            let legPhase = ph + (side > 0 ? kPi : 0)
            var hipPitch = sinf(legPhase) * walkAmp
            var knee = max(0, sinf(legPhase + kPi * 0.5)) * walkAmp * 1.6 + 0.05
            hipPitch += crouch * 1.15
            knee += crouch * 2.0
            if p.airborne > 0 { hipPitch += p.airborne * 0.5; knee += p.airborne * 0.9 }
            if p.vault >= 0 { hipPitch += sinf(p.vault * kPi) * 1.1; knee += sinf(p.vault * kPi) * 1.4 }
            if p.infected { knee += 0.12 }
            if p.death > 0 { hipPitch *= (1 - p.death); knee = mixf(knee, 0.2, p.death) }
            let hip = pelvis * Mat4.translation(Vec3(side * 0.095, -0.03, 0))
            // Thigh points down (-Y). Build as rotation of a downward segment.
            // Positive hip pitch swings the leg forward (-Z). rotationZ(pi) makes the segment's +Y point down.
            let thigh = hip * Mat4.rotationX(hipPitch) * Mat4.rotationZ(kPi)
            let kneeM = thigh * Mat4.translation(Vec3(0, 0.43, 0)) * Mat4.rotationX(knee)
            let ankle = kneeM * Mat4.translation(Vec3(0, 0.42, 0))
            // Foot: undo accumulated rotations so the sole stays roughly level.
            let footPitch = hipPitch - knee
            let foot = ankle * Mat4.rotationZ(kPi) * Mat4.rotationX(-footPitch * 0.85)
            return (thigh, kneeM, foot, kneeM.translationPart, ankle.translationPart)
        }
        let (tl, sl, fl, kl, al) = leg(-1)
        let (tr, sr, fr, kr, ar) = leg(1)
        j.thighL = tl; j.shinL = sl; j.footL = fl; j.kneeL = kl; j.ankleL = al
        j.thighR = tr; j.shinR = sr; j.footR = fr; j.kneeR = kr; j.ankleR = ar

        // Arms (IK towards hand targets defined in chest space).
        let shL = chest.transformPoint(Vec3(-0.19, 0.28, 0))
        let shR = chest.transformPoint(Vec3(0.19, 0.28, 0))
        j.shoulderL = shL
        j.shoulderR = shR
        let fwd = vnormalize(Vec3(-root.c2.x, -root.c2.y, -root.c2.z))
        let up = vnormalize(root.axisY)
        let right = vnormalize(root.axisX)
        // Aim direction (yaw from root, pitch from aim).
        let cp = cosf(p.aimPitch), sp = sinf(p.aimPitch)
        let aimDir = vnormalize(fwd * cp + up * sp)

        var handLTarget: Vec3
        var handRTarget: Vec3
        var gripRot = Mat4.identity
        var grip = Vec3(0, 0, 0)

        // Idle / walking hand targets (arms hanging and swinging).
        let swing = sinf(ph) * walkAmp * 0.55
        let hangL = shL - up * 0.5 + fwd * (-swing * 0.6 + 0.04 + crouch * 0.15) - right * 0.04
        let hangR = shR - up * 0.5 + fwd * (swing * 0.6 + 0.04 + crouch * 0.15) + right * 0.04
        handLTarget = hangL
        handRTarget = hangR

        if p.infected && p.death <= 0 {
            // Arms reaching forward.
            let reach = 0.35 + moveAmt * 0.25
            handLTarget = shL + fwd * (0.45 + reach * 0.2) - up * (0.15 - sinf(ph * 1.3) * 0.08) - right * 0.03
            handRTarget = shR + fwd * (0.45 + reach * 0.2) - up * (0.12 + sinf(ph * 1.3) * 0.08) + right * 0.03
            if p.attack >= 0 {
                let a = sinf(p.attack * kPi)
                handLTarget = shL + fwd * (0.25 + a * 0.4) + up * (0.25 - a * 0.5)
                handRTarget = shR + fwd * (0.25 + a * 0.4) + up * (0.3 - a * 0.55)
            }
        }

        let chestFwd = vnormalize(Vec3(-chest.c2.x, -chest.c2.y, -chest.c2.z))
        switch p.hold {
        case .rifle, .pistol:
            let pistol = p.hold == .pistol
            // Lowered (ready) vs raised (aiming).
            let raise = p.aim
            let lowered = vnormalize(chestFwd * 0.7 - up * 0.7)
            let dir = vnormalize(vlerp(lowered, aimDir, raise))
            var anchor: Vec3
            if pistol {
                let mid: Vec3 = (shR + shL) * 0.5
                let fwdOff: Vec3 = aimDir * (0.05 * raise)
                let upOff: Vec3 = up * (-0.05 + raise * 0.02)
                anchor = mid + fwdOff + upOff
            } else {
                let sideOff: Vec3 = right * (-0.05 * raise)
                let upOff: Vec3 = up * (-0.04 - (1 - raise) * 0.08)
                anchor = shR + sideOff + upOff
            }
            let gripDist: Float = pistol ? 0.42 + raise * 0.08 : 0.2 + raise * 0.05
            grip = anchor + dir * gripDist + right * (pistol ? 0.0 : 0.02)
            if p.reload >= 0 {
                let r = sinf(p.reload * kPi)
                grip = grip - up * (0.12 * r) - dir * (0.08 * r)
            }
            // Orientation: weapon forward (-Z) along dir.
            let wz = -dir
            var wx = vcross(up, wz)
            if vlengthSq(wx) < 1e-6 { wx = right }
            wx = vnormalize(wx)
            var wy = vcross(wz, wx)
            if p.reload >= 0 {
                // Tilt the weapon during reloads.
                let tilt = sinf(p.reload * kPi) * 0.6
                let m = Mat4.axisAngle(wz, tilt)
                wx = m.transformDirection(wx)
                wy = m.transformDirection(wy)
            }
            gripRot = Mat4.basis(right: wx, up: wy, back: wz, origin: Vec3(0, 0, 0))
            handRTarget = grip
            if pistol {
                handLTarget = grip - right * 0.03 + up * (-0.02)
            } else {
                handLTarget = grip + dir * 0.28 - up * 0.04
            }
            if p.reload >= 0 {
                // Support hand travels to the magazine and back.
                let r = sinf(p.reload * kPi)
                handLTarget = vlerp(handLTarget, grip + dir * 0.12 - up * 0.2, r)
            }
        case .melee, .twoHandMelee, .item:
            if p.attack >= 0 {
                // Overhead to forward diagonal swing.
                let t = p.attack
                let windup = smoothstepf(0, 0.3, t)
                let strike = smoothstepf(0.3, 0.6, t)
                let recover = smoothstepf(0.6, 1, t)
                let raised = shR + up * 0.25 + right * 0.15 - fwd * 0.1
                let struck = shR + fwd * 0.55 - up * 0.25 - right * 0.15
                let rest = shR + fwd * 0.3 - up * 0.3
                var pos = vlerp(rest, raised, windup)
                pos = vlerp(pos, struck, strike)
                pos = vlerp(pos, rest, recover)
                grip = pos
                handRTarget = pos
                let swingDir = vnormalize(vlerp(vlerp(up, fwd, strike), fwd - up * 0.5, recover))
                let wz = -swingDir
                var wx = vcross(up, wz)
                if vlengthSq(wx) < 1e-6 { wx = right }
                wx = vnormalize(wx)
                gripRot = Mat4.basis(right: wx, up: vcross(wz, wx), back: wz, origin: Vec3(0, 0, 0))
                if p.hold == .twoHandMelee { handLTarget = pos - swingDir * 0.18 }
            } else {
                let ready = p.aim
                let pos = vlerp(hangR + fwd * 0.12, shR + fwd * 0.38 - up * 0.18, ready)
                grip = pos
                handRTarget = pos
                let dir = vnormalize(vlerp(fwd * 0.3 + up * 0.95, fwd + up * 0.6, ready))
                let wz = -dir
                var wx = vcross(up, wz)
                if vlengthSq(wx) < 1e-6 { wx = right }
                wx = vnormalize(wx)
                gripRot = Mat4.basis(right: wx, up: vcross(wz, wx), back: wz, origin: Vec3(0, 0, 0))
                if p.hold == .twoHandMelee { handLTarget = pos + dir * 0.25 }
                if p.hold == .item {
                    handRTarget = shR + fwd * 0.3 - up * 0.32
                    grip = handRTarget
                    gripRot = Mat4.rotationY(p.yaw)
                }
            }
            if p.eat >= 0 {
                let e = sinf(min(p.eat, 1) * kPi)
                let mouth = j.headCenter + fwd * 0.12 - up * 0.04
                handRTarget = vlerp(handRTarget, mouth, e)
                grip = handRTarget
            }
        case .none:
            if p.attack >= 0 && !p.infected {
                // Punch with alternating hands.
                let t = sinf(min(p.attack, 1) * kPi)
                let guardL = shL + fwd * 0.25 - up * 0.08 + right * 0.06
                let guardR = shR + fwd * 0.25 - up * 0.08 - right * 0.06
                if p.punchSide > 0 {
                    handRTarget = vlerp(guardR, shR + aimDir * 0.5 - right * 0.08, t)
                    handLTarget = guardL
                } else {
                    handLTarget = vlerp(guardL, shL + aimDir * 0.5 + right * 0.08, t)
                    handRTarget = guardR
                }
            } else if p.aim > 0.01 && !p.infected {
                // Fists raised.
                handLTarget = vlerp(handLTarget, shL + fwd * 0.25 - up * 0.08 + right * 0.06, p.aim)
                handRTarget = vlerp(handRTarget, shR + fwd * 0.25 - up * 0.08 - right * 0.06, p.aim)
            }
            if p.eat >= 0 {
                let e = sinf(min(p.eat, 1) * kPi)
                handRTarget = vlerp(handRTarget, j.headCenter + fwd * 0.12 - up * 0.04, e)
            }
            grip = handRTarget
            gripRot = Mat4.rotationY(p.yaw)
        }
        if p.death > 0 {
            // Arms go limp along the body.
            handLTarget = vlerp(handLTarget, chest.transformPoint(Vec3(-0.35, -0.1, 0.05)), p.death)
            handRTarget = vlerp(handRTarget, chest.transformPoint(Vec3(0.35, -0.1, 0.05)), p.death)
        }

        let poleL = -right * 0.6 - up * 0.8 - fwd * 0.3
        let poleR = right * 0.6 - up * 0.8 - fwd * 0.3
        let s = scale
        let (eL, hL) = solveElbow(shoulder: shL, hand: handLTarget, l1: upperArmLen * s, l2: forearmLen * s, pole: poleL)
        let (eR, hR) = solveElbow(shoulder: shR, hand: handRTarget, l1: upperArmLen * s, l2: forearmLen * s, pole: poleR)
        j.upperArmL = segment(shL, eL, hint: fwd) * Mat4.scale(Vec3(repeating: s))
        j.forearmL = segment(eL, hL, hint: fwd) * Mat4.scale(Vec3(repeating: s))
        j.upperArmR = segment(shR, eR, hint: fwd) * Mat4.scale(Vec3(repeating: s))
        j.forearmR = segment(eR, hR, hint: fwd) * Mat4.scale(Vec3(repeating: s))
        j.handL = segment(hL, hL + (hL - eL), hint: fwd) * Mat4.scale(Vec3(repeating: s))
        j.handR = segment(hR, hR + (hR - eR), hint: fwd) * Mat4.scale(Vec3(repeating: s))
        if p.hold == .none || p.death > 0 {
            j.gripTransform = Mat4.translation(hR) * gripRot
        } else {
            j.gripTransform = Mat4.translation(grip) * gripRot * Mat4.scale(Vec3(repeating: s))
        }
        return j
    }

    /// Emits render instances for a character.
    static func emit(_ j: CharacterJoints, _ a: Appearance, meshes cm: CharacterMeshes, scene: RenderScene,
                     hideHead: Bool = false, shadow: Bool = true, highlight: Float = 0) {
        func add(_ part: CharPart, _ m: Mat4, _ color: Vec3, _ layer: Mat, dirt: Float = 0) {
            scene.add(cm.part(part), InstanceData(model: m, tint: color, layer: Float(layer.rawValue), highlight: highlight, dirt: dirt), castsShadow: shadow)
        }
        let skin = a.skin
        let topBulky = a.top.bulky
        let td = a.top.dirt
        if !hideHead {
            add(.head, j.head, skin, .skin)
            add(.eyes, j.head, Vec3(1, 1, 1), .plastic)
            if a.head == nil || a.head == .cap || a.head == .policeCap {
                add(a.longHair ? .hairLong : .hairShort, j.head, a.hair, .hair)
            }
            if let h = a.head {
                scene.add(cm.gear(h), InstanceData(model: j.head, tint: a.headTint, layer: -1, dirt: td * 0.5), castsShadow: shadow)
            }
            if let f = a.face {
                scene.add(cm.gear(f), InstanceData(model: j.head, tint: a.faceTint, layer: -1), castsShadow: false)
            }
        }
        add(.neck, j.neck * Mat4.translation(Vec3(0, -0.02, 0)), skin, .skin)
        add(topBulky ? .chestBulky : .chest, j.chest, a.top.color, a.top.layer, dirt: td)
        add(.abdomen, j.pelvis * Mat4.translation(Vec3(0, 0.06, 0)), a.top.color, a.top.layer, dirt: td)
        add(.pelvis, j.pelvis, a.pants.color, a.pants.layer, dirt: a.pants.dirt)
        add(topBulky ? .upperArmBulky : .upperArm, j.upperArmL, a.top.color, a.top.layer, dirt: td)
        add(topBulky ? .upperArmBulky : .upperArm, j.upperArmR, a.top.color, a.top.layer, dirt: td)
        let sleeve = a.top.longSleeves
        add(sleeve ? (topBulky ? .forearmBulky : .forearm) : .forearm, j.forearmL, sleeve ? a.top.color : skin, sleeve ? a.top.layer : .skin, dirt: sleeve ? td : 0)
        add(sleeve ? (topBulky ? .forearmBulky : .forearm) : .forearm, j.forearmR, sleeve ? a.top.color : skin, sleeve ? a.top.layer : .skin, dirt: sleeve ? td : 0)
        add(.hand, j.handL, skin, .skin)
        add(.hand, j.handR, skin, .skin)
        add(.thigh, j.thighL, a.pants.color, a.pants.layer, dirt: a.pants.dirt)
        add(.thigh, j.thighR, a.pants.color, a.pants.layer, dirt: a.pants.dirt)
        add(.shin, j.shinL, a.pants.color, a.pants.layer, dirt: a.pants.dirt)
        add(.shin, j.shinR, a.pants.color, a.pants.layer, dirt: a.pants.dirt)
        add(a.bootsStyle ? .boot : .foot, j.footL, a.shoes.color, a.shoes.layer)
        add(a.bootsStyle ? .boot : .foot, j.footR, a.shoes.color, a.shoes.layer)
        if let v = a.vest {
            scene.add(cm.gear(v), InstanceData(model: j.chest, tint: a.vestTint, layer: -1, dirt: td * 0.5), castsShadow: shadow)
        }
        if let b = a.backpack {
            scene.add(cm.gear(b), InstanceData(model: j.chest, tint: a.backpackTint, layer: -1, dirt: td * 0.5), castsShadow: shadow)
        }
    }
}
