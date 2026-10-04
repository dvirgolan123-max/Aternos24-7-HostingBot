//
//  Player.swift
//  Ashvale
//
//  The survivor controlled by the user: movement body, facing, appearance
//  and animation state.
//

import Foundation

final class Player {
    let body: MovementBody
    var yaw: Float
    var appearance = Appearance()
    var pose = CharacterPose()
    var joints = CharacterJoints()
    var alive = true
    var deathTimer: Float = 0
    var sprinting = false
    var timeAlive: Float = 0
    var noiseLevel: Float = 0
    /// Recently made sounds (for AI hearing): radius in meters.
    var lastNoiseRadius: Float = 0
    var hitFlash: Float = 0
    var vaultCooldown: Float = 0

    init(position: Vec3, yaw: Float) {
        body = MovementBody(position: position)
        self.yaw = yaw
        pose.position = position
        pose.yaw = yaw
    }

    var position: Vec3 {
        get { body.position }
        set { body.position = newValue }
    }

    var eyePosition: Vec3 { body.position + Vec3(0, body.eyeHeight, 0) }

    /// Default civilian look for a fresh spawn (basic clothing only).
    static func freshAppearance(_ rng: inout RNG) -> Appearance {
        var a = Appearance()
        a.skin = rng.pick([Vec3(0.88, 0.7, 0.58), Vec3(0.78, 0.6, 0.48), Vec3(0.62, 0.45, 0.34), Vec3(0.92, 0.76, 0.64)])
        a.hair = rng.pick([Vec3(0.18, 0.12, 0.08), Vec3(0.35, 0.25, 0.15), Vec3(0.08, 0.07, 0.06), Vec3(0.55, 0.42, 0.25)])
        a.longHair = rng.chance(0.3)
        return a
    }
}
