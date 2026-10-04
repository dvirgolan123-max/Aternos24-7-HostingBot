// Linux typecheck stub for AVFoundation audio (signatures only; never executed).
@_exported import Foundation

public typealias AVAudioFrameCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeBus = Int

open class AVAudioSession: NSObject {
    public struct Category: Hashable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "ambient"), soloAmbient = Category(rawValue: "soloAmbient"), playback = Category(rawValue: "playback") }
    public struct Mode: Hashable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default") }
    public struct CategoryOptions: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1) }
    open class func sharedInstance() -> AVAudioSession { AVAudioSession() }
    open func setCategory(_ c: Category, mode: Mode, options: CategoryOptions) throws {}
    open func setActive(_ active: Bool) throws {}
    public static let interruptionNotification = Notification.Name("AVAudioSessionInterruptionNotification")
}

open class AVAudioFormat: NSObject {
    public init?(standardFormatWithSampleRate rate: Double, channels: AVAudioChannelCount) {}
    open var sampleRate: Double { 0 }
    open var channelCount: AVAudioChannelCount { 1 }
}

open class AVAudioBuffer: NSObject {}
open class AVAudioPCMBuffer: AVAudioBuffer {
    public init?(pcmFormat: AVAudioFormat, frameCapacity: AVAudioFrameCount) {}
    open var frameLength: AVAudioFrameCount = 0
    open var frameCapacity: AVAudioFrameCount { 0 }
    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { nil }
}

open class AVAudioTime: NSObject {}

open class AVAudioNode: NSObject {}
open class AVAudioMixerNode: AVAudioNode {
    open var outputVolume: Float = 1
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1), interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 2)
}

open class AVAudioPlayerNode: AVAudioNode {
    open var volume: Float = 1
    open var pan: Float = 0
    open var isPlaying: Bool { false }
    open func scheduleBuffer(_ b: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionHandler: (() -> Void)? = nil) {}
    open func play() {}
    open func stop() {}
    open func pause() {}
}

open class AVAudioEngine: NSObject {
    open var mainMixerNode: AVAudioMixerNode { AVAudioMixerNode() }
    open var isRunning: Bool { false }
    open func attach(_ n: AVAudioNode) {}
    open func detach(_ n: AVAudioNode) {}
    open func connect(_ a: AVAudioNode, to b: AVAudioNode, format: AVAudioFormat?) {}
    open func prepare() {}
    open func start() throws {}
    open func stop() {}
    open func pause() {}
}
