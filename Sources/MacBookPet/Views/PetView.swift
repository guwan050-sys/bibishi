import SwiftUI

private struct ActiveActionPlayback: Equatable {
    let assetID: String
    let state: PetVisualState
}

struct PetView: View {
    @ObservedObject var state: PetState
    @ObservedObject var motionState: PetMotionState
    @ObservedObject var hungerStore: PetHungerStore
    @ObservedObject var inventoryStore: PetInventoryStore
    @ObservedObject var appearanceSettings: PetAppearanceSettings
    @ObservedObject var customizationStore: PetCustomizationStore
    @ObservedObject var languageSettings: LanguageSettings
    @ObservedObject var speechStore: PetSpeechLineStore
    @ObservedObject var travelStore: TravelStore
    @ObservedObject var catchGameStore: CatchGameStore
    var pomodoroStore: PomodoroStore? = nil
    var onOpenPomodoro: (() -> Void)? = nil
    /// 待办气泡整个可点时调这个（弹开待办窗口）。
    /// 用户在待办窗口里完成/删除对应任务，MacBookPetApp 监听 tasks 变化自动清气泡。
    var onShowTodoReminder: (() -> Void)? = nil

    @State private var isPressed = false
    @State private var activeActionPlayback: ActiveActionPlayback?
    @State private var actionPlaybackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if needsTimelineUpdates {
                TimelineView(.animation) { timeline in
                    petContent(at: timeline.date)
                }
            } else {
                petContent(at: .now)
            }
        }
        .overlay(alignment: .topLeading) {
            if catchGameStore.isActive {
                CatchGameHUD(store: catchGameStore)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
        // × exit button is implemented as an `NSButton` in
        // `PetWindow` (see `setExitButtonVisible`) because SwiftUI
        // hit-testing inside the NSHostingView has proven
        // unreliable for sub-30pt tap targets while the cube is
        // competing for mouse events.
        .overlay {
            if catchGameStore.phase == .gameOver {
                CatchGameOverOverlay(store: catchGameStore)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onChange(of: state.expression) { _, expression in
            if expression == .happy {
                pulse()
            }
        }
        .onAppear(perform: restartActionPlaybackLoop)
        .onDisappear {
            actionPlaybackTask?.cancel()
            actionPlaybackTask = nil
        }
        .onChange(of: activeVisualConfiguration) { _, _ in
            restartActionPlaybackLoop()
        }
        .frame(width: PetMetrics.canvasWidth, height: PetMetrics.canvasHeight)
    }

    private var needsTimelineUpdates: Bool {
        if case .sleeping = visualExpression { return true }
        if case .listening = visualExpression { return true }
        // 番茄钟在跑时需要每秒刷一次让倒计时气泡实时更新
        if let store = pomodoroStore, store.isRunning || store.isPaused { return true }
        // 旅行中需要每帧驱动蹦跳动画和滚动风景
        if travelStore.state.isTraveling { return true }
        // 摇摇乐中需要每帧驱动 HUD 分数 / 顶点数
        if catchGameStore.phase == .playing { return true }
        return false
    }

    private func petContent(at date: Date) -> some View {
        let expression = visualExpression
        let isSleeping = expression == .sleeping
        let isListening = expression == .listening
        let isTraveling = travelStore.state.isTraveling
        let travelingStartedAt = travelStore.state.activeTrip?.startedAt
        // Hop offsets are local — do NOT write them to motionState's
        // @Published properties from inside this TimelineView body. That
        // creates a re-entrant update cycle (see PetMotionState.swift).
        let hop = motionState.hopOffsets(at: date, traveling: isTraveling)
        let sleepingConfiguration = activeVisualConfiguration.configuration(for: .sleeping)
        let sleepingBreathEnabled = sleepingConfiguration.resolvedSleepingBreathEnabled
            && supportsSleepingBreath(for: sleepingConfiguration)
        let breathScale = sleepingBreathScale(
            at: date,
            isSleeping: isSleeping && sleepingBreathEnabled
        )
        let listeningMotion = listeningMotion(
            at: date,
            isListening: isListening
                && customizationStore.musicReactionSettings.isSwayingEnabled
                && activeVisualConfiguration.resolvedMusicSwayingEnabled
        )

        return ZStack(alignment: .bottomLeading) {
            Color.clear

            // 统一气泡位置：Cube 头顶上方居中（所有气泡同一 Y）
            let bubbleY = PetMetrics.canvasHeight
                - PetMetrics.bodyInsetY
                - PetMetrics.bodySize
                - 18

            if isTraveling, let startedAt = travelingStartedAt {
                ScrollingSceneryView(date: date, startedAt: startedAt)
                    .frame(width: PetMetrics.canvasWidth, height: PetMetrics.canvasHeight)
                    .position(
                        x: PetMetrics.canvasWidth / 2,
                        y: PetMetrics.canvasHeight / 2
                    )
            }

            if let souvenirs = travelStore.lastReturnSouvenirs {
                TravelReturnPopupView(souvenirs: souvenirs)
                    .id(souvenirs.map(\.id).joined())
                    .position(
                        x: PetMetrics.canvasWidth / 2,
                        y: bubbleY
                    )
                    .allowsHitTesting(false)
            }

            petBody(breathScale: breathScale, listeningRotation: listeningMotion.rotation)
                .rotationEffect(.degrees(hop.rotation))
                .offset(
                    x: PetMetrics.bodyInsetX + listeningMotion.x + hop.x,
                    y: -PetMetrics.bodyInsetY + listeningMotion.y + groundAlignmentOffset + hop.y
                )

            if let line = speechStore.displayedLine {
                PetSpeechBubbleView(text: line.text)
                    .id(line.id)
                    .position(
                        x: PetMetrics.canvasWidth / 2,
                        y: bubbleY
                    )
                    .allowsHitTesting(false)
            }

            // 番茄钟倒计时气泡：状态在跑时永远显示在最上层，窗口关闭也能看到
            if let pomodoroStore, let countdown = pomodoroCountdown(at: date, store: pomodoroStore) {
                PomodoroCountdownBubble(
                    text: countdown.text,
                    symbol: countdown.symbol,
                    phase: countdown.phase,
                    onTap: onOpenPomodoro
                )
                    .position(
                        x: PetMetrics.canvasWidth / 2,
                        y: bubbleY
                    )
                    .transition(.scale.combined(with: .opacity))
            } else if let workingBubble = motionState.workingBubble {
                // 待办气泡：点整个气泡 = 弹开待办窗口（用户在里面点完成/删除 → 气泡自动消失）。
                // 其他气泡（专注/喝咖啡/庆祝等）：点 = onOpenPomodoro 保持原行为。
                let tapAction: (() -> Void)? = workingBubble.taskID != nil
                    ? onShowTodoReminder
                    : onOpenPomodoro
                PetWorkingBubbleView(
                    bubble: workingBubble,
                    onTap: tapAction
                )
                    .id(workingBubble.id)
                    .position(
                        x: PetMetrics.canvasWidth / 2,
                        y: bubbleY
                    )
            }

            if isSleeping {
                sleepEffectView(
                    sleepingConfiguration.resolvedSleepingEffect,
                    date: date
                )
                    .allowsHitTesting(false)
            }

            if isListening && customizationStore.musicReactionSettings.areMusicNotesEnabled {
                MusicNotesView(date: date)
                    .allowsHitTesting(false)
            }

            if let effect = motionState.experienceGainEffect {
                ExperienceGainView(
                    text: languageSettings.experienceGainText(effect.amount)
                )
                .id(effect.id)
                .position(
                    x: PetMetrics.bodyInsetX + PetMetrics.bodySize / 2,
                    y: PetMetrics.canvasHeight - PetMetrics.bodyInsetY - PetMetrics.bodySize - 8
                )
                .allowsHitTesting(false)
            }

            if let effect = motionState.satietyGainEffect {
                ExperienceGainView(
                    text: languageSettings.satietyGainText(effect.amount)
                )
                .id(effect.id)
                .position(
                    x: PetMetrics.bodyInsetX + PetMetrics.bodySize / 2,
                    y: PetMetrics.canvasHeight - PetMetrics.bodyInsetY - PetMetrics.bodySize - 26
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func petBody(breathScale: CGFloat, listeningRotation: CGFloat) -> some View {
        let mouthOpen = motionState.feedMouthOpen
        let expression = visualExpression
        let visualRenderingExpression = expression.visualRenderingExpression
        let configuration = activeVisualConfiguration
        let visualState: PetVisualState = mouthOpen > 0.02
            ? .eating
            : PetVisualState(expression: expression)
        let stateConfiguration = configuration.configuration(
            for: visualState
        )
        let appliesVerticalBaseOffsetInView = true
        let customEyeAsset = stateConfiguration.eyes?.customAssetID.flatMap {
            customizationStore.importedVisualAsset(for: $0)
        }

        return ZStack {
            if let action = activeActionPlayback, action.state == visualState {
                ImportedPetVisualView(
                    asset: customizationStore.importedVisualAsset(for: action.assetID),
                    baseOffset: stateConfiguration.baseOffset,
                    animationPlaybackRate: stateConfiguration.actionAnimationPlaybackRate,
                    configuration: stateConfiguration.eyes,
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            } else if let bundledAsset = bundledVisualAsset(for: stateConfiguration.base) {
                ImportedPetVisualView(
                    asset: bundledAsset,
                    baseOffset: stateConfiguration.baseOffset,
                    animationPlaybackRate: stateConfiguration.animationPlaybackRate,
                    configuration: stateConfiguration.eyes,
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            } else if case let .importedAsset(assetID) = stateConfiguration.base {
                ImportedPetVisualView(
                    asset: customizationStore.importedVisualAsset(for: assetID),
                    baseOffset: stateConfiguration.baseOffset,
                    animationPlaybackRate: stateConfiguration.animationPlaybackRate,
                    configuration: stateConfiguration.eyes,
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            } else if appearanceSettings.isCustomPetSelected {
                ImportedPetVisualView(
                    asset: nil,
                    baseOffset: stateConfiguration.baseOffset,
                    animationPlaybackRate: stateConfiguration.animationPlaybackRate,
                    configuration: stateConfiguration.eyes,
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            } else {
                switch appearanceSettings.selectedPet.visualKind {
            case .cube, .cookie:
                CubePetView(
                    color: Color(nsColor: appearanceSettings.selectedSkin.color),
                    skinStyle: CubeSkinStyle(skinID: appearanceSettings.selectedSkinID),
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    mouthOpen: mouthOpen,
                    visualConfiguration: configuration,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            case .frog:
                FrogPetView(
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    mouthOpen: mouthOpen,
                    visualConfiguration: configuration,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            case .cat:
                CatPetView(
                    expression: visualRenderingExpression,
                    isBlinking: state.isBlinking,
                    gazeOffset: motionState.gazeOffset,
                    mouthOpen: mouthOpen,
                    skinID: appearanceSettings.selectedSkinID,
                    visualConfiguration: configuration,
                    customEyeAsset: customEyeAsset,
                    appliesVerticalBaseOffsetInView: appliesVerticalBaseOffsetInView
                )
            case .dog:
                Image(systemName: "dog.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.brown)
                    .padding(12)
                }
            }

            if Self.decorationsAreVisible(
                petID: appearanceSettings.selectedPetID,
                skinID: appearanceSettings.selectedSkinID,
                expression: expression
            ) {
                ForEach(
                    inventoryStore.equippedDecorations(
                        for: appearanceSettings.selectedPetID,
                        skinID: appearanceSettings.selectedSkinID
                    )
                ) { decoration in
                    if let item = ShopCatalog.petMenuItem(id: decoration.itemID) {
                        PetDecorationArtworkView(item: item)
                            .frame(
                                width: PetDecorationRenderingMetrics.sideLength(
                                    decorationScale: decoration.scale
                                ),
                                height: PetDecorationRenderingMetrics.sideLength(
                                    decorationScale: decoration.scale
                                )
                            )
                            .position(
                                decoration.position.point(
                                    in: CGSize(
                                        width: PetMetrics.bodyContentSize,
                                        height: PetMetrics.bodyContentSize
                                    )
                                )
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(width: PetMetrics.bodyContentSize, height: PetMetrics.bodyContentSize)
        .padding(PetMetrics.bodyPadding)
        .scaleEffect(CGFloat(stateConfiguration.resolvedBaseScale), anchor: .bottom)
        .scaleEffect(isPressed ? 0.96 : 1)
        .scaleEffect(x: motionState.stretchX, y: motionState.stretchY)
        .scaleEffect(x: 1, y: breathScale, anchor: .bottom)
        .rotationEffect(.degrees(motionState.rotationDegrees + listeningRotation))
        .animation(.easeInOut(duration: 0.25), value: appearanceSettings.selectedSkinID)
        .animation(.easeInOut(duration: 0.25), value: appearanceSettings.selectedPetID)
    }

    @ViewBuilder
    private func sleepEffectView(_ effect: PetSleepingEffect, date: Date) -> some View {
        switch effect {
        case .bubbles:
            SleepBubblesView(date: date)
        case .zzz:
            SleepZzzView(date: date)
        }
    }

    private var activeVisualConfiguration: PetVisualConfiguration {
        customizationStore.resolvedVisualConfiguration(
            petID: appearanceSettings.selectedPetID,
            skinID: appearanceSettings.selectedSkinID
        )
    }

    private func bundledVisualAsset(
        for source: PetBaseVisualSource
    ) -> PetImportedVisualAsset? {
        guard case let .bundledAsset(name) = source else { return nil }
        return PetBundledVisualAssetCache.visualAsset(named: name)
    }

    private var visualExpression: PetExpression {
        Self.visualExpression(
            base: state.expression,
            isHungry: hungerStore.isHungry,
            isEating: motionState.feedMouthOpen > 0.02
        )
    }

    private func restartActionPlaybackLoop() {
        actionPlaybackTask?.cancel()
        actionPlaybackTask = nil
        activeActionPlayback = nil

        actionPlaybackTask = Task {
            while !Task.isCancelled {
                let expression = visualExpression
                let visualState: PetVisualState = motionState.feedMouthOpen > 0.02
                    ? .eating
                    : PetVisualState(expression: expression)
                let configuration = activeVisualConfiguration.configuration(for: visualState)
                let actionAssetIDs = configuration.resolvedActionAssetIDs
                guard !actionAssetIDs.isEmpty else { return }

                let delay = randomActionDelay(for: configuration.resolvedActionFrequency)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled,
                      let actionAssetID = actionAssetIDs.randomElement(),
                      let asset = customizationStore.importedVisualAsset(for: actionAssetID)
                else { continue }

                activeActionPlayback = ActiveActionPlayback(
                    assetID: actionAssetID,
                    state: visualState
                )
                try? await Task.sleep(
                    nanoseconds: UInt64(asset.playbackDuration * 1_000_000_000)
                )
                if !Task.isCancelled {
                    activeActionPlayback = nil
                }
            }
        }
    }

    private func randomActionDelay(for frequency: PetActionFrequency) -> TimeInterval {
        switch frequency {
        case .low: Double.random(in: 18...30)
        case .medium: Double.random(in: 10...18)
        case .high: Double.random(in: 4...8)
        }
    }

    static func visualExpression(
        base expression: PetExpression,
        isHungry: Bool,
        isEating: Bool
    ) -> PetExpression {
        // Hunger is the persistent idle appearance. It should remain visible
        // even if the underlying interaction state is sleeping, listening, or
        // temporarily reacting to a grab; only active eating takes precedence.
        guard !isEating, isHungry else {
            return expression
        }
        return .hungry
    }

    static func decorationsAreVisible(
        petID: String,
        skinID: String,
        expression: PetExpression
    ) -> Bool {
        guard expression == .sleeping else { return true }

        return petID == PetCatalog.cube.id
            || petID == PetCatalog.frog.id
            || (petID == PetCatalog.cat.id && skinID == "cat.yellow")
    }

    private var groundAlignmentOffset: CGFloat {
        if appearanceSettings.isCustomPetSelected {
            return 5
        }
        // Align each pet's visible bottom, including PNG transparency, with the physics floor.
        switch appearanceSettings.selectedPet.visualKind {
        case .cube:
            return 5
        case .cookie:
            return 9
        case .frog:
            return 17.8
        case .cat:
            return switch appearanceSettings.selectedSkinID {
            case "cat.grayTabby": 15.4
            case "cat.calico": 11.4
            case "cat.yellow": 12.6
            default: 10.8
            }
        case .dog:
            return 10.8
        }
    }

    private func sleepingBreathScale(at date: Date, isSleeping: Bool) -> CGFloat {
        guard isSleeping else { return 1 }

        let wave = (sin(date.timeIntervalSinceReferenceDate * 1.55) + 1) / 2
        return 0.94 + CGFloat(wave) * 0.08
    }

    private func supportsSleepingBreath(for configuration: PetStateVisualConfiguration) -> Bool {
        guard case let .importedAsset(assetID) = configuration.base else { return true }
        return customizationStore.importedVisualAsset(for: assetID)?.supportsSleepingBreath == true
    }

    private func listeningMotion(at date: Date, isListening: Bool) -> (x: CGFloat, y: CGFloat, rotation: CGFloat) {
        guard isListening else { return (0, 0, 0) }

        let phase = date.timeIntervalSinceReferenceDate * 4.4
        return (
            x: CGFloat(sin(phase)) * 2.4,
            y: -abs(CGFloat(sin(phase))) * 2.0,
            rotation: CGFloat(sin(phase)) * 1.8
        )
    }

    private func pulse() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
            isPressed = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                isPressed = false
            }
        }
    }

    // MARK: - 番茄钟倒计时气泡

    private struct PomodoroCountdownInfo {
        let text: String
        let symbol: String
        let phase: PomodoroStore.Phase
    }

    private func pomodoroCountdown(at date: Date, store: PomodoroStore) -> PomodoroCountdownInfo? {
        switch store.state {
        case .running(let phase, let endDate, _):
            let remaining = max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
            let symbol = phase == .focus ? "target" : "leaf.fill"
            return PomodoroCountdownInfo(
                text: String(format: "%02d:%02d", remaining / 60, remaining % 60),
                symbol: symbol,
                phase: phase
            )
        case .paused(let phase, let elapsed, let total):
            let remaining = max(0, Int((total - elapsed).rounded(.up)))
            return PomodoroCountdownInfo(
                text: String(format: "%02d:%02d", remaining / 60, remaining % 60),
                symbol: "pause.fill",
                phase: phase
            )
        case .notRunning:
            return nil
        }
    }
}

private struct ExperienceGainView: View {
    let text: String

    @State private var opacity = 0.0
    @State private var verticalOffset: CGFloat = 8

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .opacity(opacity)
            .offset(y: verticalOffset)
            .onAppear {
                withAnimation(.easeOut(duration: 0.18)) {
                    opacity = 1
                    verticalOffset = 0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                    withAnimation(.easeInOut(duration: 0.58)) {
                        opacity = 0
                        verticalOffset = -26
                    }
                }
            }
    }
}

/// 番茄钟倒计时气泡（用统一的泡泡风格）
private struct PomodoroCountdownBubble: View {
    let text: String
    let symbol: String
    let phase: PomodoroStore.Phase
    let onTap: (() -> Void)?

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PetMenuCardPalette.cocoa)
                .frame(width: 22, height: 22)
                .background(Circle().fill(backgroundColor))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PetMenuCardPalette.cocoa)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PetMenuCardPalette.blush.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PetMenuCardPalette.cocoa.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: PetMenuCardPalette.cocoa.opacity(0.18), radius: 3, x: 0, y: 1)
        .opacity(opacity)
        .scaleEffect(scale)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .help("打开番茄钟")
        .onAppear { animateIn() }
    }

    private var backgroundColor: Color {
        switch phase {
        case .focus: return PetMenuCardPalette.softCoral.opacity(0.55)
        case .breakTime: return Color.green.opacity(0.3)
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
            opacity = 1
            scale = 1
        }
    }
}

// MARK: - Catch-game HUD

/// Top-left score badge shown while the catch game is in `.playing`.
/// Compact enough to fit a 230-wide canvas; the last-catch bonus
/// floats next to the score for a beat so the player can see they
/// scored.
private struct CatchGameHUD: View {
    @ObservedObject var store: CatchGameStore
    @State private var lastShownBonus: Int = 0
    @State private var bonusOpacity: Double = 0
    @State private var bonusYOffset: CGFloat = 0

    var body: some View {
        // Score pill only — the × close button has its own top-trailing
        // overlay so it stays visible (and clickable) for the whole game
        // and isn't swallowed by this HUD's `allowsHitTesting(false)`.
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(store.score)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if bonusOpacity > 0.05 {
                    Text("+\(lastShownBonus)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.white.opacity(0.18))
                        )
                        .opacity(bonusOpacity)
                        .offset(y: bonusYOffset)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(PetMenuCardPalette.coral.opacity(0.92))
            )
            .overlay(
                Capsule().stroke(.white.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
        .onChange(of: store.lastCatchBonus) { _, newValue in
            guard newValue > 0 else { return }
            lastShownBonus = newValue
            bonusOpacity = 0
            bonusYOffset = 0
            withAnimation(.easeOut(duration: 0.18)) {
                bonusOpacity = 1
                bonusYOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeIn(duration: 0.28)) {
                    bonusOpacity = 0
                    bonusYOffset = -8
                }
            }
        }
    }
}

/// Single × button used as the catch-game's exit affordance. Lives in
/// its own overlay (topTrailing) so the click is never swallowed by
/// the HUD's `allowsHitTesting(false)` or by `NSHostingView`'s
/// pre-routing of mouse events to the physics controller.
///
/// Centered popover shown when the catch game ends. The whole
/// popover acts as a tap target — the visible "再来一局" pill is
/// the affordance, but tapping anywhere in the rounded card also
/// restarts. Two reasons we do it this way:
/// 1. The Button-only hit area is small (~40×18pt) and easy to miss
///    inside a 230×250 floating window.
/// 2. The same overlay is rendered inside an `NSHostingView` that
///    also routes PetWindow clicks to the physics controller, so a
///    tiny SwiftUI Button occasionally loses the hit to the cube
///    underneath. Tapping the whole card sidesteps that.
///
/// Note: the actual × close affordance lives in `PetWindow` as an
/// `NSButton` so it sits outside SwiftUI's hit-test path entirely.
private struct CatchGameOverOverlay: View {
    @ObservedObject var store: CatchGameStore

    var body: some View {
        VStack(spacing: 6) {
            Text("游戏结束")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("分数 \(store.score)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            if store.bestScore > store.score {
                Text("最高 \(store.bestScore)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("新纪录！")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("再来一局")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(PetMenuCardPalette.coral)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(.white)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PetMenuCardPalette.coral.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
        // The × close button now lives in the parent PetView's
        // topTrailing overlay, so it doesn't fight with the
        // "tap anywhere = restart" gesture on the rest of the card.
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            store.restart()
        }
    }
}
