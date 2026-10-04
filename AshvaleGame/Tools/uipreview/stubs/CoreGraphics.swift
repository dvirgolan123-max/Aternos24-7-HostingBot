// Functional CoreGraphics stand-in for the Linux UI layout preview (stores values, draws nothing).
@_exported import Foundation

public struct CGAffineTransform: Equatable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) { self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty }
    public init(translationX: CGFloat, y: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: translationX, ty: y) }
    public init(scaleX: CGFloat, y: CGFloat) { self.init(a: scaleX, b: 0, c: 0, d: y, tx: 0, ty: 0) }
    public init(rotationAngle r: CGFloat) { self.init(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), tx: 0, ty: 0) }
    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { self }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { self }
    public func rotated(by: CGFloat) -> CGAffineTransform { self }
    public func concatenating(_ t: CGAffineTransform) -> CGAffineTransform { self }
}

public class CGColor {
    public let components: [CGFloat]
    public init() { components = [0, 0, 0, 1] }
    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { components = [r, g, b, a] }
}
public class CGPath { public init() {} }
public class CGColorSpace { public init() {} }
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }

public enum CGImageAlphaInfo: UInt32 {
    case none, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

public class CGImage {
    public var width: Int { 0 }
    public var height: Int { 0 }
}

public enum CGLineCap: Int32 { case butt, round, square }
public enum CGLineJoin: Int32 { case miter, round, bevel }
public enum CGBlendMode: Int32 { case normal, multiply }

public class CGContext {
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {}
    public func makeImage() -> CGImage? { nil }
    public func setFillColor(_ c: CGColor) {}
    public func setStrokeColor(_ c: CGColor) {}
    public func fill(_ r: CGRect) {}
    public func setLineWidth(_ w: CGFloat) {}
    public func saveGState() {}
    public func restoreGState() {}
}
