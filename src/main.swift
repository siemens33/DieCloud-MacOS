import AppKit
import WebKit
import QuartzCore
import Network

enum AppConfig {
    static let name = "DieCloude"
    static let version = "4.2.0"
    static let build = "36"
    static let author = "by siemens"
    static let homeURL = URL(string: "https://soundcloud.com/")!
    static let minSize = NSSize(width: 900, height: 600)
}

private enum DefaultsKey {
    static let adBlock = "DieCloudeAdBlockEnabled"
    static let focus = "DieCloudeFocusModeEnabled"
    static let theme = "DieCloudeDynamicThemeEnabled"
    static let modernDesign = "DieCloudeModernDesignEnabled"
    static let glassPanels = "DieCloudeGlassPanelsEnabled"
    static let roundedCards = "DieCloudeRoundedCardsEnabled"
    static let artworkHover = "DieCloudeArtworkHoverEnabled"
    static let compactMode = "DieCloudeCompactModeEnabled"
    static let accent = "DieCloudeAccentTheme"
    static let darkThemeFix = "DieCloudeVisualSystemV400Build31"

    /// «Что нового» показывается при каждом обновлении: ключ автоматически
    /// версионируется (DieCloudeWelcomeV402Shown → V403Shown → …), поэтому
    /// окно с изменениями новой версии увидит каждый пользователь.
    static var welcome: String {
        "DieCloudeWelcomeV" + AppConfig.version.replacingOccurrences(of: ".", with: "") + "Shown"
    }
}

/// Единый источник флагов настроек: тумблеры панели, UserDefaults и JS-движок
/// работают с одним списком — новый эффект добавляется одной строкой,
/// а не копипастой в трёх местах.
private final class SettingsState {
    struct Flag {
        let key: String        // ключ UserDefaults
        let jsKey: String      // ключ в theme-engine.js
        let title: String
        let tooltip: String    // показывается как описание под названием
        let defaultValue: Bool
        var value: Bool
        weak var control: NSControl?
    }

    private(set) var flags: [Flag]
    /// Цветовой акцент: mono / amber / blue / system.
    private(set) var accent: String

    init() {
        let initial: [(key: String, jsKey: String, title: String, tooltip: String, defaultValue: Bool)] = [
            (DefaultsKey.modernDesign, "modernDesign", "Минималистичный интерфейс DieCloude",
             "Тёмная монохромная тема поверх SoundCloud", true),
            (DefaultsKey.theme, "theme", "Белый фирменный акцент",
             "Кнопки и акценты — белый вместо оранжевого", true),
            (DefaultsKey.roundedCards, "roundedCards", "Аккуратное скругление обложек",
             "Скругляет только обложки треков, альбомов и плейлистов", true),
            (DefaultsKey.artworkHover, "artworkHover", "Мягкий эффект при наведении",
             "Слегка подсвечивает только обложку, не двигая карточку", true),
            (DefaultsKey.compactMode, "compactMode", "Компактная плотность интерфейса",
             "Уменьшает лишние вертикальные отступы без перестройки сетки SoundCloud", false),
            (DefaultsKey.focus, "focus", "Режим фокуса — скрыть рекомендации",
             "Убирает сайдбар, комментарии и промо", false),
            (DefaultsKey.adBlock, "adBlock", "Режим без рекламы",
             "Блокирует рекламные запросы, промо-треки и аудиопрероллы", true)
        ]
        flags = initial.map { Flag(key: $0.key, jsKey: $0.jsKey, title: $0.title, tooltip: $0.tooltip, defaultValue: $0.defaultValue, value: $0.defaultValue) }
        let savedAccent = UserDefaults.standard.string(forKey: DefaultsKey.accent)
        accent = ["mono", "amber", "blue", "system"].contains(savedAccent ?? "") ? savedAccent! : "mono"
        load()
    }

    /// Значения для инъекции в theme-engine.js. Для «системного» акцента
    /// прикладываем точный hex из macOS — CSS не умеет читать акцент сам.
    var json: String {
        var dict: [String: Any] = Dictionary(uniqueKeysWithValues: flags.map { ($0.jsKey, $0.value) })
        dict["accent"] = accent
        if accent == "system" { dict["accentHex"] = NSColor.controlAccentColor.hexString }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func value(for jsKey: String) -> Bool? {
        flags.first { $0.jsKey == jsKey }?.value
    }

    func setValue(_ value: Bool, for jsKey: String) {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return }
        flags[index].value = value
        UserDefaults.standard.set(value, forKey: flags[index].key)
    }

    func jsKey(of control: NSControl) -> String? {
        flags.first { $0.control === control }?.jsKey
    }

    func syncButton(for jsKey: String) {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return }
        applyValue(flags[index].value, to: flags[index].control)
    }

    private func applyValue(_ value: Bool, to control: NSControl?) {
        let state: NSControl.StateValue = value ? .on : .off
        if let sw = control as? NSSwitch {
            sw.state = state
        } else if let button = control as? NSButton {
            button.state = state
        }
    }

    /// Сброс дизайн-настроек (не трогает focus и adBlock).
    func resetDesign() {
        for index in flags.indices where flags[index].jsKey != "focus" && flags[index].jsKey != "adBlock" {
            flags[index].value = flags[index].defaultValue
            UserDefaults.standard.set(flags[index].defaultValue, forKey: flags[index].key)
            applyValue(flags[index].defaultValue, to: flags[index].control)
        }
        setAccent("mono")
        accentSegmented?.selectedSegment = 0
        accentPopup?.selectItem(at: 0)
    }

    /// Выбор акцента
    private static let accentTitles = ["Монохром (белый)", "Янтарный", "Синий", "Как в системе"]
    private static let accentValues = ["mono", "amber", "blue", "system"]
    private(set) weak var accentPopup: NSPopUpButton?
    private(set) weak var accentSegmented: NSSegmentedControl?

    func makeAccentControl(action: Selector, target: AnyObject) -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["Белый", "Янтарь", "Синий", "macOS"],
                                     trackingMode: .selectOne,
                                     target: target,
                                     action: action)
        seg.controlSize = .small
        seg.segmentStyle = .texturedRounded
        let index = Self.accentValues.firstIndex(of: accent) ?? 0
        seg.selectedSegment = index
        accentSegmented = seg
        return seg
    }

    func makeAccentPopup(action: Selector, target: AnyObject) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.accentTitles)
        popup.selectItem(at: Self.accentValues.firstIndex(of: accent) ?? 0)
        popup.target = target
        popup.action = action
        popup.toolTip = "Цвет кнопок, шкалы времени и громкости"
        accentPopup = popup
        return popup
    }

    var accentPopupIndex: Int? {
        guard let popup = accentPopup else { return nil }
        let index = popup.indexOfSelectedItem
        return Self.accentValues.indices.contains(index) ? index : nil
    }

    func setAccent(_ value: String) {
        accent = Self.accentValues.contains(value) ? value : "mono"
        UserDefaults.standard.set(accent, forKey: DefaultsKey.accent)
    }

    /// Тумблер настройки: подсказка флага становится видимым описанием строки.
    func makeSwitch(for jsKey: String, action: Selector, target: AnyObject) -> NSSwitch? {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return nil }
        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = flags[index].value ? .on : .off
        sw.target = target
        sw.action = action
        flags[index].control = sw
        return sw
    }

    func title(for jsKey: String) -> String {
        flags.first { $0.jsKey == jsKey }?.title ?? jsKey
    }

    func subtitle(for jsKey: String) -> String {
        flags.first { $0.jsKey == jsKey }?.tooltip ?? ""
    }

    private func load() {
        let defaults = UserDefaults.standard
        for index in flags.indices {
            flags[index].value = defaults.object(forKey: flags[index].key) == nil
                ? flags[index].defaultValue
                : defaults.bool(forKey: flags[index].key)
        }
    }
}

private extension NSColor {
    /// Hex системного акцента macOS для передачи в CSS.
    var hexString: String {
        guard let c = usingColorSpace(.deviceRGB) else { return "#ffffff" }
        let r = Int(round(c.redComponent * 255)), g = Int(round(c.greenComponent * 255)), b = Int(round(c.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// Кнопка тулбара: в покое полупрозрачная, при наведении проявляется
/// и подсвечивается мягкой круглой пилюлей — тихо и по-нативному.
private final class ToolbarButton: NSButton {
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var progress: NSProgressIndicator!
    private var titleLabel: NSTextField!
    private var sidePanel: NSVisualEffectView!
    private var sidePanelTrailing: NSLayoutConstraint!
    private var observations: [NSKeyValueObservation] = []
    private var adBlockRuleList: WKContentRuleList?
    private var vpnController: VPNWindowController?
    private let updateManager = UpdateManager()
    private var vpnHealthTimer: Timer?
    private let settings = SettingsState()
    private let nowPlaying = NowPlayingController()
    /// Кэш исходника theme-engine.js — не читаем файл с диска на каждый evaluate.
    private lazy var themeEngineSource: String = Self.loadThemeEngineSource()
    /// Прокси WKWebView сейчас направлен на локальный Xray.
    private var isAppProxyEnabled = false
    private var adBlockToolbarButton: NSButton?
    // Автосейв: если движок темы ещё не готов (страница грузится),
    // визуальное применение откладывается до didFinish.
    private var needsSettingsSync = false
    private var panelVisible = false
    // Статус движка и служебные оверлеи
    private var engineStatusLabel: NSTextField!
    private var statusBanner: NSVisualEffectView!
    private var statusBannerLabel: NSTextField!
    private var errorOverlay: NSVisualEffectView!
    private var errorDetail: NSTextField!
    private var playerMissingAnnounced = false
    private var connectionRetryWorkItem: DispatchWorkItem?

    // MARK: - Жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyDefaultsIfNeeded()
        buildMenu()
        buildWindow()
        wireNowPlaying()
        compileAdBlockRules()
        loadHome(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWelcomeIfNeeded()
        configureBackgroundServices()
        startVPNHealthCheck()
    }

    /// Мост: системные медиа-команды → клики по кнопкам SoundCloud,
    /// состояние плеера → MPNowPlayingInfoCenter, диагностика → панель.
    private func wireNowPlaying() {
        nowPlaying.performAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePlay: self.runPlayerScript(PlayerScripts.togglePlay)
            case .next: self.runPlayerScript(PlayerScripts.nextTrack)
            case .previous: self.runPlayerScript(PlayerScripts.previousTrack)
            }
        }
        nowPlaying.performSeek = { [weak self] position in
            self?.webView.evaluateJavaScript("window.__diecloude?.seek(\(position))", completionHandler: nil)
        }
        nowPlaying.onPlayerMissing = { [weak self] in self?.setEngineStatus(found: false) }
        nowPlaying.onPlayerFound = { [weak self] in self?.setEngineStatus(found: true) }
        nowPlaying.enableRemoteCommands()
    }

    /// Одноразовая миграция 4.0 (macOS 14+, Cmd+, вместо F1, noAds V8+).
    private func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.darkThemeFix) else { return }
        defaults.set(true, forKey: DefaultsKey.modernDesign)
        defaults.set(false, forKey: DefaultsKey.glassPanels)
        defaults.set(true, forKey: DefaultsKey.roundedCards)
        defaults.set(true, forKey: DefaultsKey.artworkHover)
        defaults.set(false, forKey: DefaultsKey.compactMode)
        defaults.set(true, forKey: DefaultsKey.theme)
        defaults.set(true, forKey: DefaultsKey.darkThemeFix)
    }

    /// Музыка живёт в окне: закрыл окно — приложение завершилось,
    /// а клик по док-иконке возвращает окно, если оно было скрыто.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: - Меню

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppConfig.name)
        appMenu.addItem(withTitle: "О программе \(AppConfig.name)", action: #selector(toggleInfoPanel(_:)), keyEquivalent: "")
        // Стандартный macOS-хоткей настроек: ⌘,
        let prefs = NSMenuItem(title: "Настройки…", action: #selector(toggleInfoPanel(_:)), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = .command
        appMenu.addItem(prefs)
        appMenu.addItem(withTitle: "Проверить обновления…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть \(AppConfig.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Завершить \(AppConfig.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let playerItem = NSMenuItem()
        let playerMenu = NSMenu(title: "Плеер")
        playerMenu.addItem(withTitle: "Пауза / Воспроизведение", action: #selector(playerTogglePlay(_:)), keyEquivalent: "p")
        let nextTrack = NSMenuItem(title: "Следующий трек", action: #selector(playerNextTrack(_:)), keyEquivalent: arrowKey(.rightArrow))
        nextTrack.keyEquivalentModifierMask = .command
        playerMenu.addItem(nextTrack)
        let prevTrack = NSMenuItem(title: "Предыдущий трек", action: #selector(playerPreviousTrack(_:)), keyEquivalent: arrowKey(.leftArrow))
        prevTrack.keyEquivalentModifierMask = .command
        playerMenu.addItem(prevTrack)
        playerItem.submenu = playerMenu
        mainMenu.addItem(playerItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Вид")
        viewMenu.addItem(withTitle: "Назад", action: #selector(goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Вперёд", action: #selector(goForward(_:)), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Обновить", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Домой", action: #selector(loadHome(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(toggleFocusFromMenu(_:)), keyEquivalent: "")
        let adBlockItem = NSMenuItem(title: "Режим без рекламы", action: #selector(toggleAdBlockFromMenu(_:)), keyEquivalent: "a")
        adBlockItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(adBlockItem)
        viewMenu.addItem(withTitle: "Настройки (⌘,)", action: #selector(toggleInfoPanel(_:)), keyEquivalent: "")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        NSApp.mainMenu = mainMenu
    }

    private func arrowKey(_ key: NSEvent.SpecialKey) -> String {
        guard let scalar = Unicode.Scalar(key.rawValue) else { return "" }
        return String(Character(scalar))
    }

    // MARK: - Окно и тулбар

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        window.title = AppConfig.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = AppConfig.minSize
        window.collectionBehavior = [.fullScreenPrimary]
        // Запоминаем размер и положение между запусками.
        window.setFrameAutosaveName("DieCloudeMainWindow")
        if !window.setFrameUsingName("DieCloudeMainWindow") { window.center() }

        let root = NSVisualEffectView(frame: frame)
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.wantsLayer = true
        toolbar.layer?.masksToBounds = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        let adBlock = symbolButton("hand.raised.fill", action: #selector(toggleAdBlockFromMenu(_:)), tooltip: "Режим без рекламы (⌘⇧A)")
        adBlockToolbarButton = adBlock
        syncAdBlockToolbarButton()
        let vpn = symbolButton("lock.shield.fill", action: #selector(openVPN(_:)), tooltip: "VPN — только DieCloude")
        let info = symbolButton("slider.horizontal.3", action: #selector(toggleInfoPanel(_:)), tooltip: "Настройки (⌘,)")

        titleLabel = NSTextField(labelWithString: AppConfig.name)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.alphaValue = 0.9
        progress.translatesAutoresizingMaskIntoConstraints = false

        let rightButtons = NSStackView(views: [adBlock, vpn, info])
        rightButtons.orientation = .horizontal
        rightButtons.spacing = 8
        rightButtons.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(titleLabel)
        toolbar.addSubview(rightButtons)
        toolbar.addSubview(progress)

        let toolbarSeparator = NSView()
        toolbarSeparator.wantsLayer = true
        toolbarSeparator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(toolbarSeparator)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 14.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(source: featureJavaScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // Мост страница → приложение: состояние плеера, диагностика движка
        nowPlaying.register(on: configuration.userContentController)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)
        buildStatusBanner(in: root)
        buildErrorOverlay(in: root)
        buildSidePanel(in: root)
        observeWebView()

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: toolbar.leadingAnchor, constant: 80),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightButtons.leadingAnchor, constant: -12),
            rightButtons.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            rightButtons.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbarSeparator.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            toolbarSeparator.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            toolbarSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Панель настроек

    private func buildSidePanel(in root: NSView) {
        sidePanel = NSVisualEffectView()
        sidePanel.material = .hudWindow
        sidePanel.appearance = NSAppearance(named: .darkAqua)
        sidePanel.blendingMode = .withinWindow
        sidePanel.state = .active
        sidePanel.wantsLayer = true
        sidePanel.layer?.cornerRadius = 20
        sidePanel.layer?.masksToBounds = true
        sidePanel.layer?.borderWidth = 1
        sidePanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        sidePanel.layer?.shadowOpacity = 0.4
        sidePanel.layer?.shadowRadius = 32
        sidePanel.layer?.shadowOffset = NSSize(width: -6, height: 0)
        sidePanel.layer?.shadowColor = NSColor.black.cgColor
        sidePanel.alphaValue = 0
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidePanel, positioned: .above, relativeTo: webView)

        // Заголовок панели: иконка + имя + бейдж версии + статус движка
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 9
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: AppConfig.name)
        name.font = .systemFont(ofSize: 18, weight: .bold)

        let verBadge = NSTextField(labelWithString: "v\(AppConfig.version)")
        verBadge.font = .systemFont(ofSize: 10, weight: .bold)
        verBadge.textColor = .secondaryLabelColor
        verBadge.wantsLayer = true
        verBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        verBadge.layer?.cornerRadius = 5
        verBadge.alignment = .center

        let nameRow = NSStackView(views: [name, verBadge])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8

        engineStatusLabel = NSTextField(labelWithString: "● Применяется сразу, без перезагрузки")
        engineStatusLabel.textColor = .systemGreen
        engineStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)

        let headerText = NSStackView(views: [nameRow, engineStatusLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2

        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        // Секция «Внешний вид»
        let toggleAction = #selector(toggleFlag(_:))
        let designSpecs: [(key: String, symbol: String, color: NSColor)] = [
            ("modernDesign", "sparkles", .systemBlue),
            ("theme", "checkmark.seal.fill", .systemIndigo),
            ("roundedCards", "square.inset.filled", .systemPink),
            ("artworkHover", "cursorarrow.rays", .systemTeal),
            ("compactMode", "arrow.up.and.down.and.arrow.left.and.right", .systemOrange)
        ]
        let designRows: [NSView] = designSpecs.compactMap { spec in
            guard let sw = settings.makeSwitch(for: spec.key, action: toggleAction, target: self) else { return nil }
            let badge = iconBadge(symbol: spec.symbol, color: spec.color)
            return modernSettingsRow(icon: badge, title: settings.title(for: spec.key), subtitle: settings.subtitle(for: spec.key), control: sw)
        }
        let designCard = makeCard(rows: designRows)

        // Секция «Цветовой акцент»
        let accentCtrl = settings.makeAccentControl(action: #selector(changeAccent(_:)), target: self)
        let accentBadge = iconBadge(symbol: "paintpalette.fill", color: .systemPurple)
        let accentRow = modernSettingsRow(icon: accentBadge,
                                         title: "Цветовой акцент",
                                         subtitle: "Кнопки, шкала времени и громкость",
                                         control: accentCtrl)
        let accentCard = makeCard(rows: [accentRow])

        // Секция «Прослушивание»
        let listeningSpecs: [(key: String, symbol: String, color: NSColor)] = [
            ("focus", "eye.slash.fill", .systemPurple),
            ("adBlock", "shield.lefthalf.filled", .systemGreen)
        ]
        let listeningRows: [NSView] = listeningSpecs.compactMap { spec in
            guard let sw = settings.makeSwitch(for: spec.key, action: toggleAction, target: self) else { return nil }
            let badge = iconBadge(symbol: spec.symbol, color: spec.color)
            return modernSettingsRow(icon: badge, title: settings.title(for: spec.key), subtitle: settings.subtitle(for: spec.key), control: sw)
        }
        let listeningCard = makeCard(rows: listeningRows)

        // Секция «Управление»
        let vpnBtn = NSButton(title: "Открыть…", target: self, action: #selector(openVPN(_:)))
        vpnBtn.bezelStyle = .rounded
        vpnBtn.controlSize = .small
        let vpnRow = modernSettingsRow(icon: iconBadge(symbol: "lock.shield.fill", color: .systemCyan),
                                       title: "Встроенный VPN",
                                       subtitle: "Действует только на DieCloude",
                                       control: vpnBtn)

        let resetBtn = NSButton(title: "Сбросить", target: self, action: #selector(resetDesignSettings(_:)))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        let resetRow = modernSettingsRow(icon: iconBadge(symbol: "arrow.counterclockwise", color: .systemYellow),
                                         title: "Сбросить оформление",
                                         subtitle: "Вернуть параметры по умолчанию",
                                         control: resetBtn)

        let updateBtn = NSButton(title: "Проверить…", target: self, action: #selector(checkForUpdates(_:)))
        updateBtn.bezelStyle = .rounded
        updateBtn.controlSize = .small
        let updateRow = modernSettingsRow(icon: iconBadge(symbol: "arrow.triangle.2.circlepath", color: .systemBlue),
                                          title: "Обновления",
                                          subtitle: "Проверить новую версию на GitHub",
                                          control: updateBtn)
        let actionsCard = makeCard(rows: [vpnRow, resetRow, updateRow])

        // Футер
        let footer = NSTextField(labelWithString: "Версия \(AppConfig.version) (\(AppConfig.build)) · \(AppConfig.author)")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let close = symbolButton("xmark", action: #selector(toggleInfoPanel(_:)), tooltip: "Закрыть (Esc)")

        let stack = NSStackView(views: [
            header,
            sectionTitle("Оформление"),
            designCard,
            sectionTitle("Акцент"),
            accentCard,
            sectionTitle("Прослушивание"),
            listeningCard,
            sectionTitle("Система"),
            actionsCard,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: header)
        stack.setCustomSpacing(12, after: designCard)
        stack.setCustomSpacing(12, after: accentCard)
        stack.setCustomSpacing(12, after: listeningCard)
        stack.setCustomSpacing(16, after: actionsCard)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for card in [designCard, accentCard, listeningCard, actionsCard, footer] as [NSView] {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidePanel.addSubview(scroll)
        sidePanel.addSubview(close)

        sidePanelTrailing = sidePanel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: 500)
        NSLayoutConstraint.activate([
            sidePanel.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            sidePanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            sidePanel.widthAnchor.constraint(equalToConstant: 420),
            sidePanelTrailing,
            scroll.topAnchor.constraint(equalTo: sidePanel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidePanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            close.topAnchor.constraint(equalTo: sidePanel.topAnchor, constant: 14),
            close.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor, constant: -14)
        ])
    }

    private func iconBadge(symbol: String, color: NSColor) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 28).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = (NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()).withSymbolConfiguration(config)
        let imageView = NSImageView(image: img ?? NSImage())
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private func makeCard(rows: [NSView]) -> NSView {
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.appearance = NSAppearance(named: .darkAqua)
        card.blendingMode = .withinWindow
        card.wantsLayer = true
        card.layer?.cornerRadius = 13
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        for (i, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if i < rows.count - 1 {
                let div = NSView()
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
                div.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(div)
                div.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 50).isActive = true
                div.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12).isActive = true
                div.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }
        return card
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .tertiaryLabelColor
        if let attributed = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attributed.addAttribute(.kern, value: 1.1, range: NSRange(location: 0, length: attributed.length))
            label.attributedStringValue = attributed
        }
        return label
    }

    private func modernSettingsRow(icon: NSView, title: String, subtitle: String, control: NSControl) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [icon, text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func symbolButton(_ symbol: String, action: Selector, tooltip: String) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = (NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()).withSymbolConfiguration(config) ?? NSImage()
        let button = ToolbarButton(image: image, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                self?.progress.doubleValue = view.estimatedProgress
                self?.progress.isHidden = view.estimatedProgress >= 1
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                let title = (view.title?.isEmpty == false ? view.title : AppConfig.name) ?? AppConfig.name
                self?.titleLabel.stringValue = title
                self?.window.title = title
            }
        ]
    }

    // MARK: - Блокировка рекламы

    private func compileAdBlockRules() {
        // noAds V9: network-правила из AdBlockService + DOM-чистка в theme-engine.js
        AdBlockService.compile { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                self.adBlockRuleList = list
                self.applyContentRuleLists(enabled: self.settings.value(for: "adBlock") == true)
            }
        }
    }

    /// Единая точка для тумблера настроек, меню и кнопки тулбара.
    private func applyContentRuleLists(enabled: Bool) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if enabled, let adBlockRuleList {
            controller.add(adBlockRuleList)
        }
    }

    private func setAdBlockEnabled(_ enabled: Bool) {
        settings.setValue(enabled, for: "adBlock")
        settings.syncButton(for: "adBlock")
        syncAdBlockToolbarButton()
        applyContentRuleLists(enabled: enabled)
        applySetting("adBlock", value: enabled, reload: true)
    }

    private func syncAdBlockToolbarButton() {
        guard let button = adBlockToolbarButton else { return }
        let on = settings.value(for: "adBlock") == true
        button.contentTintColor = on ? .controlAccentColor : nil
        button.toolTip = on
            ? "Режим без рекламы включён (⌘⇧A)"
            : "Режим без рекламы выключен (⌘⇧A)"
        button.alphaValue = on ? 1 : 0.6
    }

    // MARK: - Мост в theme-engine.js

    private func pushAllSettings() {
        let json = settings.json
        webView.evaluateJavaScript("window.__diecloude?.setAll(\(json))") { [weak self] result, _ in
            // Движка нет (страница ещё грузится) — повторим в didFinish.
            if result == nil { self?.needsSettingsSync = true }
        }
    }

    private func applySetting(_ jsKey: String, value: Bool, reload: Bool = false) {
        // Безопасная передача без строковой интерполяции значений
        let payload = (try? JSONSerialization.data(withJSONObject: [jsKey: value])) ?? Data()
        let json = String(data: payload, encoding: .utf8) ?? "{}"
        if reload {
            // Контекст страницы будет уничтожен — просто перезагружаем,
            // didFinish сам вольёт все сохранённые настройки.
            needsSettingsSync = true
            webView.reload()
            return
        }
        webView.evaluateJavaScript("window.__diecloude?.setAll(\(json))") { [weak self] result, _ in
            guard let self else { return }
            // Движка нет на странице (не успел вгрузиться или инъекция
            // не сработала) — поднимаем его принудительно и втягиваем всё.
            if result == nil {
                self.needsSettingsSync = true
                self.ensureThemeEngine { _ in self.pushAllSettings() }
            }
        }
    }

    /// Движок обязан существовать: если user-script не сработал,
    /// впрыскиваем его напрямую evaluateJavaScript (перевпрыск безопасен).
    private func ensureThemeEngine(completion: ((Bool) -> Void)? = nil) {
        webView.evaluateJavaScript("typeof window.__diecloude") { [weak self] result, _ in
            guard let self else { completion?(false); return }
            if (result as? String) == "object" {
                completion?(true)
                return
            }
            let source = self.featureJavaScript()
            self.webView.evaluateJavaScript(source) { _, _ in
                self.webView.evaluateJavaScript("typeof window.__diecloude") { result2, _ in
                    completion?((result2 as? String) == "object")
                }
            }
        }
    }

    private static func loadThemeEngineSource() -> String {
        if let url = Bundle.main.url(forResource: "theme-engine", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8), !source.isEmpty {
            return source
        }
        NSLog("DieCloude: resources/theme-engine.js not found")
        return "window.__diecloudeThemeEngineError = 'theme-engine.js missing';"
    }

    /// Cached halves of theme-engine.js split at __SETTINGS__ placeholder.
    private lazy var themeEngineParts: (String, String) = {
        let parts = themeEngineSource.components(separatedBy: "__SETTINGS__")
        return (parts.first ?? "", parts.count > 1 ? parts.dropFirst().joined(separator: "__SETTINGS__") : "")
    }()

    private func featureJavaScript() -> String {
        themeEngineParts.0 + settings.json + themeEngineParts.1
    }

    // MARK: - Переключатели настроек

    @objc private func toggleFlag(_ sender: NSControl) {
        let on: Bool
        if let sw = sender as? NSSwitch {
            on = sw.state == .on
        } else if let button = sender as? NSButton {
            on = button.state == .on
        } else {
            return
        }
        guard let jsKey = settings.jsKey(of: sender) else { return }
        if jsKey == "adBlock" {
            setAdBlockEnabled(on)
        } else {
            settings.setValue(on, for: jsKey)
            applySetting(jsKey, value: on)
        }
    }

    @objc private func resetDesignSettings(_ sender: Any?) {
        settings.resetDesign()
        pushAllSettings()
    }

    @objc private func toggleFocusFromMenu(_ sender: Any?) {
        let newValue = !(settings.value(for: "focus") ?? false)
        settings.setValue(newValue, for: "focus")
        settings.syncButton(for: "focus")
        applySetting("focus", value: newValue)
    }

    @objc private func toggleAdBlockFromMenu(_ sender: Any?) {
        // Раньше меню/тулбар меняли только флаг и JS, но не WKContentRuleList —
        // сетевая блокировка оставалась в старом состоянии до перезапуска.
        setAdBlockEnabled(!(settings.value(for: "adBlock") ?? false))
    }

    @objc private func toggleInfoPanel(_ sender: Any?) {
        panelVisible.toggle()
        sidePanelTrailing.constant = panelVisible ? -18 : 500
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            sidePanel.animator().alphaValue = panelVisible ? 1 : 0
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Цветовой акцент

    @objc private func changeAccent(_ sender: Any) {
        let values = ["mono", "amber", "blue", "system"]
        let index: Int
        if let seg = sender as? NSSegmentedControl {
            index = seg.selectedSegment
        } else if let popup = sender as? NSPopUpButton {
            index = popup.indexOfSelectedItem
        } else {
            return
        }
        guard values.indices.contains(index) else { return }
        settings.setAccent(values[index])
        pushAllSettings()
    }

    // MARK: - Диагностика движка темы

    private func setEngineStatus(found: Bool) {
        guard let label = engineStatusLabel else { return }
        if found {
            label.stringValue = "Настройки · ⌘, — применяются сразу"
            if !statusBanner.isHidden { hideStatusBanner(nil) }
        } else {
            label.stringValue = "Панель плеера не найдена — SoundCloud изменил разметку"
            if !playerMissingAnnounced {
                playerMissingAnnounced = true
                showStatusBanner("DieCloude не нашёл панель плеера: SoundCloud изменил разметку. Оформление может применяться не полностью.")
            }
        }
    }

    // MARK: - Баннер поверх контента (тихое уведомление)

    private func buildStatusBanner(in root: NSView) {
        statusBanner = NSVisualEffectView()
        statusBanner.material = .hudWindow
        statusBanner.appearance = NSAppearance(named: .darkAqua)
        statusBanner.blendingMode = .withinWindow
        statusBanner.state = .active
        statusBanner.wantsLayer = true
        statusBanner.layer?.cornerRadius = 12
        statusBanner.layer?.masksToBounds = true
        statusBanner.layer?.borderWidth = 1
        statusBanner.layer?.borderColor = NSColor.separatorColor.cgColor
        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        statusBanner.isHidden = true

        statusBannerLabel = NSTextField(labelWithString: "")
        statusBannerLabel.font = .systemFont(ofSize: 12)
        statusBannerLabel.textColor = .labelColor
        statusBannerLabel.lineBreakMode = .byTruncatingTail
        statusBannerLabel.translatesAutoresizingMaskIntoConstraints = false

        let ok = NSButton(title: "Понятно", target: self, action: #selector(hideStatusBanner))
        ok.bezelStyle = .rounded
        ok.controlSize = .small

        statusBanner.addSubview(statusBannerLabel)
        statusBanner.addSubview(ok)
        root.addSubview(statusBanner)
        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: root.topAnchor, constant: 88),
            statusBanner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            statusBanner.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            statusBanner.heightAnchor.constraint(equalToConstant: 38),
            statusBannerLabel.leadingAnchor.constraint(equalTo: statusBanner.leadingAnchor, constant: 14),
            statusBannerLabel.centerYAnchor.constraint(equalTo: statusBanner.centerYAnchor),
            statusBannerLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 470),
            ok.leadingAnchor.constraint(equalTo: statusBannerLabel.trailingAnchor, constant: 12),
            ok.trailingAnchor.constraint(equalTo: statusBanner.trailingAnchor, constant: -10),
            ok.centerYAnchor.constraint(equalTo: statusBanner.centerYAnchor)
        ])
    }

    private func showStatusBanner(_ text: String) {
        statusBannerLabel.stringValue = text
        statusBanner.isHidden = false
        statusBanner.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            statusBanner.animator().alphaValue = 1
        }
    }

    @objc private func hideStatusBanner(_ sender: Any?) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            statusBanner.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.statusBanner.isHidden = true
        })
    }

    // MARK: - Встроенная страница ошибки (вместо модального алерта)

    private func buildErrorOverlay(in root: NSView) {
        errorOverlay = NSVisualEffectView()
        errorOverlay.material = .underWindowBackground
        errorOverlay.blendingMode = .behindWindow
        errorOverlay.state = .active
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay.isHidden = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "wifi.exclamationmark", accessibilityDescription: "Нет соединения")
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Нет соединения с SoundCloud")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        errorDetail = NSTextField(wrappingLabelWithString: "")
        errorDetail.textColor = .secondaryLabelColor
        errorDetail.font = .systemFont(ofSize: 13)
        errorDetail.alignment = .center

        let retry = NSButton(title: "Повторить", target: self, action: #selector(retryConnection))
        retry.bezelStyle = .rounded
        retry.keyEquivalent = "\r"
        let dismiss = NSButton(title: "Скрыть", target: self, action: #selector(dismissConnectionError(_:)))
        dismiss.bezelStyle = .rounded
        let buttons = NSStackView(views: [retry, dismiss])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, title, errorDetail, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        errorOverlay.addSubview(stack)
        root.addSubview(errorOverlay, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            errorOverlay.topAnchor.constraint(equalTo: webView.topAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: errorOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorOverlay.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            errorDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func showConnectionError(_ error: NSError) {
        errorDetail.stringValue = error.localizedDescription
        errorOverlay.isHidden = false
        errorOverlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            errorOverlay.animator().alphaValue = 1
        }
    }

    private func hideConnectionError() {
        connectionRetryWorkItem?.cancel()
        connectionRetryWorkItem = nil
        guard !errorOverlay.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            errorOverlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.errorOverlay.isHidden = true
        })
    }

    @objc private func retryConnection(_ sender: Any?) {
        hideConnectionError()
        loadHome(nil)
    }

    @objc private func dismissConnectionError(_ sender: Any?) {
        hideConnectionError()
    }

    // MARK: - Управление плеером (⌘P / ⌘← / ⌘→)

    @objc private func playerTogglePlay(_ sender: Any?) { runPlayerScript(PlayerScripts.togglePlay) }
    @objc private func playerNextTrack(_ sender: Any?) { runPlayerScript(PlayerScripts.nextTrack) }
    @objc private func playerPreviousTrack(_ sender: Any?) { runPlayerScript(PlayerScripts.previousTrack) }

    private func runPlayerScript(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Окно «Что нового»

    private func showWelcomeIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.welcome) else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "DieCloude \(AppConfig.version)"
        alert.informativeText = bundledReleaseNotes()
        alert.addButton(withTitle: "Начать слушать")
        alert.addButton(withTitle: "Подробнее")
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            defaults.set(true, forKey: DefaultsKey.welcome)
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/siemens33/DieCloud-MacOS/releases/latest") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    /// RELEASE_NOTES.md из бандла → читаемый текст для окна «Что нового»:
    /// заголовки убираются, пункты списка становятся точками,
    /// служебная секция «Скачать» не показывается.
    private func bundledReleaseNotes() -> String {
        let fallback = "Обновление производительности и дизайна. Полный список — на GitHub."
        guard let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        var lines: [String] = []
        for rawLine in raw.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "---" { continue }
            if line.hasPrefix("#") {
                if line.lowercased().contains("скачать") { break }
                continue
            }
            if line.hasPrefix("- ") {
                lines.append("•   " + String(line.dropFirst(2)))
            } else {
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? fallback : String(text.prefix(1400))
    }

    // MARK: - Сервисы: VPN и обновления

    private func configureBackgroundServices() {
        let controller = VPNWindowController()
        controller.onProxyChanged = { [weak self] enabled, port in
            self?.applyPerAppProxy(enabled: enabled, port: port)
        }
        vpnController = controller
        controller.window?.appearance = NSAppearance(named: .darkAqua)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak controller] in
            controller?.attemptAutoConnect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.updateManager.checkForUpdates(presenting: self?.window, silentWhenCurrent: true)
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates(presenting: window, silentWhenCurrent: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        connectionRetryWorkItem?.cancel()
        vpnHealthTimer?.invalidate()
        vpnHealthTimer = nil
        nowPlaying.disableRemoteCommands()
        nowPlaying.unregister()
        if isAppProxyEnabled {
            isAppProxyEnabled = false
            webView?.configuration.websiteDataStore.proxyConfigurations = []
        }
        XrayManager.shared.stop()
    }

    /// Следит, чтобы WebView не оставался с мёртвым локальным прокси:
    /// если процесс Xray упал, сбрасываем proxyConfigurations и UI VPN.
    private func startVPNHealthCheck() {
        vpnHealthTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isAppProxyEnabled else { return }
            if XrayManager.shared.isRunning { return }
            NSLog("DieCloude: Xray process gone, clearing per-app proxy")
            self.applyPerAppProxy(enabled: false, port: XrayManager.shared.localPort)
            self.vpnController?.markDisconnected(reason: "VPN отключён — процесс прокси завершился")
        }
        // Не блокируем run loop при фоне/трекинге.
        vpnHealthTimer?.tolerance = 2
    }

    @objc private func openVPN(_ sender: Any?) {
        vpnController?.showWindow(nil)
        vpnController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPerAppProxy(enabled: Bool, port: Int) {
        // Прокси действует только на WKWebView DieCloude, не на всю систему
        let store = webView.configuration.websiteDataStore
        if enabled, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            store.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)]
            isAppProxyEnabled = true
        } else {
            store.proxyConfigurations = []
            isAppProxyEnabled = false
        }
        webView.reload()
    }

    // MARK: - Навигация

    @objc private func loadHome(_ sender: Any?) { webView.load(URLRequest(url: AppConfig.homeURL)) }
    @objc private func goBack(_ sender: Any?) { if webView.canGoBack { webView.goBack() } }
    @objc private func goForward(_ sender: Any?) { if webView.canGoForward { webView.goForward() } }
    @objc private func reloadPage(_ sender: Any?) { webView.reload() }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let request = navigationAction.request as URLRequest? { webView.load(request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        switch url.scheme?.lowercased() {
        case "http", "https", "about", "blob": decisionHandler(.allow)
        default: NSWorkspace.shared.open(url); decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Каждая загрузка втягивает сохранённые настройки в страницу.
        // Сначала убеждаемся, что движок вообще есть (самопочинка),
        // иначе тоглы молча ни на что не влияют.
        needsSettingsSync = false
        ensureThemeEngine { [weak self] _ in self?.pushAllSettings() }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Страница начала грузиться — ошибка соединения больше не актуальна.
        hideConnectionError()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        showConnectionError(nsError)
        scheduleConnectionRetry()
    }

    private func scheduleConnectionRetry() {
        connectionRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.errorOverlay.isHidden else { return }
            let task = URLSession.shared.dataTask(with: URLRequest(url: AppConfig.homeURL, timeoutInterval: 4)) { [weak self] _, response, _ in
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    DispatchQueue.main.async { self?.retryConnection(nil) }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, !self.errorOverlay.isHidden else { return }
                        self.scheduleConnectionRetry()
                    }
                }
            }
            task.resume()
        }
        connectionRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    deinit {
        connectionRetryWorkItem?.cancel()
        vpnHealthTimer?.invalidate()
        observations.removeAll()
        nowPlaying.disableRemoteCommands()
        nowPlaying.unregister()
    }
}

/// Клики по нативным кнопкам SoundCloud: основные классы + фолбэк
/// по aria-label (классы SoundCloud меняются, aria-label — реже).
private enum PlayerScripts {
    static let togglePlay = """
    (function(){
      var b = document.querySelector('.playControls__play');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/play|pause|воспроизвед|пауз/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) b.click();
    })();
    """

    static let nextTrack = """
    (function(){
      var b = document.querySelector('.skipControls__next');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/next|следующ/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) b.click();
    })();
    """

    static let previousTrack = """
    (function(){
      var b = document.querySelector('.skipControls__previous');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/previous|prev|предыдущ/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) b.click();
    })();
    """
}


let application = NSApplication.shared
application.setActivationPolicy(.regular)
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
