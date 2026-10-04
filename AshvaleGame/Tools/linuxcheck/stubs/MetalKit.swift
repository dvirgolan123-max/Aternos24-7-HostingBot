// Linux typecheck stub for MetalKit (signatures only; never executed).
@_exported import Metal
@_exported import UIKit

public protocol CAMetalDrawable: MTLDrawable {
    var texture: MTLTexture { get }
}

public protocol MTKViewDelegate: AnyObject {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    func draw(in view: MTKView)
}

open class MTKView: UIView {
    public init(frame: CGRect, device: MTLDevice?) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var device: MTLDevice?
    open weak var delegate: MTKViewDelegate?
    open var colorPixelFormat: MTLPixelFormat = .bgra8Unorm
    open var depthStencilPixelFormat: MTLPixelFormat = .invalid
    open var clearDepth: Double = 1
    open var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    open var preferredFramesPerSecond = 60
    open var framebufferOnly = true
    open var autoResizeDrawable = true
    open var drawableSize: CGSize = .zero
    open var sampleCount = 1
    open var isPaused = false
    open var enableSetNeedsDisplay = false
    open var currentRenderPassDescriptor: MTLRenderPassDescriptor? { nil }
    open var currentDrawable: CAMetalDrawable? { nil }
}
