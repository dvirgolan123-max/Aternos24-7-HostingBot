//
//  GPUResources.swift
//  Ashvale
//
//  Shared GPU mesh storage and background terrain chunk streaming.
//

import Foundation
import Metal

/// All registry meshes packed into one vertex buffer and one index buffer.
final class GPUMeshLibrary {
    struct Range {
        var indexOffset: Int
        var indexCount: Int
        var bounds: AABB
    }

    private(set) var vertexBuffer: MTLBuffer?
    private(set) var indexBuffer: MTLBuffer?
    private(set) var ranges: [Range] = []
    private(set) var uploadedGeneration = -1
    private(set) var uploadedCount = 0

    func upload(device: MTLDevice, registry: MeshRegistry) {
        let entries = registry.entries
        var totalV = 0, totalI = 0
        for e in entries { totalV += e.vertices.count; totalI += e.indices.count }
        guard totalV > 0, totalI > 0 else { return }
        var verts = [Vertex]()
        verts.reserveCapacity(totalV)
        var inds = [UInt32]()
        inds.reserveCapacity(totalI)
        var newRanges: [Range] = []
        for e in entries {
            let base = UInt32(verts.count)
            let offset = inds.count
            verts.append(contentsOf: e.vertices)
            for i in e.indices { inds.append(i + base) }
            newRanges.append(Range(indexOffset: offset, indexCount: e.indices.count, bounds: e.bounds))
        }
        let vb = verts.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        let ib = inds.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        vb?.label = "MeshLibrary.vertices"
        ib?.label = "MeshLibrary.indices"
        vertexBuffer = vb
        indexBuffer = ib
        ranges = newRanges
        uploadedGeneration = registry.generation
        uploadedCount = entries.count
    }

    func range(_ id: MeshID) -> Range? {
        let i = Int(id.raw)
        return i >= 0 && i < ranges.count ? ranges[i] : nil
    }
}

/// Builds terrain chunk meshes on background threads and keeps GPU buffers for nearby chunks.
final class ChunkStreamer {
    struct ChunkGPU {
        var vertexBuffer: MTLBuffer
        var indexBuffer: MTLBuffer
        var indexCount: Int
        var bounds: AABB
        var lastUsed: Int
    }

    private let device: MTLDevice
    private weak var world: World?
    private var chunks: [Int: ChunkGPU] = [:]   // key = chunkIndex * 2 + lod
    private var pending = Set<Int>()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ashvale.chunks", qos: .userInitiated, attributes: .concurrent)
    private var inFlight = 0
    private let maxInFlight = 3
    var frame = 0

    init(device: MTLDevice, world: World) {
        self.device = device
        self.world = world
    }

    @inline(__always) static func key(_ cx: Int, _ cz: Int, _ lod: Int) -> Int { (cz * World.chunksPerSide + cx) * 2 + lod }

    func get(_ cx: Int, _ cz: Int, _ lod: Int) -> ChunkGPU? {
        let k = ChunkStreamer.key(cx, cz, lod)
        lock.lock()
        defer { lock.unlock() }
        guard var c = chunks[k] else { return nil }
        c.lastUsed = frame
        chunks[k] = c
        return c
    }

    func request(_ cx: Int, _ cz: Int, _ lod: Int, priority: Bool = false) {
        let k = ChunkStreamer.key(cx, cz, lod)
        lock.lock()
        if chunks[k] != nil || pending.contains(k) || (!priority && inFlight >= maxInFlight) {
            lock.unlock()
            return
        }
        pending.insert(k)
        inFlight += 1
        lock.unlock()
        queue.async { [weak self] in
            self?.buildNow(cx, cz, lod, key: k)
        }
    }

    /// Synchronously builds a chunk (used while the loading screen is visible).
    func buildBlocking(_ cx: Int, _ cz: Int, _ lod: Int) {
        let k = ChunkStreamer.key(cx, cz, lod)
        lock.lock()
        let exists = chunks[k] != nil
        lock.unlock()
        if exists { return }
        lock.lock(); inFlight += 1; pending.insert(k); lock.unlock()
        buildNow(cx, cz, lod, key: k)
    }

    private func buildNow(_ cx: Int, _ cz: Int, _ lod: Int, key k: Int) {
        guard let world = world else { return }
        let mb = ChunkMesher.build(world: world, cx: cx, cz: cz, lod: lod)
        var gpu: ChunkGPU?
        if !mb.indices.isEmpty {
            let vb = mb.vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            let ib = mb.indices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            if let vb = vb, let ib = ib {
                gpu = ChunkGPU(vertexBuffer: vb, indexBuffer: ib, indexCount: mb.indices.count, bounds: mb.bounds, lastUsed: frame)
            }
        }
        lock.lock()
        if let g = gpu { chunks[k] = g }
        pending.remove(k)
        inFlight -= 1
        lock.unlock()
    }

    /// Drops chunks not used for a while.
    func evict(maxAgeFrames: Int, keepLimit: Int) {
        lock.lock()
        defer { lock.unlock() }
        if chunks.count < keepLimit { return }
        let old = chunks.filter { frame - $0.value.lastUsed > maxAgeFrames }.map { $0.key }
        for k in old { chunks.removeValue(forKey: k) }
    }

    var loadedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
    }
}
