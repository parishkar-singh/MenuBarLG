import AppKit

@MainActor
final class GlassViewController: NSViewController {
    private struct AppearanceState: Equatable {
        let isDark: Bool
        let reduceTransparency: Bool
        let materialPreset: BlurStyleManager.MaterialPreset
        let presetTuning: GlassTuningManager.PresetTuning
    }

    private let rootView = NSView(frame: .zero)
    private let fallbackView = NSView(frame: .zero)
    private let tintOverlayView = NSView(frame: .zero)
    private let edgeDecorationView = NSView(frame: .zero)
    private let bottomBorderLayer = CALayer()
    private let bottomShadowLayer = CALayer()

    private let glassEffectView = NSGlassEffectView(frame: .zero)
    private let glassContentView = NSView(frame: .zero)

    // Coalesces rapid updates (theme/style/tuning changes) into a single main-runloop apply.
    private var pendingAppearanceState: AppearanceState?
    private var lastAppliedAppearanceState: AppearanceState?
    private var isInLayoutPass = false
    private var isAppearanceApplyScheduled = false
    private var shouldApplyAfterLayoutPass = false
    private var lastBottomEdgeFrame: CGRect = .null

    override func loadView() {
        // Fallback layer is only visible when Reduce Transparency is enabled.
        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        fallbackView.wantsLayer = true
        fallbackView.isHidden = true

        tintOverlayView.translatesAutoresizingMaskIntoConstraints = false
        tintOverlayView.wantsLayer = true
        tintOverlayView.isHidden = true

        edgeDecorationView.translatesAutoresizingMaskIntoConstraints = false
        edgeDecorationView.wantsLayer = true
        if let edgeLayer = edgeDecorationView.layer {
            edgeLayer.backgroundColor = NSColor.clear.cgColor
            edgeLayer.masksToBounds = false
            // Decoration layers draw only on the bottom edge to emulate Dock-style separation.
            bottomShadowLayer.masksToBounds = false
            bottomShadowLayer.backgroundColor = NSColor.clear.cgColor
            edgeLayer.addSublayer(bottomShadowLayer)
            edgeLayer.addSublayer(bottomBorderLayer)
        }

        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        glassEffectView.cornerRadius = 0
        glassEffectView.clipsToBounds = true
        glassEffectView.contentView = glassContentView

        rootView.addSubview(glassEffectView)
        rootView.addSubview(tintOverlayView)
        rootView.addSubview(edgeDecorationView)
        rootView.addSubview(fallbackView)

        NSLayoutConstraint.activate([
            glassEffectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            glassEffectView.topAnchor.constraint(equalTo: rootView.topAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            tintOverlayView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tintOverlayView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tintOverlayView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tintOverlayView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

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
        layoutBottomEdgeLayers()
        isInLayoutPass = false

        if shouldApplyAfterLayoutPass {
            shouldApplyAfterLayoutPass = false
            // Defer to the next runloop so AppKit is fully out of its layout recursion guards.
            scheduleCoalescedAppearanceApply()
        }
    }

    func updateAppearance(
        isDark: Bool,
        reduceTransparency: Bool,
        materialPreset: BlurStyleManager.MaterialPreset,
        presetTuning: GlassTuningManager.PresetTuning
    ) {
        let newState = AppearanceState(
            isDark: isDark,
            reduceTransparency: reduceTransparency,
            materialPreset: materialPreset,
            presetTuning: presetTuning
        )

        // Ignore no-op update requests to avoid unnecessary AppKit view/layer churn.
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

        if let fallbackLayer = fallbackView.layer {
            fallbackLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        if state.reduceTransparency {
            // Respect accessibility preference by replacing glass with an opaque system color.
            fallbackView.isHidden = false
            glassEffectView.isHidden = true
            tintOverlayView.isHidden = true
            edgeDecorationView.isHidden = true
            return
        }

        fallbackView.isHidden = true
        glassEffectView.isHidden = false
        edgeDecorationView.isHidden = false

        configureLiquidGlass(with: state.presetTuning)
        configureEdgeDecoration(isDark: state.isDark, materialPreset: state.materialPreset)
    }

    private func configureLiquidGlass(with tuning: GlassTuningManager.PresetTuning) {
        // The style/tint/alpha controls are intentionally narrow and map 1:1 to NSGlassEffectView.
        if glassEffectView.cornerRadius != 0 {
            glassEffectView.cornerRadius = 0
        }

        let targetAlpha = CGFloat(tuning.alphaValue)
        if glassEffectView.alphaValue != targetAlpha {
            glassEffectView.alphaValue = targetAlpha
        }

        let targetStyle: NSGlassEffectView.Style = tuning.style == "regular" ? .regular : .clear
        if glassEffectView.style != targetStyle {
            glassEffectView.style = targetStyle
        }

        tintOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        tintOverlayView.isHidden = true

        if tuning.tintWhiteAlpha > 0 {
            let targetTint = NSColor.white.withAlphaComponent(CGFloat(tuning.tintWhiteAlpha))
            if glassEffectView.tintColor != targetTint {
                glassEffectView.tintColor = targetTint
            }
        } else if tuning.tintWhiteAlpha < 0 {
            // NSGlassEffectView tint can skew bright on some systems; use an explicit overlay for black tint.
            if glassEffectView.tintColor != nil {
                glassEffectView.tintColor = nil
            }
            tintOverlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(-tuning.tintWhiteAlpha)).cgColor
            tintOverlayView.isHidden = false
        } else {
            if glassEffectView.tintColor != nil {
                glassEffectView.tintColor = nil
            }
        }
    }

    private func configureEdgeDecoration(isDark: Bool, materialPreset: BlurStyleManager.MaterialPreset) {
        guard edgeDecorationView.layer != nil else {
            return
        }

        let borderAlpha: CGFloat
        let shadowAlpha: CGFloat
        let shadowRadius: CGFloat

        switch (materialPreset, isDark) {
        case (.moreLiquid, true):
            borderAlpha = 0.08
            shadowAlpha = 0.14
            shadowRadius = 2
        case (.moreLiquid, false):
            borderAlpha = 0.10
            shadowAlpha = 0.10
            shadowRadius = 2
        case (.normal, true):
            borderAlpha = 0.12
            shadowAlpha = 0.20
            shadowRadius = 3
        case (.normal, false):
            borderAlpha = 0.14
            shadowAlpha = 0.14
            shadowRadius = 3
        case (.frosted, true):
            borderAlpha = 0.10
            shadowAlpha = 0.16
            shadowRadius = 4
        case (.frosted, false):
            borderAlpha = 0.18
            shadowAlpha = 0.12
            shadowRadius = 4
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

        // Keep border width pixel-perfect on all display scales to avoid blurry seams.
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
