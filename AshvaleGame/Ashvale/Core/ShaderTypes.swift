//
//  ShaderTypes.swift
//  Ashvale
//
//  CPU mirrors of the structures declared in Shaders.metal. Every member is
//  16-byte aligned (Vec4 / Mat4) so the layouts match exactly.
//

import Foundation

struct FrameUniforms {
    var viewProj: Mat4 = .identity
    var view: Mat4 = .identity
    var invViewProj: Mat4 = .identity
    var shadowViewProj: Mat4 = .identity
    var viewModelProj: Mat4 = .identity
    /// xyz camera position, w = time (seconds).
    var cameraPos = Vec4(0, 0, 0, 0)
    /// xyz direction towards the sun (or moon at night), w = direct light intensity.
    var sunDir = Vec4(0, 1, 0, 1)
    var sunColor = Vec4(1, 0.95, 0.85, 1)
    var skyAmbient = Vec4(0.4, 0.45, 0.55, 1)
    var groundAmbient = Vec4(0.25, 0.22, 0.18, 1)
    var skyZenith = Vec4(0.25, 0.45, 0.8, 1)
    var skyHorizon = Vec4(0.7, 0.78, 0.88, 1)
    /// rgb fog color bias, w = fog density.
    var fogColor = Vec4(0.7, 0.75, 0.8, 0.0015)
    /// x = height falloff, y = rain wetness, z = night factor (0 day .. 1 night), w = cloud coverage.
    var fogParams = Vec4(0.02, 0, 0, 0.3)
    /// xyz position, w = enabled (0/1).
    var flashlightPos = Vec4(0, 0, 0, 0)
    /// xyz direction, w = cos(cone angle).
    var flashlightDir = Vec4(0, 0, -1, 0.9)
    /// xyz position, w = intensity (muzzle flash / fire light).
    var pointLight = Vec4(0, 0, 0, 0)
    /// x = width, y = height, z = shadow map texel size, w = shadow distance.
    var screen = Vec4(1, 1, 1.0 / 2048, 100)
    /// x = saturation, y = vignette, z = damage flash, w = exposure.
    var grade = Vec4(1, 0.3, 0, 1)
    /// xy = wind direction, z = wind strength, w = rain intensity.
    var wind = Vec4(1, 0, 0.3, 0)
    /// xyz = moon direction, w = star visibility.
    var moonDir = Vec4(0, 1, 0, 0)
}

struct InstanceData {
    var model: Mat4
    /// rgb tint (for tintable vertices), a = texture layer override (< 0 = none).
    var tint: Vec4
    /// x = wind sway, y = wetness, z = highlight, w = darkness/dirt.
    var params: Vec4

    init(model: Mat4, tint: Vec3 = Vec3(1, 1, 1), layer: Float = -1, sway: Float = 0, highlight: Float = 0, dirt: Float = 0) {
        self.model = model
        self.tint = Vec4(tint.x, tint.y, tint.z, layer)
        self.params = Vec4(sway, 0, highlight, dirt)
    }
}

struct ParticleInstance {
    /// xyz position, w = size.
    var posSize: Vec4
    /// rgba (premultiplied in shader).
    var color: Vec4
    /// xyz velocity (for stretched streaks), w = kind (0 soft, 1 streak, 2 flash, 3 smoke).
    var velKind: Vec4
}
