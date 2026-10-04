// Linux typecheck stub for UIKit (signatures only; never executed).
@_exported import Foundation
@_exported import CoreGraphics
@_exported import QuartzCore

/// Stand-in for `#selector(...)`; the check script rewrites selectors to `StubSelector()`.
public struct StubSelector { public init() {} }

// MARK: Colors, fonts, text

open class UIColor {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {}
    public init(cgColor: CGColor) {}
    open func withAlphaComponent(_ a: CGFloat) -> UIColor { self }
    open var cgColor: CGColor { CGColor() }
    open func setFill() {}
    open func setStroke() {}
    open func set() {}
    open func getRed(_ r: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool { false }
    open class var black: UIColor { UIColor(white: 0, alpha: 1) }
    open class var white: UIColor { UIColor(white: 1, alpha: 1) }
    open class var clear: UIColor { UIColor(white: 0, alpha: 0) }
    open class var red: UIColor { UIColor(white: 0, alpha: 1) }
    open class var green: UIColor { UIColor(white: 0, alpha: 1) }
    open class var blue: UIColor { UIColor(white: 0, alpha: 1) }
    open class var yellow: UIColor { UIColor(white: 0, alpha: 1) }
    open class var orange: UIColor { UIColor(white: 0, alpha: 1) }
    open class var gray: UIColor { UIColor(white: 0, alpha: 1) }
    open class var darkGray: UIColor { UIColor(white: 0, alpha: 1) }
    open class var lightGray: UIColor { UIColor(white: 0, alpha: 1) }
}

open class UIFont {
    public struct Weight: Hashable {
        public let rawValue: CGFloat
        public init(_ v: CGFloat) { rawValue = v }
        public static let ultraLight = Weight(-0.8), thin = Weight(-0.6), light = Weight(-0.4), regular = Weight(0)
        public static let medium = Weight(0.23), semibold = Weight(0.3), bold = Weight(0.4), heavy = Weight(0.56), black = Weight(0.62)
    }
    public init?(name: String, size: CGFloat) {}
    public init() {}
    open class func systemFont(ofSize s: CGFloat) -> UIFont { UIFont() }
    open class func systemFont(ofSize s: CGFloat, weight: Weight) -> UIFont { UIFont() }
    open class func boldSystemFont(ofSize s: CGFloat) -> UIFont { UIFont() }
    open class func monospacedDigitSystemFont(ofSize s: CGFloat, weight: Weight) -> UIFont { UIFont() }
    open class func monospacedSystemFont(ofSize s: CGFloat, weight: Weight) -> UIFont { UIFont() }
    open var pointSize: CGFloat { 0 }
    open var lineHeight: CGFloat { 0 }
    open func withSize(_ s: CGFloat) -> UIFont { self }
}

public enum NSTextAlignment: Int { case left, center, right, justified, natural }
public enum NSLineBreakMode: Int { case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle }

open class NSParagraphStyle: NSObject {
    open var lineSpacing: CGFloat { 0 }
    open var alignment: NSTextAlignment { .left }
}

open class NSMutableParagraphStyle: NSParagraphStyle {
    private var _ls: CGFloat = 0
    private var _al: NSTextAlignment = .left
    open override var lineSpacing: CGFloat { get { _ls } set { _ls = newValue } }
    open override var alignment: NSTextAlignment { get { _al } set { _al = newValue } }
    open var paragraphSpacing: CGFloat = 0
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping
}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let strokeColor = NSAttributedString.Key("NSStrokeColor")
    public static let strokeWidth = NSAttributedString.Key("NSStrokeWidth")
}

public struct UIEdgeInsets: Equatable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) { self.top = top; self.left = left; self.bottom = bottom; self.right = right }
    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

// MARK: Responders and views

open class UIResponder: NSObject {
    open var next: UIResponder? { nil }
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open var canBecomeFirstResponder: Bool { false }
    @discardableResult open func becomeFirstResponder() -> Bool { false }
}

open class UITraitCollection: NSObject {
    open var displayScale: CGFloat { 2 }
}

open class UIScreen: NSObject {
    public static let main = UIScreen()
    open var scale: CGFloat { 2 }
    open var nativeScale: CGFloat { 2 }
    open var bounds: CGRect { .zero }
    open var maximumFramesPerSecond: Int { 60 }
}

open class UIView: UIResponder {
    public enum ContentMode: Int { case scaleToFill, scaleAspectFit, scaleAspectFill, redraw, center, top, bottom, left, right }
    public struct AutoresizingMask: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let flexibleLeftMargin = AutoresizingMask(rawValue: 1), flexibleWidth = AutoresizingMask(rawValue: 2)
        public static let flexibleRightMargin = AutoresizingMask(rawValue: 4), flexibleTopMargin = AutoresizingMask(rawValue: 8)
        public static let flexibleHeight = AutoresizingMask(rawValue: 16), flexibleBottomMargin = AutoresizingMask(rawValue: 32)
    }
    public struct AnimationOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let curveEaseInOut = AnimationOptions(rawValue: 0), curveEaseIn = AnimationOptions(rawValue: 1 << 16)
        public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16), curveLinear = AnimationOptions(rawValue: 3 << 16)
        public static let allowUserInteraction = AnimationOptions(rawValue: 2), beginFromCurrentState = AnimationOptions(rawValue: 4)
        public static let `repeat` = AnimationOptions(rawValue: 8), autoreverse = AnimationOptions(rawValue: 16)
    }

    public convenience override init() { self.init(frame: .zero) }
    public init(frame: CGRect) { super.init() }
    public required init?(coder: NSCoder) { super.init() }

    open class var layerClass: AnyClass { CALayer.self }
    open var layer: CALayer { CALayer() }
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var center: CGPoint = .zero
    open var transform: CGAffineTransform = .identity
    open var alpha: CGFloat = 1
    open var isHidden = false
    open var backgroundColor: UIColor?
    open var isOpaque = true
    open var clipsToBounds = false
    open var tag = 0
    open var isUserInteractionEnabled = true
    open var isMultipleTouchEnabled = false
    open var isExclusiveTouch = false
    open var contentMode: ContentMode = .scaleToFill
    open var autoresizingMask: AutoresizingMask = []
    open var subviews: [UIView] { [] }
    open var superview: UIView? { nil }
    open var window: UIWindow? { nil }
    open var safeAreaInsets: UIEdgeInsets { .zero }
    open var tintColor: UIColor!
    open var traitCollection: UITraitCollection { UITraitCollection() }
    open var gestureRecognizers: [UIGestureRecognizer]?
    open var contentScaleFactor: CGFloat = 2

    open func addSubview(_ v: UIView) {}
    open func removeFromSuperview() {}
    open func insertSubview(_ v: UIView, at index: Int) {}
    open func insertSubview(_ v: UIView, belowSubview: UIView) {}
    open func insertSubview(_ v: UIView, aboveSubview: UIView) {}
    open func bringSubviewToFront(_ v: UIView) {}
    open func sendSubviewToBack(_ v: UIView) {}
    open func layoutSubviews() {}
    open func setNeedsLayout() {}
    open func layoutIfNeeded() {}
    open func setNeedsDisplay() {}
    open func draw(_ rect: CGRect) {}
    open func sizeThatFits(_ size: CGSize) -> CGSize { .zero }
    open func sizeToFit() {}
    open func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    open func convert(_ point: CGPoint, to view: UIView?) -> CGPoint { point }
    open func convert(_ point: CGPoint, from view: UIView?) -> CGPoint { point }
    open func convert(_ rect: CGRect, to view: UIView?) -> CGRect { rect }
    open func convert(_ rect: CGRect, from view: UIView?) -> CGRect { rect }
    open func viewWithTag(_ tag: Int) -> UIView? { nil }
    open func addGestureRecognizer(_ g: UIGestureRecognizer) {}
    open func removeGestureRecognizer(_ g: UIGestureRecognizer) {}
    open func didMoveToSuperview() {}
    open func didMoveToWindow() {}
    open func safeAreaInsetsDidChange() {}

    open class func animate(withDuration d: TimeInterval, animations: @escaping () -> Void) {}
    open class func animate(withDuration d: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {}
    open class func animate(withDuration d: TimeInterval, delay: TimeInterval, options: AnimationOptions, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {}
    open class func performWithoutAnimation(_ actions: () -> Void) {}
}

open class UIWindow: UIView {
    public init(windowScene: UIWindowScene) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var rootViewController: UIViewController?
    open func makeKeyAndVisible() {}
}

open class UILabel: UIView {
    open var text: String?
    open var attributedText: NSAttributedString?
    open var font: UIFont!
    open var textColor: UIColor!
    open var textAlignment: NSTextAlignment = .left
    open var numberOfLines = 1
    open var adjustsFontSizeToFitWidth = false
    open var minimumScaleFactor: CGFloat = 0
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    open var shadowColor: UIColor?
    open var shadowOffset: CGSize = .zero
}

open class UIImage: NSObject {
    public enum Orientation: Int { case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored }
    public enum RenderingMode: Int { case automatic, alwaysOriginal, alwaysTemplate }
    public init(cgImage: CGImage, scale: CGFloat, orientation: Orientation) {}
    public init(cgImage: CGImage) {}
    public init?(systemName: String) {}
    public init?(named: String) {}
    open var size: CGSize { .zero }
    open var cgImage: CGImage? { nil }
    open func withRenderingMode(_ m: RenderingMode) -> UIImage { self }
}

open class UIImageView: UIView {
    public init(image: UIImage?) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var image: UIImage?
}

open class UIBezierPath: NSObject {
    public override init() {}
    public init(rect: CGRect) {}
    public init(ovalIn rect: CGRect) {}
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {}
    public init(arcCenter: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    open var lineWidth: CGFloat = 1
    open var usesEvenOddFillRule = false
    open var lineCapStyle: CGLineCap = .butt
    open var lineJoinStyle: CGLineJoin = .miter
    open var cgPath: CGPath { CGPath() }
    open func move(to p: CGPoint) {}
    open func addLine(to p: CGPoint) {}
    open func addArc(withCenter c: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    open func addQuadCurve(to p: CGPoint, controlPoint: CGPoint) {}
    open func close() {}
    open func append(_ p: UIBezierPath) {}
    open func reversing() -> UIBezierPath { self }
    open func fill() {}
    open func stroke() {}
}

// MARK: Controls

public class UIAction {
    public init(title: String = "", image: UIImage? = nil, handler: @escaping (UIAction) -> Void) {}
    public var sender: Any? { nil }
}

open class UIControl: UIView {
    public struct Event: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let touchDown = Event(rawValue: 1), touchDownRepeat = Event(rawValue: 2), touchDragInside = Event(rawValue: 4)
        public static let touchDragOutside = Event(rawValue: 8), touchDragEnter = Event(rawValue: 16), touchDragExit = Event(rawValue: 32)
        public static let touchUpInside = Event(rawValue: 64), touchUpOutside = Event(rawValue: 128), touchCancel = Event(rawValue: 256)
        public static let valueChanged = Event(rawValue: 4096), primaryActionTriggered = Event(rawValue: 8192), allEvents = Event(rawValue: 0xFFFFFFFF)
    }
    public struct State: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State([]), highlighted = State(rawValue: 1), disabled = State(rawValue: 2), selected = State(rawValue: 4)
    }
    open var isEnabled = true
    open var isSelected = false
    open var isHighlighted = false
    open func addTarget(_ target: Any?, action: StubSelector, for events: Event) {}
    open func addAction(_ action: UIAction, for events: Event) {}
    open func sendActions(for events: Event) {}
}

open class UISwitch: UIControl {
    open var isOn = false
    open var onTintColor: UIColor?
    open var thumbTintColor: UIColor?
    open func setOn(_ on: Bool, animated: Bool) {}
}

open class UISlider: UIControl {
    open var value: Float = 0
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
    open var isContinuous = true
    open var minimumTrackTintColor: UIColor?
    open var maximumTrackTintColor: UIColor?
    open var thumbTintColor: UIColor?
    open func setValue(_ v: Float, animated: Bool) {}
}

open class UISegmentedControl: UIControl {
    public init(items: [Any]?) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var selectedSegmentIndex = 0
    open var numberOfSegments: Int { 0 }
    open var selectedSegmentTintColor: UIColor?
    open func setTitleTextAttributes(_ attrs: [NSAttributedString.Key: Any]?, for state: UIControl.State) {}
}

open class UIScrollView: UIView {
    open var contentSize: CGSize = .zero
    open var contentOffset: CGPoint = .zero
    open var contentInset: UIEdgeInsets = .zero
    open var showsVerticalScrollIndicator = true
    open var showsHorizontalScrollIndicator = true
    open var alwaysBounceVertical = false
    open var alwaysBounceHorizontal = false
    open var delaysContentTouches = true
    open var canCancelContentTouches = true
    open var isScrollEnabled = true
    open var bounces = true
    open func setContentOffset(_ p: CGPoint, animated: Bool) {}
}

// MARK: Touches and gestures

open class UITouch: NSObject {
    public enum Phase: Int { case began, moved, stationary, ended, cancelled }
    open func location(in view: UIView?) -> CGPoint { .zero }
    open func previousLocation(in view: UIView?) -> CGPoint { .zero }
    open var phase: Phase { .began }
    open var tapCount: Int { 0 }
    open var view: UIView? { nil }
    open var timestamp: TimeInterval { 0 }
}

open class UIEvent: NSObject {
    open var allTouches: Set<UITouch>? { nil }
}

public protocol UIGestureRecognizerDelegate: AnyObject {}
extension UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { true }
    public func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
}

open class UIGestureRecognizer: NSObject {
    public enum State: Int { case possible, began, changed, ended, cancelled, failed
        public static let recognized = State.ended }
    public init(target: Any?, action: StubSelector?) {}
    open var state: State { .possible }
    open var view: UIView? { nil }
    open var isEnabled = true
    open weak var delegate: UIGestureRecognizerDelegate?
    open var cancelsTouchesInView = true
    open var delaysTouchesBegan = false
    open var delaysTouchesEnded = true
    open var numberOfTouches: Int { 0 }
    open func location(in view: UIView?) -> CGPoint { .zero }
    open func require(toFail other: UIGestureRecognizer) {}
}

open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired = 1
    open var numberOfTouchesRequired = 1
}

open class UILongPressGestureRecognizer: UIGestureRecognizer {
    open var minimumPressDuration: TimeInterval = 0.5
    open var allowableMovement: CGFloat = 10
    open var numberOfTouchesRequired = 1
}

open class UIPanGestureRecognizer: UIGestureRecognizer {
    open func translation(in view: UIView?) -> CGPoint { .zero }
    open func velocity(in view: UIView?) -> CGPoint { .zero }
    open func setTranslation(_ t: CGPoint, in view: UIView?) {}
}

open class UIImpactFeedbackGenerator: NSObject {
    public enum FeedbackStyle: Int { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) {}
    open func prepare() {}
    open func impactOccurred() {}
    open func impactOccurred(intensity: CGFloat) {}
}

// MARK: Controllers, app and scenes

public struct UIRectEdge: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = UIRectEdge(rawValue: 1), left = UIRectEdge(rawValue: 2), bottom = UIRectEdge(rawValue: 4), right = UIRectEdge(rawValue: 8)
    public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}

public struct UIInterfaceOrientationMask: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let portrait = UIInterfaceOrientationMask(rawValue: 2), landscapeLeft = UIInterfaceOrientationMask(rawValue: 16)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 8), portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 4)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown]
}

public enum UIInterfaceOrientation: Int { case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight }

open class UIViewController: UIResponder {
    public convenience override init() { self.init(nibName: nil, bundle: nil) }
    public init(nibName: String?, bundle: Bundle?) { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open var view: UIView!
    open func loadView() {}
    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewWillLayoutSubviews() {}
    open func viewDidLayoutSubviews() {}
    open var prefersStatusBarHidden: Bool { false }
    open var prefersHomeIndicatorAutoHidden: Bool { false }
    open var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [] }
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    open var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    open var traitCollection: UITraitCollection { UITraitCollection() }
    open func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
    open func setNeedsUpdateOfScreenEdgesDeferringSystemGestures() {}
    open func setNeedsStatusBarAppearanceUpdate() {}
    open func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {}
    open func dismiss(animated: Bool, completion: (() -> Void)? = nil) {}
}

open class UIApplication: UIResponder {
    public struct LaunchOptionsKey: Hashable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
    public static let shared = UIApplication()
    open var isIdleTimerDisabled = false
}

public protocol UIApplicationDelegate: AnyObject {}
extension UIApplicationDelegate {
    public static func main() {}
}

open class UISceneSession: NSObject {
    public struct Role: Hashable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
    open var role: Role { Role(rawValue: "") }
    open var configuration: UISceneConfiguration { UISceneConfiguration(name: nil, sessionRole: role) }
}

open class UISceneConfiguration: NSObject {
    public init(name: String?, sessionRole: UISceneSession.Role) {}
    open var delegateClass: AnyClass?
}

open class UIScene: UIResponder {
    open class ConnectionOptions: NSObject {}
    open var session: UISceneSession { UISceneSession() }
}

open class UIWindowScene: UIScene {
    open var windows: [UIWindow] { [] }
}

public protocol UISceneDelegate: AnyObject {}
public protocol UIWindowSceneDelegate: UISceneDelegate {
    var window: UIWindow? { get set }
}
