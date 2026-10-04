//
//  Geometry.swift
//  Ashvale
//
//  Bounding volumes, rays and intersection routines.
//

import Foundation

struct AABB {
    var min: Vec3
    var max: Vec3

    init(min: Vec3, max: Vec3) { self.min = min; self.max = max }
    init(center: Vec3, halfExtents: Vec3) { min = center - halfExtents; max = center + halfExtents }

    static let empty = AABB(min: Vec3(repeating: .greatestFiniteMagnitude), max: Vec3(repeating: -.greatestFiniteMagnitude))

    var center: Vec3 { (min + max) * 0.5 }
    var size: Vec3 { max - min }
    var halfExtents: Vec3 { (max - min) * 0.5 }
    var isValid: Bool { min.x <= max.x && min.y <= max.y && min.z <= max.z }
    var radius: Float { vlength(halfExtents) }

    mutating func expand(_ p: Vec3) {
        min = Vec3(Swift.min(min.x, p.x), Swift.min(min.y, p.y), Swift.min(min.z, p.z))
        max = Vec3(Swift.max(max.x, p.x), Swift.max(max.y, p.y), Swift.max(max.z, p.z))
    }

    mutating func expand(_ b: AABB) {
        if !b.isValid { return }
        expand(b.min); expand(b.max)
    }

    func expanded(by r: Float) -> AABB { AABB(min: min - Vec3(repeating: r), max: max + Vec3(repeating: r)) }

    @inline(__always) func contains(_ p: Vec3) -> Bool {
        p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y && p.z >= min.z && p.z <= max.z
    }

    @inline(__always) func intersects(_ b: AABB) -> Bool {
        min.x <= b.max.x && max.x >= b.min.x && min.y <= b.max.y && max.y >= b.min.y && min.z <= b.max.z && max.z >= b.min.z
    }

    /// Transforms the box by a rigid matrix and returns the enclosing AABB.
    func transformed(_ m: Mat4) -> AABB {
        var out = AABB.empty
        for i in 0..<8 {
            let p = Vec3(i & 1 == 0 ? min.x : max.x, i & 2 == 0 ? min.y : max.y, i & 4 == 0 ? min.z : max.z)
            out.expand(m.transformPoint(p))
        }
        return out
    }

    /// Slab test. Returns entry distance or nil.
    @inline(__always) func rayIntersect(origin o: Vec3, invDir: Vec3, maxDist: Float) -> Float? {
        let t1 = (min - o) * invDir
        let t2 = (max - o) * invDir
        let tminV = pointwiseMin(t1, t2)
        let tmaxV = pointwiseMax(t1, t2)
        let tmin = Swift.max(Swift.max(tminV.x, tminV.y), Swift.max(tminV.z, 0))
        let tmax = Swift.min(Swift.min(tmaxV.x, tmaxV.y), Swift.min(tmaxV.z, maxDist))
        return tmin <= tmax ? tmin : nil
    }

    /// Returns the outward normal of the face hit at point p.
    func faceNormal(at p: Vec3) -> Vec3 {
        let c = center, h = halfExtents
        let d = (p - c) / Vec3(Swift.max(h.x, 1e-4), Swift.max(h.y, 1e-4), Swift.max(h.z, 1e-4))
        let ax = abs(d.x), ay = abs(d.y), az = abs(d.z)
        if ax >= ay && ax >= az { return Vec3(signf(d.x), 0, 0) }
        if ay >= az { return Vec3(0, signf(d.y), 0) }
        return Vec3(0, 0, signf(d.z))
    }
}

struct Ray {
    var origin: Vec3
    var direction: Vec3
    var invDir: Vec3

    init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction
        invDir = Vec3(1 / (abs(direction.x) > 1e-9 ? direction.x : 1e-9),
                      1 / (abs(direction.y) > 1e-9 ? direction.y : 1e-9),
                      1 / (abs(direction.z) > 1e-9 ? direction.z : 1e-9))
    }

    func at(_ t: Float) -> Vec3 { origin + direction * t }
}

/// Ray vs sphere; returns nearest positive t.
func raySphere(_ ray: Ray, center: Vec3, radius: Float, maxDist: Float) -> Float? {
    let oc = ray.origin - center
    let b = vdot(oc, ray.direction)
    let c = vdot(oc, oc) - radius * radius
    let disc = b * b - c
    if disc < 0 { return nil }
    let s = sqrtf(disc)
    var t = -b - s
    if t < 0 { t = -b + s }
    if t < 0 || t > maxDist { return nil }
    return t
}

/// Ray vs vertical-axis capsule (segment from a to b with radius r). Returns nearest t.
func rayCapsule(_ ray: Ray, a: Vec3, b: Vec3, radius: Float, maxDist: Float) -> Float? {
    // Approximate with sampled spheres plus an exact infinite-cylinder test along the axis.
    let ba = b - a
    let oa = ray.origin - a
    let baba = vdot(ba, ba)
    let bard = vdot(ba, ray.direction)
    let baoa = vdot(ba, oa)
    let rdoa = vdot(ray.direction, oa)
    let oaoa = vdot(oa, oa)
    let aa = baba - bard * bard
    var bb = baba * rdoa - baoa * bard
    var cc = baba * oaoa - baoa * baoa - radius * radius * baba
    var h = bb * bb - aa * cc
    if h >= 0 && aa > 1e-8 {
        let t = (-bb - sqrtf(h)) / aa
        let y = baoa + t * bard
        if y > 0 && y < baba && t >= 0 && t <= maxDist { return t }
        // Caps
        let oc = y <= 0 ? oa : ray.origin - b
        bb = vdot(ray.direction, oc)
        cc = vdot(oc, oc) - radius * radius
        h = bb * bb - cc
        if h > 0 {
            let t2 = -bb - sqrtf(h)
            if t2 >= 0 && t2 <= maxDist { return t2 }
        }
        return nil
    }
    // Parallel case: fall back to spheres at ends.
    if let t = raySphere(ray, center: a, radius: radius, maxDist: maxDist) { return t }
    return raySphere(ray, center: b, radius: radius, maxDist: maxDist)
}

/// Closest point on segment ab to p.
@inline(__always) func closestPointOnSegment(_ p: Vec3, _ a: Vec3, _ b: Vec3) -> Vec3 {
    let ab = b - a
    let t = saturatef(vdot(p - a, ab) / Swift.max(vdot(ab, ab), 1e-8))
    return a + ab * t
}

/// Distance from point to 2D segment.
@inline(__always) func distancePointSegment2D(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> (dist: Float, t: Float) {
    let ab = b - a
    let t = saturatef(vdot2(p - a, ab) / Swift.max(vdot2(ab, ab), 1e-8))
    let c = a + ab * t
    return (vlength2(p - c), t)
}
