//
//  Renderer.swift
//  Ashvale
//
//  Metal renderer: directional shadow map, instanced world rendering with
//  frustum/distance culling and LOD, terrain chunk streaming, water, sky,
//  particles, rain and the first-person view model.
//

import Foundation
import Metal
import MetalKit

final class Renderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private(set) var library: MTLLibrary

    private var litPipeline: MTLRenderPipelineState?
    private var viewModelPipeline: MTLRenderPipelineState?
    private var waterPipeline: MTLRenderPipelineState?
    private var skyPipeline: MTLRenderPipelineState?
    private var particlePipeline: MTLRenderPipelineState?
    private var rainPipeline: MTLRenderPipelineState?
    private var shadowPipeline: MTLRenderPipelineState?

    private var depthWrite: MTLDepthStencilState?
    private var depthRead: MTLDepthStencilState?
    private var depthSky: MTLDepthStencilState?
    private var depthShadow: MTLDepthStencilState?

    private(set) var albedo: MTLTexture?
    private var shadowMap: MTLTexture?
    private var sampler: MTLSamplerState?

    let meshes = GPUMeshLibrary()
    private(set) var chunks: ChunkStreamer?
    weak var world: World?
    var registry: MeshRegistry?

    private let maxFrames = 3
    private let inFlight: DispatchSemaphore
    private var frameSlot = 0
    private var frameCounter = 0
    private var uniformBuffers: [MTLBuffer] = []
    private var instanceBuffers: [MTLBuffer] = []
    private var particleBuffers: [MTLBuffer] = []
    private let instanceCapacity = 60_000
    private let particleCapacity = 4096

    private var lakeBuffers: [(MTLBuffer, MTLBuffer, Int)] = []
    private var buildingBounds: [AABB] = []
    private var propBounds: [AABB] = []

    var settings = RenderSettings()
    private(set) var sampleCount = 1
    let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    let depthFormat: MTLPixelFormat = .depth32Float

    // Stats.
    private(set) var lastDrawCalls = 0
    private(set) var lastTriangles = 0
    private(set) var lastInstances = 0

    // Per-frame group scratch.
    private struct Group {
        var mesh: MeshID
        var items: [InstanceData]
    }
    private var mainGroups: [Group] = []
    private var mainIndex: [Int32: Int] = [:]
    private var shadowGroups: [Group] = []
    private var shadowIndex: [Int32: Int] = [:]
    private var vmGroups: [Group] = []
    private var vmIndex: [Int32: Int] = [:]
    private var visibleChunks: [(ChunkStreamer.ChunkGPU, Bool)] = []

    init?(device: MTLDevice) {
        self.device = device
        guard let q = device.makeCommandQueue(), let lib = device.makeDefaultLibrary() else { return nil }
        commandQueue = q
        library = lib
        inFlight = DispatchSemaphore(value: maxFrames)
        for i in 0..<maxFrames {
            guard let ub = device.makeBuffer(length: MemoryLayout<FrameUniforms>.stride, options: .storageModeShared),
                  let ib = device.makeBuffer(length: MemoryLayout<InstanceData>.stride * instanceCapacity, options: .storageModeShared),
                  let pb = device.makeBuffer(length: MemoryLayout<ParticleInstance>.stride * particleCapacity, options: .storageModeShared) else { return nil }
            ub.label = "Uniforms\(i)"
            ib.label = "Instances\(i)"
            pb.label = "Particles\(i)"
            uniformBuffers.append(ub)
            instanceBuffers.append(ib)
            particleBuffers.append(pb)
        }
        buildStates()
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .repeat
        sd.tAddressMode = .repeat
        sd.maxAnisotropy = 4
        sampler = device.makeSamplerState(descriptor: sd)
        createShadowMap(size: settings.shadowMapSize)
    }

    // MARK: Setup

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3
        vd.attributes[1].offset = 12
        vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float2
        vd.attributes[2].offset = 24
        vd.attributes[2].bufferIndex = 0
        vd.attributes[3].format = .uchar4Normalized
        vd.attributes[3].offset = 32
        vd.attributes[3].bufferIndex = 0
        vd.attributes[4].format = .uchar4
        vd.attributes[4].offset = 36
        vd.attributes[4].bufferIndex = 0
        vd.attributes[5].format = .uchar4Normalized
        vd.attributes[5].offset = 40
        vd.attributes[5].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<Vertex>.stride
        vd.layouts[0].stepFunction = .perVertex
        vd.layouts[0].stepRate = 1
        return vd
    }

    private func buildStates() {
        let dw = MTLDepthStencilDescriptor()
        dw.depthCompareFunction = .greater
        dw.isDepthWriteEnabled = true
        depthWrite = device.makeDepthStencilState(descriptor: dw)
        let dr = MTLDepthStencilDescriptor()
        dr.depthCompareFunction = .greater
        dr.isDepthWriteEnabled = false
        depthRead = device.makeDepthStencilState(descriptor: dr)
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .greaterEqual
        ds.isDepthWriteEnabled = false
        depthSky = device.makeDepthStencilState(descriptor: ds)
        let dsh = MTLDepthStencilDescriptor()
        dsh.depthCompareFunction = .lessEqual
        dsh.isDepthWriteEnabled = true
        depthShadow = device.makeDepthStencilState(descriptor: dsh)
        buildPipelines(sampleCount: settings.msaa)
    }

    func buildPipelines(sampleCount requested: Int) {
        sampleCount = device.supportsTextureSampleCount(requested) ? requested : 1
        let vd = Renderer.vertexDescriptor()
        func make(_ vs: String, _ fs: String?, blend: Bool = false, vertexDesc: MTLVertexDescriptor?, color: Bool = true, label: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.label = label
            d.vertexFunction = library.makeFunction(name: vs)
            if let fs = fs { d.fragmentFunction = library.makeFunction(name: fs) }
            d.vertexDescriptor = vertexDesc
            if color {
                d.colorAttachments[0].pixelFormat = colorFormat
                if blend {
                    d.colorAttachments[0].isBlendingEnabled = true
                    d.colorAttachments[0].rgbBlendOperation = .add
                    d.colorAttachments[0].alphaBlendOperation = .add
                    d.colorAttachments[0].sourceRGBBlendFactor = .one
                    d.colorAttachments[0].sourceAlphaBlendFactor = .one
                    d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                    d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                d.rasterSampleCount = sampleCount
            } else {
                d.rasterSampleCount = 1
            }
            d.depthAttachmentPixelFormat = depthFormat
            do {
                return try device.makeRenderPipelineState(descriptor: d)
            } catch {
                print("Pipeline \(label) failed: \(error)")
                return nil
            }
        }
        litPipeline = make("lit_vertex", "lit_fragment", vertexDesc: vd, label: "Lit")
        viewModelPipeline = make("viewmodel_vertex", "lit_fragment", vertexDesc: vd, label: "ViewModel")
        waterPipeline = make("lit_vertex", "water_fragment", vertexDesc: vd, label: "Water")
        skyPipeline = make("sky_vertex", "sky_fragment", vertexDesc: nil, label: "Sky")
        particlePipeline = make("particle_vertex", "particle_fragment", blend: true, vertexDesc: nil, label: "Particles")
        rainPipeline = make("rain_vertex", "particle_fragment", blend: true, vertexDesc: nil, label: "Rain")
        shadowPipeline = make("shadow_vertex", nil, vertexDesc: vd, color: false, label: "Shadow")
    }

    private func createShadowMap(size: Int) {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private
        shadowMap = device.makeTexture(descriptor: td)
        shadowMap?.label = "ShadowMap"
    }

    func applySettings(_ s: RenderSettings, view: MTKView?) {
        let old = settings
        settings = s
        if old.shadowMapSize != s.shadowMapSize { createShadowMap(size: s.shadowMapSize) }
        if old.msaa != s.msaa {
            buildPipelines(sampleCount: s.msaa)
            view?.sampleCount = sampleCount
        }
    }

    /// Uploads procedural material textures into a mipmapped texture array.
    func uploadTextures(_ layers: [[UInt8]]) {
        let size = TextureFactory.size
        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray
        td.pixelFormat = .rgba8Unorm_srgb
        td.width = size
        td.height = size
        td.arrayLength = layers.count
        var mips = 1
        var s = size
        while s > 1 { s /= 2; mips += 1 }
        td.mipmapLevelCount = mips
        td.usage = [.shaderRead]
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { return }
        tex.label = "Materials"
        for (i, data) in layers.enumerated() where data.count == size * size * 4 {
            data.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: i,
                            withBytes: raw.baseAddress!, bytesPerRow: size * 4, bytesPerImage: size * size * 4)
            }
        }
        if let cb = commandQueue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        albedo = tex
    }

    /// Uploads all registered meshes and prepares world culling data.
    func prepare(world: World, registry: MeshRegistry) {
        self.world = world
        self.registry = registry
        meshes.upload(device: device, registry: registry)
        if chunks == nil { chunks = ChunkStreamer(device: device, world: world) }
        buildingBounds = world.buildings.map { b -> AABB in
            if let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] {
                var bb = registry.bounds(ids.shell).transformed(b.transform)
                bb.expand(registry.bounds(ids.interior).transformed(b.transform))
                return bb
            }
            return AABB(center: b.position, halfExtents: Vec3(10, 10, 10))
        }
        propBounds = world.props.map { p -> AABB in
            if let id = world.propMeshIDs[p.type.rawValue] {
                return registry.bounds(id).transformed(p.transform)
            }
            return AABB(center: p.position, halfExtents: Vec3(2, 2, 2))
        }
        lakeBuffers = world.water.compactMap { lake in
            let mb = ChunkMesher.lakeMesh(lake)
            guard let vb = mb.vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
                  let ib = mb.indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }
            return (vb, ib, mb.indices.count)
        }
    }

    /// Re-uploads the mesh library if new meshes were registered.
    func refreshMeshesIfNeeded() {
        guard let reg = registry else { return }
        if reg.generation != meshes.uploadedGeneration {
            meshes.upload(device: device, registry: reg)
        }
    }

    /// Builds terrain chunks around a point synchronously (loading screen).
    func prewarm(around p: Vec3, radius: Float, progress: ((Float) -> Void)? = nil) {
        guard let chunks = chunks else { return }
        let r = Int(ceilf(radius / World.chunkSize))
        let cx0 = Int(p.x / World.chunkSize), cz0 = Int(p.z / World.chunkSize)
        var list: [(Int, Int, Int)] = []
        for dz in -r...r {
            for dx in -r...r {
                let cx = cx0 + dx, cz = cz0 + dz
                if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                let c = Vec3((Float(cx) + 0.5) * World.chunkSize, p.y, (Float(cz) + 0.5) * World.chunkSize)
                let d = vdistanceXZ(c, p)
                if d < settings.lod0Distance { list.append((cx, cz, 0)) }
                if d < radius { list.append((cx, cz, 1)) }
            }
        }
        for (i, item) in list.enumerated() {
            chunks.buildBlocking(item.0, item.1, item.2)
            progress?(Float(i + 1) / Float(list.count))
        }
    }

    // MARK: Frame

    private func addTo(_ groups: inout [Group], _ index: inout [Int32: Int], _ mesh: MeshID, _ inst: InstanceData) {
        if let gi = index[mesh.raw] {
            groups[gi].items.append(inst)
        } else {
            index[mesh.raw] = groups.count
            var g = Group(mesh: mesh, items: [])
            g.items.reserveCapacity(64)
            g.items.append(inst)
            groups.append(g)
        }
    }

    private func resetGroups() {
        // Keep allocations: clear items but keep group slots mapped.
        for i in 0..<mainGroups.count { mainGroups[i].items.removeAll(keepingCapacity: true) }
        for i in 0..<shadowGroups.count { shadowGroups[i].items.removeAll(keepingCapacity: true) }
        for i in 0..<vmGroups.count { vmGroups[i].items.removeAll(keepingCapacity: true) }
        if mainGroups.count > 600 { mainGroups.removeAll(); mainIndex.removeAll() }
        if shadowGroups.count > 600 { shadowGroups.removeAll(); shadowIndex.removeAll() }
        if vmGroups.count > 64 { vmGroups.removeAll(); vmIndex.removeAll() }
    }

    private func computeShadowMatrix(scene: RenderScene) -> Mat4 {
        var L = Vec3(scene.uniforms.sunDir.x, scene.uniforms.sunDir.y, scene.uniforms.sunDir.z)
        if L.y < 0.15 { L.y = 0.15 }
        L = vnormalize(L)
        let range = settings.shadowRange
        let fwd = scene.forward
        var center = scene.cameraPos + Vec3(fwd.x, 0, fwd.z) * (range * 0.45)
        let up: Vec3 = abs(L.y) > 0.95 ? Vec3(0, 0, 1) : Vec3(0, 1, 0)
        // Snap the center to shadow texels in light space to avoid shimmering.
        let lightView0 = Mat4.lookAt(eye: Vec3(0, 0, 0), target: -L, up: up)
        let texel = (range * 2) / Float(settings.shadowMapSize)
        var ls = lightView0.transformPoint(center)
        ls.x = floorf(ls.x / texel) * texel
        ls.y = floorf(ls.y / texel) * texel
        center = lightView0.inverse.transformPoint(ls)
        let lightView = Mat4.lookAt(eye: center + L * 250, target: center, up: up)
        let proj = Mat4.orthographic(left: -range, right: range, bottom: -range, top: range, near: 1, far: 520)
        return proj * lightView
    }

    /// Renders one frame. Returns false if no drawable was available.
    @discardableResult
    func draw(in view: MTKView, scene: RenderScene) -> Bool {
        guard let litPipeline = litPipeline, let albedo = albedo else { return false }
        inFlight.wait()
        frameSlot = (frameSlot + 1) % maxFrames
        frameCounter += 1
        chunks?.frame = frameCounter
        refreshMeshesIfNeeded()

        let size = view.drawableSize
        let aspect = Float(max(size.width, 1) / max(size.height, 1))
        let proj = Mat4.perspectiveReverseZ(fovY: scene.fovY, aspect: aspect, near: scene.near)
        let viewProj = proj * scene.view
        let frustum = Frustum(viewProjection: viewProj)
        var u = scene.uniforms
        u.viewProj = viewProj
        u.view = scene.view
        u.invViewProj = viewProj.inverse
        u.viewModelProj = Mat4.perspectiveReverseZ(fovY: scene.viewModelFovY, aspect: aspect, near: 0.01)
        u.cameraPos = Vec4(scene.cameraPos.x, scene.cameraPos.y, scene.cameraPos.z, fmodf(scene.time, 3600))
        u.screen = Vec4(Float(size.width), Float(size.height), 1 / Float(settings.shadowMapSize), settings.shadowRange)
        u.wind.w = scene.rainIntensity
        let shadowsOn = scene.shadowsEnabled && u.sunDir.w > 0.02
        let shadowVP = computeShadowMatrix(scene: scene)
        u.shadowViewProj = shadowVP
        uniformBuffers[frameSlot].contents().storeBytes(of: u, as: FrameUniforms.self)

        resetGroups()
        visibleChunks.removeAll(keepingCapacity: true)
        let cam = scene.cameraPos
        let shadowCenter = cam
        let shadowR = settings.shadowRange * 1.6
        var triangles = 0

        if scene.drawWorld, let world = world, let chunks = chunks {
            let viewDist = settings.viewDistance
            let r = Int(ceilf(viewDist / World.chunkSize))
            let ccx = Int(cam.x / World.chunkSize), ccz = Int(cam.z / World.chunkSize)
            for dz in -r...r {
                for dx in -r...r {
                    let cx = ccx + dx, cz = ccz + dz
                    if cx < 0 || cz < 0 || cx >= World.chunksPerSide || cz >= World.chunksPerSide { continue }
                    let minB = Vec3(Float(cx) * World.chunkSize, -50, Float(cz) * World.chunkSize)
                    let maxB = Vec3(Float(cx + 1) * World.chunkSize, 400, Float(cz + 1) * World.chunkSize)
                    let center = (minB + maxB) * 0.5
                    let d = max(0, vdistanceXZ(center, cam) - World.chunkSize * 0.7)
                    if d > viewDist { continue }
                    let inView = frustum.intersectsBox(min: minB, max: maxB)
                    let inShadow = shadowsOn && d < shadowR
                    if !inView && !inShadow { continue }
                    // Terrain.
                    let lod = d < settings.lod0Distance ? 0 : 1
                    var chunk = chunks.get(cx, cz, lod)
                    if chunk == nil {
                        chunks.request(cx, cz, lod, priority: d < 70)
                        chunk = chunks.get(cx, cz, 1 - lod)
                        if chunk == nil { chunks.request(cx, cz, 1 - lod) }
                    }
                    if let ch = chunk {
                        visibleChunks.append((ch, inView))
                        if inView { triangles += ch.indexCount / 3 }
                    }
                    let ci = cz * World.chunksPerSide + cx
                    // Buildings.
                    for bi in world.buildingsByChunk[ci] {
                        let bb = buildingBounds[bi]
                        let bd = max(0, vdistance(bb.center, cam) - bb.radius)
                        if bd > viewDist { continue }
                        let b = world.buildings[bi]
                        guard let ids = world.buildingMeshIDs[World.modelKey(b.type, b.variant)] else { continue }
                        let visible = frustum.intersectsBox(min: bb.min, max: bb.max)
                        let model = b.transform
                        let inst = InstanceData(model: model, tint: b.tint)
                        let showInterior = bd < settings.interiorDistance
                        if visible {
                            addTo(&mainGroups, &mainIndex, ids.shell, inst)
                            addTo(&mainGroups, &mainIndex, showInterior ? ids.interior : ids.plugs, inst)
                        }
                        if shadowsOn && bd < shadowR {
                            addTo(&shadowGroups, &shadowIndex, ids.shell, inst)
                            if bd < settings.shadowRange * 0.6 { addTo(&shadowGroups, &shadowIndex, ids.interior, inst) }
                        }
                    }
                    // Props.
                    for pi in world.propsByChunk[ci] {
                        let p = world.props[pi]
                        let pb = propBounds[pi]
                        let pd = vdistance(pb.center, cam)
                        if pd > p.type.drawDistance * settings.propDistanceScale { continue }
                        guard let id = world.propMeshIDs[p.type.rawValue] else { continue }
                        let inst = InstanceData(model: p.transform, tint: p.tint)
                        if frustum.intersectsBox(min: pb.min, max: pb.max) { addTo(&mainGroups, &mainIndex, id, inst) }
                        if shadowsOn && pd < shadowR { addTo(&shadowGroups, &shadowIndex, id, inst) }
                    }
                    // Trees.
                    if d < settings.treeDistance {
                        for ti in world.treesByChunk[ci] {
                            let t = world.trees[ti]
                            let td = vdistance(t.position, cam)
                            if td > settings.treeDistance { continue }
                            guard let ids = world.treeMeshIDs[t.kind.rawValue] else { continue }
                            let rad: Float = (t.kind == .bush ? 2 : 6) * t.scale
                            let c = t.position + Vec3(0, rad, 0)
                            let hi = td < settings.treeHiDistance
                            let model = Mat4.translation(t.position) * Mat4.rotationY(t.yaw) * Mat4.scale(Vec3(repeating: t.scale))
                            let inst = InstanceData(model: model, tint: t.tint, sway: hi ? 1 : 0)
                            if frustum.containsSphere(c, rad * 1.3) { addTo(&mainGroups, &mainIndex, hi ? ids.hi : ids.lo, inst) }
                            if shadowsOn && td < shadowR { addTo(&shadowGroups, &shadowIndex, hi ? ids.hi : ids.lo, inst) }
                        }
                    }
                    // Doors.
                    for di in world.doorsByChunk[ci] {
                        let door = world.doors[di]
                        let dd = vdistance(door.hinge, cam)
                        if dd > settings.interiorDistance + 20 { continue }
                        guard let id = world.doorMeshIDs[Int(door.style.rawValue)] else { continue }
                        let model = door.transform * Mat4.scale(Vec3(door.width, door.height / 2.12, 1))
                        let inst = InstanceData(model: model)
                        if frustum.containsSphere(door.center, 1.6) { addTo(&mainGroups, &mainIndex, id, inst) }
                        if shadowsOn && dd < settings.shadowRange { addTo(&shadowGroups, &shadowIndex, id, inst) }
                    }
                }
            }
            if frameCounter % 120 == 0 { chunks.evict(maxAgeFrames: 600, keepLimit: 260) }
        }
        // Dynamic objects.
        for item in scene.dynamic {
            let c = item.instance.model.translationPart
            if vdistance(c, cam) > 220 { continue }
            if !frustum.containsSphere(c, 3) { continue }
            addTo(&mainGroups, &mainIndex, item.mesh, item.instance)
        }
        if shadowsOn {
            for item in scene.shadowCasters where vdistance(item.instance.model.translationPart, shadowCenter) < shadowR {
                addTo(&shadowGroups, &shadowIndex, item.mesh, item.instance)
            }
        }
        for item in scene.viewModel { addTo(&vmGroups, &vmIndex, item.mesh, item.instance) }

        // Upload instances.
        let ib = instanceBuffers[frameSlot]
        let stride = MemoryLayout<InstanceData>.stride
        var cursor = 0
        func upload(_ groups: [Group]) -> [(MeshID, Int, Int)] {
            var out: [(MeshID, Int, Int)] = []
            out.reserveCapacity(groups.count)
            for g in groups where !g.items.isEmpty {
                let n = min(g.items.count, instanceCapacity - cursor)
                if n <= 0 { break }
                g.items.withUnsafeBytes { raw in
                    (ib.contents() + cursor * stride).copyMemory(from: raw.baseAddress!, byteCount: n * stride)
                }
                out.append((g.mesh, cursor * stride, n))
                cursor += n
            }
            return out
        }
        let mainDraws = upload(mainGroups)
        let shadowDraws = shadowsOn ? upload(shadowGroups) : []
        let vmDraws = upload(vmGroups)
        lastInstances = cursor

        // Particles.
        let pcount = min(scene.particles.count, particleCapacity)
        if pcount > 0 {
            scene.particles.withUnsafeBytes { raw in
                particleBuffers[frameSlot].contents().copyMemory(from: raw.baseAddress!, byteCount: pcount * MemoryLayout<ParticleInstance>.stride)
            }
        }

        guard let cb = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return false
        }
        cb.label = "Frame"
        let sem = inFlight
        cb.addCompletedHandler { _ in sem.signal() }
        var drawCalls = 0
        var identity = InstanceData(model: .identity)
        let ub = uniformBuffers[frameSlot]

        // Shadow pass.
        if shadowsOn, let shadowMap = shadowMap, let sp = shadowPipeline {
            let pd = MTLRenderPassDescriptor()
            pd.depthAttachment.texture = shadowMap
            pd.depthAttachment.loadAction = .clear
            pd.depthAttachment.storeAction = .store
            pd.depthAttachment.clearDepth = 1.0
            if let enc = cb.makeRenderCommandEncoder(descriptor: pd) {
                enc.label = "Shadow"
                enc.setRenderPipelineState(sp)
                enc.setDepthStencilState(depthShadow)
                enc.setDepthBias(1.5, slopeScale: 2.5, clamp: 0.02)
                enc.setDepthClipMode(.clamp)
                enc.setCullMode(.none)
                enc.setVertexBuffer(ub, offset: 0, index: 2)
                enc.setVertexBytes(&identity, length: stride, index: 1)
                for (ch, _) in visibleChunks where vdistanceXZ(ch.bounds.center, cam) < shadowR + 40 {
                    enc.setVertexBuffer(ch.vertexBuffer, offset: 0, index: 0)
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: ch.indexCount, indexType: .uint32, indexBuffer: ch.indexBuffer, indexBufferOffset: 0, instanceCount: 1)
                    drawCalls += 1
                }
                if let vb = meshes.vertexBuffer, let ixb = meshes.indexBuffer {
                    enc.setVertexBuffer(vb, offset: 0, index: 0)
                    enc.setVertexBuffer(ib, offset: 0, index: 1)
                    for (mesh, offset, count) in shadowDraws {
                        guard let r = meshes.range(mesh), r.indexCount > 0 else { continue }
                        enc.setVertexBufferOffset(offset, index: 1)
                        enc.drawIndexedPrimitives(type: .triangle, indexCount: r.indexCount, indexType: .uint32, indexBuffer: ixb, indexBufferOffset: r.indexOffset * 4, instanceCount: count)
                        drawCalls += 1
                    }
                }
                enc.endEncoding()
            }
        }

        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
            cb.commit()
            return false
        }
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.clearDepth = 0.0
        rpd.depthAttachment.storeAction = .dontCare
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
            cb.commit()
            return false
        }
        enc.label = "Main"
        let worldViewport = MTLViewport(originX: 0, originY: 0, width: Double(size.width), height: Double(size.height), znear: 0.0, zfar: 0.96)
        enc.setViewport(worldViewport)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setRenderPipelineState(litPipeline)
        enc.setDepthStencilState(depthWrite)
        enc.setVertexBuffer(ub, offset: 0, index: 2)
        enc.setFragmentBuffer(ub, offset: 0, index: 0)
        enc.setFragmentTexture(albedo, index: 0)
        enc.setFragmentTexture(shadowMap, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)

        // Terrain.
        enc.setVertexBytes(&identity, length: stride, index: 1)
        enc.setCullMode(.none)
        for (ch, inView) in visibleChunks where inView {
            enc.setVertexBuffer(ch.vertexBuffer, offset: 0, index: 0)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: ch.indexCount, indexType: .uint32, indexBuffer: ch.indexBuffer, indexBufferOffset: 0, instanceCount: 1)
            drawCalls += 1
        }
        enc.setCullMode(.back)

        // Instanced meshes.
        if let vb = meshes.vertexBuffer, let ixb = meshes.indexBuffer {
            enc.setVertexBuffer(vb, offset: 0, index: 0)
            enc.setVertexBuffer(ib, offset: 0, index: 1)
            for (mesh, offset, count) in mainDraws {
                guard let r = meshes.range(mesh), r.indexCount > 0 else { continue }
                enc.setVertexBufferOffset(offset, index: 1)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: r.indexCount, indexType: .uint32, indexBuffer: ixb, indexBufferOffset: r.indexOffset * 4, instanceCount: count)
                drawCalls += 1
                triangles += r.indexCount / 3 * count
            }
        }

        // Water.
        if scene.drawWorld, let wp = waterPipeline, !lakeBuffers.isEmpty {
            enc.setRenderPipelineState(wp)
            enc.setCullMode(.none)
            enc.setVertexBytes(&identity, length: stride, index: 1)
            for (vb, ixb, n) in lakeBuffers {
                enc.setVertexBuffer(vb, offset: 0, index: 0)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: n, indexType: .uint32, indexBuffer: ixb, indexBufferOffset: 0, instanceCount: 1)
                drawCalls += 1
            }
        }

        // Sky (fills only untouched depth).
        if let skyP = skyPipeline {
            enc.setRenderPipelineState(skyP)
            enc.setDepthStencilState(depthSky)
            enc.setCullMode(.none)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            drawCalls += 1
        }

        // First-person view model (always in front of the world).
        if !vmDraws.isEmpty, let vmp = viewModelPipeline, let vb = meshes.vertexBuffer, let ixb = meshes.indexBuffer {
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(size.width), height: Double(size.height), znear: 0.96, zfar: 1.0))
            enc.setRenderPipelineState(vmp)
            enc.setDepthStencilState(depthWrite)
            enc.setCullMode(.back)
            enc.setVertexBuffer(vb, offset: 0, index: 0)
            enc.setVertexBuffer(ib, offset: 0, index: 1)
            for (mesh, offset, count) in vmDraws {
                guard let r = meshes.range(mesh), r.indexCount > 0 else { continue }
                enc.setVertexBufferOffset(offset, index: 1)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: r.indexCount, indexType: .uint32, indexBuffer: ixb, indexBufferOffset: r.indexOffset * 4, instanceCount: count)
                drawCalls += 1
            }
            enc.setViewport(worldViewport)
        }

        // Particles and rain (blended, no depth writes).
        if pcount > 0, let pp = particlePipeline {
            enc.setRenderPipelineState(pp)
            enc.setDepthStencilState(depthRead)
            enc.setCullMode(.none)
            enc.setVertexBuffer(particleBuffers[frameSlot], offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: pcount)
            drawCalls += 1
        }
        if scene.drawRain && scene.rainIntensity > 0.02, let rp = rainPipeline {
            enc.setRenderPipelineState(rp)
            enc.setDepthStencilState(depthRead)
            enc.setCullMode(.none)
            let drops = Int(3500 * scene.rainIntensity)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: drops)
            drawCalls += 1
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
        lastDrawCalls = drawCalls
        lastTriangles = triangles
        return true
    }

    // MARK: Offscreen rendering (item icons)

    private var iconPipeline: MTLRenderPipelineState?

    /// Renders a mesh into an RGBA8 image (premultiplied, top-left origin).
    func renderIcon(mesh: MeshID, size: Int, yaw: Float, pitch: Float, uniforms baseUniforms: FrameUniforms) -> [UInt8]? {
        guard let r = meshes.range(mesh), r.indexCount > 0, let vb = meshes.vertexBuffer, let ixb = meshes.indexBuffer, let albedo = albedo else { return nil }
        if iconPipeline == nil {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "lit_vertex")
            d.fragmentFunction = library.makeFunction(name: "lit_fragment")
            d.vertexDescriptor = Renderer.vertexDescriptor()
            d.colorAttachments[0].pixelFormat = .rgba8Unorm_srgb
            d.depthAttachmentPixelFormat = .depth32Float
            iconPipeline = try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let pipe = iconPipeline else { return nil }
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: size, height: size, mipmapped: false)
        cd.usage = [.renderTarget, .shaderRead]
        cd.storageMode = .shared
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
        dd.usage = [.renderTarget]
        dd.storageMode = .private
        guard let color = device.makeTexture(descriptor: cd), let depth = device.makeTexture(descriptor: dd),
              let shadow = shadowMap, let cb = commandQueue.makeCommandBuffer() else { return nil }
        // Frame the mesh bounds.
        let b = r.bounds
        let c = b.center
        let radius = max(vlength(b.halfExtents), 0.05)
        let rot = Mat4.rotationX(pitch) * Mat4.rotationY(yaw)
        let model = rot * Mat4.translation(-c)
        let eye = Vec3(0, 0, radius * 2.9)
        let view = Mat4.lookAt(eye: eye, target: Vec3(0, 0, 0), up: Vec3(0, 1, 0))
        let proj = Mat4.perspectiveReverseZ(fovY: 40 * kDegToRad, aspect: 1, near: 0.01)
        var u = baseUniforms
        u.viewProj = proj * view
        u.view = view
        u.invViewProj = (proj * view).inverse
        u.cameraPos = Vec4(eye.x, eye.y, eye.z, 0)
        u.sunDir = Vec4(vnormalize(Vec3(-0.4, 0.8, 0.6)).x, vnormalize(Vec3(-0.4, 0.8, 0.6)).y, vnormalize(Vec3(-0.4, 0.8, 0.6)).z, 1.2)
        u.sunColor = Vec4(1, 0.97, 0.92, 1)
        u.skyAmbient = Vec4(0.55, 0.57, 0.62, 1)
        u.groundAmbient = Vec4(0.3, 0.3, 0.3, 1)
        u.fogColor = Vec4(1, 1, 1, 0)
        u.fogParams = Vec4(0, 0, 0, 0)
        u.flashlightPos = Vec4(0, 0, 0, 0)
        u.pointLight = Vec4(0, 0, 0, 0)
        u.screen = Vec4(Float(size), Float(size), 1, 0.001)
        u.grade = Vec4(1, 0, 0, 1.15)
        u.shadowViewProj = Mat4.orthographic(left: -1, right: 1, bottom: -1, top: 1, near: -100, far: -99)
        var inst = InstanceData(model: model)
        let pd = MTLRenderPassDescriptor()
        pd.colorAttachments[0].texture = color
        pd.colorAttachments[0].loadAction = .clear
        pd.colorAttachments[0].storeAction = .store
        pd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pd.depthAttachment.texture = depth
        pd.depthAttachment.loadAction = .clear
        pd.depthAttachment.clearDepth = 0
        pd.depthAttachment.storeAction = .dontCare
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pd) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthWrite)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setVertexBuffer(vb, offset: 0, index: 0)
        enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 1)
        enc.setVertexBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 2)
        enc.setFragmentBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setFragmentTexture(albedo, index: 0)
        enc.setFragmentTexture(shadow, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: r.indexCount, indexType: .uint32, indexBuffer: ixb, indexBufferOffset: r.indexOffset * 4, instanceCount: 1)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { raw in
            color.getBytes(raw.baseAddress!, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        }
        // The lit shader writes alpha 1 for every covered pixel; derive coverage from depth by checking non-black.
        return bytes
    }
}
