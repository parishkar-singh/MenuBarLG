import AppKit
import ObjectiveC.runtime

@MainActor
final class GlassViewController: NSViewController {
    private struct AppearanceState: Equatable {
        let isDark: Bool
        let reduceTransparency: Bool
        let blurConfiguration: BlurStyleManager.Configuration
        let tintWhiteAlpha: Double
        let customCornersEnabled: Bool
        let cornerRadii: GlassTuningManager.CornerRadii
    }

    private let rootView = NSView(frame: .zero)
    private let fallbackView = NSView(frame: .zero)
    private let edgeDecorationView = NSView(frame: .zero)
    private let bottomBorderLayer = CALayer()
    private let bottomShadowLayer = CALayer()

    private let liquidGlassEffectView = NSGlassEffectView(frame: .zero)
    private let backdropEffectView = NSVisualEffectView(frame: .zero)
    private let backdropBoostEffectView = NSVisualEffectView(frame: .zero)
    private let rootCornerMaskLayer = CAShapeLayer()
    private let liquidCornerMaskLayer = CAShapeLayer()
    private let backdropCornerMaskLayer = CAShapeLayer()
    private let backdropBoostCornerMaskLayer = CAShapeLayer()
    private let fallbackCornerMaskLayer = CAShapeLayer()
    private var lastAppliedPrivateVariant: Int?
    private var lastAppliedPrivateScrim: Int?
    private var lastAppliedPrivateSubdued: Int?

    private var pendingAppearanceState: AppearanceState?
    private var lastAppliedAppearanceState: AppearanceState?
    private var isInLayoutPass = false
    private var isAppearanceApplyScheduled = false
    private var shouldApplyAfterLayoutPass = false
    private var lastBottomEdgeFrame: CGRect = .null
    private var currentCustomCornersEnabled = false
    private var currentCornerRadii = GlassTuningManager.CornerRadii.zero

    private static let privateVariantSelector = NSSelectorFromString("set_variant:")
    private static let privateScrimSelector = NSSelectorFromString("set_scrim:")
    private static let privateSubduedSelector = NSSelectorFromString("set_subdued:")

    override func loadView() {
        rootView.wantsLayer = true
        rootView.layer?.mask = nil

        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        fallbackView.wantsLayer = true
        fallbackView.isHidden = true

        edgeDecorationView.translatesAutoresizingMaskIntoConstraints = false
        edgeDecorationView.wantsLayer = true
        if let edgeLayer = edgeDecorationView.layer {
            edgeLayer.backgroundColor = NSColor.clear.cgColor
            edgeLayer.masksToBounds = false
            bottomShadowLayer.masksToBounds = false
            bottomShadowLayer.backgroundColor = NSColor.clear.cgColor
            edgeLayer.addSublayer(bottomShadowLayer)
            edgeLayer.addSublayer(bottomBorderLayer)
        }

        liquidGlassEffectView.translatesAutoresizingMaskIntoConstraints = false
        liquidGlassEffectView.wantsLayer = true
        liquidGlassEffectView.isHidden = true

        backdropEffectView.translatesAutoresizingMaskIntoConstraints = false
        backdropEffectView.wantsLayer = true
        backdropEffectView.state = .active
        backdropEffectView.material = .underWindowBackground
        backdropEffectView.blendingMode = .behindWindow
        backdropEffectView.isHidden = true

        backdropBoostEffectView.translatesAutoresizingMaskIntoConstraints = false
        backdropBoostEffectView.wantsLayer = true
        backdropBoostEffectView.state = .active
        backdropBoostEffectView.material = .underWindowBackground
        backdropBoostEffectView.blendingMode = .behindWindow
        backdropBoostEffectView.alphaValue = 0
        backdropBoostEffectView.isHidden = true

        rootView.addSubview(liquidGlassEffectView)
        rootView.addSubview(backdropEffectView)
        rootView.addSubview(backdropBoostEffectView)
        rootView.addSubview(edgeDecorationView)
        rootView.addSubview(fallbackView)

        NSLayoutConstraint.activate([
            liquidGlassEffectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            liquidGlassEffectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            liquidGlassEffectView.topAnchor.constraint(equalTo: rootView.topAnchor),
            liquidGlassEffectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            backdropEffectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            backdropEffectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            backdropEffectView.topAnchor.constraint(equalTo: rootView.topAnchor),
            backdropEffectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            backdropBoostEffectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            backdropBoostEffectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            backdropBoostEffectView.topAnchor.constraint(equalTo: rootView.topAnchor),
            backdropBoostEffectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            edgeDecorationView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            edgeDecorationView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            edgeDecorationView.topAnchor.constraint(equalTo: rootView.topAnchor),
            edgeDecorationView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            fallbackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            fallbackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            fallbackView.topAnchor.constraint(equalTo: rootView.topAnchor),
            fallbackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        view = rootView
    }

    override func viewWillLayout() {
        isInLayoutPass = true
        super.viewWillLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCornerMaskPathIfNeeded()
        layoutBottomEdgeLayers()
        isInLayoutPass = false

        if shouldApplyAfterLayoutPass {
            shouldApplyAfterLayoutPass = false
            scheduleCoalescedAppearanceApply()
        }
    }

    func updateAppearance(
        isDark: Bool,
        reduceTransparency: Bool,
        blurConfiguration: BlurStyleManager.Configuration,
        tintWhiteAlpha: Double,
        customCornersEnabled: Bool,
        cornerRadii: GlassTuningManager.CornerRadii
    ) {
        let newState = AppearanceState(
            isDark: isDark,
            reduceTransparency: reduceTransparency,
            blurConfiguration: blurConfiguration,
            tintWhiteAlpha: tintWhiteAlpha,
            customCornersEnabled: customCornersEnabled,
            cornerRadii: cornerRadii
        )

        if newState == lastAppliedAppearanceState, pendingAppearanceState == nil {
            return
        }

        pendingAppearanceState = newState
        scheduleCoalescedAppearanceApply()
    }

    private func scheduleCoalescedAppearanceApply() {
        guard !isAppearanceApplyScheduled else {
            return
        }

        isAppearanceApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isAppearanceApplyScheduled = false
            self.applyPendingAppearanceIfNeeded()
        }
    }

    private func applyPendingAppearanceIfNeeded() {
        guard isViewLoaded else {
            return
        }

        if isInLayoutPass {
            shouldApplyAfterLayoutPass = true
            return
        }

        guard let state = pendingAppearanceState else {
            return
        }

        pendingAppearanceState = nil
        if state == lastAppliedAppearanceState {
            return
        }
        lastAppliedAppearanceState = state

        currentCustomCornersEnabled = state.customCornersEnabled
        currentCornerRadii = Self.clampedCornerRadii(for: state.cornerRadii)
        updateCornerMaskPathIfNeeded()
        fallbackView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        if state.reduceTransparency {
            fallbackView.isHidden = false
            liquidGlassEffectView.isHidden = true
            backdropEffectView.isHidden = true
            backdropBoostEffectView.isHidden = true
            edgeDecorationView.isHidden = true
            return
        }

        fallbackView.isHidden = true
        edgeDecorationView.isHidden = false

        switch state.blurConfiguration.blurMode {
        case .liquidGlass:
            liquidGlassEffectView.isHidden = false
            backdropEffectView.isHidden = true
            backdropBoostEffectView.isHidden = true
            configureLiquidGlass(
                configuration: state.blurConfiguration,
                tintWhiteAlpha: state.tintWhiteAlpha
            )
        case .backdropBlur:
            liquidGlassEffectView.isHidden = true
            backdropEffectView.isHidden = false
            configureBackdropBlur(configuration: state.blurConfiguration)
        }

        configureEdgeDecoration(isDark: state.isDark, configuration: state.blurConfiguration)
    }

    private func configureLiquidGlass(
        configuration: BlurStyleManager.Configuration,
        tintWhiteAlpha: Double
    ) {
        let targetStyle: NSGlassEffectView.Style
        if configuration.variant.supportsStyleOverride {
            targetStyle = configuration.style == .clear ? .clear : .regular
        } else {
            targetStyle = .clear
        }
        var styleDidChange = false
        if liquidGlassEffectView.style != targetStyle {
            liquidGlassEffectView.style = targetStyle
            styleDidChange = true
        }

        // Private glass state can be reset by style mutation; force reapplication.
        if styleDidChange {
            lastAppliedPrivateVariant = nil
            lastAppliedPrivateScrim = nil
            lastAppliedPrivateSubdued = nil
        }

        if liquidGlassEffectView.alphaValue != 1 {
            liquidGlassEffectView.alphaValue = 1
        }

        applyPrivateIntProperty(selector: Self.privateVariantSelector, value: configuration.variant.rawValue, cache: &lastAppliedPrivateVariant)
        applyPrivateIntProperty(selector: Self.privateScrimSelector, value: configuration.scrim ? 1 : 0, cache: &lastAppliedPrivateScrim)
        applyPrivateIntProperty(selector: Self.privateSubduedSelector, value: configuration.subdued ? 1 : 0, cache: &lastAppliedPrivateSubdued)

        let targetTintColor = Self.liquidGlassTintColor(for: tintWhiteAlpha)
        if liquidGlassEffectView.tintColor != targetTintColor {
            liquidGlassEffectView.tintColor = targetTintColor
        }
    }

    private func configureBackdropBlur(configuration: BlurStyleManager.Configuration) {
        let targetMaterial = configuration.backdropMaterial.visualEffectMaterial
        if backdropEffectView.material != targetMaterial {
            backdropEffectView.material = targetMaterial
        }
        if backdropBoostEffectView.material != targetMaterial {
            backdropBoostEffectView.material = targetMaterial
        }

        let targetBlendMode = configuration.backdropBlendMode.visualEffectBlendMode
        if backdropEffectView.blendingMode != targetBlendMode {
            backdropEffectView.blendingMode = targetBlendMode
        }
        if backdropBoostEffectView.blendingMode != targetBlendMode {
            backdropBoostEffectView.blendingMode = targetBlendMode
        }

        if backdropEffectView.isEmphasized != configuration.backdropEmphasized {
            backdropEffectView.isEmphasized = configuration.backdropEmphasized
        }
        if backdropBoostEffectView.isEmphasized != configuration.backdropEmphasized {
            backdropBoostEffectView.isEmphasized = configuration.backdropEmphasized
        }

        if backdropEffectView.state != .active {
            backdropEffectView.state = .active
        }
        if backdropBoostEffectView.state != .active {
            backdropBoostEffectView.state = .active
        }

        let clampedIntensity = min(max(configuration.backdropIntensity, BlurStyleManager.minBackdropIntensity), BlurStyleManager.maxBackdropIntensity)
        let clampedAlpha = min(max(configuration.backdropAlpha, BlurStyleManager.minBackdropAlpha), BlurStyleManager.maxBackdropAlpha)

        // Two visual-effect passes: stronger blur feel while preserving live backdrop sampling.
        let primaryAlpha = min(max((0.45 + clampedIntensity * 0.55) * clampedAlpha, 0), 1)
        let boostAlpha = min(max((clampedIntensity - 0.35) * 0.9 * clampedAlpha, 0), 0.55)

        if backdropEffectView.alphaValue != primaryAlpha {
            backdropEffectView.alphaValue = primaryAlpha
        }
        if backdropBoostEffectView.alphaValue != boostAlpha {
            backdropBoostEffectView.alphaValue = boostAlpha
        }

        backdropEffectView.isHidden = primaryAlpha <= 0.001
        backdropBoostEffectView.isHidden = boostAlpha <= 0.001
    }

    private static func clampedCornerRadii(for radii: GlassTuningManager.CornerRadii) -> GlassTuningManager.CornerRadii {
        GlassTuningManager.CornerRadii(
            topLeft: min(max(radii.topLeft, GlassTuningManager.minCornerRadius), GlassTuningManager.maxCornerRadius),
            topRight: min(max(radii.topRight, GlassTuningManager.minCornerRadius), GlassTuningManager.maxCornerRadius),
            bottomLeft: min(max(radii.bottomLeft, GlassTuningManager.minCornerRadius), GlassTuningManager.maxCornerRadius),
            bottomRight: min(max(radii.bottomRight, GlassTuningManager.minCornerRadius), GlassTuningManager.maxCornerRadius)
        )
    }

    private func updateCornerMaskPathIfNeeded() {
        if !currentCustomCornersEnabled {
            rootView.layer?.mask = nil
            liquidGlassEffectView.layer?.mask = nil
            backdropEffectView.layer?.mask = nil
            backdropBoostEffectView.layer?.mask = nil
            fallbackView.layer?.mask = nil
            return
        }

        applyCornerMask(to: rootView, using: rootCornerMaskLayer)
        applyCornerMask(to: liquidGlassEffectView, using: liquidCornerMaskLayer)
        applyCornerMask(to: backdropEffectView, using: backdropCornerMaskLayer)
        applyCornerMask(to: backdropBoostEffectView, using: backdropBoostCornerMaskLayer)
        applyCornerMask(to: fallbackView, using: fallbackCornerMaskLayer)
    }

    private func applyCornerMask(to view: NSView, using maskLayer: CAShapeLayer) {
        guard let targetLayer = view.layer else {
            return
        }

        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        if targetLayer.mask !== maskLayer {
            targetLayer.mask = maskLayer
        }

        let yAxisDown = targetLayer.isGeometryFlipped
        maskLayer.isGeometryFlipped = yAxisDown
        maskLayer.frame = bounds
        maskLayer.path = Self.makeCornerMaskPath(in: bounds, radii: currentCornerRadii, yAxisDown: yAxisDown)
    }

    private static func makeCornerMaskPath(
        in rect: CGRect,
        radii: GlassTuningManager.CornerRadii,
        yAxisDown: Bool
    ) -> CGPath {
        // Treat the configured value as horizontal and vertical corner intent, then resolve
        // into a valid elliptical corner per side. This keeps top-corner adjustments visible
        // even on the thin menu bar height by allowing wide X reach while clamping Y depth.
        var topLeftX = min(max(CGFloat(radii.topLeft), 0), rect.width)
        var topRightX = min(max(CGFloat(radii.topRight), 0), rect.width)
        var bottomLeftX = min(max(CGFloat(radii.bottomLeft), 0), rect.width)
        var bottomRightX = min(max(CGFloat(radii.bottomRight), 0), rect.width)

        var topLeftY = min(max(CGFloat(radii.topLeft), 0), rect.height)
        var topRightY = min(max(CGFloat(radii.topRight), 0), rect.height)
        var bottomLeftY = min(max(CGFloat(radii.bottomLeft), 0), rect.height)
        var bottomRightY = min(max(CGFloat(radii.bottomRight), 0), rect.height)

        let topXScale = min(1, rect.width / max(topLeftX + topRightX, 0.001))
        topLeftX *= topXScale
        topRightX *= topXScale

        let bottomXScale = min(1, rect.width / max(bottomLeftX + bottomRightX, 0.001))
        bottomLeftX *= bottomXScale
        bottomRightX *= bottomXScale

        let leftYScale = min(1, rect.height / max(topLeftY + bottomLeftY, 0.001))
        topLeftY *= leftYScale
        bottomLeftY *= leftYScale

        let rightYScale = min(1, rect.height / max(topRightY + bottomRightY, 0.001))
        topRightY *= rightYScale
        bottomRightY *= rightYScale

        let topY = yAxisDown ? rect.minY : rect.maxY
        let bottomY = yAxisDown ? rect.maxY : rect.minY
        let yStep: CGFloat = yAxisDown ? 1 : -1

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + topLeftX, y: topY))
        path.addLine(to: CGPoint(x: rect.maxX - topRightX, y: topY))
        if topRightX > 0 || topRightY > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: topY + (yStep * topRightY)),
                control: CGPoint(x: rect.maxX, y: topY)
            )
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: bottomY - (yStep * bottomRightY)))
        if bottomRightX > 0 || bottomRightY > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - bottomRightX, y: bottomY),
                control: CGPoint(x: rect.maxX, y: bottomY)
            )
        }

        path.addLine(to: CGPoint(x: rect.minX + bottomLeftX, y: bottomY))
        if bottomLeftX > 0 || bottomLeftY > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: bottomY - (yStep * bottomLeftY)),
                control: CGPoint(x: rect.minX, y: bottomY)
            )
        }

        path.addLine(to: CGPoint(x: rect.minX, y: topY + (yStep * topLeftY)))
        if topLeftX > 0 || topLeftY > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + topLeftX, y: topY),
                control: CGPoint(x: rect.minX, y: topY)
            )
        }
        path.closeSubpath()
        return path
    }

    private func applyPrivateIntProperty(selector: Selector, value: Int, cache: inout Int?) {
        guard liquidGlassEffectView.responds(to: selector) else {
            return
        }

        guard cache != value else {
            return
        }

        guard let method = class_getInstanceMethod(NSGlassEffectView.self, selector) else {
            return
        }

        typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: Setter.self)
        function(liquidGlassEffectView, selector, value)
        cache = value
    }

    private static func liquidGlassTintColor(for signedTintStrength: Double) -> NSColor? {
        guard signedTintStrength != 0 else {
            return nil
        }

        let clampedStrength = min(max(signedTintStrength, GlassTuningManager.minTintWhiteAlpha), GlassTuningManager.maxTintWhiteAlpha)
        let tintAlpha = min(max(CGFloat(abs(clampedStrength)) * 0.10, 0), 0.24)
        let baseColor: NSColor = clampedStrength > 0 ? .white : .black
        return baseColor.withAlphaComponent(tintAlpha)
    }

    private func configureEdgeDecoration(isDark: Bool, configuration: BlurStyleManager.Configuration) {
        guard edgeDecorationView.layer != nil else {
            return
        }

        let borderAlpha: CGFloat
        let shadowAlpha: CGFloat
        let shadowRadius: CGFloat

        switch configuration.blurMode {
        case .liquidGlass:
            let baseStrength: CGFloat = configuration.style == .regular ? 1.15 : 1.0
            let scrimStrength: CGFloat = configuration.scrim ? 1.15 : 1.0
            borderAlpha = (isDark ? 0.10 : 0.12) * baseStrength
            shadowAlpha = (isDark ? 0.16 : 0.12) * scrimStrength
            shadowRadius = configuration.style == .regular ? 3.5 : 2.5
        case .backdropBlur:
            let emphasisStrength: CGFloat = configuration.backdropEmphasized ? 1.1 : 1.0
            borderAlpha = (isDark ? 0.09 : 0.11) * emphasisStrength
            shadowAlpha = (isDark ? 0.14 : 0.10) * emphasisStrength
            shadowRadius = 2.8
        }

        let borderBaseColor: NSColor = isDark ? .white : .black
        bottomBorderLayer.backgroundColor = borderBaseColor.withAlphaComponent(borderAlpha).cgColor
        bottomShadowLayer.shadowColor = NSColor.black.withAlphaComponent(shadowAlpha).cgColor
        bottomShadowLayer.shadowOpacity = 1
        bottomShadowLayer.shadowRadius = shadowRadius
        bottomShadowLayer.shadowOffset = CGSize(width: 0, height: -2)

        layoutBottomEdgeLayers()
    }

    private func layoutBottomEdgeLayers() {
        let bounds = edgeDecorationView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let onePixel = 1 / max(scale, 1)
        let edgeFrame = CGRect(x: 0, y: 0, width: bounds.width, height: onePixel)
        guard edgeFrame != lastBottomEdgeFrame else {
            return
        }
        lastBottomEdgeFrame = edgeFrame

        bottomBorderLayer.frame = edgeFrame
        bottomShadowLayer.frame = edgeFrame
        bottomShadowLayer.shadowPath = CGPath(rect: edgeFrame, transform: nil)
    }
}
