//
//  MeshRegistry.swift
//  Ashvale
//
//  Collects every static mesh the game needs (buildings, props, trees, items,
//  weapons, characters). The renderer uploads all of them into one shared
//  GPU buffer and draws them instanced.
//

import Foundation

struct MeshID: Hashable {
    let raw: Int32
    static let none = MeshID(raw: -1)
    var isValid: Bool { raw >= 0 }
}

final class MeshRegistry {
    struct Entry {
        var name: String
        var vertices: [Vertex]
        var indices: [UInt32]
        var bounds: AABB
    }

    private(set) var entries: [Entry] = []
    private var byName: [String: MeshID] = [:]
    private let lock = NSLock()
    /// Incremented whenever new meshes are added after the initial upload.
    private(set) var generation: Int = 0

    @discardableResult
    func add(_ name: String, _ builder: MeshBuilder) -> MeshID {
        lock.lock()
        defer { lock.unlock() }
        if let existing = byName[name] { return existing }
        let id = MeshID(raw: Int32(entries.count))
        var bounds = builder.bounds
        if !bounds.isValid { bounds = AABB(min: Vec3(0, 0, 0), max: Vec3(0, 0, 0)) }
        entries.append(Entry(name: name, vertices: builder.vertices, indices: builder.indices, bounds: bounds))
        byName[name] = id
        generation += 1
        return id
    }

    func id(named name: String) -> MeshID {
        lock.lock()
        defer { lock.unlock() }
        return byName[name] ?? .none
    }

    func bounds(_ id: MeshID) -> AABB {
        guard id.isValid && Int(id.raw) < entries.count else { return AABB(min: Vec3(0, 0, 0), max: Vec3(0, 0, 0)) }
        return entries[Int(id.raw)].bounds
    }

    var count: Int { entries.count }

    func indexCount(_ id: MeshID) -> Int {
        guard id.isValid && Int(id.raw) < entries.count else { return 0 }
        return entries[Int(id.raw)].indices.count
    }

    /// Frees CPU copies once uploaded (bounds and counts are kept).
    func releaseCPUData(upTo count: Int) {
        lock.lock()
        defer { lock.unlock() }
        for i in 0..<min(count, entries.count) {
            entries[i].vertices = []
            entries[i].indices = []
        }
    }

    var totalTriangles: Int { entries.reduce(0) { $0 + $1.indices.count / 3 } }
}
