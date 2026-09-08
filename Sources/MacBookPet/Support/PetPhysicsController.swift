import AppKit

enum PetPhysicsRefreshMode: Equatable {
    case active
    case resting

    var interval: TimeInterval {
        switch self {
        case .active:
            1.0 / 60.0
        case .resting:
            1.0 / 5.0
        }
    }

    var tolerance: TimeInterval {
        switch self {
        case .active:
            0
        case .resting:
            0.04
        }
    }
}

enum PetPhysicsRefreshPolicy {
    static let mouseWakeDistance: CGFloat = 330

    static func mode(
        isResting: Bool,
        isDragging: Bool,
        mouseDistance: CGFloat
    ) -> PetPhysicsRefreshMode {
        if isDragging || !isResting || mouseDistance <= mouseWakeDistance {
            return .active
        }
        return .resting
    }
}

@MainActor
final class PetPhysicsController {
    private static let dragActivationDistance: CGFloat = 5

    private weak var window: NSWindow?
    private let motionState: PetMotionState

    private var timer: Timer?
    private var inputEventTap: CFMachPort?
    private var inputEventRunLoopSource: CFRunLoopSource?
    private var localRightClickMonitor: Any?
    private var globalRightClickMonitor: Any?
    private var lastStepTime = ProcessInfo.processInfo.systemUptime
    private var lastGazeUpdateTime = ProcessInfo.processInfo.systemUptime
    private var refreshMode = PetPhysicsRefreshMode.active

    private var position: CGPoint
    private var velocity = CGVector(dx: 0, dy: 0)

    private var dragAnchorInWindow: CGPoint?
    private var dragTargetOrigin: CGPoint?
    private var dragStartMouse: CGPoint?
    private var lastDragMouse: CGPoint?
    private var lastDragTime: TimeInterval?
    private var dragMouseVelocity = CGVector(dx: 0, dy: 0)
    private var flingVelocity = CGVector(dx: 0, dy: 0)
    private var flingVelocityTime: TimeInterval?
    private var maxDragDistance: CGFloat = 0
    private var hasTriggeredGrabReaction = false
    private var isTrackingInputTapDrag = false
    /// Cached catch-game floor y in screen-coordinates, recomputed
    /// every `step()` from the active screen frame. Used by the click
    /// handler so it can pass the right `catchLineY` to the game store.
    private var lastCatchLineY: CGFloat?
    /// System uptime at which the catch-game floor check is allowed
    /// to fire again. Without this grace period, the small opening
    /// kick places the cube close to the floor — the very first
    /// `step()` after `beginCatchGame()` would land the cube and
    /// immediately re-trigger `gameOver()`, making the "再来一局"
    /// button look broken.
    private var catchGameGraceUntil: TimeInterval = 0

    var onClick: (() -> Void)?
    var onRightClick: ((CGRect) -> Void)?
    var onGrab: (() -> Void)?
    var onLand: (() -> Void)?
    /// 工作气泡（待办提醒 / 番茄钟倒计时 / 专注喝咖啡…）的整块可点区域
    /// 被点下时调。taskID 用来区分待办气泡（带 taskID）和普通工作气泡
    /// （nil）——调用方根据这个决定弹哪个窗口。
    /// 不走 NSHostingView 的 SwiftUI hit-testing（之前在 PetView 注释里
    /// 提过 sub-30pt 目标经常被 NSHostingView 抢走事件），所以由物理
    /// 控制器自己识别并直接 fire 回调。
    var onBubbleClick: ((UUID?) -> Void)?
    /// When wired up, the controller routes clicks and floor touches
    /// through the catch-game store instead of the default pet click
    /// reaction. See `Sources/MacBookPet/Stores/CatchGameStore.swift`.
    var catchGameStore: CatchGameStore?
    var isMouseGazeEnabled: (() -> Bool)?
    var isBottomPetEnabled: (() -> Bool)?
    var isGravityEnabled: (() -> Bool)?
    var isUsingInputEventTap: Bool {
        inputEventTap != nil
    }
    /// 当前 leftMouseDown 是否落在工作气泡上。endDrag 看到这个标记会
    /// 跳过桌宠的 onClick 反应，改调 onBubbleClick。
    private var isMouseDownOnBubble = false

    init(window: NSWindow, motionState: PetMotionState) {
        self.window = window
        self.motionState = motionState
        self.position = window.frame.origin
    }

    func start() {
        scheduleTimer(for: .active)
        // TEMP: skip the CGEvent tap so the PetWindow.sendEvent path is the
        // sole route for left clicks. The tap was injecting coordinates that
        // failed the window hit test on this retina display. We can revisit
        // and re-enable once the conversion is bullet-proof.
        // startInputEventTap()
        startRightClickEventMonitors()
    }

    /// Catch-game entry: give the cube a generous upward kick so
    /// the player has a moment to click before it falls back. Called
    /// when `catchGameStore` transitions to `.playing`. Also starts
    /// a 0.5s grace period during which the floor check is suppressed
    /// — without it, the first post-kick `step()` would re-fire
    /// `gameOver()` immediately and the "再来一局" button would
    /// look broken.
    func beginCatchGame() {
        velocity.dx = 0
        velocity.dy = 900
        dragTargetOrigin = nil
        dragAnchorInWindow = nil
        flingVelocity = CGVector(dx: 0, dy: 0)
        catchGameGraceUntil = ProcessInfo.processInfo.systemUptime + 0.5
    }

    /// Catch-game exit: clear any in-flight kick / fling and let the
    /// normal physics take over again. Called when the store moves
    /// to `.idle` or `.gameOver`.
    func endCatchGame() {
        velocity.dx = 0
        velocity.dy = 0
        dragTargetOrigin = nil
    }

    private func scheduleTimer(for mode: PetPhysicsRefreshMode) {
        timer?.invalidate()
        refreshMode = mode
        lastStepTime = ProcessInfo.processInfo.systemUptime

        let timer = Timer(timeInterval: mode.interval, repeats: true) { [weak self] _ in
            // The timer is explicitly attached to RunLoop.main below, so stepping
            // synchronously avoids allocating a new task for every physics frame.
            MainActor.assumeIsolated {
                self?.step()
            }
        }
        timer.tolerance = mode.tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setRefreshMode(_ mode: PetPhysicsRefreshMode) {
        guard mode != refreshMode else { return }
        scheduleTimer(for: mode)
    }

    func beginDrag(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        beginDrag(mouse: mouse, anchorInWindow: event.locationInWindow, timestamp: event.timestamp)
    }

    func updateDrag(with event: NSEvent) {
        updateDrag(mouse: NSEvent.mouseLocation, timestamp: event.timestamp)
    }

    func endDrag(with event: NSEvent) {
        endDrag(timestamp: event.timestamp)
    }

    /// 本次左键落下点是否落在桌宠头顶的工作气泡上（待办提醒 / 番茄钟倒计时
    /// 等）。beginDrag 用它来跳过拖拽 setup、记下 isMouseDownOnBubble；
    /// endDrag 看到标记会 fire `onBubbleClick(taskID)`，由调用方决定
    /// 弹哪个窗口（待办气泡 = 弹待办；普通工作气泡 = 弹番茄钟）。
    /// 不走 NSHostingView 的 SwiftUI hit-testing 路径（sub-30pt 目标
    /// 经常被 NSHostingView 抢走，参见 PetView.swift 注释）。
    func isClickOnWorkingBubble(at windowPoint: CGPoint) -> Bool {
        guard let frame = motionState.bubbleHitTestFrame else { return false }
        return frame.contains(windowPoint)
    }

    func handleInputEventTap(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let inputEventTap {
                CGEvent.tapEnable(tap: inputEventTap, enable: true)
            }
            return
        }

        let mouse = appKitMouseLocation(from: event)
        let timestamp = TimeInterval(event.timestamp) / 1_000_000_000

        switch type {
        case .leftMouseDown:
            // Accept any click within the window (not just the body) so the
            // user can grab the pet from anywhere on the canvas. The body
            // just follows the cursor during drag.
            guard let window, window.frame.contains(mouse) else { return }

            isTrackingInputTapDrag = true
            let anchor = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
            beginDrag(mouse: mouse, anchorInWindow: anchor, timestamp: timestamp)
        case .leftMouseDragged:
            guard isTrackingInputTapDrag else { return }
            updateDrag(mouse: mouse, timestamp: timestamp)
        case .leftMouseUp:
            guard isTrackingInputTapDrag else { return }
            isTrackingInputTapDrag = false
            endDrag(timestamp: timestamp)
        default:
            break
        }
    }

    private func beginDrag(mouse: CGPoint, anchorInWindow: CGPoint, timestamp: TimeInterval) {
        let locationInWindow = anchorInWindow
        // Accept any click inside the window so the user can grab the pet
        // from anywhere on the canvas — the 76×76 body is too small a target
        // to reliably hit otherwise. `locationInWindow` is in *window-local*
        // coordinates (origin at the window's bottom-left, ranges 0…width ×
        // 0…height), so compare against a rect with the same origin and size.
        guard let window,
              locationInWindow.x >= 0,
              locationInWindow.x <= window.frame.width,
              locationInWindow.y >= 0,
              locationInWindow.y <= window.frame.height
        else { return }

        // 工作气泡上的点击：跳过整个拖拽 setup，不让桌宠被抓起 / 触发
        // onClick 笑一下——只记下标记，endDrag 会拿它去 fire onBubbleClick。
        if isClickOnWorkingBubble(at: locationInWindow) {
            isMouseDownOnBubble = true
            return
        }
        isMouseDownOnBubble = false

        setRefreshMode(.active)

        dragAnchorInWindow = locationInWindow
        dragTargetOrigin = CGPoint(x: mouse.x - locationInWindow.x, y: mouse.y - locationInWindow.y)
        dragStartMouse = mouse
        lastDragMouse = mouse
        lastDragTime = timestamp
        dragMouseVelocity = CGVector(dx: 0, dy: 0)
        flingVelocity = CGVector(dx: 0, dy: 0)
        flingVelocityTime = nil
        maxDragDistance = 0
        hasTriggeredGrabReaction = false

        motionState.isGrabbed = true
        setGazeOffset(.zero)
    }

    private func updateDrag(mouse: CGPoint, timestamp: TimeInterval) {
        guard let dragAnchorInWindow else { return }

        dragTargetOrigin = CGPoint(x: mouse.x - dragAnchorInWindow.x, y: mouse.y - dragAnchorInWindow.y)

        let now = timestamp
        if let lastDragMouse, let lastDragTime {
            let dt = CGFloat(now - lastDragTime)
            if dt > 0.001 {
                let instantVelocity = CGVector(
                    dx: (mouse.x - lastDragMouse.x) / dt,
                    dy: (mouse.y - lastDragMouse.y) / dt
                )
                dragMouseVelocity.dx = dragMouseVelocity.dx * 0.28 + instantVelocity.dx * 0.72
                dragMouseVelocity.dy = dragMouseVelocity.dy * 0.28 + instantVelocity.dy * 0.72
                recordFlingVelocity(instantVelocity, at: now)
            }
        }
        lastDragMouse = mouse
        lastDragTime = now

        if let dragStartMouse {
            maxDragDistance = Swift.max(maxDragDistance, mouse.distance(to: dragStartMouse))
        }

        if !hasTriggeredGrabReaction, maxDragDistance >= Self.dragActivationDistance {
            hasTriggeredGrabReaction = true
            onGrab?()
        }
    }

    private func endDrag(timestamp: TimeInterval) {
        // 落在工作气泡上的点击 → 调 onBubbleClick 让对应窗口弹出，
        // 走完就 return，不进入下面的桌宠 onClick / 拖拽释放分支。
        if isMouseDownOnBubble {
            isMouseDownOnBubble = false
            onBubbleClick?(motionState.workingBubble?.taskID)
            return
        }

        let wasClick = maxDragDistance < Self.dragActivationDistance
        let releaseVelocity = releaseVelocity(at: timestamp)
        dragAnchorInWindow = nil
        dragTargetOrigin = nil
        dragStartMouse = nil
        lastDragMouse = nil
        lastDragTime = nil
        dragMouseVelocity = CGVector(dx: 0, dy: 0)
        flingVelocity = CGVector(dx: 0, dy: 0)
        flingVelocityTime = nil
        maxDragDistance = 0
        hasTriggeredGrabReaction = false

        motionState.isGrabbed = false

        if wasClick {
            // Catch-game mode: route the click to the score store and
            // give the cube a fresh upward kick instead of the normal
            // pet click reaction (so we don't trigger happy speech /
            // grab at the same time). One click = one point, no
            // height bonus — the only thing that matters is whether
            // the player kept the cube airborne.
            if let cgStore = catchGameStore, cgStore.isActive {
                if cgStore.phase == .gameOver {
                    // Click anywhere on the cube / pet window also
                    // restarts — gives the player a fallback in case
                    // the SwiftUI overlay didn't capture the tap.
                    cgStore.restart()
                } else {
                    cgStore.recordCatch()
                    velocity.dx = 0
                    velocity.dy = 360
                }
            } else {
                velocity.dx *= 0.25
                velocity.dy *= 0.25
                onClick?()
            }
        } else if isGravityEnabled?() != true {
            velocity = CGVector(dx: 0, dy: 0)
            // With gravity disabled, releasing a drag is the hover-mode
            // equivalent of landing, so the scared grab expression can reset.
            onLand?()
        } else if isBottomPetEnabled?() == true {
            velocity = CGVector(dx: 0, dy: 0)
        } else {
            velocity.dx = releaseVelocity.dx * 1.08
            velocity.dy = releaseVelocity.dy * 1.08
            // Catch-game mode: a drag-release (toss) also counts as a
            // catch — gives the player another way to "丢起来" beyond
            // tapping the cube. Also clamp velocity.dy to at least
            // the same kick the tap path uses, otherwise a sideways
            // or downward toss would carry the cube straight into
            // the catch line and trigger an instant game-over.
            if let cgStore = catchGameStore, cgStore.phase == .playing {
                cgStore.recordCatch()
                velocity.dy = max(velocity.dy, 360)
            }
        }
    }

    private func startInputEventTap() {
        guard inputEventTap == nil else { return }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        let mask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: petInputEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        inputEventTap = tap
        inputEventRunLoopSource = source
    }

    private func startRightClickEventMonitors() {
        guard localRightClickMonitor == nil, globalRightClickMonitor == nil else { return }

        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.handleRightClickEvent(event)
            }
            return event
        }
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.handleRightClickEvent(event)
            }
        }
    }

    private func handleRightClickEvent(_ event: NSEvent) {
        guard let window else { return }
        let mouse = screenPoint(for: event)
        guard bodyInteractionFrame(for: window).contains(mouse) else { return }
        onRightClick?(bodyFrame(for: window))
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        if let eventWindow = event.window {
            return eventWindow.convertPoint(toScreen: event.locationInWindow)
        }

        return NSEvent.mouseLocation
    }

    private func appKitMouseLocation(from event: CGEvent) -> CGPoint {
        let quartzPoint = event.location
        // `event.location` is in display *pixels*; everything AppKit (NSScreen,
        // NSWindow.frame, our bodyFrame) is in *points*. Convert to points
        // first, then do the Y-flip, otherwise every click on a retina
        // display resolves to a coordinate outside the pet's window and
        // drag never starts.
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let maxScreenY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(
            x: quartzPoint.x / scale,
            y: maxScreenY - quartzPoint.y / scale
        )
    }

    private func recordFlingVelocity(_ candidate: CGVector, at time: TimeInterval) {
        let candidateSpeed = candidate.speed
        let currentSpeed = flingVelocity.speed

        if candidateSpeed > currentSpeed * 0.72 || flingVelocityTime == nil {
            flingVelocity = candidate
            flingVelocityTime = time
        }
    }

    private func releaseVelocity(at time: TimeInterval) -> CGVector {
        if let flingVelocityTime, time - flingVelocityTime <= 0.18, flingVelocity.speed > dragMouseVelocity.speed {
            return flingVelocity
        }

        if dragMouseVelocity.speed > 40 {
            return dragMouseVelocity
        }

        return velocity
    }

    private func step() {
        guard let window else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(now - lastStepTime, 1.0 / 120.0), 1.0 / 30.0)
        lastStepTime = now

        position = window.frame.origin

        let bottomPetEnabled = isBottomPetEnabled?() == true
        let gravityEnabled = isGravityEnabled?() ?? true
        if let dragTargetOrigin {
            // 拖拽期间直接定位到鼠标目标（忽略弹簧 + 重力），
            // 让身体精确跟随鼠标，并可以穿越到鼠标所在的拓展屏。
            // Fling 速度仍在 updateDrag 里独立记录，释放时不受影响。
            position = CGPoint(
                x: dragTargetOrigin.x,
                y: bottomPetEnabled ? position.y : dragTargetOrigin.y
            )
            velocity = CGVector(dx: 0, dy: 0)
        } else if gravityEnabled {
            let acceleration = CGVector(dx: 0, dy: -1_850)
            velocity.dx *= pow(0.994, dt * 60)
            velocity.dx += acceleration.dx * dt
            velocity.dy += acceleration.dy * dt
        } else {
            velocity = CGVector(dx: 0, dy: 0)
        }

        let maxSpeed = CGFloat(2_900)
        velocity.dx = velocity.dx.clamped(to: -maxSpeed...maxSpeed)
        velocity.dy = velocity.dy.clamped(to: -maxSpeed...maxSpeed)

        position.x += velocity.dx * dt
        position.y += velocity.dy * dt

        let bodySize = CGSize(width: PetMetrics.bodySize, height: PetMetrics.bodySize)
        let bodyPosition = CGPoint(
            x: position.x + PetMetrics.bodyInsetX,
            y: position.y + PetMetrics.bodyInsetY
        )
        let screenFrame = activeScreenFrame(for: bodyPosition, bodySize: bodySize)
        lastCatchLineY = screenFrame.minY + 4 + bodySize.height / 2
        let adjustedBodyPosition = collide(
            bodyPosition: bodyPosition,
            in: screenFrame,
            bodySize: bodySize
        )
        position = CGPoint(
            x: adjustedBodyPosition.position.x - PetMetrics.bodyInsetX,
            y: adjustedBodyPosition.position.y - PetMetrics.bodyInsetY
        )

        // Catch-game mode: if the cube reaches the floor line while
        // moving downward, end the game instead of bouncing. The
        // grace period covers the first half-second after a fresh
        // kick so the cube has time to climb before the floor check
        // is allowed to fire.
        if let cgStore = catchGameStore, cgStore.isActive,
           ProcessInfo.processInfo.systemUptime >= catchGameGraceUntil {
            let bodyCenterY = adjustedBodyPosition.position.y + bodySize.height / 2
            if bodyCenterY <= (lastCatchLineY ?? -CGFloat.greatestFiniteMagnitude) && velocity.dy < -50 {
                cgStore.gameOver()
                velocity.dy = 0
            }
        }

        if window.frame.origin.distance(to: position) > 0.01 {
            window.setFrameOrigin(position)
        }
        updateMouseEventPassthrough(for: window)
        updateMotionState()

        if adjustedBodyPosition.landed {
            onLand?()
        }

        updateMouseGaze(now: now)
        updateRefreshMode(
            gravityEnabled: gravityEnabled,
            screenFrame: screenFrame,
            adjustedBodyPosition: adjustedBodyPosition.position
        )
    }

    private func updateRefreshMode(
        gravityEnabled: Bool,
        screenFrame: CGRect,
        adjustedBodyPosition: CGPoint
    ) {
        let isOnFloor = abs(adjustedBodyPosition.y - screenFrame.minY) <= 0.5
        let isResting = dragTargetOrigin == nil
            && velocity.speed < 0.5
            && (!gravityEnabled || isOnFloor)
        let bodyCenter = CGPoint(
            x: position.x + PetMetrics.bodyInsetX + PetMetrics.bodySize / 2,
            y: position.y + PetMetrics.bodyInsetY + PetMetrics.bodySize / 2
        )
        let mode = PetPhysicsRefreshPolicy.mode(
            isResting: isResting,
            isDragging: motionState.isGrabbed,
            mouseDistance: bodyCenter.distance(to: NSEvent.mouseLocation)
        )
        setRefreshMode(mode)
    }

    private func updateMouseEventPassthrough(for window: NSWindow) {
        let interactionFrame = bodyFrame(for: window).insetBy(
            dx: -PetMetrics.fileDropMargin,
            dy: -PetMetrics.fileDropMargin
        )
        let shouldReceiveMouseEvents = motionState.isGrabbed || interactionFrame.contains(NSEvent.mouseLocation)
        let shouldIgnoreMouseEvents = !shouldReceiveMouseEvents

        if window.ignoresMouseEvents != shouldIgnoreMouseEvents {
            window.ignoresMouseEvents = shouldIgnoreMouseEvents
        }

        if shouldIgnoreMouseEvents, motionState.feedMouthOpen != 0 {
            motionState.feedMouthOpen = 0
        }
    }

    private func collide(bodyPosition: CGPoint, in bounds: CGRect, bodySize: CGSize) -> (position: CGPoint, landed: Bool) {
        let restitution = CGFloat(0.46)
        let floorFriction = CGFloat(0.72)
        let minX = bounds.minX
        let maxX = bounds.maxX - bodySize.width
        let minY = bounds.minY
        let maxY = bounds.maxY - bodySize.height
        var bodyPosition = bodyPosition
        var landed = false

        if bodyPosition.x < minX {
            bodyPosition.x = minX
            velocity.dx = abs(velocity.dx) * restitution
        } else if bodyPosition.x > maxX {
            bodyPosition.x = maxX
            velocity.dx = -abs(velocity.dx) * restitution
        }

        if bodyPosition.y < minY {
            bodyPosition.y = minY
            landed = velocity.dy < -120
            velocity.dy = abs(velocity.dy) * restitution
            velocity.dx *= floorFriction

            if abs(velocity.dy) < 55 {
                velocity.dy = 0
            }
            if abs(velocity.dx) < 8 {
                velocity.dx = 0
            }
        } else if bodyPosition.y > maxY {
            bodyPosition.y = maxY
            velocity.dy = -abs(velocity.dy) * restitution
        }

        return (bodyPosition, landed)
    }

    private func updateMotionState() {
        let speed = hypot(velocity.dx, velocity.dy)
        let targetRotation = (velocity.dx / 62).clamped(to: -13...13)
        let stretch = (speed / 2_600).clamped(to: 0...0.12)

        motionState.updateMotionTransform(
            rotationDegrees: targetRotation,
            stretchX: 1 + stretch,
            stretchY: 1 - stretch * 0.55
        )
    }

    private func updateMouseGaze(now: TimeInterval) {
        guard now - lastGazeUpdateTime >= 1.0 / 30.0 else { return }
        lastGazeUpdateTime = now

        guard isMouseGazeEnabled?() == true, !motionState.isGrabbed else {
            setGazeOffset(.zero)
            return
        }

        let mouse = NSEvent.mouseLocation
        let bodyCenter = CGPoint(
            x: position.x + PetMetrics.bodyInsetX + PetMetrics.bodySize / 2,
            y: position.y + PetMetrics.bodyInsetY + PetMetrics.bodySize / 2
        )
        let dx = mouse.x - bodyCenter.x
        let dy = mouse.y - bodyCenter.y
        let distance = hypot(dx, dy)
        let gazeRange = PetPhysicsRefreshPolicy.mouseWakeDistance

        guard distance > 1, distance <= gazeRange else {
            setGazeOffset(.zero)
            return
        }

        let maxOffset = CGFloat(5.4)
        let strength = (distance / 90).clamped(to: 0...1)
        let target = CGSize(
            width: dx / distance * maxOffset * strength,
            height: -dy / distance * maxOffset * 0.65 * strength
        )
        setGazeOffset(target)
    }

    private func setGazeOffset(_ target: CGSize) {
        guard motionState.gazeOffset.distance(to: target) > 0.2 else { return }
        motionState.gazeOffset = target
    }

    private func activeScreenFrame(for origin: CGPoint, bodySize: CGSize) -> CGRect {
        let bodyCenter = CGPoint(x: origin.x + bodySize.width / 2, y: origin.y + bodySize.height / 2)

        // 找**最近**的屏，而不是 first(where: contains)：
        // contains 在屏间空隙 / 屏边缘 / multi-monitor 坐标错位时会返
        // 回 nil 并 fallback 到 NSScreen.main（主屏），导致副屏的 body
        // 被错误 clamp 到主屏的 visibleFrame —— 表现为 cube 偶尔掉到
        // 拓展屏底部的菜单栏 / Dock 后面。
        let activeScreen: NSScreen? = NSScreen.screens.min { lhs, rhs in
            distance(bodyCenter, screenCenter(lhs)) < distance(bodyCenter, screenCenter(rhs))
        } ?? NSScreen.main

        guard let screen = activeScreen else {
            return CGRect(x: 0, y: 0, width: 1280, height: 900)
        }

        // visibleFrame 边缘紧贴菜单栏 / Dock 时，落到 minY 的 body
        // 底边会有一两像素被遮。留 4pt buffer 让 cube 离系统 UI 远
        // 一点 —— 同时也作为 multi-monitor visibleFrame 计算偶发不
        // 准时的安全余量。
        return screen.visibleFrame.insetBy(dx: 0, dy: 4)
    }

    private func screenCenter(_ screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private var bodyBoundsInWindow: CGRect {
        PetMetrics.bodyBoundsInWindow
    }

    private func bodyFrame(for window: NSWindow) -> CGRect {
        CGRect(
            x: window.frame.minX + PetMetrics.bodyInsetX,
            y: window.frame.minY + PetMetrics.bodyInsetY,
            width: PetMetrics.bodySize,
            height: PetMetrics.bodySize
        )
    }

    private func bodyInteractionFrame(for window: NSWindow) -> CGRect {
        bodyFrame(for: window).insetBy(
            dx: -PetMetrics.fileDropMargin,
            dy: -PetMetrics.fileDropMargin
        )
    }

    deinit {
        timer?.invalidate()
        if let localRightClickMonitor {
            NSEvent.removeMonitor(localRightClickMonitor)
        }
        if let globalRightClickMonitor {
            NSEvent.removeMonitor(globalRightClickMonitor)
        }
        if let inputEventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), inputEventRunLoopSource, .commonModes)
        }
        if let inputEventTap {
            CFMachPortInvalidate(inputEventTap)
        }
    }
}

private func petInputEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<PetPhysicsController>.fromOpaque(userInfo).takeUnretainedValue()
    let eventCopy = event.copy() ?? event

    Task { @MainActor in
        controller.handleInputEventTap(type: type, event: eventCopy)
    }

    return Unmanaged.passUnretained(event)
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension CGSize {
    func distance(to other: CGSize) -> CGFloat {
        hypot(width - other.width, height - other.height)
    }
}

private extension CGVector {
    var speed: CGFloat {
        hypot(dx, dy)
    }
}
