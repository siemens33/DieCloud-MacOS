import AppKit
import QuartzCore

/// Кнопка тулбара: в покое полупрозрачная, при наведении проявляется
/// и подсвечивается мягкой круглой пилюлей.
final class ToolbarButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let idleAlpha: CGFloat = 0.6
    private let idleDisabledAlpha: CGFloat = 0.22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        alphaValue = idleAlpha
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
        alphaValue = isEnabled ? idleAlpha : idleDisabledAlpha
        setHoverBackground(false)
    }

    override func mouseEntered(with event: NSEvent) {
        animateAlpha(to: isEnabled ? 1 : idleDisabledAlpha)
        setHoverBackground(isEnabled)
    }

    override func mouseExited(with event: NSEvent) {
        animateAlpha(to: isEnabled ? idleAlpha : idleDisabledAlpha)
        setHoverBackground(false)
    }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            animateAlpha(to: isEnabled ? idleAlpha : idleDisabledAlpha)
            if !isEnabled { setHoverBackground(false) }
        }
    }

    private func setHoverBackground(_ visible: Bool) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        layer.backgroundColor = visible
            ? NSColor.white.withAlphaComponent(0.09).cgColor
            : NSColor.clear.cgColor
        CATransaction.commit()
    }

    private func animateAlpha(to value: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = value
        }
    }
}
