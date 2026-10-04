//
//  Random.swift
//  Ashvale
//
//  Deterministic random number generation and hashing used by world generation,
//  loot spawning and AI.
//

import Foundation

/// SplitMix64 based deterministic generator.
struct RNG: RandomNumberGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform float in [0, 1).
    mutating func float() -> Float {
        return Float(next() >> 40) / Float(1 << 24)
    }

    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * float() }

    mutating func int(_ lo: Int, _ hi: Int) -> Int {
        if hi <= lo { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }

    mutating func chance(_ p: Float) -> Bool { float() < p }

    mutating func pick<T>(_ array: [T]) -> T { array[int(0, array.count - 1)] }

    /// Picks an index using relative weights.
    mutating func weightedIndex(_ weights: [Float]) -> Int {
        let total = weights.reduce(0, +)
        if total <= 0 { return 0 }
        var r = float() * total
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return i }
        }
        return weights.count - 1
    }

    mutating func unitDisk() -> Vec2 {
        let a = float() * kTwoPi
        let r = sqrtf(float())
        return Vec2(cosf(a) * r, sinf(a) * r)
    }
}

/// Integer hash helpers for stateless per-cell randomness.
@inline(__always) func hash32(_ x: UInt32) -> UInt32 {
    var h = x
    h ^= h >> 16; h = h &* 0x7feb352d
    h ^= h >> 15; h = h &* 0x846ca68b
    h ^= h >> 16
    return h
}

@inline(__always) func hash2i(_ x: Int32, _ y: Int32, _ seed: UInt32 = 0) -> UInt32 {
    return hash32(UInt32(bitPattern: x) &* 0x8da6b343 ^ UInt32(bitPattern: y) &* 0xd8163841 ^ seed &* 0xcb1ab31f)
}

@inline(__always) func hashFloat(_ x: Int32, _ y: Int32, _ seed: UInt32 = 0) -> Float {
    return Float(hash2i(x, y, seed) >> 8) / Float(1 << 24)
}

/// Stable string hash (FNV-1a) used to derive seeds from identifiers.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x100000001b3
    }
    return h
}
