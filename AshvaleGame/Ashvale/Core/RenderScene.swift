//
//  RenderScene.swift
//  Ashvale
//
//  Per-frame description of what the game wants drawn. Filled by gameplay
//  code (platform independent) and consumed by the Metal renderer.
//

import Foundation

struct DrawItem {
    var mesh: MeshID
    var instance: InstanceData
}

enum QualityLevel: Int, Codable, CaseIterable {
    case low = 0, medium, high

    var name: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }
}

struct RenderSettings {
    var quality: QualityLevel = .medium
    var viewDistance: Float { [520, 760, 1000][quality.rawValue] }
    var treeDistance: Float { [300, 450, 620][quality.rawValue] }
    var treeHiDistance: Float { [70, 110, 160][quality.rawValue] }
    var propDistanceScale: Float { [0.7, 1.0, 1.3][quality.rawValue] }
    var interiorDistance: Float { [55, 85, 120][quality.rawValue] }
    var lod0Distance: Float { [130, 190, 260][quality.rawValue] }
    var shadowMapSize: Int { [1024, 2048, 2048][quality.rawValue] }
    var shadowRange: Float { [45, 65, 90][quality.rawValue] }
    var renderScale: Float { [0.72, 0.85, 1.0][quality.rawValue] }
    var msaa: Int { [1, 1, 4][quality.rawValue] }
}

final class RenderScene {
    // Camera.
    var cameraPos = Vec3(0, 0, 0)
    var view: Mat4 = .identity
    var fovY: Float = 60 * kDegToRad
    var viewModelFovY: Float = 55 * kDegToRad
    var near: Float = 0.06

    var time: Float = 0
    var uniforms = FrameUniforms()

    var dynamic: [DrawItem] = []
    var viewModel: [DrawItem] = []
    var shadowCasters: [DrawItem] = []
    var particles: [ParticleInstance] = []
    var rainIntensity: Float = 0
    var drawRain = true
    var drawWorld = true
    var shadowsEnabled = true

    init() {
        dynamic.reserveCapacity(2048)
        viewModel.reserveCapacity(64)
        particles.reserveCapacity(1024)
    }

    func beginFrame() {
        dynamic.removeAll(keepingCapacity: true)
        viewModel.removeAll(keepingCapacity: true)
        shadowCasters.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
    }

    /// Adds a dynamic object that also casts shadows.
    func add(_ mesh: MeshID, _ instance: InstanceData, castsShadow: Bool = true) {
        guard mesh.isValid else { return }
        dynamic.append(DrawItem(mesh: mesh, instance: instance))
        if castsShadow { shadowCasters.append(DrawItem(mesh: mesh, instance: instance)) }
    }

    func addViewModel(_ mesh: MeshID, _ instance: InstanceData) {
        guard mesh.isValid else { return }
        viewModel.append(DrawItem(mesh: mesh, instance: instance))
    }

    var forward: Vec3 {
        // Third row of the view rotation, negated.
        Vec3(-view.c0.z, -view.c1.z, -view.c2.z)
    }
}
