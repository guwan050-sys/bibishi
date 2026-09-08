import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let showsSystemInfoKey = "MacBookPet.showsSystemInfo"
    private static let fixedMenuWidth: CGFloat = 260
    private static let petContextMenuWidth: CGFloat = 180
    private static let fixedMenuRowHeight: CGFloat = 22
    private static let meterMenuRowHeight: CGFloat = 34
    private static let fixedMenuAppearance = NSAppearance(named: .aqua)

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let progressItem = NSMenuItem()
    private let satietyItem = NSMenuItem()
    private let cpuItem = NSMenuItem()
    private let networkItem = NSMenuItem()
    private let progressRowView = FixedMenuStatusRowView(width: fixedMenuWidth, height: fixedMenuRowHeight)
    private let satietyRowView = FixedMenuMeterRowView(width: fixedMenuWidth, height: meterMenuRowHeight)
    private let cpuMemoryRowView = FixedMenuStatusRowView(width: fixedMenuWidth, height: fixedMenuRowHeight)
    private let networkRowView = FixedMenuStatusRowView(
        width: fixedMenuWidth,
        height: fixedMenuRowHeight,
        leftWidth: 42
    )
    private let metricsBottomSeparator = NSMenuItem.separator()
    private let petMenuWindowItem = NSMenuItem(title: "商店", action: #selector(openPetMenu), keyEquivalent: "")
    private let utilitiesItem = NSMenuItem(title: "实用工具", action: nil, keyEquivalent: "")
    private let todoReminderItem = NSMenuItem(title: "待办提醒", action: #selector(openTodoReminder), keyEquivalent: "")
    private let pomodoroItem = NSMenuItem(title: "番茄钟", action: #selector(openPomodoro), keyEquivalent: "")
    private let workSessionItem = NSMenuItem(title: "指挥比比十", action: nil, keyEquivalent: "")
    private let skinItem = NSMenuItem()
    private let shopItem = NSMenuItem()
    private let shopFoodItem = NSMenuItem()
    private let shopSkinsItem = NSMenuItem()
    private let shopPetsItem = NSMenuItem()
    private let settingItem = NSMenuItem()
    private let petItem = NSMenuItem()
    private let petCustomizationItem = NSMenuItem(
        title: "",
        action: #selector(openPetCustomization),
        keyEquivalent: ""
    )
    private let feedItem = NSMenuItem()
    private let languageItem = NSMenuItem()
    private let showSystemInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutSettingsItem = NSMenuItem(
        title: "",
        action: #selector(showShortcutSettings),
        keyEquivalent: ""
    )
    private let permissionSettingsItem = NSMenuItem(
        title: "",
        action: #selector(showPermissionSettings),
        keyEquivalent: ""
    )
    private let menuFontItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem(
        title: "",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private let quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "")
    private let moveToTrashItem = NSMenuItem(title: "", action: #selector(selectMoveToTrash), keyEquivalent: "")
    private let moveToFolderItem = NSMenuItem(title: "", action: #selector(selectMoveToFolder), keyEquivalent: "")
    private let airDropItem = NSMenuItem(title: "", action: #selector(selectAirDrop), keyEquivalent: "")
    private let feedSettings: FeedSettings
    private let languageSettings: LanguageSettings
    private let ageStore: PetAgeStore
    private let progressStore: PetProgressStore
    private let hungerStore: PetHungerStore
    private let appearanceSettings: PetAppearanceSettings
    private let menuFontSettings: MenuFontSettings
    private let customizationStore: PetCustomizationStore
    private let featureEntitlementStore: FeatureEntitlementStore
    private let shortcutSettings: ShortcutSettings
    private let launchAtLoginController: LaunchAtLoginController
    private let travelStore: TravelStore?
    private let catchGameStore: CatchGameStore?
    private let metricsMonitor = SystemMetricsMonitor()
    private let onShowPetMenu: () -> Void
    private let onShowPetCustomization: () -> Void
    private let onShowShortcutSettings: () -> Void
    private let onShowPermissionSettings: () -> Void
    private let onShowTodoReminder: () -> Void
    private let onShowPomodoro: () -> Void
    private let onShowWorkSession: () -> Void
    private let onStartCatchGame: () -> Void
    private let onQuit: () -> Void
    private var languageMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var menuFontMenuItems: [MenuFont: NSMenuItem] = [:]
    private var petMenuItems: [String: NSMenuItem] = [:]
    private var skinMenuItems: [String: NSMenuItem] = [:]
    private var shopFoodMenuItems: [String: NSMenuItem] = [:]
    private var shopSkinMenuItems: [String: NSMenuItem] = [:]
    private var shopPetMenuItems: [String: NSMenuItem] = [:]
    private var latestMetrics = SystemMetricsSnapshot()
    private var lastPetContextMenuOpenTime: TimeInterval = 0
    private var isRootMenuOpen = false
    private var cancellables = Set<AnyCancellable>()
    private let rootMenu = NSMenu()

    init(
        feedSettings: FeedSettings,
        languageSettings: LanguageSettings,
        ageStore: PetAgeStore,
        progressStore: PetProgressStore,
        hungerStore: PetHungerStore,
        appearanceSettings: PetAppearanceSettings,
        menuFontSettings: MenuFontSettings,
        customizationStore: PetCustomizationStore,
        featureEntitlementStore: FeatureEntitlementStore,
        shortcutSettings: ShortcutSettings,
        launchAtLoginController: LaunchAtLoginController,
        travelStore: TravelStore? = nil,
        catchGameStore: CatchGameStore? = nil,
        onShowPetMenu: @escaping () -> Void,
        onShowPetCustomization: @escaping () -> Void,
        onShowShortcutSettings: @escaping () -> Void,
        onShowPermissionSettings: @escaping () -> Void,
        onShowTodoReminder: @escaping () -> Void,
        onShowPomodoro: @escaping () -> Void,
        onShowWorkSession: @escaping () -> Void,
        onStartCatchGame: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.feedSettings = feedSettings
        self.languageSettings = languageSettings
        self.ageStore = ageStore
        self.progressStore = progressStore
        self.hungerStore = hungerStore
        self.appearanceSettings = appearanceSettings
        self.menuFontSettings = menuFontSettings
        self.customizationStore = customizationStore
        self.featureEntitlementStore = featureEntitlementStore
        self.shortcutSettings = shortcutSettings
        self.launchAtLoginController = launchAtLoginController
        self.travelStore = travelStore
        self.catchGameStore = catchGameStore
        self.onShowPetMenu = onShowPetMenu
        self.onShowPetCustomization = onShowPetCustomization
        self.onShowShortcutSettings = onShowShortcutSettings
        self.onShowPermissionSettings = onShowPermissionSettings
        self.onShowTodoReminder = onShowTodoReminder
        self.onShowPomodoro = onShowPomodoro
        self.onShowWorkSession = onShowWorkSession
        self.onStartCatchGame = onStartCatchGame
        self.onQuit = onQuit
        super.init()

        configureButton()
        configureMenu()
        applyMenuStyle()
        customizationStore.$customPets
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.appearanceSettings.isCustomPetSelected,
                       self.customizationStore.customPet(id: self.appearanceSettings.selectedPetID) == nil {
                        self.appearanceSettings.selectDefaultPet()
                    }
                    self.refreshAppearanceMenuAndIcon()
                }
            }
            .store(in: &cancellables)
        appearanceSettings.$selectedPetID
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshAppearanceMenuAndIcon()
                }
            }
            .store(in: &cancellables)
        progressStore.onChange = { [weak self] in
            guard let self else { return }
            self.updateProgressMenuState()
        }
        hungerStore.onChange = { [weak self] in
            guard let self else { return }
            self.updateHungerMenuState()
        }
        shortcutSettings.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateShortcutSettingsMenuState()
            }
            .store(in: &cancellables)
        metricsMonitor.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.latestMetrics = snapshot
            self.updateMetricsMenuState()
        }

        // When travel state changes (start trip / finish trip / end
        // early), rebuild the "指挥比比十" submenu so the travel item
        // shows the right title and action for the new state.
        travelStore?.$state
            .dropFirst()
            .sink { [weak self] _ in
                self?.workSessionItem.submenu = self?.makeGoOutMenu()
            }
            .store(in: &cancellables)
        // Catch-game phase change also affects the same submenu —
        // the "摇摇乐" item flips to "结束游戏" while the game is
        // in progress so the player has a way to bail out.
        catchGameStore?.$phase
            .dropFirst()
            .sink { [weak self] _ in
                self?.workSessionItem.submenu = self?.makeGoOutMenu()
            }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        updateStatusImage()
        button.imagePosition = .imageOnly
        button.toolTip = "CubePet"
        button.target = nil
        button.action = nil
    }

    private func configureMenu() {
        let menu = rootMenu
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = Self.fixedMenuWidth
        configureRootMenuImages()

        petMenuWindowItem.target = self
        menu.addItem(petMenuWindowItem)

        todoReminderItem.target = self
        pomodoroItem.target = self
        let utilitiesMenu = NSMenu()
        utilitiesMenu.autoenablesItems = false
        utilitiesMenu.addItem(todoReminderItem)
        utilitiesMenu.addItem(pomodoroItem)
        utilitiesItem.submenu = utilitiesMenu
        menu.addItem(utilitiesItem)

        workSessionItem.submenu = makeGoOutMenu()
        menu.addItem(workSessionItem)

        // Keep the food submenu available to the pet action panel without
        // exposing the old standalone shop in the status menu.
        shopItem.submenu = makeShopMenu()

        skinItem.submenu = makeSkinMenu()
        menu.addItem(skinItem)

        petItem.submenu = makePetMenu()
        menu.addItem(petItem)

        petCustomizationItem.target = self
        menu.addItem(petCustomizationItem)

        settingItem.submenu = makeSettingMenu()
        menu.addItem(settingItem)

        menu.addItem(.separator())

        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateLocalizedText()
    }

    private func configureRootMenuImages() {
        shopItem.image = NSImage(systemSymbolName: "bag", accessibilityDescription: nil)
        petMenuWindowItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        utilitiesItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        todoReminderItem.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
        pomodoroItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        workSessionItem.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)
        skinItem.image = NSImage(systemSymbolName: "tshirt", accessibilityDescription: nil)
        petItem.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
        settingItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        showSystemInfoItem.image = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        isRootMenuOpen = true
        progressStore.synchronizeRuntime(ageStore.totalRuntime)
        hungerStore.refresh()
        refreshPetMenu()
        updateLocalizedText()
        applyMenuStyle()
        // System info display was removed — never start the monitor.
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        isRootMenuOpen = false
        metricsMonitor.stop()
        updateMetricsMenuState()
        updateProgressMenuState()
    }

    func showMenuFromShortcut() {
        progressStore.synchronizeRuntime(ageStore.totalRuntime)
        hungerStore.refresh()
        refreshPetMenu()
        updateLocalizedText()
        _ = rootMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func showPetContextMenu(at screenPoint: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPetContextMenuOpenTime >= 0.08 else { return }
        lastPetContextMenuOpenTime = now

        progressStore.synchronizeRuntime(ageStore.totalRuntime)
        hungerStore.refresh()
        updateLocalizedText()

        let menu = makePetContextMenu()
        applyMenuStyle(to: menu)
        _ = menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    func showFoodShopMenuFromActionPanel(at screenPoint: NSPoint) {
        progressStore.synchronizeRuntime(ageStore.totalRuntime)
        hungerStore.refresh()
        updateLocalizedText()

        guard let menu = shopFoodItem.submenu else { return }
        applyMenuStyle(to: menu)
        _ = menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    func showSettingsMenuFromActionPanel(at screenPoint: NSPoint) {
        updateLocalizedText()

        guard let menu = settingItem.submenu else { return }
        applyMenuStyle(to: menu)
        _ = menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    @objc private func quit() {
        onQuit()
    }

    private func applyMenuStyle() {
        applyMenuStyle(to: rootMenu)
    }

    private func applyMenuStyle(to menu: NSMenu) {
        applyMenuAppearance(to: menu)
        applyMenuFont(to: menu)
        menu.update()
    }

    private func applyMenuAppearance(to menu: NSMenu) {
        menu.appearance = Self.fixedMenuAppearance
        for item in menu.items {
            if let submenu = item.submenu {
                applyMenuAppearance(to: submenu)
            }
        }
    }

    private func applyMenuFont(to menu: NSMenu) {
        let font = menuFontSettings.font.menuFont
        for item in menu.items where !item.isSeparatorItem {
            applyMenuFont(to: item, font: font)
            if let submenu = item.submenu {
                applyMenuFont(to: submenu)
            }
        }
    }

    private func applyMenuFont(to item: NSMenuItem, font: NSFont) {
        if let rowView = item.view as? FixedMenuStatusRowView {
            rowView.applyMenuFont(font)
        } else if let rowView = item.view as? FixedMenuMeterRowView {
            rowView.applyMenuFont(font)
        }

        let currentTitle = item.attributedTitle
        let hasParagraphStyle = currentTitle?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) != nil
        let hasExplicitColor = currentTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil

        if hasParagraphStyle || hasExplicitColor {
            let title = NSMutableAttributedString(attributedString: currentTitle ?? NSAttributedString(string: ""))
            title.addAttribute(NSAttributedString.Key.font, value: font, range: NSRange(location: 0, length: title.length))
            item.attributedTitle = title
            return
        }

        if item.title.isEmpty {
            item.attributedTitle = nil
            return
        }

        item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: font])
    }

    @objc private func showShortcutSettings() {
        onShowShortcutSettings()
    }

    @objc private func showPermissionSettings() {
        onShowPermissionSettings()
    }

    @objc private func selectMenuFont(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let font = MenuFont(rawValue: rawValue)
        else { return }

        menuFontSettings.select(font)
        applyMenuStyle()
        updateMenuFontMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginController.toggle()
            updateLaunchAtLoginMenuState()

            if launchAtLoginController.requiresApproval {
                showLaunchAtLoginAlert(
                    title: languageSettings.launchAtLoginText(.approvalRequiredTitle),
                    message: languageSettings.launchAtLoginText(.approvalRequiredMessage)
                )
            }
        } catch {
            showLaunchAtLoginAlert(
                title: languageSettings.launchAtLoginText(.updateFailedTitle),
                message: error.localizedDescription
            )
        }
    }

    @objc private func openPetCustomization() {
        guard featureEntitlementStore.isUnlocked(.petCustomization) else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = languageSettings.text(.petCustomizationLocked)
            alert.informativeText = languageSettings.text(.petCustomizationLockedMessage)
            alert.addButton(withTitle: languageSettings.text(.ok))
            alert.runModal()
            return
        }

        onShowPetCustomization()
    }

    @objc private func openPetMenu() {
        onShowPetMenu()
    }

    @objc private func openTodoReminder() {
        onShowTodoReminder()
    }

    @objc private func openPomodoro() {
        onShowPomodoro()
    }

    @objc private func openWorkSession() {
        onShowWorkSession()
    }

    @objc private func selectMoveToTrash() {
        feedSettings.destination = .trash
        updateFeedMenuState()
    }

    @objc private func selectMoveToFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = languageSettings.text(.chooseFeedFolder)
        panel.prompt = languageSettings.text(.choose)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = feedSettings.folderURL

        if panel.runModal() == .OK, let url = panel.url {
            feedSettings.folderURL = url
            feedSettings.destination = .folder
        }

        updateFeedMenuState()
    }

    @objc private func selectAirDrop() {
        feedSettings.destination = .airDrop
        updateFeedMenuState()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = AppLanguage(rawValue: rawValue)
        else { return }

        applyLanguage(language)
    }

    private func applyLanguage(_ language: AppLanguage) {
        languageSettings.language = language
        updateLocalizedText()
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let skinID = sender.representedObject as? String else { return }

        selectSkin(id: skinID)
    }

    private func selectSkin(id skinID: String) {
        if appearanceSettings.selectSkin(id: skinID, progress: progressStore) {
            updateStatusImage()
        }
        updateSkinMenuState()
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let petID = sender.representedObject as? String else { return }

        selectPet(id: petID)
    }

    private func selectPet(id petID: String) {
        let didSelect = PetCatalog.pet(id: petID) != nil
            ? appearanceSettings.selectPet(id: petID, progress: progressStore)
            : appearanceSettings.selectCustomPet(
                id: petID,
                customizationStore: customizationStore,
                featureEntitlementStore: featureEntitlementStore
            )

        if didSelect {
            skinItem.submenu = makeSkinMenu()
            shopSkinsItem.submenu = makeShopSkinMenu()
            updateStatusImage()
        }
        updatePetMenuState()
        updateSkinMenuState()
    }

    @objc private func buyFood(_ sender: NSMenuItem) {
        guard
            let foodID = sender.representedObject as? String,
            ShopCatalog.food(id: foodID) != nil
        else { return }

        buyFood(id: foodID)
    }

    @objc private func startTravel(_ sender: NSMenuItem) {
        guard let travelStore, !travelStore.state.isTraveling else { return }
        travelStore.startTrip()
    }

    private func buyFood(id foodID: String) {
        guard
            let food = ShopCatalog.food(id: foodID),
            progressStore.canAfford(food)
        else { return }

        do {
            let createdFood = try DesktopFoodFile.create(
                food: food,
                displayName: languageSettings.foodName(food.name)
            )
            guard progressStore.purchaseFood(food, token: createdFood.payload.token) else {
                DesktopFoodFile.remove(createdFood.url)
                return
            }
        } catch {
            showFoodCreationError(error)
            return
        }

        updateProgressMenuState()
    }

    private func showFoodCreationError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = languageSettings.text(.foodCreationFailed)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: languageSettings.text(.ok))
        alert.runModal()
    }

    @objc private func buySkin(_ sender: NSMenuItem) {
        guard
            let skinID = sender.representedObject as? String,
            appearanceSettings.selectedPet.skin(id: skinID) != nil
        else { return }

        buySkin(id: skinID)
    }

    private func buySkin(id skinID: String) {
        guard
            let skin = appearanceSettings.selectedPet.skin(id: skinID),
            progressStore.buySkin(skin, for: appearanceSettings.selectedPetID)
        else { return }

        _ = appearanceSettings.selectSkin(id: skin.id, progress: progressStore)
        updateStatusImage()
        updateProgressMenuState()
    }

    @objc private func buyPet(_ sender: NSMenuItem) {
        guard
            let petID = sender.representedObject as? String,
            PetCatalog.pet(id: petID) != nil
        else { return }

        buyPet(id: petID)
    }

    private func buyPet(id petID: String) {
        guard
            let pet = PetCatalog.pet(id: petID),
            progressStore.buyPet(pet)
        else { return }

        _ = appearanceSettings.selectPet(id: pet.id, progress: progressStore)
        skinItem.submenu = makeSkinMenu()
        shopSkinsItem.submenu = makeShopSkinMenu()
        updateStatusImage()
        updateProgressMenuState()
    }

    private func makeShopMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        shopFoodMenuItems.removeAll()
        shopPetMenuItems.removeAll()

        let foodMenu = NSMenu()
        foodMenu.autoenablesItems = false
        for food in ShopCatalog.foods {
            let item = NSMenuItem(title: "", action: #selector(buyFood(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = food.id
            foodMenu.addItem(item)
            shopFoodMenuItems[food.id] = item
        }
        shopFoodItem.image = NSImage(
            systemSymbolName: "takeoutbag.and.cup.and.straw",
            accessibilityDescription: languageSettings.text(.food)
        )
        shopFoodItem.submenu = foodMenu
        menu.addItem(shopFoodItem)

        shopSkinsItem.image = NSImage(systemSymbolName: "tshirt", accessibilityDescription: nil)
        shopSkinsItem.submenu = makeShopSkinMenu()
        menu.addItem(shopSkinsItem)

        let petMenu = NSMenu()
        petMenu.autoenablesItems = false
        for pet in PetCatalog.pets {
            let item = NSMenuItem(title: "", action: #selector(buyPet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            item.image = Self.makeStatusImage(pet: pet, skin: pet.skins[0])
            petMenu.addItem(item)
            shopPetMenuItems[pet.id] = item
        }
        shopPetsItem.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
        shopPetsItem.submenu = petMenu
        menu.addItem(shopPetsItem)

        updateShopMenuState()
        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makeShopSkinMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        shopSkinMenuItems.removeAll()

        guard !appearanceSettings.isCustomPetSelected else {
            menu.appearance = Self.fixedMenuAppearance
            return menu
        }

        for skin in appearanceSettings.selectedPet.skins {
            let item = NSMenuItem(title: "", action: #selector(buySkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skin.id
            item.image = Self.makeSkinSwatch(color: skin.color)
            menu.addItem(item)
            shopSkinMenuItems[skin.id] = item
        }

        updateShopMenuState()
        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makeSkinMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        skinMenuItems.removeAll()

        guard !appearanceSettings.isCustomPetSelected else {
            menu.appearance = Self.fixedMenuAppearance
            return menu
        }

        for skin in appearanceSettings.selectedPet.skins {
            let item = NSMenuItem(title: "", action: #selector(selectSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skin.id
            item.image = Self.makeSkinSwatch(color: skin.color)
            menu.addItem(item)
            skinMenuItems[skin.id] = item
        }

        updateSkinMenuState()
        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makeSettingMenu() -> NSMenu {
        let menu = NSMenu()

        let feedMenu = NSMenu()

        moveToTrashItem.target = self
        feedMenu.addItem(moveToTrashItem)

        moveToFolderItem.target = self
        feedMenu.addItem(moveToFolderItem)

        airDropItem.target = self
        feedMenu.addItem(airDropItem)

        feedItem.submenu = feedMenu
        menu.addItem(feedItem)

        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
            languageMenuItems[language] = item
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())
        let fontMenu = NSMenu()
        fontMenu.autoenablesItems = false
        menuFontMenuItems.removeAll()
        for font in MenuFont.selectableCases {
            let item = NSMenuItem(title: "", action: #selector(selectMenuFont(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = font.rawValue
            fontMenu.addItem(item)
            menuFontMenuItems[font] = item
        }
        menuFontItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        menuFontItem.submenu = fontMenu
        menu.addItem(menuFontItem)

        shortcutSettingsItem.target = self
        shortcutSettingsItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(shortcutSettingsItem)

        permissionSettingsItem.target = self
        permissionSettingsItem.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        menu.addItem(permissionSettingsItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(launchAtLoginItem)

        updateFeedMenuState()
        updatePetMenuState()
        updateLanguageMenuState()
        updateSystemInfoVisibility()

        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makeSubmenuClone(of source: NSMenu) -> NSMenu {
        let clone = NSMenu()
        clone.autoenablesItems = false
        var kept: [NSMenuItem] = []
        for item in source.items {
            if item.view != nil {
                continue
            }
            if item.isSeparatorItem,
               kept.last?.isSeparatorItem == true
               || kept.last == nil
               || kept.last?.view != nil {
                continue
            }
            let cloned = makeSubmenuItemClone(of: item)
            clone.addItem(cloned)
            kept.append(cloned)
        }
        if clone.items.last?.isSeparatorItem == true {
            clone.removeItem(clone.items.last!)
        }
        clone.appearance = Self.fixedMenuAppearance
        return clone
    }

    private func makeSubmenuItemClone(of source: NSMenuItem) -> NSMenuItem {
        let clone: NSMenuItem
        if source.isSeparatorItem {
            clone = NSMenuItem.separator()
        } else {
            clone = NSMenuItem(
                title: source.title,
                action: source.action,
                keyEquivalent: source.keyEquivalent
            )
            clone.target = source.target
            if let attributedTitle = source.attributedTitle {
                clone.attributedTitle = attributedTitle
            }
            clone.image = source.image
            clone.toolTip = source.toolTip
            clone.representedObject = source.representedObject
            clone.state = source.state
            clone.indentationLevel = source.indentationLevel
        }

        if let sourceSubmenu = source.submenu {
            clone.submenu = makeSubmenuClone(of: sourceSubmenu)
        }

        clone.view = source.view
        return clone
    }

    private func makePetContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Self.petContextMenuWidth

        let coinsView = FixedMenuStatusRowView(width: Self.petContextMenuWidth, height: Self.fixedMenuRowHeight)
        let level = progressStore.level(for: appearanceSettings.selectedPetID)
        coinsView.setText(
            left: "\(languageSettings.text(.level)) \(level)",
            right: "\(progressStore.coins)G"
        )
        let coinsItem = NSMenuItem()
        coinsItem.view = coinsView
        coinsItem.isEnabled = false
        menu.addItem(coinsItem)

        // 等级进度条:复刻饱腹度样式,展示当前宠物经验进度
        let levelView = FixedMenuMeterRowView(width: Self.petContextMenuWidth, height: Self.meterMenuRowHeight)
        let experienceProgress = progressStore.experienceProgress(for: appearanceSettings.selectedPetID)
        levelView.setValue(
            label: "经验值",
            fraction: Double(experienceProgress) / 100,
            valueText: "\(experienceProgress)/100"
        )
        let levelItem = NSMenuItem()
        levelItem.view = levelView
        levelItem.isEnabled = false
        menu.addItem(levelItem)

        let satietyView = FixedMenuMeterRowView(width: Self.petContextMenuWidth, height: Self.meterMenuRowHeight)
        satietyView.setValue(
            label: languageSettings.text(.satiety),
            fraction: hungerStore.satietyFraction,
            valueText: "\(hungerStore.satiety)%"
        )
        let satietyItem = NSMenuItem()
        satietyItem.view = satietyView
        satietyItem.isEnabled = false
        menu.addItem(satietyItem)

        menu.addItem(.separator())

        let foodItem = NSMenuItem(
            title: languageSettings.text(.buyFood),
            action: nil,
            keyEquivalent: ""
        )
        foodItem.image = NSImage(
            systemSymbolName: "takeoutbag.and.cup.and.straw",
            accessibilityDescription: languageSettings.text(.food)
        )
        foodItem.submenu = makePetContextFoodMenu()
        menu.addItem(foodItem)

        // 「召唤主菜单」:克隆 rootMenu 的内容作为 submenu,鼠标悬停自动展开
        let summonMenuItem = NSMenuItem(
            title: languageSettings.text(.showMainMenu),
            action: nil,
            keyEquivalent: ""
        )
        summonMenuItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
        summonMenuItem.submenu = makeSubmenuClone(of: rootMenu)
        menu.addItem(summonMenuItem)

        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makePetContextFoodMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for food in ShopCatalog.foods {
            let item = NSMenuItem(title: "", action: #selector(buyFood(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = food.id
            item.attributedTitle = foodStoreTitle(food)
            item.toolTip = foodDetailText(food)
            item.isEnabled = progressStore.canAfford(food)
            menu.addItem(item)
        }

        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    /// "比比十出发！" — submenu of the root menu's goOutItem. Lets the
    /// user pick whether the pet should go to work or go on a trip from
    /// the same top-level entry.
    private func makeGoOutMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let workItem = NSMenuItem(
            title: "比比十上班",
            action: #selector(openWorkSession),
            keyEquivalent: ""
        )
        workItem.target = self
        workItem.image = NSImage(
            systemSymbolName: "laptopcomputer",
            accessibilityDescription: nil
        )
        menu.addItem(workItem)

        // Travel item: title + action swap based on current state.
        // - Idle: "比比十出发！" → start a trip
        // - Traveling: "比比十回家" → end the trip early
        let isTraveling = travelStore?.state.isTraveling ?? false
        let travelMenuItem = NSMenuItem(
            title: isTraveling ? "比比十回家" : "比比十出发！",
            action: isTraveling ? #selector(endTravelEarly) : #selector(startTravel(_:)),
            keyEquivalent: ""
        )
        travelMenuItem.target = self
        travelMenuItem.image = NSImage(
            systemSymbolName: isTraveling ? "house.fill" : "airplane",
            accessibilityDescription: nil
        )
        menu.addItem(travelMenuItem)

        let isCatchGameActive = catchGameStore?.phase == .playing
        let gameItem = NSMenuItem(
            title: isCatchGameActive ? "结束游戏" : "摇摇乐",
            action: isCatchGameActive ? #selector(endCatchGame) : #selector(startCatchGame),
            keyEquivalent: ""
        )
        gameItem.target = self
        gameItem.image = NSImage(
            systemSymbolName: isCatchGameActive ? "stop.circle" : "figure.boxing",
            accessibilityDescription: nil
        )
        menu.addItem(gameItem)

        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    @objc private func endTravelEarly() {
        guard let travelStore, travelStore.state.isTraveling else { return }
        travelStore.endTripEarly()
    }

    @objc private func startCatchGame() {
        onStartCatchGame()
    }

    @objc private func endCatchGame() {
        catchGameStore?.dismiss()
    }

    private func makePetContextSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let feedMenu = NSMenu()
        feedMenu.autoenablesItems = false

        let trashItem = NSMenuItem(title: languageSettings.text(.moveToTrash), action: #selector(selectMoveToTrash), keyEquivalent: "")
        trashItem.target = self
        trashItem.state = feedSettings.destination == .trash ? .on : .off
        feedMenu.addItem(trashItem)

        let folderItem = NSMenuItem(
            title: languageSettings.moveToFolderTitle(folderName: feedSettings.folderURL?.lastPathComponent),
            action: #selector(selectMoveToFolder),
            keyEquivalent: ""
        )
        folderItem.target = self
        folderItem.state = feedSettings.destination == .folder ? .on : .off
        folderItem.toolTip = feedSettings.folderURL?.path
        feedMenu.addItem(folderItem)

        let airDropItem = NSMenuItem(title: languageSettings.text(.airDrop), action: #selector(selectAirDrop), keyEquivalent: "")
        airDropItem.target = self
        airDropItem.state = feedSettings.destination == .airDrop ? .on : .off
        feedMenu.addItem(airDropItem)

        let feedRootItem = NSMenuItem(title: languageSettings.text(.eatAction), action: nil, keyEquivalent: "")
        feedRootItem.submenu = feedMenu
        menu.addItem(feedRootItem)

        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = languageSettings.language == language ? .on : .off
            languageMenu.addItem(item)
        }
        let languageRootItem = NSMenuItem(title: languageSettings.text(.language), action: nil, keyEquivalent: "")
        languageRootItem.submenu = languageMenu
        menu.addItem(languageRootItem)

        menu.addItem(.separator())

        let shortcutItem = NSMenuItem(
            title: languageSettings.text(.shortcutSettings),
            action: #selector(showShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        shortcutItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutItem.toolTip = String(
            format: languageSettings.shortcutText(.currentShortcutTooltip),
            shortcutSettings.shortcut.displayString
        )
        menu.addItem(shortcutItem)

        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func makePetMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        petMenuItems.removeAll()

        for pet in PetCatalog.pets {
            let item = NSMenuItem(title: "", action: #selector(selectPet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            item.isEnabled = true
            item.image = Self.makeStatusImage(pet: pet, skin: pet.skins[0])
            menu.addItem(item)
            petMenuItems[pet.id] = item
        }

        if featureEntitlementStore.isUnlocked(.petCustomization) {
            for pet in customizationStore.customPets {
                let item = NSMenuItem(title: pet.name, action: #selector(selectPet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pet.id
                item.isEnabled = true
                item.image = customPetStatusImage(pet)
                menu.addItem(item)
                petMenuItems[pet.id] = item
            }
        }

        updatePetMenuState()
        menu.appearance = Self.fixedMenuAppearance
        return menu
    }

    private func refreshPetMenu() {
        petItem.submenu = makePetMenu()
    }

    private func refreshAppearanceMenuAndIcon() {
        refreshPetMenu()
        skinItem.submenu = makeSkinMenu()
        shopSkinsItem.submenu = makeShopSkinMenu()
        updateStatusImage()
        updatePetMenuState()
        updateSkinMenuState()
    }

    private func updateLocalizedText() {
        petMenuWindowItem.title = "商店"
        todoReminderItem.title = "待办提醒"
        pomodoroItem.title = "番茄钟"
        workSessionItem.title = "指挥比比十"
        workSessionItem.submenu = makeGoOutMenu()
        skinItem.title = languageSettings.text(.changeSkin)
        shopItem.title = languageSettings.text(.shop)
        shopFoodItem.title = languageSettings.text(.food)
        shopSkinsItem.title = languageSettings.text(.skins)
        shopPetsItem.title = languageSettings.text(.pets)
        settingItem.title = languageSettings.text(.setting)
        petItem.title = languageSettings.text(.pet)
        skinItem.isEnabled = !appearanceSettings.isCustomPetSelected
        updatePetCustomizationMenuState()
        quitItem.title = languageSettings.text(.exit)
        menuFontItem.title = languageSettings.text(.menuFont)
        for font in MenuFont.selectableCases {
            menuFontMenuItems[font]?.title = menuFontTitle(font)
        }
        feedItem.title = languageSettings.text(.eatAction)
        languageItem.title = languageSettings.text(.language)
        // showSystemInfoItem is no longer added to any menu, so don't bother
        // updating its title. Keep the property as a no-op anchor so the
        // call sites don't need to change.
        updateShortcutSettingsMenuState()
        permissionSettingsItem.title = languageSettings.permissionSettingsText(.title)
        updateLaunchAtLoginMenuState()
        updateMetricsMenuState()
        updateProgressTitle()
        updateHungerMenuState()
        updateFeedMenuState()
        updatePetMenuState()
        updateSkinMenuState()
        updateShopMenuState()
        updateLanguageMenuState()
        updateMenuFontMenuState()
        updateSystemInfoVisibility()
        applyMenuFont(to: rootMenu)
    }

    
    private func updateFeedMenuState() {
        moveToTrashItem.state = feedSettings.destination == .trash ? .on : .off
        moveToFolderItem.state = feedSettings.destination == .folder ? .on : .off
        airDropItem.state = feedSettings.destination == .airDrop ? .on : .off
        moveToTrashItem.title = languageSettings.text(.moveToTrash)
        airDropItem.title = languageSettings.text(.airDrop)

        if let folderURL = feedSettings.folderURL {
            moveToFolderItem.title = languageSettings.moveToFolderTitle(folderName: folderURL.lastPathComponent)
            moveToFolderItem.toolTip = folderURL.path
        } else {
            moveToFolderItem.title = languageSettings.moveToFolderTitle(folderName: nil)
            moveToFolderItem.toolTip = nil
        }
    }

    private func updateLanguageMenuState() {
        for (language, item) in languageMenuItems {
            item.state = languageSettings.language == language ? .on : .off
        }
    }

    private func updateMenuFontMenuState() {
        for font in MenuFont.selectableCases {
            menuFontMenuItems[font]?.state = menuFontSettings.font == font ? .on : .off
        }
    }

    private func menuFontTitle(_ font: MenuFont) -> String {
        switch font {
        case .system:
            languageSettings.text(.menuFontSystem)
        case .hannotate:
            languageSettings.text(.menuFontHannotate)
        case .yuppy:
            languageSettings.text(.menuFontYuppy)
        }
    }

    private func updatePetMenuState() {
        for pet in PetCatalog.pets {
            guard let item = petMenuItems[pet.id] else { continue }
            item.title = languageSettings.petName(pet.name)
            item.isEnabled = progressStore.ownsPet(pet.id)
            item.state = appearanceSettings.selectedPetID == pet.id ? .on : .off
        }
        for pet in customizationStore.customPets {
            guard let item = petMenuItems[pet.id] else { continue }
            item.title = pet.name
            item.isEnabled = featureEntitlementStore.isUnlocked(.petCustomization)
            item.state = appearanceSettings.selectedPetID == pet.id ? .on : .off
        }
        skinItem.isEnabled = !appearanceSettings.isCustomPetSelected
        updatePetCustomizationMenuState()
    }

    private func updatePetCustomizationMenuState() {
        let isUnlocked = featureEntitlementStore.isUnlocked(.petCustomization)
        petCustomizationItem.title = languageSettings.text(.petCustomization)
        petCustomizationItem.isEnabled = isUnlocked
        petCustomizationItem.image = NSImage(
            systemSymbolName: isUnlocked ? "slider.horizontal.3" : "lock.fill",
            accessibilityDescription: nil
        )
    }

    private func updateSkinMenuState() {
        guard !appearanceSettings.isCustomPetSelected else {
            skinItem.isEnabled = false
            return
        }
        let level = progressStore.level(for: appearanceSettings.selectedPetID)

        for skin in appearanceSettings.selectedPet.skins {
            guard let item = skinMenuItems[skin.id] else { continue }

            let isUnlocked = progressStore.ownsSkin(skin.id) && skin.isUnlocked(at: level)
            item.isEnabled = isUnlocked
            item.state = appearanceSettings.selectedSkinID == skin.id ? .on : .off
            item.title = level < skin.unlockLevel
                ? "\(languageSettings.skinName(skin.name)) · Lv\(skin.unlockLevel)"
                : languageSettings.skinName(skin.name)
        }
    }

    private func updateProgressMenuState() {
        updateProgressTitle()
        updatePetMenuState()
        updateSkinMenuState()
        updateShopMenuState()
    }

    private func updateProgressTitle() {
        let level = progressStore.level(for: appearanceSettings.selectedPetID)
        progressRowView.setText(
            left: "\(languageSettings.text(.level)) \(level)",
            right: "\(progressStore.coins)G"
        )
    }

    private func updateHungerMenuState() {
        satietyRowView.setValue(
            label: languageSettings.text(.satiety),
            fraction: hungerStore.satietyFraction,
            valueText: "\(hungerStore.satiety)%"
        )
    }

    private func updateShopMenuState() {
        for food in ShopCatalog.foods {
            guard let item = shopFoodMenuItems[food.id] else { continue }
            item.attributedTitle = foodStoreTitle(food)
            item.toolTip = foodDetailText(food)
            item.isEnabled = progressStore.coins >= food.price
        }

        if !appearanceSettings.isCustomPetSelected {
            let petID = appearanceSettings.selectedPetID
            let level = progressStore.level(for: petID)
            for skin in appearanceSettings.selectedPet.skins {
                guard let item = shopSkinMenuItems[skin.id] else { continue }
                let isOwned = progressStore.ownsSkin(skin.id)
                item.title = languageSettings.skinStoreTitle(skin, isOwned: isOwned, currentLevel: level)
                item.isEnabled = !isOwned && skin.isUnlocked(at: level) && progressStore.coins >= skin.price
            }
        }

        for pet in PetCatalog.pets {
            guard let item = shopPetMenuItems[pet.id] else { continue }
            let isOwned = progressStore.ownsPet(pet.id)
            item.title = languageSettings.petStoreTitle(pet, isOwned: isOwned)
            item.isEnabled = !isOwned && progressStore.coins >= pet.price
        }
    }

    private func foodStoreTitle(_ food: FoodDefinition) -> NSAttributedString {
        let font = menuFontSettings.font.menuFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .right, location: foodPriceTabLocation(font: font))]

        return NSAttributedString(
            string: "\(languageSettings.foodName(food.name))\t\(food.price)G",
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func foodDetailText(_ food: FoodDefinition) -> String {
        "\(languageSettings.satietyGainText(food.satiety)) · \(languageSettings.experienceGainText(food.experience))"
    }

    private func foodPriceTabLocation(font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let longestName = ShopCatalog.foods
            .map { (languageSettings.foodName($0.name) as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let widestPrice = ShopCatalog.foods
            .map { ("\($0.price)G" as NSString).size(withAttributes: attributes).width }
            .max() ?? 0

        return ceil(longestName + 12 + widestPrice)
    }

    private func updateMetricsMenuState() {
        cpuMemoryRowView.setText(
            left: "\(languageSettings.text(.cpu)): \(percentage(latestMetrics.cpuUsage))",
            right: "\(languageSettings.text(.memory)): \(percentage(latestMetrics.memoryUsage))"
        )
        networkRowView.setText(
            left: languageSettings.text(.network),
            right: "↓\(speed(latestMetrics.downloadBytesPerSecond)) ↑\(speed(latestMetrics.uploadBytesPerSecond))"
        )
    }

    private func updateSystemInfoVisibility() {
        // System info display was removed — keep the metric rows hidden
        // permanently. Method kept as a no-op for any call sites that
        // haven't been migrated yet.
        cpuItem.isHidden = true
        networkItem.isHidden = true
        metricsBottomSeparator.isHidden = true
    }

    private func updateShortcutSettingsMenuState() {
        let displayString = shortcutSettings.shortcut.displayString
        shortcutSettingsItem.title = languageSettings.text(.shortcutSettings)
        shortcutSettingsItem.toolTip = String(
            format: languageSettings.shortcutText(.currentShortcutTooltip),
            displayString
        )
    }

    private func updateLaunchAtLoginMenuState() {
        launchAtLoginItem.title = languageSettings.launchAtLoginText(.title)
        launchAtLoginItem.state = launchAtLoginController.isEnabled ? .on : .off
    }

    private func showLaunchAtLoginAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: languageSettings.text(.ok))
        alert.runModal()
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1_024 {
            return "\(Int(bytesPerSecond.rounded())) B/s"
        }
        if bytesPerSecond < 1_048_576 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_024)
        }
        if bytesPerSecond < 1_073_741_824 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
    }

    private func updateStatusImage() {
        statusItem.button?.image = CubePetBrandIcon.statusImage()
    }

    private func customPetStatusImage(_ pet: CustomPetDefinition) -> NSImage? {
        let state = pet.visualConfiguration.configuration(for: .normal)
        guard
            case let .importedAsset(assetID) = state.base,
            let url = customizationStore.assetURL(for: assetID),
            let source = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: 18, height: 18),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func makeStatusImage(pet: PetDefinition, skin: PetSkinDefinition) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        switch pet.visualKind {
        case .cube:
            let bodyRect = NSRect(x: 2.5, y: 2.5, width: 13, height: 13)
            let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
            let cubeStyle = CubeSkinStyle(skinID: skin.id)
            switch cubeStyle {
            case .solid:
                skin.color.setFill()
                bodyPath.fill()
            case .ice:
                NSGradient(
                    starting: NSColor(srgbRed: 0.76, green: 0.95, blue: 1, alpha: 1),
                    ending: NSColor(srgbRed: 0.24, green: 0.63, blue: 0.90, alpha: 1)
                )?.draw(in: bodyPath, angle: -45)
                NSColor.white.withAlphaComponent(0.72).setStroke()
                bodyPath.lineWidth = 0.8
                bodyPath.stroke()
            case .rainbow:
                NSGradient(colors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple])?.draw(in: bodyPath, angle: -45)
            case .ice2:
                NSGradient(
                    starting: NSColor(srgbRed: 0.90, green: 0.99, blue: 1, alpha: 1),
                    ending: NSColor(srgbRed: 0.31, green: 0.66, blue: 0.80, alpha: 1)
                )?.draw(in: bodyPath, angle: -45)
                NSColor.white.withAlphaComponent(0.8).setStroke()
                bodyPath.lineWidth = 0.8
                bodyPath.stroke()
            case .rainbow2:
                NSGradient(colors: [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple])?.draw(in: bodyPath, angle: 0)
            }

            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 8, width: 2.5, height: 4), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 2.5, height: 4), xRadius: 1.2, yRadius: 1.2).fill()
        case .frog:
            NSGraphicsContext.current?.imageInterpolation = .high
            FrogPetAsset.image?.draw(
                in: NSRect(x: 0, y: 0, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.4, y: 11.8, width: 0.9, height: 0.9)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.9, y: 11.8, width: 0.9, height: 0.9)).fill()
        case .cat:
            NSGraphicsContext.current?.imageInterpolation = .high
            let catImage: NSImage? = switch skin.id {
            case "cat.grayTabby": CatPetAsset.grayTabbyImage
            case "cat.calico": CatPetAsset.calicoImage
            case "cat.black": CatPetAsset.blackImage
            case "cat.siamese": CatPetAsset.siameseImage
            case "cat.yellow": CatPetAsset.yellowImage
            default: CatPetAsset.image
            }
            catImage?.draw(
                in: NSRect(x: 0, y: 0, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            if skin.id != "cat.yellow" {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: 6.1, y: 11.1, width: 2.5, height: 2.5)).fill()
                NSBezierPath(ovalIn: NSRect(x: 9.1, y: 11.1, width: 2.5, height: 2.5)).fill()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 6.9, y: 11.9, width: 0.95, height: 0.95)).fill()
                NSBezierPath(ovalIn: NSRect(x: 9.9, y: 11.9, width: 0.95, height: 0.95)).fill()
            }
        case .dog:
            NSGraphicsContext.current?.imageInterpolation = .high
            let resourceName = skin.id == "dog.shiba" ? "ShibaPet" : "BeaglePetNormal"
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.draw(
                    in: NSRect(x: 0, y: 0, width: 18, height: 18),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        case .cookie:
            let cookieRect = NSRect(x: 1.8, y: 1.8, width: 14.4, height: 14.4)
            skin.color.setFill()
            NSBezierPath(ovalIn: cookieRect).fill()
            NSColor(srgbRed: 0.38, green: 0.18, blue: 0.08, alpha: 1).setFill()
            for point in [NSPoint(x: 5.1, y: 12.8), NSPoint(x: 13.1, y: 11.4), NSPoint(x: 11.9, y: 5.1)] {
                NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: 2.1, height: 2.1)).fill()
            }
            NSBezierPath(ovalIn: NSRect(x: 6.3, y: 8.5, width: 1.3, height: 1.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.4, y: 8.5, width: 1.3, height: 1.5)).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func makeSkinSwatch(color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)

        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 12, height: 12), xRadius: 3, yRadius: 3).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private final class FixedMenuStatusRowView: NSView {
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let preferredLeftWidth: CGFloat?
    private let horizontalInset: CGFloat = 16
    private let gap: CGFloat = 8
    private let labelHeight: CGFloat = 17

    init(width: CGFloat, height: CGFloat, leftWidth: CGFloat? = nil) {
        self.preferredLeftWidth = leftWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for label in [leftLabel, rightLabel] {
            label.font = .menuFont(ofSize: 0)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
        }

        rightLabel.alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        frame.size
    }

    override func layout() {
        super.layout()

        let y = floor((bounds.height - labelHeight) / 2)
        let contentWidth = max(0, bounds.width - horizontalInset * 2)
        let leftWidth: CGFloat
        let rightWidth: CGFloat
        if let preferredLeftWidth {
            leftWidth = min(preferredLeftWidth, max(0, contentWidth - gap))
            rightWidth = max(0, contentWidth - leftWidth - gap)
        } else {
            rightWidth = min(92, max(58, contentWidth * 0.38))
            leftWidth = max(0, contentWidth - rightWidth - gap)
        }

        leftLabel.frame = NSRect(
            x: horizontalInset,
            y: y,
            width: leftWidth,
            height: labelHeight
        )
        rightLabel.frame = NSRect(
            x: horizontalInset + leftWidth + gap,
            y: y,
            width: rightWidth,
            height: labelHeight
        )
    }

    func setText(left: String, right: String) {
        leftLabel.stringValue = left
        rightLabel.stringValue = right
    }

    func applyMenuFont(_ font: NSFont) {
        leftLabel.font = font
        rightLabel.font = font
    }
}

private final class FixedMenuMeterRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    /// Custom drawn progress bar (NSProgressIndicator looked grey in
    /// the status menu and only turned blue on hover). Backed by
    /// two CALayers: a grey track and a blue fill whose width we set
    /// to `trackWidth * fraction` in `layout()`.
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let progressHeight: CGFloat = 6
    private var currentFraction: CGFloat = 1
    private let horizontalInset: CGFloat = 16
    private let labelHeight: CGFloat = 15

    init(width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // IMPORTANT: this view hosts CALayers, so it must be layer-backed
        // BEFORE we add any sublayers. Setting wantsLayer = true after the
        // fact means addSublayer goes to nil and the bar never paints.
        wantsLayer = true

        for label in [titleLabel, valueLabel] {
            label.font = .menuFont(ofSize: 0)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
        }

        valueLabel.alignment = .right

        trackLayer.cornerRadius = progressHeight / 2
        trackLayer.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        trackLayer.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(trackLayer)

        fillLayer.cornerRadius = progressHeight / 2
        fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        fillLayer.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        trackLayer.addSublayer(fillLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        frame.size
    }

    override func layout() {
        super.layout()

        let contentWidth = max(0, bounds.width - horizontalInset * 2)
        let valueWidth = min(72, max(42, contentWidth * 0.32))
        let titleWidth = max(0, contentWidth - valueWidth - 8)
        titleLabel.frame = NSRect(
            x: horizontalInset,
            y: bounds.height - labelHeight - 3,
            width: titleWidth,
            height: labelHeight
        )
        valueLabel.frame = NSRect(
            x: horizontalInset + titleWidth + 8,
            y: bounds.height - labelHeight - 3,
            width: valueWidth,
            height: labelHeight
        )
        let trackY: CGFloat = 6
        trackLayer.frame = NSRect(
            x: horizontalInset,
            y: trackY,
            width: contentWidth,
            height: progressHeight
        )
        let fillW = max(0, contentWidth * currentFraction)
        fillLayer.frame = NSRect(
            x: 0,
            y: 0,
            width: fillW,
            height: progressHeight
        )
    }

    func setValue(label: String, fraction: Double, valueText: String) {
        titleLabel.stringValue = label
        valueLabel.stringValue = valueText
        currentFraction = CGFloat(min(max(fraction, 0), 1))
        needsLayout = true
    }

    func applyMenuFont(_ font: NSFont) {
        titleLabel.font = font
        valueLabel.font = font
    }
}

private final class ExitAndMenuStyleRowView: NSView {
    var onQuit: (() -> Void)?
    var onSelectStyle: ((MenuStyle) -> Void)?

    private let exitButton = MenuHoverButton(title: "", target: nil, action: nil)
    private let glassSurface = NSVisualEffectView()
    private var styleButtons: [MenuStyle: MenuStyleButton] = [:]
    private let buttonSize: CGFloat = 20
    private let buttonSpacing: CGFloat = 6
    private let horizontalInset: CGFloat = 12

    init(width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        exitButton.target = self
        exitButton.action = #selector(quit)
        exitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        exitButton.imagePosition = .imageLeading
        exitButton.imageScaling = .scaleProportionallyDown
        exitButton.bezelStyle = .inline
        exitButton.controlSize = .small
        exitButton.alignment = .left
        addSubview(exitButton)

        glassSurface.material = .menu
        glassSurface.blendingMode = .withinWindow
        glassSurface.state = .active
        glassSurface.wantsLayer = true
        glassSurface.layer?.cornerRadius = 13
        glassSurface.layer?.masksToBounds = true
        addSubview(glassSurface)

        for style in MenuStyle.allCases {
            let button = MenuStyleButton(style: style, target: self, action: #selector(selectStyle(_:)))
            styleButtons[style] = button
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        frame.size
    }

    override func layout() {
        super.layout()

        let controlsWidth = buttonSize * CGFloat(MenuStyle.allCases.count)
            + buttonSpacing * CGFloat(MenuStyle.allCases.count - 1)
        let controlsX = bounds.width - horizontalInset - controlsWidth
        let buttonY = floor((bounds.height - buttonSize) / 2)
        glassSurface.frame = NSRect(
            x: controlsX - 8,
            y: 2,
            width: controlsWidth + 16,
            height: bounds.height - 4
        )
        exitButton.frame = NSRect(
            x: horizontalInset - 4,
            y: 3,
            width: max(0, controlsX - horizontalInset - 8),
            height: bounds.height - 6
        )

        for (index, style) in MenuStyle.allCases.enumerated() {
            styleButtons[style]?.frame = NSRect(
                x: controlsX + CGFloat(index) * (buttonSize + buttonSpacing),
                y: buttonY,
                width: buttonSize,
                height: buttonSize
            )
        }
    }

    func update(selectedStyle: MenuStyle, languageSettings: LanguageSettings, animated: Bool) {
        exitButton.title = languageSettings.text(.exit)
        exitButton.toolTip = languageSettings.text(.exit)
        updateGlassSurface(isVisible: selectedStyle == .liquidGlass, animated: animated)

        for style in MenuStyle.allCases {
            let title: String
            switch style {
            case .default:
                title = languageSettings.text(.menuStyleDefault)
            case .liquidGlass:
                title = languageSettings.text(.menuStyleLiquidGlass)
            case .dark:
                title = languageSettings.text(.menuStyleDark)
            case .light:
                title = languageSettings.text(.menuStyleLight)
            }
            styleButtons[style]?.update(
                isSelected: style == selectedStyle,
                tooltip: title,
                animated: animated
            )
        }
    }

    private func updateGlassSurface(isVisible: Bool, animated: Bool) {
        guard animated else {
            glassSurface.isHidden = !isVisible
            glassSurface.alphaValue = 1
            return
        }

        if isVisible {
            glassSurface.isHidden = false
            glassSurface.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                glassSurface.animator().alphaValue = 1
            }
        } else if !glassSurface.isHidden {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                glassSurface.animator().alphaValue = 0
            } completionHandler: { [weak glassSurface] in
                glassSurface?.isHidden = true
                glassSurface?.alphaValue = 1
            }
        }
    }

    @objc private func quit() {
        onQuit?()
    }

    @objc private func selectStyle(_ sender: MenuStyleButton) {
        onSelectStyle?(sender.style)
    }
}

private final class MenuStyleButton: NSButton {
    let style: MenuStyle
    private var isSelectedStyle = false
    private var isHovering = false {
        didSet { updateVisuals() }
    }
    private var hoverTrackingArea: NSTrackingArea?

    init(style: MenuStyle, target: AnyObject?, action: Selector?) {
        self.style = style
        super.init(frame: .zero)

        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
    }

    func update(isSelected: Bool, tooltip: String, animated: Bool) {
        let selectionChanged = isSelectedStyle != isSelected
        isSelectedStyle = isSelected
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        updateVisuals()

        guard animated, selectionChanged else { return }
        animateSelectionChange(selected: isSelected)
    }

    private func animateSelectionChange(selected: Bool) {
        let animation = CASpringAnimation(keyPath: "transform.scale")
        animation.fromValue = selected ? 0.82 : 1.12
        animation.toValue = 1
        animation.damping = 12
        animation.stiffness = 190
        animation.mass = 0.7
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        layer?.add(animation, forKey: "menuStyleSelection")
    }

    private func updateVisuals() {
        let backgroundColor: NSColor
        let foregroundColor: NSColor
        let borderColor: NSColor

        switch style {
        case .default:
            backgroundColor = .controlAccentColor
            foregroundColor = .white
            borderColor = .controlAccentColor
        case .liquidGlass:
            backgroundColor = .clear
            foregroundColor = .labelColor
            borderColor = .separatorColor
        case .dark:
            backgroundColor = .black
            foregroundColor = .white
            borderColor = .black
        case .light:
            backgroundColor = .white
            foregroundColor = .black
            borderColor = .quaternaryLabelColor
        }

        contentTintColor = foregroundColor
        layer?.backgroundColor = backgroundColor.cgColor
        let resolvedBorderColor = isHovering
            ? NSColor.controlAccentColor
            : (isSelectedStyle ? NSColor.controlAccentColor : borderColor)
        layer?.borderColor = resolvedBorderColor.cgColor
        layer?.borderWidth = (isSelectedStyle || isHovering) ? 2 : 1
        layer?.shadowColor = isHovering ? NSColor.controlAccentColor.cgColor : nil
        layer?.shadowOpacity = isHovering ? 0.28 : 0
        layer?.shadowRadius = isHovering ? 3 : 0
        layer?.shadowOffset = .zero
    }
}

private final class MenuHoverButton: NSButton {
    private var isHovering = false {
        didSet { updateHoverAppearance() }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 6
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    private func updateHoverAppearance() {
        let color = isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : NSColor.clear.cgColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        layer?.backgroundColor = color
        CATransaction.commit()
    }
}

private extension MenuStyle {
    var symbolName: String {
        switch self {
        case .default: "circle.lefthalf.filled"
        case .liquidGlass: "sparkles"
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }
}
