// Minimal software rasterizer used only by the headless preview tool to visually
// verify generated geometry and camera math on machines without a GPU.
import Foundation

final class Raster {
    let w: Int, h: Int
    var color: [Vec3]
    var depth: [Float]
    var sunDir = vnormalize(Vec3(0.4, 0.8, 0.3))
    var fogColor = Vec3(0.7, 0.75, 0.8)
    var fogDensity: Float = 0.0025
    var camPos = Vec3(0, 0, 0)

    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        color = Array(repeating: Vec3(0, 0, 0), count: w * h)
        depth = Array(repeating: 0, count: w * h)
    }

    func clear(_ c: Vec3) {
        for i in 0..<color.count { color[i] = c; depth[i] = 0 }
    }

    static func matColor(_ m: UInt8) -> Vec3 {
        switch Mat(rawValue: m) {
        case .grass: return Vec3(0.33, 0.42, 0.2)
        case .dirt: return Vec3(0.45, 0.37, 0.27)
        case .rock: return Vec3(0.5, 0.49, 0.47)
        case .forestFloor: return Vec3(0.3, 0.27, 0.18)
        case .asphalt: return Vec3(0.25, 0.25, 0.26)
        case .concrete: return Vec3(0.62, 0.61, 0.58)
        case .brick: return Vec3(0.6, 0.33, 0.25)
        case .plaster, .wallpaper: return Vec3(0.85, 0.83, 0.78)
        case .woodPlanks: return Vec3(0.6, 0.45, 0.3)
        case .woodDark: return Vec3(0.4, 0.28, 0.18)
        case .roofTiles: return Vec3(0.6, 0.3, 0.22)
        case .metalPainted, .sheetMetal: return Vec3(0.7, 0.7, 0.7)
        case .metalCorrugated: return Vec3(0.6, 0.62, 0.64)
        case .fabric, .carpet: return Vec3(0.7, 0.7, 0.7)
        case .floorTiles, .linoleum: return Vec3(0.75, 0.74, 0.7)
        case .gravel: return Vec3(0.5, 0.46, 0.4)
        case .bark: return Vec3(0.45, 0.37, 0.3)
        case .foliage: return Vec3(0.35, 0.5, 0.25)
        case .glass: return Vec3(0.4, 0.45, 0.5)
        case .rust: return Vec3(0.45, 0.25, 0.15)
        case .canvas, .burlap: return Vec3(0.6, 0.58, 0.45)
        case .camo: return Vec3(0.35, 0.38, 0.28)
        case .skin: return Vec3(0.8, 0.62, 0.5)
        case .denim: return Vec3(0.25, 0.33, 0.5)
        default: return Vec3(0.6, 0.6, 0.6)
        }
    }

    @inline(__always) func unpack(_ c: UInt32) -> Vec4 {
        Vec4(Float(c & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float((c >> 16) & 0xFF) / 255, Float((c >> 24) & 0xFF) / 255)
    }

    struct CV { var clip: Vec4; var col: Vec3; var world: Vec3 }

    func shade(_ v: Vertex, model: Mat4, tint: Vec3) -> (Vec3, Vec3) {
        let p = model.transformPoint(Vec3(v.px, v.py, v.pz))
        let n = vnormalize(model.transformDirection(Vec3(v.nx, v.ny, v.nz)))
        let mat = UInt8(v.material & 0xFF)
        let flags = UInt8((v.material >> 8) & 0xFF)
        let vc = unpack(v.color)
        var base: Vec3
        if mat == 255 {
            let wts = unpack(v.weights)
            base = Raster.matColor(Mat.grass.rawValue) * wts.x + Raster.matColor(Mat.dirt.rawValue) * wts.y +
                Raster.matColor(Mat.rock.rawValue) * wts.z + Raster.matColor(Mat.forestFloor.rawValue) * wts.w
        } else {
            base = Raster.matColor(mat)
        }
        base *= Vec3(vc.x, vc.y, vc.z)
        if flags & 1 != 0 { base *= tint }
        let ndl = max(0, vdot(n, sunDir))
        let lit = base * (Vec3(0.35, 0.38, 0.45) * vc.w + Vec3(1.0, 0.95, 0.85) * ndl * 0.9)
        return (lit, p)
    }

    func drawMesh(vertices: [Vertex], indices: [UInt32], model: Mat4, viewProj: Mat4, tint: Vec3 = Vec3(1, 1, 1), cull: Bool = true) {
        var cache = [Int: CV]()
        cache.reserveCapacity(vertices.count)
        func get(_ i: Int) -> CV {
            if let c = cache[i] { return c }
            let (col, wp) = shade(vertices[i], model: model, tint: tint)
            let clip = viewProj.mulVec(Vec4(wp.x, wp.y, wp.z, 1))
            let cv = CV(clip: clip, col: col, world: wp)
            cache[i] = cv
            return cv
        }
        var t = 0
        while t + 2 < indices.count {
            let a = get(Int(indices[t])), b = get(Int(indices[t + 1])), c = get(Int(indices[t + 2]))
            t += 3
            drawClipped([a, b, c], cull: cull)
        }
    }

    private func drawClipped(_ tri: [CV], cull: Bool) {
        let nearW: Float = 0.05
        var poly = tri
        // Clip against w >= nearW.
        var out: [CV] = []
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let ain = a.clip.w >= nearW, bin = b.clip.w >= nearW
            if ain { out.append(a) }
            if ain != bin {
                let t = (nearW - a.clip.w) / (b.clip.w - a.clip.w)
                out.append(CV(clip: a.clip + (b.clip - a.clip) * t, col: a.col + (b.col - a.col) * t, world: a.world + (b.world - a.world) * t))
            }
        }
        poly = out
        if poly.count < 3 { return }
        for i in 1..<(poly.count - 1) { rasterize(poly[0], poly[i], poly[i + 1], cull: cull) }
    }

    private func rasterize(_ a: CV, _ b: CV, _ c: CV, cull: Bool) {
        func toScreen(_ v: CV) -> Vec3 {
            let ndc = Vec3(v.clip.x / v.clip.w, v.clip.y / v.clip.w, v.clip.z / v.clip.w)
            return Vec3((ndc.x * 0.5 + 0.5) * Float(w), (1 - (ndc.y * 0.5 + 0.5)) * Float(h), ndc.z)
        }
        let sa = toScreen(a), sb = toScreen(b), sc = toScreen(c)
        // Signed area (screen y down flips orientation: CCW in NDC => negative here).
        let area = (sb.x - sa.x) * (sc.y - sa.y) - (sb.y - sa.y) * (sc.x - sa.x)
        if cull && area >= 0 { return }
        if abs(area) < 1e-6 { return }
        let minX = max(0, Int(floorf(min(sa.x, min(sb.x, sc.x)))))
        let maxX = min(w - 1, Int(ceilf(max(sa.x, max(sb.x, sc.x)))))
        let minY = max(0, Int(floorf(min(sa.y, min(sb.y, sc.y)))))
        let maxY = min(h - 1, Int(ceilf(max(sa.y, max(sb.y, sc.y)))))
        if minX > maxX || minY > maxY { return }
        let ia = 1 / a.clip.w, ib = 1 / b.clip.w, ic = 1 / c.clip.w
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Float(x) + 0.5, py = Float(y) + 0.5
                var w0 = (sb.x - px) * (sc.y - py) - (sb.y - py) * (sc.x - px)
                var w1 = (sc.x - px) * (sa.y - py) - (sc.y - py) * (sa.x - px)
                var w2 = (sa.x - px) * (sb.y - py) - (sa.y - py) * (sb.x - px)
                if area < 0 { w0 = -w0; w1 = -w1; w2 = -w2 }
                if w0 < 0 || w1 < 0 || w2 < 0 { continue }
                let s = w0 + w1 + w2
                let b0 = w0 / s, b1 = w1 / s, b2 = w2 / s
                let z = sa.z * b0 + sb.z * b1 + sc.z * b2
                let idx = y * w + x
                if z <= depth[idx] { continue } // reverse-Z: greater is closer
                depth[idx] = z
                // Perspective-correct attributes.
                let pw0 = b0 * ia, pw1 = b1 * ib, pw2 = b2 * ic
                let ps = pw0 + pw1 + pw2
                let col = (a.col * pw0 + b.col * pw1 + c.col * pw2) / ps
                let wp = (a.world * pw0 + b.world * pw1 + c.world * pw2) / ps
                let dist = vlength(wp - camPos)
                let fog = 1 - expf(-dist * fogDensity)
                color[idx] = vlerp(col, fogColor, fog)
            }
        }
    }

    func savePPM(_ path: String) {
        var data = Data("P6\n\(w) \(h)\n255\n".utf8)
        data.reserveCapacity(w * h * 3 + 20)
        for c in color {
            // Simple filmic-ish tonemap.
            let m = c / (c + Vec3(0.6, 0.6, 0.6)) * 1.6
            data.append(UInt8(clampf(powf(m.x, 1 / 1.1), 0, 1) * 255))
            data.append(UInt8(clampf(powf(m.y, 1 / 1.1), 0, 1) * 255))
            data.append(UInt8(clampf(powf(m.z, 1 / 1.1), 0, 1) * 255))
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
