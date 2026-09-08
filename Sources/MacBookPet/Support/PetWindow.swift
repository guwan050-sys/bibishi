import AppKit

/// A tiny borderless `NSPanel` used as an overlay host for the catch-
/// game × exit button. It lives in its own window above `PetWindow`
/// so the button always draws and hit-tests correctly, independent
/// of how `NSHostingView` decides to layer its SwiftUI content. The
/// panel follows the parent window's position and only orders front
/// when the button is actually visible.
private final class ExitButtonPanel: NSPanel {
    let button: NSButton

    init() {
        button = NSButton(frame: .zero)
        button.title = ""
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.wantsLayer = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isHidden = true
        button.toolTip = "结束游戏"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .heavy)
        button.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "结束游戏"
        )?.withSymbolConfiguration(config)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 26, height: 26),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        contentView?.addSubview(button)
        button.frame = contentView?.bounds ?? .zero
        button.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetWindow: NSWindow {
    var physicsController: PetPhysicsController?
    var onRightClick: ((CGRect) -> Void)?
    /// Optional store reference so the AppKit-side × exit button can
    /// dismiss the catch game without relying on the SwiftUI hit-test
    /// path inside `NSHostingView` (which has proven unreliable for
    /// sub-30pt tap targets inside this window).
    weak var catchGameStore: CatchGameStore? {
        didSet { exitPanel.button.target = self; exitPanel.button.action = #selector(PetWindow.handleExitButtonClick(_:)) }
    }
    private let exitPanel = ExitButtonPanel()

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        title = "MacBook Pet"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // The exit-button panel is its own NSWindow and therefore does
        // not automatically follow this window when it moves. Re-align
        // it on every move / resize so the button stays glued to the
        // top-trailing corner while the pet is being dragged around.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameDidChange),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameDidChange),
            name: NSWindow.didResizeNotification,
            object: self
        )
    }

    @objc private func handleFrameDidChange() {
        guard !exitPanel.button.isHidden else { return }
        alignExitPanel()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    deinit {
        exitPanel.orderOut(nil)
    }

    // MARK: - Exit button (catch-game ×)

    /// Update the AppKit-side × button's appearance / visibility. Called
    /// from MacBookPetApp whenever the catch-game phase changes.
    func setExitButtonVisible(_ visible: Bool) {
        let button = exitPanel.button
        button.isHidden = !visible
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 13
        if visible {
            alignExitPanel()
            exitPanel.orderFrontRegardless()
        } else {
            exitPanel.orderOut(nil)
        }
    }

    private func alignExitPanel() {
        let size: CGFloat = 26
        let inset: CGFloat = 8
        // Position the overlay panel in screen coordinates so the
        // button sits in the parent window's top-trailing corner,
        // 8pt in from each edge. AppKit's window coords have the
        // origin at the screen's bottom-left.
        let parentTopRightScreen = NSPoint(
            x: frame.maxX - inset - size,
            y: frame.maxY - inset - size
        )
        exitPanel.setFrame(
            NSRect(origin: parentTopRightScreen, size: NSSize(width: size, height: size)),
            display: true
        )
    }

    @objc fileprivate func handleExitButtonClick(_ sender: NSButton) {
        catchGameStore?.dismiss()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if physicsController?.isUsingInputEventTap == true { break }
            physicsController?.beginDrag(with: event)
            return
        case .leftMouseDragged:
            if physicsController?.isUsingInputEventTap == true { break }
            physicsController?.updateDrag(with: event)
            return
        case .leftMouseUp:
            if physicsController?.isUsingInputEventTap == true { break }
            physicsController?.endDrag(with: event)
            return
        case .rightMouseDown:
            guard bodyInteractionBoundsInWindow.contains(event.locationInWindow) else { break }
            onRightClick?(bodyFrameInScreen)
            return
        default:
            break
        }

        super.sendEvent(event)
    }

    private var bodyFrameInScreen: CGRect {
        CGRect(
            x: frame.minX + PetMetrics.bodyInsetX,
            y: frame.minY + PetMetrics.bodyInsetY,
            width: PetMetrics.bodySize,
            height: PetMetrics.bodySize
        )
    }

    private var bodyInteractionBoundsInWindow: CGRect {
        PetMetrics.bodyBoundsInWindow.insetBy(
            dx: -PetMetrics.fileDropMargin,
            dy: -PetMetrics.fileDropMargin
        )
    }
}
