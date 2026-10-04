// Functional QuartzCore stand-in for the Linux UI layout preview.
@_exported import Foundation
@_exported import CoreGraphics

public typealias CFTimeInterval = Double
public func CACurrentMediaTime() -> CFTimeInterval { Date().timeIntervalSince1970 }

open class CALayer {
    public required init() {}
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var position: CGPoint = .zero
    open var cornerRadius: CGFloat = 0
    open var borderWidth: CGFloat = 0
    open var borderColor: CGColor?
    open var backgroundColor: CGColor?
    open var shadowColor: CGColor?
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 0
    open var shadowOffset: CGSize = .zero
    open var shadowPath: CGPath?
    open var masksToBounds = false
    open var opacity: Float = 1
    open var zPosition: CGFloat = 0
    open var isOpaque = false
    open var contents: Any?
    open var contentsScale: CGFloat = 1
    open var sublayers: [CALayer]?
    open var cornerCurve: String = ""
    open func addSublayer(_ l: CALayer) {}
    open func insertSublayer(_ l: CALayer, at: UInt32) {}
    open func removeFromSuperlayer() {}
    open func setNeedsDisplay() {}
    open func removeAllAnimations() {}
}

open class CAGradientLayer: CALayer {
    open var colors: [Any]?
    open var locations: [NSNumber]?
    open var startPoint: CGPoint = CGPoint(x: 0.5, y: 0)
    open var endPoint: CGPoint = CGPoint(x: 0.5, y: 1)
}

open class CAShapeLayer: CALayer {
    open var path: CGPath?
    open var fillColor: CGColor?
    open var strokeColor: CGColor?
    open var lineWidth: CGFloat = 1
}
