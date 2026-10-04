// Linux typecheck stub for Metal (signatures only; never executed).
@_exported import Foundation

public enum MTLPixelFormat: UInt { case invalid, rgba8Unorm, rgba8Unorm_srgb, bgra8Unorm, bgra8Unorm_srgb, rgba16Float, r32Float, depth32Float, depth16Unorm, depth32Float_stencil8 }
public enum MTLTextureType: UInt { case type2D, type2DArray, type2DMultisample, typeCube, type3D }
public enum MTLStorageMode: UInt { case shared, managed, `private`, memoryless }
public enum MTLCPUCacheMode: UInt { case defaultCache, writeCombined }
public enum MTLVertexFormat: UInt { case invalid, float, float2, float3, float4, uchar4, uchar4Normalized, half2, half4, ushort2, short2Normalized }
public enum MTLVertexStepFunction: UInt { case constant, perVertex, perInstance }
public enum MTLCompareFunction: UInt { case never, less, equal, lessEqual, greater, notEqual, greaterEqual, always }
public enum MTLSamplerMinMagFilter: UInt { case nearest, linear }
public enum MTLSamplerMipFilter: UInt { case notMipmapped, nearest, linear }
public enum MTLSamplerAddressMode: UInt { case clampToEdge, mirrorClampToEdge, `repeat`, mirrorRepeat, clampToZero }
public enum MTLBlendOperation: UInt { case add, subtract, reverseSubtract, min, max }
public enum MTLBlendFactor: UInt { case zero, one, sourceColor, oneMinusSourceColor, sourceAlpha, oneMinusSourceAlpha, destinationColor, oneMinusDestinationColor, destinationAlpha, oneMinusDestinationAlpha }
public enum MTLPrimitiveType: UInt { case point, line, lineStrip, triangle, triangleStrip }
public enum MTLIndexType: UInt { case uint16, uint32 }
public enum MTLLoadAction: UInt { case dontCare, load, clear }
public enum MTLStoreAction: UInt { case dontCare, store, multisampleResolve, storeAndMultisampleResolve, unknown }
public enum MTLCullMode: UInt { case none, front, back }
public enum MTLWinding: UInt { case clockwise, counterClockwise }
public enum MTLDepthClipMode: UInt { case clip, clamp }
public enum MTLGPUFamily: Int { case apple4 = 1004, apple5 = 1005, apple6 = 1006, apple7 = 1007, apple8 = 1008 }

public struct MTLResourceOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let storageModeShared = MTLResourceOptions([]), storageModePrivate = MTLResourceOptions(rawValue: 32)
    public static let cpuCacheModeWriteCombined = MTLResourceOptions(rawValue: 1)
}
public struct MTLTextureUsage: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let shaderRead = MTLTextureUsage(rawValue: 1), shaderWrite = MTLTextureUsage(rawValue: 2), renderTarget = MTLTextureUsage(rawValue: 4)
}
public struct MTLColorWriteMask: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let all = MTLColorWriteMask(rawValue: 15)
}

public struct MTLClearColor { public init(red: Double, green: Double, blue: Double, alpha: Double) {} }
public struct MTLViewport { public init(originX: Double, originY: Double, width: Double, height: Double, znear: Double, zfar: Double) {} }
public struct MTLOrigin { public var x = 0, y = 0, z = 0; public init(x: Int, y: Int, z: Int) {} }
public struct MTLSize { public var width = 0, height = 0, depth = 0; public init(width: Int, height: Int, depth: Int) {} }
public struct MTLRegion { public var origin: MTLOrigin; public var size: MTLSize; public init(origin: MTLOrigin, size: MTLSize) { self.origin = origin; self.size = size } }
public func MTLRegionMake2D(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MTLRegion { MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0), size: MTLSize(width: w, height: h, depth: 1)) }

public protocol MTLResource: AnyObject { var label: String? { get set } }
public protocol MTLBuffer: MTLResource {
    func contents() -> UnsafeMutableRawPointer
    var length: Int { get }
}
public protocol MTLTexture: MTLResource {
    var width: Int { get }
    var height: Int { get }
    var pixelFormat: MTLPixelFormat { get }
    func replace(region: MTLRegion, mipmapLevel: Int, slice: Int, withBytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int)
    func replace(region: MTLRegion, mipmapLevel: Int, withBytes: UnsafeRawPointer, bytesPerRow: Int)
    func getBytes(_ bytes: UnsafeMutableRawPointer, bytesPerRow: Int, from region: MTLRegion, mipmapLevel: Int)
}
public protocol MTLFunction: AnyObject {}
public protocol MTLLibrary: AnyObject { func makeFunction(name: String) -> MTLFunction? }
public protocol MTLRenderPipelineState: AnyObject {}
public protocol MTLDepthStencilState: AnyObject {}
public protocol MTLSamplerState: AnyObject {}
public protocol MTLDrawable: AnyObject {}

public protocol MTLCommandEncoder: AnyObject {
    var label: String? { get set }
    func endEncoding()
    func pushDebugGroup(_ s: String)
    func popDebugGroup()
}
public protocol MTLBlitCommandEncoder: MTLCommandEncoder {
    func generateMipmaps(for texture: MTLTexture)
}
public protocol MTLRenderCommandEncoder: MTLCommandEncoder {
    func setRenderPipelineState(_ s: MTLRenderPipelineState)
    func setDepthStencilState(_ s: MTLDepthStencilState?)
    func setDepthBias(_ bias: Float, slopeScale: Float, clamp: Float)
    func setDepthClipMode(_ m: MTLDepthClipMode)
    func setCullMode(_ m: MTLCullMode)
    func setFrontFacing(_ w: MTLWinding)
    func setViewport(_ v: MTLViewport)
    func setVertexBuffer(_ b: MTLBuffer?, offset: Int, index: Int)
    func setVertexBufferOffset(_ offset: Int, index: Int)
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setFragmentBuffer(_ b: MTLBuffer?, offset: Int, index: Int)
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setFragmentTexture(_ t: MTLTexture?, index: Int)
    func setFragmentSamplerState(_ s: MTLSamplerState?, index: Int)
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int)
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int)
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int, instanceCount: Int)
}
public protocol MTLCommandBuffer: AnyObject {
    var label: String? { get set }
    func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder?
    func makeBlitCommandEncoder() -> MTLBlitCommandEncoder?
    func addCompletedHandler(_ block: @escaping (MTLCommandBuffer) -> Void)
    func present(_ drawable: MTLDrawable)
    func commit()
    func waitUntilCompleted()
}
public protocol MTLCommandQueue: AnyObject {
    var label: String? { get set }
    func makeCommandBuffer() -> MTLCommandBuffer?
}

public protocol MTLDevice: AnyObject {
    var name: String { get }
    func makeCommandQueue() -> MTLCommandQueue?
    func makeDefaultLibrary() -> MTLLibrary?
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeBuffer(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture?
    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState
    func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> MTLDepthStencilState?
    func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState?
    func supportsTextureSampleCount(_ count: Int) -> Bool
    func supportsFamily(_ f: MTLGPUFamily) -> Bool
}
public func MTLCreateSystemDefaultDevice() -> MTLDevice? { nil }

open class MTLTextureDescriptor: NSObject {
    open var textureType: MTLTextureType = .type2D
    open var pixelFormat: MTLPixelFormat = .rgba8Unorm
    open var width = 1, height = 1, depth = 1, arrayLength = 1, mipmapLevelCount = 1, sampleCount = 1
    open var usage: MTLTextureUsage = .shaderRead
    open var storageMode: MTLStorageMode = .shared
    open class func texture2DDescriptor(pixelFormat: MTLPixelFormat, width: Int, height: Int, mipmapped: Bool) -> MTLTextureDescriptor { MTLTextureDescriptor() }
}

open class MTLSamplerDescriptor: NSObject {
    open var minFilter: MTLSamplerMinMagFilter = .nearest
    open var magFilter: MTLSamplerMinMagFilter = .nearest
    open var mipFilter: MTLSamplerMipFilter = .notMipmapped
    open var sAddressMode: MTLSamplerAddressMode = .clampToEdge
    open var tAddressMode: MTLSamplerAddressMode = .clampToEdge
    open var rAddressMode: MTLSamplerAddressMode = .clampToEdge
    open var maxAnisotropy = 1
    open var compareFunction: MTLCompareFunction = .never
    open var label: String?
}

open class MTLDepthStencilDescriptor: NSObject {
    open var depthCompareFunction: MTLCompareFunction = .always
    open var isDepthWriteEnabled = false
    open var label: String?
}

open class MTLVertexAttributeDescriptor: NSObject {
    open var format: MTLVertexFormat = .invalid
    open var offset = 0
    open var bufferIndex = 0
}
open class MTLVertexAttributeDescriptorArray: NSObject {
    open subscript(i: Int) -> MTLVertexAttributeDescriptor! { get { MTLVertexAttributeDescriptor() } set {} }
}
open class MTLVertexBufferLayoutDescriptor: NSObject {
    open var stride = 0
    open var stepFunction: MTLVertexStepFunction = .perVertex
    open var stepRate = 1
}
open class MTLVertexBufferLayoutDescriptorArray: NSObject {
    open subscript(i: Int) -> MTLVertexBufferLayoutDescriptor! { get { MTLVertexBufferLayoutDescriptor() } set {} }
}
open class MTLVertexDescriptor: NSObject {
    open var attributes: MTLVertexAttributeDescriptorArray { MTLVertexAttributeDescriptorArray() }
    open var layouts: MTLVertexBufferLayoutDescriptorArray { MTLVertexBufferLayoutDescriptorArray() }
}

open class MTLRenderPipelineColorAttachmentDescriptor: NSObject {
    open var pixelFormat: MTLPixelFormat = .invalid
    open var isBlendingEnabled = false
    open var rgbBlendOperation: MTLBlendOperation = .add
    open var alphaBlendOperation: MTLBlendOperation = .add
    open var sourceRGBBlendFactor: MTLBlendFactor = .one
    open var sourceAlphaBlendFactor: MTLBlendFactor = .one
    open var destinationRGBBlendFactor: MTLBlendFactor = .zero
    open var destinationAlphaBlendFactor: MTLBlendFactor = .zero
    open var writeMask: MTLColorWriteMask = .all
}
open class MTLRenderPipelineColorAttachmentDescriptorArray: NSObject {
    open subscript(i: Int) -> MTLRenderPipelineColorAttachmentDescriptor! { get { MTLRenderPipelineColorAttachmentDescriptor() } set {} }
}
open class MTLRenderPipelineDescriptor: NSObject {
    open var label: String?
    open var vertexFunction: MTLFunction?
    open var fragmentFunction: MTLFunction?
    open var vertexDescriptor: MTLVertexDescriptor?
    open var colorAttachments: MTLRenderPipelineColorAttachmentDescriptorArray { MTLRenderPipelineColorAttachmentDescriptorArray() }
    open var depthAttachmentPixelFormat: MTLPixelFormat = .invalid
    open var stencilAttachmentPixelFormat: MTLPixelFormat = .invalid
    open var rasterSampleCount = 1
}

open class MTLRenderPassAttachmentDescriptor: NSObject {
    open var texture: MTLTexture?
    open var resolveTexture: MTLTexture?
    open var loadAction: MTLLoadAction = .dontCare
    open var storeAction: MTLStoreAction = .dontCare
}
open class MTLRenderPassColorAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    open var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
}
open class MTLRenderPassDepthAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    open var clearDepth: Double = 1
}
open class MTLRenderPassColorAttachmentDescriptorArray: NSObject {
    open subscript(i: Int) -> MTLRenderPassColorAttachmentDescriptor! { get { MTLRenderPassColorAttachmentDescriptor() } set {} }
}
open class MTLRenderPassDescriptor: NSObject {
    open var colorAttachments: MTLRenderPassColorAttachmentDescriptorArray { MTLRenderPassColorAttachmentDescriptorArray() }
    open var depthAttachment: MTLRenderPassDepthAttachmentDescriptor! = MTLRenderPassDepthAttachmentDescriptor()
}
