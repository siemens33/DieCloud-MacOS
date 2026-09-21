import AppKit
import WebKit
import QuartzCore
import Network

enum AppConfig {
    static let name = "DieCloude"
    static let version = "4.1.0"
    static let build = "34"
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
        accentPopup?.selectItem(at: 0)
    }

    /// Выбор акцента из popup-кнопки (индексы совпадают с accentTitles).
    private static let accentTitles = ["Монохром (белый)", "Янтарный", "Синий", "Как в системе"]
    private static let accentValues = ["mono", "amber", "blue", "system"]
    private(set) weak var accentPopup: NSPopUpButton?

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
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var progress: NSProgressIndicator!
    private var titleLabel: NSTextField!
    private var sidePanel: NSVisualEffectView!
    private var sidePanelTrailing: NSLayoutConstraint!
    private var observations: [NSKeyValueObservation] = []
    private var adBlockRuleList: WKContentRuleList?
    private var vpnController: VPNWindowController?
    private let updateManager = UpdateManager()
    private let settings = SettingsState()
    private let nowPlaying = NowPlayingController()
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

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Вид")
        viewMenu.addItem(withTitle: "Назад", action: #selector(goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Вперёд", action: #selector(goForward(_:)), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Обновить", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Домой", action: #selector(loadHome(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(toggleFocusFromMenu(_:)), keyEquivalent: "")
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
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        backButton = symbolButton("chevron.left", action: #selector(goBack(_:)), tooltip: "Назад")
        forwardButton = symbolButton("chevron.right", action: #selector(goForward(_:)), tooltip: "Вперёд")
        let reload = symbolButton("arrow.clockwise", action: #selector(reloadPage(_:)), tooltip: "Обновить")
        let home = symbolButton("house.fill", action: #selector(loadHome(_:)), tooltip: "Домой")
        let playPause = symbolButton("playpause.fill", action: #selector(playerTogglePlay(_:)), tooltip: "Пауза / Воспроизведение (⌘P)")
        let vpn = symbolButton("lock.shield.fill", action: #selector(openVPN(_:)), tooltip: "VPN — только DieCloude")
        let info = symbolButton("slider.horizontal.3", action: #selector(toggleInfoPanel(_:)), tooltip: "Настройки (⌘,)")

        titleLabel = NSTextField(labelWithString: AppConfig.name)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
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

        let left = NSStackView(views: [backButton, forwardButton, reload, home, playPause])
        left.orientation = .horizontal
        left.spacing = 6
        left.translatesAutoresizingMaskIntoConstraints = false
        [left, titleLabel, vpn, info, progress].forEach(toolbar.addSubview)

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
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),
            left.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            info.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            vpn.trailingAnchor.constraint(equalTo: info.leadingAnchor, constant: -6),
            vpn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            info.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
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
        sidePanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        sidePanel.layer?.shadowOpacity = 0.3
        sidePanel.layer?.shadowRadius = 28
        sidePanel.layer?.shadowOffset = NSSize(width: -8, height: 0)
        sidePanel.layer?.shadowColor = NSColor.black.cgColor
        sidePanel.alphaValue = 0
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidePanel, positioned: .above, relativeTo: webView)

        // Заголовок панели: иконка + имя + строка статуса движка
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: AppConfig.name)
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        engineStatusLabel = NSTextField(labelWithString: "Применяется сразу, без перезагрузки")
        engineStatusLabel.textColor = .secondaryLabelColor
        engineStatusLabel.font = .systemFont(ofSize: 11)
        let headerText = NSStackView(views: [name, engineStatusLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2
        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        // Секция «Внешний вид»: строки с тумблерами + акцент + сброс
        let toggleAction = #selector(toggleFlag(_:))
        let designRows: [NSView] = ["modernDesign", "theme", "roundedCards", "artworkHover", "compactMode"].compactMap {
            guard let sw = settings.makeSwitch(for: $0, action: toggleAction, target: self) else { return nil }
            return settingsRow(title: settings.title(for: $0), subtitle: settings.subtitle(for: $0), control: sw)
        }
        let accentPopup = settings.makeAccentPopup(action: #selector(changeAccent(_:)), target: self)
        accentPopup.widthAnchor.constraint(equalToConstant: 176).isActive = true
        let accentRow = settingsRow(title: "Цветовой акцент",
                                    subtitle: "Кнопки, шкала времени и громкость",
                                    control: accentPopup)
        let reset = NSButton(title: "Сбросить оформление", target: self, action: #selector(resetDesignSettings(_:)))
        reset.bezelStyle = .inline
        reset.controlSize = .small
        reset.contentTintColor = .secondaryLabelColor
        let designSection = section(header: "Внешний вид", rows: designRows + [accentRow], footer: reset)

        // Секция «Прослушивание»
        let listeningRows: [NSView] = ["focus", "adBlock"].compactMap {
            guard let sw = settings.makeSwitch(for: $0, action: toggleAction, target: self) else { return nil }
            return settingsRow(title: settings.title(for: $0), subtitle: settings.subtitle(for: $0), control: sw)
        }
        let listeningSection = section(header: "Прослушивание", rows: listeningRows, footer: nil)

        // Секция «О программе»
        let version = NSTextField(labelWithString: "Версия \(AppConfig.version) (\(AppConfig.build)) · \(AppConfig.author)")
        version.textColor = .secondaryLabelColor
        version.font = .systemFont(ofSize: 11)
        let updateButton = NSButton(title: "Проверить обновления…", target: self, action: #selector(checkForUpdates(_:)))
        updateButton.bezelStyle = .inline
        updateButton.controlSize = .small
        updateButton.contentTintColor = .secondaryLabelColor
        let aboutSection = section(header: "О программе", rows: [version], footer: updateButton)

        let close = symbolButton("xmark", action: #selector(toggleInfoPanel(_:)), tooltip: "Закрыть")

        let stack = NSStackView(views: [header, separator(), designSection, separator(), listeningSection, separator(), aboutSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for fullWidth in [header, designSection, listeningSection, aboutSection] as [NSView] {
            fullWidth.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true
            fullWidth.setContentHuggingPriority(.defaultLow, for: .horizontal)
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
            sidePanel.topAnchor.constraint(equalTo: root.topAnchor, constant: 94),
            sidePanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            sidePanel.widthAnchor.constraint(equalToConstant: 440),
            sidePanelTrailing,
            scroll.topAnchor.constraint(equalTo: sidePanel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidePanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            close.topAnchor.constraint(equalTo: sidePanel.topAnchor, constant: 14),
            close.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor, constant: -14)
        ])
    }

    /// Заголовок секции: маленький капс, приглушённый — вместо рамок NSBox.
    private func section(header title: String, rows: [NSView], footer: NSView?) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        if let attributed = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attributed.addAttribute(.kern, value: 1.2, range: NSRange(location: 0, length: attributed.length))
            label.attributedStringValue = attributed
        }
        let stack = NSStackView(views: [label] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        if let footer {
            stack.addArrangedSubview(footer)
            stack.setCustomSpacing(12, after: rows.last ?? label)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// Строка настройки: название + описание слева, элемент управления справа.
    private func settingsRow(title: String, subtitle: String, control: NSControl) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
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
        let row = NSStackView(views: [text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func symbolButton(_ symbol: String, action: Selector, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
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
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in self?.backButton.isEnabled = view.canGoBack },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in self?.forwardButton.isEnabled = view.canGoForward }
        ]
    }

    // MARK: - Блокировка рекламы

    private func compileAdBlockRules() {
        // noAds V9: network-правила из AdBlockService + DOM-чистка в theme-engine.js
        AdBlockService.compile { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                self.adBlockRuleList = list
                if self.settings.value(for: "adBlock") == true, let list {
                    self.webView.configuration.userContentController.add(list)
                }
            }
        }
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

    private func featureJavaScript() -> String {
        guard let url = Bundle.main.url(forResource: "theme-engine", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("DieCloude: resources/theme-engine.js not found")
            return "window.__diecloudeThemeEngineError = 'theme-engine.js missing';"
        }
        return source.replacingOccurrences(of: "__SETTINGS__", with: settings.json)
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
        settings.setValue(on, for: jsKey)
        if jsKey == "adBlock" {
            // WKUserContentController хранит только наш V9-лист — пересобираем чисто
            webView.configuration.userContentController.removeAllContentRuleLists()
            if on, let adBlockRuleList { webView.configuration.userContentController.add(adBlockRuleList) }
            applySetting(jsKey, value: on, reload: true)
        } else {
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

    @objc private func toggleInfoPanel(_ sender: Any?) {
        panelVisible.toggle()
        sidePanelTrailing.constant = panelVisible ? -18 : 500
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sidePanel.animator().alphaValue = panelVisible ? 1 : 0
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Цветовой акцент

    @objc private func changeAccent(_ sender: NSPopUpButton) {
        let values = ["mono", "amber", "blue", "system"]
        let index = sender.indexOfSelectedItem
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
        alert.beginSheetModal(for: window) { response in
            defaults.set(true, forKey: DefaultsKey.welcome)
            if response == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/siemens33/DieCloud-MacOS/releases/latest") {
                    NSWorkspace.shared.open(url)
                }
            }
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
        XrayManager.shared.stop()
    }

    @objc private func openVPN(_ sender: Any?) {
        vpnController?.showWindow(nil)
        vpnController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPerAppProxy(enabled: Bool, port: Int) {
        // Прокси действует только на WKWebView DieCloude, не на всю систему
        let store = webView.configuration.websiteDataStore
        if enabled {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            store.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)]
        } else { store.proxyConfigurations = [] }
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
        if nsError.code != NSURLErrorCancelled { showConnectionError(nsError) }
    }

    deinit {
        observations.removeAll()
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
