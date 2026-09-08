import AppKit
import Combine
import Sparkle
import SwiftUI

final class MacBookPetApp: NSObject, NSApplicationDelegate, NSSharingServiceDelegate {
    private var petWindow: PetWindow?
    private var petState: PetState?
    private var petMotionState: PetMotionState?
    private var physicsController: PetPhysicsController?
    private var travelStore: TravelStore?
    private var musicPlaybackMonitor: MusicPlaybackMonitor?
    private var musicReactionSettingsCancellable: AnyCancellable?
    private var workSessionCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var workBubbleLoopTask: Task<Void, Never>?
    private var pomodoroCancellable: AnyCancellable?
    private var todoReminderCancellable: AnyCancellable?
    private var activeSharingService: NSSharingService?
    private var petCustomizationWindowController: PetCustomizationWindowController?
    private var petMenuWindowController: PetMenuWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var permissionSettingsWindowController: PermissionSettingsWindowController?
    private var todoReminderWindowController: TodoReminderWindowController?
    private var pomodoroWindowController: PomodoroWindowController?
    private var todoTaskChangeCancellable: AnyCancellable?
    private var workWindowController: WorkWindowController?
    private var statusItemController: StatusItemController?
    private var globalShortcutController: GlobalShortcutController?
    private var ageStore: PetAgeStore?
    private var progressStore: PetProgressStore?
    private var inventoryStore: PetInventoryStore?
    private var hungerStore: PetHungerStore?
    private var customizationStore: PetCustomizationStore?
    private var featureEntitlementStore: FeatureEntitlementStore?
    private var speechStore: PetSpeechLineStore?
    private var todoStore: TodoStore?
    private var pomodoroStore: PomodoroStore?
    private var workStore: WorkSessionStore?
    private var catchGameStore: CatchGameStore?
    private let feedSettings = FeedSettings()
    private let languageSettings = LanguageSettings()
    private let appearanceSettings = PetAppearanceSettings()
    private let menuFontSettings = MenuFontSettings()
    private let shortcutSettings = ShortcutSettings()
    private let launchAtLoginController = LaunchAtLoginController()
    private var updaterController: SPUStandardUpdaterController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let petState = PetState()
        let motionState = PetMotionState()
        self.petState = petState
        self.petMotionState = motionState

        let ageStore = PetAgeStore()
        self.ageStore = ageStore
        ageStore.start()
        let progressStore = PetProgressStore(
            currentRuntime: ageStore.totalRuntime,
            selectedPetID: appearanceSettings.selectedPetID,
            selectedSkinID: appearanceSettings.selectedSkinID
        )
        self.progressStore = progressStore
        let inventoryStore = PetInventoryStore()
        self.inventoryStore = inventoryStore
        progressStore.start { [weak ageStore] in
            ageStore?.totalRuntime ?? 0
        }
        let hungerStore = PetHungerStore()
        self.hungerStore = hungerStore
        hungerStore.start()

        let travelStore = TravelStore()
        self.travelStore = travelStore

        let catchGameStore = CatchGameStore()
        self.catchGameStore = catchGameStore

        let customizationStore = PetCustomizationStore()
        self.customizationStore = customizationStore
        let featureEntitlementStore = FeatureEntitlementStore()
        self.featureEntitlementStore = featureEntitlementStore
        appearanceSettings.ensureValidSelection(
            progress: progressStore,
            customizationStore: customizationStore,
            featureEntitlementStore: featureEntitlementStore
        )

        let speechStore = PetSpeechLineStore()
        self.speechStore = speechStore
        // Seed default speech lines per pet. Only fills in the pool the first
        // time a given pet is seen so user edits are preserved across launches.
        speechStore.ensureDefaults(for: PetCatalog.cube.id, defaults: [
            "嗨～",
            "今天也要元气满满呀！",
            "嘎嘎嘎",
            "再点我就要发火啦！",
            "摸一摸就很开心"
        ])

        let workStore = WorkSessionStore()
        self.workStore = workStore
        progressStore.coinMultiplier = workStore.currentCoinMultiplier
        hungerStore.hungerMultiplier = workStore.currentHungerMultiplier

        let todoStore = TodoStore()
        self.todoStore = todoStore

        // 订阅 todoStore.$lastFiredTaskID：到点任务触发气泡
        // 注意：订阅必须放在 todoStore.start() 之前，否则 start() 里的 scanOverdue() 设置
        // lastFiredTaskID 时订阅还没建立，Combine 的 @Published 不会重发历史值，气泡会错过。
        // 注意：这里**不**直接弹待办窗口。to-do fire 时只挂气泡，等用户点
        // 气泡再弹窗（点击路径由 PetPhysicsController.onBubbleClick 接住）。
        todoReminderCancellable = todoStore.$lastFiredTaskID
            .compactMap { id -> (UUID, String)? in
                guard let id, let task = todoStore.tasks.first(where: { $0.id == id }) else { return nil }
                return (id, "待办到时啦：\(task.title)")
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak motionState] pair in
                motionState?.showWorkingBubble(
                    mood: .reminder,
                    text: pair.1,
                    duration: nil,
                    taskID: pair.0
                )
            }

        // 订阅 todoStore.$tasks：用户操作（toggleDone / 删除）让当前气泡对应任务完成后，
        // 自动清气泡。task isDone → completeReminderBubble，task 不在列表 → dismissReminderBubble
        // （当成"知道了"语义清掉）。
        todoTaskChangeCancellable = todoStore.$tasks
            .dropFirst()  // 跳过 init 时第一次 emit（避免启动时把刚 fire 的气泡立刻清掉）
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                guard let self,
                      let bubble = self.petMotionState?.workingBubble,
                      let taskID = bubble.taskID else { return }
                if let task = tasks.first(where: { $0.id == taskID }) {
                    if task.isDone {
                        self.petMotionState?.completeReminderBubble(taskID: taskID)
                    }
                } else {
                    // 任务被删除
                    self.petMotionState?.dismissReminderBubble(taskID: taskID)
                }
            }

        todoStore.start()

        // 临时 debug 路径：env CUBEPET_TODO_DEBUG_FIRE 存在时，启动 3 秒后注入一个已过期任务，
        // 方便立即看气泡和测勾叉。生产 / build_and_run.sh 启动不传 env，不会触发。
        // 验证后想清理就把这整段 if 块删掉。
        if ProcessInfo.processInfo.environment["CUBEPET_TODO_DEBUG_FIRE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak todoStore] in
                guard let todoStore else { return }
                let debugTask = TodoTask(
                    title: "测试：勾叉可点验证",
                    dueDate: Date().addingTimeInterval(-5)  // 已过期 5s → scanOverdue 立刻 fire
                )
                todoStore.add(debugTask)
            }
        }

        let pomodoroStore = PomodoroStore()
        self.pomodoroStore = pomodoroStore

        // 番茄钟 → Cube 联动：运行/暂停期间不显示 working bubble（倒计时气泡已带状态）；
        // .notRunning 不要 clear —— 否则 .sink 订阅时的初始 fire 会立刻清掉刚被 todo 提醒设上的气泡
        pomodoroCancellable = pomodoroStore.$state
            .sink { [weak motionState] newState in
                guard let motionState else { return }
                switch newState {
                case .running, .paused:
                    motionState.clearWorkingBubble()
                case .notRunning:
                    break
                }
            }

        let contentView = PetView(
            state: petState,
            motionState: motionState,
            hungerStore: hungerStore,
            inventoryStore: inventoryStore,
            appearanceSettings: appearanceSettings,
            customizationStore: customizationStore,
            languageSettings: languageSettings,
            speechStore: speechStore,
            travelStore: travelStore,
            catchGameStore: catchGameStore,
            pomodoroStore: pomodoroStore,
            onOpenPomodoro: { [weak self] in
                self?.pomodoroWindowController?.show()
            },
            onShowTodoReminder: { [weak self] in
                self?.todoReminderWindowController?.show()
            }
        )

        let hostingView = PetHostingView(rootView: contentView)
        hostingView.motionState = motionState
        hostingView.onFeedInteractionBegan = { [weak petState] in
            petState?.reactToFeed()
        }
        hostingView.canAcceptFeedFiles = { [weak self] urls in
            self?.canAcceptFeedFiles(urls) == true
        }
        hostingView.onFeedFiles = { [weak self, weak petState] urls in
            guard self?.handleFedItems(urls) == true else { return false }
            petState?.reactToFeed()
            return true
        }
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: PetMetrics.canvasWidth,
            height: PetMetrics.canvasHeight
        )

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let initialOrigin = NSPoint(
            x: screenFrame.midX - PetMetrics.bodySize / 2 - PetMetrics.bodyInsetX,
            y: screenFrame.midY - PetMetrics.bodySize / 2 - PetMetrics.bodyInsetY
        )

        let window = PetWindow(
            contentRect: NSRect(
                origin: initialOrigin,
                size: NSSize(width: PetMetrics.canvasWidth, height: PetMetrics.canvasHeight)
            )
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        let physicsController = PetPhysicsController(window: window, motionState: motionState)
        physicsController.isMouseGazeEnabled = { [weak petState] in
            petState?.allowsMouseGaze == true && !hungerStore.isHungry
        }
        physicsController.isBottomPetEnabled = { [appearanceSettings = self.appearanceSettings, customizationStore] in
            if appearanceSettings.selectedPetID == PetCatalog.cat.id,
               appearanceSettings.selectedSkinID == "cat.yellow" {
                return true
            }

            return customizationStore.resolvedVisualConfiguration(
                petID: appearanceSettings.selectedPetID,
                skinID: appearanceSettings.selectedSkinID
            )
            .resolvedBottomPetEnabled
        }
        physicsController.isGravityEnabled = { [appearanceSettings = self.appearanceSettings, customizationStore] in
            customizationStore.resolvedVisualConfiguration(
                petID: appearanceSettings.selectedPetID,
                skinID: appearanceSettings.selectedSkinID
            )
            .resolvedGravityEnabled
        }
        physicsController.onClick = { [petState, petMotionState, pomodoroStore, speechStore] in
            petState.reactToClick(isHungry: hungerStore.isHungry)
            if !hungerStore.isHungry {
                let isPomodoroActive = pomodoroStore.isRunning || pomodoroStore.isPaused
                let hasStatusBubble = petMotionState?.workingBubble != nil || isPomodoroActive
                if !hasStatusBubble {
                    speechStore.showRandomLine(for: self.appearanceSettings.selectedPetID)
                }
            }
        }
        physicsController.onGrab = { [petState] in
            petState.reactToGrab()
        }
        physicsController.onLand = { [petState] in
            petState.recoverAfterLanding()
        }
        physicsController.catchGameStore = catchGameStore
        window.physicsController = physicsController
        window.catchGameStore = catchGameStore

        petWindow = window
        self.physicsController = physicsController
        petState.start()
        physicsController.start()

        // 监听 catch game phase 变化：进入 .playing 时给 cube 一个开
        // 局向上冲量、退出时把物理交还给普通模式；同时切换 × 退出
        // 按钮（NSButton）的可见性——只在 .gameOver 时显示，让玩家
        // 可以从结束画面退出回到正常状态。
        catchGameStore.$phase
            .sink { [weak physicsController, weak window] phase in
                guard let physicsController else { return }
                switch phase {
                case .playing:
                    physicsController.beginCatchGame()
                case .idle, .gameOver:
                    physicsController.endCatchGame()
                }
                window?.setExitButtonVisible(phase == .gameOver)
            }
            .store(in: &cancellables)

        let musicPlaybackMonitor = MusicPlaybackMonitor()
        musicPlaybackMonitor.onPlaybackChanged = { [weak petState] isPlaying in
            petState?.setMusicPlaying(isPlaying)
        }
        musicReactionSettingsCancellable = customizationStore.$musicReactionSettings
            .sink { [weak petState] settings in
                petState?.setMusicReactionSettings(settings)
            }
        self.musicPlaybackMonitor = musicPlaybackMonitor
        musicPlaybackMonitor.start()

        let petCustomizationWindowController = PetCustomizationWindowController(
            customizationStore: customizationStore,
            appearanceSettings: appearanceSettings,
            progressStore: progressStore,
            languageSettings: languageSettings,
            speechStore: speechStore
        )
        self.petCustomizationWindowController = petCustomizationWindowController
        let petMenuWindowController = PetMenuWindowController(
            progressStore: progressStore,
            inventoryStore: inventoryStore,
            languageSettings: languageSettings,
            travelStore: travelStore,
            useFood: { [weak self] item in
                self?.useInventoryFood(item) == true
            }
        )
        self.petMenuWindowController = petMenuWindowController
        let todoReminderWindowController = TodoReminderWindowController(todoStore: todoStore)
        self.todoReminderWindowController = todoReminderWindowController
        let pomodoroWindowController = PomodoroWindowController(
            pomodoroStore: pomodoroStore,
            todoStore: todoStore
        )
        self.pomodoroWindowController = pomodoroWindowController
        // 桌宠头顶工作气泡被点：带 taskID = 待办气泡 → 弹待办窗口；
        // 没 taskID = 番茄钟倒计时 / 专注 / 喝咖啡 / 庆祝 等 → 弹番茄钟。
        // 在两个 window controller 都建好之后才接，因为回调里要用到。
        physicsController.onBubbleClick = { [weak todoReminderWindowController, weak pomodoroWindowController] taskID in
            if taskID != nil {
                todoReminderWindowController?.show()
            } else {
                pomodoroWindowController?.show()
            }
        }
        pomodoroStore.onFocusComplete = { [weak motionState] in
            motionState?.showWorkingBubble(mood: .celebrating, text: "完成！", duration: 3)
        }
        let workWindowController = WorkWindowController(
            workStore: workStore,
            levelProvider: { [weak progressStore, weak appearanceSettings] in
                guard let progressStore, let appearanceSettings else { return 1 }
                return progressStore.level(for: appearanceSettings.selectedPetID)
            }
        )
        self.workWindowController = workWindowController

        workSessionCancellable = workStore.$activeProject
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak progressStore, weak hungerStore, weak petState] project in
                progressStore?.coinMultiplier = project?.coinMultiplier ?? 1.0
                hungerStore?.hungerMultiplier = project?.hungerMultiplier ?? 1.0
                if let project, !project.displayName.isEmpty {
                    petState?.reactToClick(isHungry: hungerStore?.isHungry ?? false)
                }
                self?.updateWorkBubbleLoop(active: project != nil, motionState: self?.petMotionState)
            }

        // 启动时如有遗留 work bubble loop，先关掉（防止热重启后空跑）
        updateWorkBubbleLoop(active: false, motionState: self.petMotionState)
        let permissionSettingsWindowController = PermissionSettingsWindowController(
            languageSettings: languageSettings
        )
        self.permissionSettingsWindowController = permissionSettingsWindowController
        let statusItemController = StatusItemController(
            feedSettings: feedSettings,
            languageSettings: languageSettings,
            ageStore: ageStore,
            progressStore: progressStore,
            hungerStore: hungerStore,
            appearanceSettings: appearanceSettings,
            menuFontSettings: menuFontSettings,
            customizationStore: customizationStore,
            featureEntitlementStore: featureEntitlementStore,
            shortcutSettings: shortcutSettings,
            launchAtLoginController: launchAtLoginController,
            travelStore: travelStore,
            catchGameStore: catchGameStore,
            onShowPetMenu: { [weak petMenuWindowController] in
                petMenuWindowController?.show()
            },
            onShowPetCustomization: { [weak petCustomizationWindowController] in
                petCustomizationWindowController?.show()
            },
            onShowShortcutSettings: { [weak self] in
                self?.shortcutSettingsWindowController?.show()
            },
            onShowPermissionSettings: { [weak permissionSettingsWindowController] in
                permissionSettingsWindowController?.show()
            },
            onShowTodoReminder: { [weak todoReminderWindowController] in
                todoReminderWindowController?.show()
            },
            onShowPomodoro: { [weak pomodoroWindowController] in
                pomodoroWindowController?.show()
            },
            onShowWorkSession: { [weak workWindowController] in
                workWindowController?.show()
            },
            onStartCatchGame: { [weak catchGameStore, weak self] in
                guard let catchGameStore, let self else { return }
                if catchGameStore.phase == .gameOver {
                    catchGameStore.restart()
                } else if !catchGameStore.isActive {
                    catchGameStore.startGame()
                }
                // 把窗口带到前面，让玩家立刻看到 cube
                self.petWindow?.makeKeyAndOrderFront(nil)
            },
            onQuit: { NSApp.terminate(nil) }
        )
        self.statusItemController = statusItemController

        window.onRightClick = { [weak statusItemController] _ in
            statusItemController?.showPetContextMenu(at: NSEvent.mouseLocation)
        }
        physicsController.onRightClick = { [weak statusItemController] _ in
            statusItemController?.showPetContextMenu(at: NSEvent.mouseLocation)
        }

        globalShortcutController = GlobalShortcutController(
            settings: shortcutSettings,
            onShortcut: { [weak statusItemController] in
                statusItemController?.showMenuFromShortcut()
            }
        )

        let shortcutSettingsWindowController = ShortcutSettingsWindowController(
            shortcutSettings: shortcutSettings,
            languageSettings: languageSettings,
            onSaveShortcut: { [weak self] shortcut in
                self?.globalShortcutController?.register(shortcut: shortcut) == true
            }
        )
        self.shortcutSettingsWindowController = shortcutSettingsWindowController

        // Sparkle auto-update. The feed URL and edDSA public key are read from
        // the bundle's Info.plist at startup; running this unconditionally is
        // fine — if SUFeedURL is empty (e.g. during local dev before keys are
        // generated), Sparkle simply has nothing to check.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        workBubbleLoopTask?.cancel()
        workBubbleLoopTask = nil
        musicPlaybackMonitor?.stop()
        musicReactionSettingsCancellable?.cancel()
        todoReminderCancellable?.cancel()
        workSessionCancellable?.cancel()
        ageStore?.stopAndPersist()
        if let ageStore {
            progressStore?.synchronizeRuntime(ageStore.totalRuntime)
        }
        progressStore?.stop()
        hungerStore?.stop()
        todoStore?.stop()
    }

    /// 上班时桌宠"在忙"的循环气泡：随机在 focusing / sipping / note /
    /// idea 之间切换，每 4–8 秒一个。让 work 状态看起来不像单纯图标
    /// 切换，而像桌宠真的在思考、喝咖啡、记笔记。停工后立即清理。
    @MainActor
    private func updateWorkBubbleLoop(active: Bool, motionState: PetMotionState?) {
        workBubbleLoopTask?.cancel()
        workBubbleLoopTask = nil
        guard active, let motionState else {
            motionState?.clearWorkingBubble()
            return
        }
        workBubbleLoopTask = Task { @MainActor [weak motionState] in
            let workMoods: [PetWorkingBubble.Mood] = [
                .focusing, .sipping, .note, .focusing, .idea, .sipping
            ]
            while !Task.isCancelled {
                let mood = workMoods.randomElement() ?? .focusing
                let text: String? = {
                    switch mood {
                    case .focusing: return "专注中…"
                    case .sipping: return nil
                    case .note: return "记一下"
                    case .idea: return "想到啦！"
                    default: return nil
                    }
                }()
                motionState?.showWorkingBubble(
                    mood: mood,
                    text: text,
                    duration: Double.random(in: 2.2...3.6)
                )
                let sleepSeconds = Double.random(in: 4.0...7.5)
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            }
        }
    }

    @MainActor
    private func canAcceptFeedFiles(_ urls: [URL]) -> Bool {
        guard let progressStore else { return false }
        let petID = appearanceSettings.selectedPetID
        let isUsableCustomPet = featureEntitlementStore?.isUnlocked(.petCustomization) == true
            && customizationStore?.customPet(id: petID) != nil

        return urls.contains { url in
            guard DesktopFoodFile.isFoodFile(url) else { return true }
            guard let payload = DesktopFoodFile.payload(at: url) else { return false }
            return progressStore.canConsumeFood(
                payload,
                for: petID,
                allowUnownedPet: isUsableCustomPet
            )
        }
    }

    @discardableResult
    @MainActor
    private func useInventoryFood(_ item: PetShopItemDefinition) -> Bool {
        guard
            let inventoryStore,
            let progressStore,
            let hungerStore
        else { return false }

        let petID = appearanceSettings.selectedPetID
        let isUsableCustomPet = featureEntitlementStore?.isUnlocked(.petCustomization) == true
            && customizationStore?.customPet(id: petID) != nil
        guard let result = inventoryStore.useFood(
            item,
            for: petID,
            allowUnownedPet: isUsableCustomPet,
            progressStore: progressStore,
            hungerStore: hungerStore
        ) else { return false }

        petState?.reactToFeed()
        petMotionState?.showExperienceGain(result.experience)
        petMotionState?.showSatietyGain(result.satiety)
        return true
    }

    @discardableResult
    @MainActor
    private func handleFedItems(_ urls: [URL]) -> Bool {
        guard let progressStore else { return false }
        let petID = appearanceSettings.selectedPetID
        let isUsableCustomPet = featureEntitlementStore?.isUnlocked(.petCustomization) == true
            && customizationStore?.customPet(id: petID) != nil
        var regularURLs: [URL] = []
        var didConsumeFood = false
        var gainedExperience = 0
        var gainedSatiety = 0

        for url in urls {
            guard DesktopFoodFile.isFoodFile(url) else {
                regularURLs.append(url)
                continue
            }

            guard
                let payload = DesktopFoodFile.payload(at: url),
                progressStore.consumeFood(
                    payload,
                    for: petID,
                    allowUnownedPet: isUsableCustomPet
                )
            else { continue }

            DesktopFoodFile.remove(url)
            didConsumeFood = true
            if let food = ShopCatalog.food(id: payload.foodID) {
                gainedExperience += food.experience
                gainedSatiety += hungerStore?.feed(food) ?? 0
            }
        }

        if gainedExperience > 0 {
            petMotionState?.showExperienceGain(gainedExperience)
        }
        if gainedSatiety > 0 {
            petMotionState?.showSatietyGain(gainedSatiety)
        }

        guard !regularURLs.isEmpty else { return didConsumeFood }

        switch feedSettings.destination {
        case .trash:
            return trashFeedItems(regularURLs) > 0 || didConsumeFood
        case .folder:
            guard let folderURL = feedSettings.folderURL else {
                if trashFeedItems(regularURLs) > 0 {
                    showMissingFeedFolderAlert()
                    return true
                }
                return didConsumeFood
            }

            if moveFeedItems(regularURLs, to: folderURL) {
                showMissingFeedFolderAlert()
            }
            return true
        case .airDrop:
            return shareFeedItemsViaAirDrop(regularURLs) || didConsumeFood
        }
    }

    @MainActor
    private func shareFeedItemsViaAirDrop(_ urls: [URL]) -> Bool {
        let items: [Any] = urls
        guard
            let service = NSSharingService(named: .sendViaAirDrop),
            service.canPerform(withItems: items)
        else {
            showAirDropUnavailableAlert()
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        activeSharingService = service
        service.delegate = self
        service.perform(withItems: items)
        return true
    }

    @MainActor
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        if activeSharingService === sharingService {
            activeSharingService = nil
        }
    }

    @MainActor
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if activeSharingService === sharingService {
            activeSharingService = nil
        }
        NSLog("MacBookPet failed to share fed items via AirDrop: \(error.localizedDescription)")
        showAirDropUnavailableAlert()
    }

    @discardableResult
    private func trashFeedItems(_ urls: [URL]) -> Int {
        var trashedItemCount = 0

        for url in urls {
            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                trashedItemCount += 1
            } catch {
                NSLog("MacBookPet failed to move fed item to Trash: \(url.path), \(error.localizedDescription)")
            }
        }

        return trashedItemCount
    }

    private func moveFeedItems(_ urls: [URL], to folderURL: URL) -> Bool {
        var didFallbackToTrash = false

        for url in urls {
            do {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    didFallbackToTrash = trashFeedItems([url]) > 0 || didFallbackToTrash
                    continue
                }

                let destinationURL = availableDestinationURL(for: url, in: folderURL)
                try FileManager.default.moveItem(at: url, to: destinationURL)
            } catch {
                NSLog("MacBookPet failed to move fed item to folder: \(url.path), \(error.localizedDescription)")
            }
        }

        return didFallbackToTrash
    }

    private func showMissingFeedFolderAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = languageSettings.text(.folderNotFound)
        alert.informativeText = languageSettings.text(.folderNotFoundMessage)
        alert.addButton(withTitle: languageSettings.text(.ok))
        alert.runModal()
    }

    @MainActor
    private func showAirDropUnavailableAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = languageSettings.text(.airDropUnavailable)
        alert.informativeText = languageSettings.text(.airDropUnavailableMessage)
        alert.addButton(withTitle: languageSettings.text(.ok))
        alert.runModal()
    }

    private func availableDestinationURL(for sourceURL: URL, in folderURL: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = folderURL.appendingPathComponent(sourceURL.lastPathComponent)

        if candidate.standardizedFileURL != sourceURL.standardizedFileURL, !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var index = 2
        while true {
            let fileName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
            candidate = folderURL.appendingPathComponent(fileName)

            if candidate.standardizedFileURL != sourceURL.standardizedFileURL, !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            index += 1
        }
    }

}
