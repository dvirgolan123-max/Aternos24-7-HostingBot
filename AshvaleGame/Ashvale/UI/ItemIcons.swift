//
//  ItemIcons.swift
//  Ashvale
//
//  Inventory icons rendered from the actual 3D item models with Metal at
//  load time.
//

import UIKit
import CoreGraphics

final class ItemIcons {
    static let shared = ItemIcons()
    private var images: [Int: UIImage] = [:]
    private(set) var generated = false

    func image(for model: ItemModel) -> UIImage? { images[model.rawValue] }
    func image(for item: ItemInstance) -> UIImage? { images[item.def.model.rawValue] }

    func generate(renderer: Renderer, uniforms: FrameUniforms) {
        guard !generated else { return }
        let size = 112
        for m in ItemModel.allCases {
            let weaponLike = ItemVisuals.isWeaponModel(m) || [.magKestrel, .magVanta, .magSMG, .suppressorPistol, .suppressorRifle, .scope, .splint].contains(m)
            let yaw: Float = weaponLike ? kPi * 0.5 : 0.65
            let pitch: Float = weaponLike ? 0.12 : 0.5
            guard let bytes = renderer.renderIcon(mesh: ItemVisuals.mesh(m), size: size, yaw: yaw, pitch: pitch, uniforms: uniforms),
                  let img = ItemIcons.makeImage(bytes, size: size) else { continue }
            images[m.rawValue] = img
        }
        generated = true
    }

    static func makeImage(_ bytes: [UInt8], size: Int) -> UIImage? {
        var data = bytes
        // Premultiply alpha (lit shader outputs straight color with alpha = coverage).
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = UInt16(data[i + 3])
            data[i] = UInt8(UInt16(data[i]) * a / 255)
            data[i + 1] = UInt8(UInt16(data[i + 1]) * a / 255)
            data[i + 2] = UInt8(UInt16(data[i + 2]) * a / 255)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return data.withUnsafeMutableBytes { raw -> UIImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: cs, bitmapInfo: info),
                  let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg, scale: 2, orientation: .up)
        }
    }
}
