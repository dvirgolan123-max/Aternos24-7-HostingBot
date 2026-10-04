//
//  Math.swift
//  Ashvale
//
//  Self-contained vector / matrix math built on the Swift standard library SIMD
//  types. Matrices are column-major and memory compatible with Metal's float4x4.
//  World space is right-handed: +Y up, -Z is "north"/forward at yaw 0.
//

import Foundation

typealias Vec2 = SIMD2<Float>
typealias Vec3 = SIMD3<Float>
typealias Vec4 = SIMD4<Float>

let kPi: Float = 3.14159265358979
let kTwoPi: Float = 6.28318530717959
let kDegToRad: Float = 0.0174532925199

// MARK: - Scalar helpers

@inline(__always) func clampf(_ x: Float, _ lo: Float, _ hi: Float) -> Float { x < lo ? lo : (x > hi ? hi : x) }
@inline(__always) func saturatef(_ x: Float) -> Float { x < 0 ? 0 : (x > 1 ? 1 : x) }
@inline(__always) func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func smoothstepf(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = saturatef((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}
@inline(__always) func signf(_ x: Float) -> Float { x > 0 ? 1 : (x < 0 ? -1 : 0) }

/// Frame-rate independent exponential approach.
@inline(__always) func damp(_ current: Float, _ target: Float, _ rate: Float, _ dt: Float) -> Float {
    return mixf(current, target, 1 - expf(-rate * dt))
}

/// Wraps an angle to [-pi, pi].
@inline(__always) func wrapAngle(_ a: Float) -> Float {
    var x = fmodf(a + kPi, kTwoPi)
    if x < 0 { x += kTwoPi }
    return x - kPi
}

/// Exponential approach for angles taking the short way round.
@inline(__always) func dampAngle(_ current: Float, _ target: Float, _ rate: Float, _ dt: Float) -> Float {
    let d = wrapAngle(target - current)
    return current + d * (1 - expf(-rate * dt))
}

@inline(__always) func moveTowards(_ current: Float, _ target: Float, _ maxDelta: Float) -> Float {
    if abs(target - current) <= maxDelta { return target }
    return current + signf(target - current) * maxDelta
}

// MARK: - Vector helpers

@inline(__always) func vdot(_ a: Vec3, _ b: Vec3) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
@inline(__always) func vdot2(_ a: Vec2, _ b: Vec2) -> Float { a.x * b.x + a.y * b.y }
@inline(__always) func vcross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
@inline(__always) func vlength(_ a: Vec3) -> Float { sqrtf(vdot(a, a)) }
@inline(__always) func vlength2(_ a: Vec2) -> Float { sqrtf(a.x * a.x + a.y * a.y) }
@inline(__always) func vlengthSq(_ a: Vec3) -> Float { vdot(a, a) }
@inline(__always) func vnormalize(_ a: Vec3) -> Vec3 {
    let l = vlength(a)
    return l > 1e-8 ? a / l : Vec3(0, 1, 0)
}
@inline(__always) func vnormalize2(_ a: Vec2) -> Vec2 {
    let l = vlength2(a)
    return l > 1e-8 ? a / l : Vec2(0, 0)
}
@inline(__always) func vlerp(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 { a + (b - a) * t }
@inline(__always) func vdistance(_ a: Vec3, _ b: Vec3) -> Float { vlength(a - b) }
@inline(__always) func vdistanceXZ(_ a: Vec3, _ b: Vec3) -> Float {
    let dx = a.x - b.x, dz = a.z - b.z
    return sqrtf(dx * dx + dz * dz)
}
@inline(__always) func xz(_ v: Vec3) -> Vec2 { Vec2(v.x, v.z) }

/// Forward direction for a yaw/pitch pair (yaw 0 looks down -Z, positive yaw turns left).
@inline(__always) func directionFrom(yaw: Float, pitch: Float) -> Vec3 {
    let cp = cosf(pitch)
    return Vec3(-sinf(yaw) * cp, sinf(pitch), -cosf(yaw) * cp)
}
@inline(__always) func flatForward(yaw: Float) -> Vec3 { Vec3(-sinf(yaw), 0, -cosf(yaw)) }
@inline(__always) func flatRight(yaw: Float) -> Vec3 { Vec3(cosf(yaw), 0, -sinf(yaw)) }
/// Yaw that faces along the XZ direction (dx, dz).
@inline(__always) func yawFromDirection(_ dx: Float, _ dz: Float) -> Float { atan2f(-dx, -dz) }

// MARK: - 4x4 matrix

struct Mat4: Equatable {
    var c0: Vec4
    var c1: Vec4
    var c2: Vec4
    var c3: Vec4

    init(_ c0: Vec4, _ c1: Vec4, _ c2: Vec4, _ c3: Vec4) {
        self.c0 = c0; self.c1 = c1; self.c2 = c2; self.c3 = c3
    }

    static let identity = Mat4(Vec4(1, 0, 0, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1))

    static func translation(_ t: Vec3) -> Mat4 {
        Mat4(Vec4(1, 0, 0, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 1, 0), Vec4(t.x, t.y, t.z, 1))
    }

    static func scale(_ s: Vec3) -> Mat4 {
        Mat4(Vec4(s.x, 0, 0, 0), Vec4(0, s.y, 0, 0), Vec4(0, 0, s.z, 0), Vec4(0, 0, 0, 1))
    }

    static func rotationX(_ a: Float) -> Mat4 {
        let c = cosf(a), s = sinf(a)
        return Mat4(Vec4(1, 0, 0, 0), Vec4(0, c, s, 0), Vec4(0, -s, c, 0), Vec4(0, 0, 0, 1))
    }

    static func rotationY(_ a: Float) -> Mat4 {
        let c = cosf(a), s = sinf(a)
        return Mat4(Vec4(c, 0, -s, 0), Vec4(0, 1, 0, 0), Vec4(s, 0, c, 0), Vec4(0, 0, 0, 1))
    }

    static func rotationZ(_ a: Float) -> Mat4 {
        let c = cosf(a), s = sinf(a)
        return Mat4(Vec4(c, s, 0, 0), Vec4(-s, c, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1))
    }

    /// Rotation by yaw (Y), then pitch (X), then roll (Z) applied in local space.
    static func rotationYXZ(yaw: Float, pitch: Float, roll: Float) -> Mat4 {
        return rotationY(yaw) * rotationX(pitch) * rotationZ(roll)
    }

    static func axisAngle(_ axis: Vec3, _ angle: Float) -> Mat4 {
        let a = vnormalize(axis)
        let c = cosf(angle), s = sinf(angle), t = 1 - c
        let x = a.x, y = a.y, z = a.z
        return Mat4(
            Vec4(t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0),
            Vec4(t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0),
            Vec4(t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0),
            Vec4(0, 0, 0, 1))
    }

    /// Right-handed perspective projection with reversed, infinite depth (near -> 1, infinity -> 0).
    static func perspectiveReverseZ(fovY: Float, aspect: Float, near: Float) -> Mat4 {
        let ys = 1 / tanf(fovY * 0.5)
        let xs = ys / aspect
        return Mat4(Vec4(xs, 0, 0, 0), Vec4(0, ys, 0, 0), Vec4(0, 0, 0, -1), Vec4(0, 0, near, 0))
    }

    /// Right-handed perspective with standard [0,1] depth.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> Mat4 {
        let ys = 1 / tanf(fovY * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return Mat4(Vec4(xs, 0, 0, 0), Vec4(0, ys, 0, 0), Vec4(0, 0, zs, -1), Vec4(0, 0, zs * near, 0))
    }

    /// Right-handed orthographic projection with [0,1] depth.
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> Mat4 {
        let rl = 1 / (right - left), tb = 1 / (top - bottom), nf = 1 / (near - far)
        return Mat4(
            Vec4(2 * rl, 0, 0, 0),
            Vec4(0, 2 * tb, 0, 0),
            Vec4(0, 0, nf, 0),
            Vec4(-(right + left) * rl, -(top + bottom) * tb, near * nf, 1))
    }

    static func lookAt(eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
        let f = vnormalize(target - eye)
        var s = vcross(f, up)
        if vlengthSq(s) < 1e-10 { s = vcross(f, Vec3(0, 0, 1)) }
        s = vnormalize(s)
        let u = vcross(s, f)
        return Mat4(
            Vec4(s.x, u.x, -f.x, 0),
            Vec4(s.y, u.y, -f.y, 0),
            Vec4(s.z, u.z, -f.z, 0),
            Vec4(-vdot(s, eye), -vdot(u, eye), vdot(f, eye), 1))
    }

    /// Builds a rigid transform with the given basis (columns) and origin.
    static func basis(right: Vec3, up: Vec3, back: Vec3, origin: Vec3) -> Mat4 {
        Mat4(Vec4(right.x, right.y, right.z, 0), Vec4(up.x, up.y, up.z, 0),
             Vec4(back.x, back.y, back.z, 0), Vec4(origin.x, origin.y, origin.z, 1))
    }

    static func * (a: Mat4, b: Mat4) -> Mat4 {
        return Mat4(a.mulVec(b.c0), a.mulVec(b.c1), a.mulVec(b.c2), a.mulVec(b.c3))
    }

    @inline(__always) func mulVec(_ v: Vec4) -> Vec4 {
        return c0 * v.x + c1 * v.y + c2 * v.z + c3 * v.w
    }

    @inline(__always) func transformPoint(_ p: Vec3) -> Vec3 {
        let r = c0 * p.x + c1 * p.y + c2 * p.z + c3
        return Vec3(r.x, r.y, r.z)
    }

    @inline(__always) func transformDirection(_ d: Vec3) -> Vec3 {
        let r = c0 * d.x + c1 * d.y + c2 * d.z
        return Vec3(r.x, r.y, r.z)
    }

    var translationPart: Vec3 { Vec3(c3.x, c3.y, c3.z) }
    var axisX: Vec3 { Vec3(c0.x, c0.y, c0.z) }
    var axisY: Vec3 { Vec3(c1.x, c1.y, c1.z) }
    var axisZ: Vec3 { Vec3(c2.x, c2.y, c2.z) }

    var transposed: Mat4 {
        Mat4(Vec4(c0.x, c1.x, c2.x, c3.x), Vec4(c0.y, c1.y, c2.y, c3.y),
             Vec4(c0.z, c1.z, c2.z, c3.z), Vec4(c0.w, c1.w, c2.w, c3.w))
    }

    /// General 4x4 inverse (cofactor expansion).
    var inverse: Mat4 {
        let m00 = c0.x, m01 = c0.y, m02 = c0.z, m03 = c0.w
        let m10 = c1.x, m11 = c1.y, m12 = c1.z, m13 = c1.w
        let m20 = c2.x, m21 = c2.y, m22 = c2.z, m23 = c2.w
        let m30 = c3.x, m31 = c3.y, m32 = c3.z, m33 = c3.w

        let b00 = m00 * m11 - m01 * m10
        let b01 = m00 * m12 - m02 * m10
        let b02 = m00 * m13 - m03 * m10
        let b03 = m01 * m12 - m02 * m11
        let b04 = m01 * m13 - m03 * m11
        let b05 = m02 * m13 - m03 * m12
        let b06 = m20 * m31 - m21 * m30
        let b07 = m20 * m32 - m22 * m30
        let b08 = m20 * m33 - m23 * m30
        let b09 = m21 * m32 - m22 * m31
        let b10 = m21 * m33 - m23 * m31
        let b11 = m22 * m33 - m23 * m32

        let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
        if abs(det) < 1e-12 { return .identity }
        let inv = 1 / det

        return Mat4(
            Vec4((m11 * b11 - m12 * b10 + m13 * b09) * inv,
                 (m02 * b10 - m01 * b11 - m03 * b09) * inv,
                 (m31 * b05 - m32 * b04 + m33 * b03) * inv,
                 (m22 * b04 - m21 * b05 - m23 * b03) * inv),
            Vec4((m12 * b08 - m10 * b11 - m13 * b07) * inv,
                 (m00 * b11 - m02 * b08 + m03 * b07) * inv,
                 (m32 * b02 - m30 * b05 - m33 * b01) * inv,
                 (m20 * b05 - m22 * b02 + m23 * b01) * inv),
            Vec4((m10 * b10 - m11 * b08 + m13 * b06) * inv,
                 (m01 * b08 - m00 * b10 - m03 * b06) * inv,
                 (m30 * b04 - m31 * b02 + m33 * b00) * inv,
                 (m21 * b02 - m20 * b04 - m23 * b00) * inv),
            Vec4((m11 * b07 - m10 * b09 - m12 * b06) * inv,
                 (m00 * b09 - m01 * b07 + m02 * b06) * inv,
                 (m31 * b01 - m30 * b03 - m32 * b00) * inv,
                 (m20 * b03 - m21 * b01 + m22 * b00) * inv))
    }
}

// MARK: - Frustum

struct Frustum {
    /// Planes as (normal.xyz, d) with normal pointing inwards: dot(n, p) + d >= 0 is inside.
    var planes: [Vec4] = []

    init(viewProjection m: Mat4) {
        let r0 = Vec4(m.c0.x, m.c1.x, m.c2.x, m.c3.x)
        let r1 = Vec4(m.c0.y, m.c1.y, m.c2.y, m.c3.y)
        let r2 = Vec4(m.c0.z, m.c1.z, m.c2.z, m.c3.z)
        let r3 = Vec4(m.c0.w, m.c1.w, m.c2.w, m.c3.w)
        // Left, right, bottom, top, and the z >= 0 plane (near for standard, far for reverse-Z).
        var ps = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2]
        for i in 0..<ps.count {
            let n = Vec3(ps[i].x, ps[i].y, ps[i].z)
            let l = vlength(n)
            if l > 1e-8 { ps[i] /= l }
        }
        planes = ps
    }

    @inline(__always) func containsSphere(_ c: Vec3, _ r: Float) -> Bool {
        for p in planes {
            if p.x * c.x + p.y * c.y + p.z * c.z + p.w < -r { return false }
        }
        return true
    }

    func intersectsBox(min bmin: Vec3, max bmax: Vec3) -> Bool {
        for p in planes {
            // Positive vertex test.
            let vx = p.x >= 0 ? bmax.x : bmin.x
            let vy = p.y >= 0 ? bmax.y : bmin.y
            let vz = p.z >= 0 ? bmax.z : bmin.z
            if p.x * vx + p.y * vy + p.z * vz + p.w < 0 { return false }
        }
        return true
    }
}

// MARK: - Colors

struct RGBA8 {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ c: Vec3, a: Float = 1) {
        r = UInt8(clampf(c.x, 0, 1) * 255 + 0.5)
        g = UInt8(clampf(c.y, 0, 1) * 255 + 0.5)
        b = UInt8(clampf(c.z, 0, 1) * 255 + 0.5)
        self.a = UInt8(clampf(a, 0, 1) * 255 + 0.5)
    }
    static let white = RGBA8(255, 255, 255, 255)
}

/// Convenience: hex color (0xRRGGBB) to linear-ish Vec3 in 0...1.
@inline(__always) func rgb(_ hex: UInt32) -> Vec3 {
    Vec3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
}
