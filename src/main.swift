import AppKit
import WebKit
import QuartzCore
import Network

enum AppConfig {
    static let name = "DieCloude"
    static let version = "3.5.0"
    static let author = "by siemens"
    static let homeURL = URL(string: "https://soundcloud.com/")!
    static let minSize = NSSize(width: 900, height: 600)
}

private enum DefaultsKey {
    static let adBlock = "DieCloudeAdBlockEnabled"
    static let focus = "DieCloudeFocusModeEnabled"
    static let theme = "DieCloudeDynamicThemeEnabled"
    static let ambient = "DieCloudeAmbientBackgroundEnabled"
    static let visualizer = "DieCloudeVisualizerEnabled"
    static let modernDesign = "DieCloudeModernDesignEnabled"
    static let glassPanels = "DieCloudeGlassPanelsEnabled"
    static let roundedCards = "DieCloudeRoundedCardsEnabled"
    static let hoverAnimations = "DieCloudeHoverAnimationsEnabled"
    static let pageTransitions = "DieCloudePageTransitionsEnabled"
    static let buttonGlow = "DieCloudeButtonGlowEnabled"
    static let spinningArtwork = "DieCloudeSpinningArtworkEnabled"
    static let playWave = "DieCloudePlayWaveEnabled"
    static let compactMode = "DieCloudeCompactModeEnabled"
    static let smoothScrolling = "DieCloudeSmoothScrollingEnabled"
    static let reduceMotion = "DieCloudeReduceMotionEnabled"
    static let welcome = "DieCloudeWelcomeV350Shown"
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
    private var keyMonitor: Any?
    private var observations: [NSKeyValueObservation] = []
    private var adBlockRuleList: WKContentRuleList?
    private var vpnController: VPNWindowController?
    private let updateManager = UpdateManager()

    private var adBlockEnabled = true
    private var focusEnabled = false
    private var themeEnabled = true
    private var ambientEnabled = true
    private var visualizerEnabled = false
    private var modernDesignEnabled = true
    private var glassPanelsEnabled = true
    private var roundedCardsEnabled = true
    private var hoverAnimationsEnabled = true
    private var pageTransitionsEnabled = true
    private var buttonGlowEnabled = true
    private var spinningArtworkEnabled = false
    private var playWaveEnabled = true
    private var compactModeEnabled = false
    private var smoothScrollingEnabled = true
    private var reduceMotionEnabled = false
    private var panelVisible = false

    private var adBlockSwitch: NSButton!
    private var focusSwitch: NSButton!
    private var themeSwitch: NSButton!
    private var ambientSwitch: NSButton!
    private var visualizerSwitch: NSButton!
    private var modernDesignSwitch: NSButton!
    private var glassPanelsSwitch: NSButton!
    private var roundedCardsSwitch: NSButton!
    private var hoverAnimationsSwitch: NSButton!
    private var pageTransitionsSwitch: NSButton!
    private var buttonGlowSwitch: NSButton!
    private var spinningArtworkSwitch: NSButton!
    private var playWaveSwitch: NSButton!
    private var compactModeSwitch: NSButton!
    private var smoothScrollingSwitch: NSButton!
    private var reduceMotionSwitch: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        adBlockEnabled = defaults.object(forKey: DefaultsKey.adBlock) == nil ? true : defaults.bool(forKey: DefaultsKey.adBlock)
        focusEnabled = defaults.bool(forKey: DefaultsKey.focus)
        themeEnabled = defaults.object(forKey: DefaultsKey.theme) == nil ? true : defaults.bool(forKey: DefaultsKey.theme)
        ambientEnabled = defaults.object(forKey: DefaultsKey.ambient) == nil ? true : defaults.bool(forKey: DefaultsKey.ambient)
        visualizerEnabled = defaults.bool(forKey: DefaultsKey.visualizer)
        modernDesignEnabled = defaults.object(forKey: DefaultsKey.modernDesign) == nil ? true : defaults.bool(forKey: DefaultsKey.modernDesign)
        glassPanelsEnabled = defaults.object(forKey: DefaultsKey.glassPanels) == nil ? true : defaults.bool(forKey: DefaultsKey.glassPanels)
        roundedCardsEnabled = defaults.object(forKey: DefaultsKey.roundedCards) == nil ? true : defaults.bool(forKey: DefaultsKey.roundedCards)
        hoverAnimationsEnabled = defaults.object(forKey: DefaultsKey.hoverAnimations) == nil ? true : defaults.bool(forKey: DefaultsKey.hoverAnimations)
        pageTransitionsEnabled = defaults.object(forKey: DefaultsKey.pageTransitions) == nil ? true : defaults.bool(forKey: DefaultsKey.pageTransitions)
        buttonGlowEnabled = defaults.object(forKey: DefaultsKey.buttonGlow) == nil ? true : defaults.bool(forKey: DefaultsKey.buttonGlow)
        spinningArtworkEnabled = defaults.bool(forKey: DefaultsKey.spinningArtwork)
        playWaveEnabled = defaults.object(forKey: DefaultsKey.playWave) == nil ? true : defaults.bool(forKey: DefaultsKey.playWave)
        compactModeEnabled = defaults.bool(forKey: DefaultsKey.compactMode)
        smoothScrollingEnabled = defaults.object(forKey: DefaultsKey.smoothScrolling) == nil ? true : defaults.bool(forKey: DefaultsKey.smoothScrolling)
        reduceMotionEnabled = defaults.bool(forKey: DefaultsKey.reduceMotion)

        buildMenu()
        buildWindow()
        compileAdBlockRules()
        installF1Handler()
        loadHome(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWelcomeIfNeeded()
        configureBackgroundServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppConfig.name)
        appMenu.addItem(withTitle: "О программе \(AppConfig.name)", action: #selector(toggleInfoPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Проверить обновления…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть \(AppConfig.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Завершить \(AppConfig.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Вид")
        viewMenu.addItem(withTitle: "Назад", action: #selector(goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Вперёд", action: #selector(goForward(_:)), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Обновить", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Домой", action: #selector(loadHome(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(toggleFocusFromMenu(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Настройки (F1)", action: #selector(toggleInfoPanel(_:)), keyEquivalent: "")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        window.title = AppConfig.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
        window.minSize = AppConfig.minSize
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()

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
        let vpn = symbolButton("lock.shield.fill", action: #selector(openVPN(_:)), tooltip: "VPN — только DieCloude")
        let info = symbolButton("slider.horizontal.3", action: #selector(toggleInfoPanel(_:)), tooltip: "Настройки (F1)")

        titleLabel = NSTextField(labelWithString: AppConfig.name)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false

        let left = NSStackView(views: [backButton, forwardButton, reload, home])
        left.orientation = .horizontal
        left.spacing = 6
        left.translatesAutoresizingMaskIntoConstraints = false
        [left, titleLabel, vpn, info, progress].forEach(toolbar.addSubview)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: featureJavaScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)
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

    private func buildSidePanel(in root: NSView) {
        sidePanel = NSVisualEffectView()
        sidePanel.material = .sidebar
        sidePanel.blendingMode = .withinWindow
        sidePanel.state = .active
        sidePanel.wantsLayer = true
        sidePanel.layer?.cornerRadius = 18
        sidePanel.layer?.masksToBounds = true
        sidePanel.layer?.borderWidth = 0.5
        sidePanel.layer?.borderColor = NSColor.separatorColor.cgColor
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidePanel, positioned: .above, relativeTo: webView)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: AppConfig.name)
        name.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Настройки внешнего вида и прослушивания")
        subtitle.textColor = .secondaryLabelColor

        let designTitle = sectionLabel("Дизайн")
        modernDesignSwitch = checkbox("Современный дизайн DieCloude", state: modernDesignEnabled, action: #selector(toggleModernDesign(_:)))
        glassPanelsSwitch = checkbox("Стеклянные полупрозрачные панели", state: glassPanelsEnabled, action: #selector(toggleGlassPanels(_:)))
        roundedCardsSwitch = checkbox("Скруглённые карточки треков", state: roundedCardsEnabled, action: #selector(toggleRoundedCards(_:)))
        compactModeSwitch = checkbox("Компактный режим", state: compactModeEnabled, action: #selector(toggleCompactMode(_:)))
        themeSwitch = checkbox("Dynamic Theme — акцент от обложки", state: themeEnabled, action: #selector(toggleTheme(_:)))
        ambientSwitch = checkbox("Ambient Background — фон из обложки", state: ambientEnabled, action: #selector(toggleAmbient(_:)))

        let animationTitle = sectionLabel("Анимации")
        hoverAnimationsSwitch = checkbox("Анимации при наведении", state: hoverAnimationsEnabled, action: #selector(toggleHoverAnimations(_:)))
        pageTransitionsSwitch = checkbox("Плавные переходы страниц", state: pageTransitionsEnabled, action: #selector(togglePageTransitions(_:)))
        buttonGlowSwitch = checkbox("Свечение кнопок воспроизведения", state: buttonGlowEnabled, action: #selector(toggleButtonGlow(_:)))
        spinningArtworkSwitch = checkbox("Вращение обложки при воспроизведении", state: spinningArtworkEnabled, action: #selector(toggleSpinningArtwork(_:)))
        playWaveSwitch = checkbox("Волна рядом с кнопкой Play", state: playWaveEnabled, action: #selector(togglePlayWave(_:)))
        visualizerSwitch = checkbox("Визуализатор", state: visualizerEnabled, action: #selector(toggleVisualizer(_:)))
        smoothScrollingSwitch = checkbox("Плавная прокрутка", state: smoothScrollingEnabled, action: #selector(toggleSmoothScrolling(_:)))
        reduceMotionSwitch = checkbox("Сниженная анимация", state: reduceMotionEnabled, action: #selector(toggleReduceMotion(_:)))

        let listeningTitle = sectionLabel("Прослушивание")
        focusSwitch = checkbox("Focus Mode — убрать лишние блоки", state: focusEnabled, action: #selector(toggleFocus(_:)))
        adBlockSwitch = checkbox("Режим без рекламы", state: adBlockEnabled, action: #selector(toggleAdBlock(_:)))
        adBlockSwitch.toolTip = "Блокирует известные рекламные запросы и скрывает рекламные блоки"

        let version = NSTextField(labelWithString: "Версия \(AppConfig.version)")
        version.textColor = .secondaryLabelColor
        let author = NSTextField(labelWithString: AppConfig.author)
        author.textColor = .tertiaryLabelColor
        let s1 = NSBox(); s1.boxType = .separator
        let s2 = NSBox(); s2.boxType = .separator
        let s3 = NSBox(); s3.boxType = .separator
        let close = symbolButton("xmark", action: #selector(toggleInfoPanel(_:)), tooltip: "Закрыть")

        let stack = NSStackView(views: [icon, name, subtitle, s1, designTitle, modernDesignSwitch, glassPanelsSwitch, roundedCardsSwitch, compactModeSwitch, themeSwitch, ambientSwitch, s2, animationTitle, hoverAnimationsSwitch, pageTransitionsSwitch, buttonGlowSwitch, spinningArtworkSwitch, playWaveSwitch, visualizerSwitch, smoothScrollingSwitch, reduceMotionSwitch, s3, listeningTitle, focusSwitch, adBlockSwitch, version, author])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidePanel.addSubview(scroll)
        sidePanel.addSubview(close)

        sidePanelTrailing = sidePanel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: 440)
        NSLayoutConstraint.activate([
            sidePanel.topAnchor.constraint(equalTo: root.topAnchor, constant: 94),
            sidePanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            sidePanel.widthAnchor.constraint(equalToConstant: 410),
            sidePanelTrailing,
            scroll.topAnchor.constraint(equalTo: sidePanel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidePanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            close.topAnchor.constraint(equalTo: sidePanel.topAnchor, constant: 14),
            close.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor, constant: -14)
        ])
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }

    private func symbolButton(_ symbol: String, action: Selector, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func checkbox(_ title: String, state: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state ? .on : .off
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

    private func compileAdBlockRules() {
        let rules = #"[{"trigger":{"url-filter":".*(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|amazon-adsystem\\.com|scorecardresearch\\.com|adnxs\\.com|criteo\\.com|taboola\\.com|outbrain\\.com|adsrvr\\.org|quantserve\\.com|rubiconproject\\.com|pubmatic\\.com|openx\\.net|moatads\\.com|demdex\\.net|everesttech\\.net).*","resource-type":["document","image","style-sheet","script","font","raw","popup"]},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "DieCloudeAdBlockRulesV6", encodedContentRuleList: rules) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { NSLog("DieCloude ad-block rules error: \(error)"); return }
                self.adBlockRuleList = list
                if self.adBlockEnabled, let list { self.webView.configuration.userContentController.add(list) }
            }
        }
    }

    private func applySetting(_ name: String, value: Bool, reload: Bool = false) {
        webView.evaluateJavaScript("window.__diecloude?.set('\(name)', \(value ? "true" : "false"))")
        if reload { webView.reload() }
    }

    @objc private func toggleAdBlock(_ sender: NSButton) {
        adBlockEnabled = sender.state == .on
        UserDefaults.standard.set(adBlockEnabled, forKey: DefaultsKey.adBlock)
        webView.configuration.userContentController.removeAllContentRuleLists()
        if adBlockEnabled, let adBlockRuleList { webView.configuration.userContentController.add(adBlockRuleList) }
        applySetting("adBlock", value: adBlockEnabled, reload: true)
    }
    @objc private func toggleFocus(_ sender: NSButton) { focusEnabled = sender.state == .on; saveAndApply(DefaultsKey.focus, "focus", focusEnabled) }
    @objc private func toggleTheme(_ sender: NSButton) { themeEnabled = sender.state == .on; saveAndApply(DefaultsKey.theme, "theme", themeEnabled) }
    @objc private func toggleAmbient(_ sender: NSButton) { ambientEnabled = sender.state == .on; saveAndApply(DefaultsKey.ambient, "ambient", ambientEnabled) }
    @objc private func toggleVisualizer(_ sender: NSButton) { visualizerEnabled = sender.state == .on; saveAndApply(DefaultsKey.visualizer, "visualizer", visualizerEnabled) }
    @objc private func toggleModernDesign(_ sender: NSButton) { modernDesignEnabled = sender.state == .on; saveAndApply(DefaultsKey.modernDesign, "modernDesign", modernDesignEnabled) }
    @objc private func toggleGlassPanels(_ sender: NSButton) { glassPanelsEnabled = sender.state == .on; saveAndApply(DefaultsKey.glassPanels, "glassPanels", glassPanelsEnabled) }
    @objc private func toggleRoundedCards(_ sender: NSButton) { roundedCardsEnabled = sender.state == .on; saveAndApply(DefaultsKey.roundedCards, "roundedCards", roundedCardsEnabled) }
    @objc private func toggleHoverAnimations(_ sender: NSButton) { hoverAnimationsEnabled = sender.state == .on; saveAndApply(DefaultsKey.hoverAnimations, "hoverAnimations", hoverAnimationsEnabled) }
    @objc private func togglePageTransitions(_ sender: NSButton) { pageTransitionsEnabled = sender.state == .on; saveAndApply(DefaultsKey.pageTransitions, "pageTransitions", pageTransitionsEnabled) }
    @objc private func toggleButtonGlow(_ sender: NSButton) { buttonGlowEnabled = sender.state == .on; saveAndApply(DefaultsKey.buttonGlow, "buttonGlow", buttonGlowEnabled) }
    @objc private func toggleSpinningArtwork(_ sender: NSButton) { spinningArtworkEnabled = sender.state == .on; saveAndApply(DefaultsKey.spinningArtwork, "spinningArtwork", spinningArtworkEnabled) }
    @objc private func togglePlayWave(_ sender: NSButton) { playWaveEnabled = sender.state == .on; saveAndApply(DefaultsKey.playWave, "playWave", playWaveEnabled) }
    @objc private func toggleCompactMode(_ sender: NSButton) { compactModeEnabled = sender.state == .on; saveAndApply(DefaultsKey.compactMode, "compactMode", compactModeEnabled) }
    @objc private func toggleSmoothScrolling(_ sender: NSButton) { smoothScrollingEnabled = sender.state == .on; saveAndApply(DefaultsKey.smoothScrolling, "smoothScrolling", smoothScrollingEnabled) }
    @objc private func toggleReduceMotion(_ sender: NSButton) { reduceMotionEnabled = sender.state == .on; saveAndApply(DefaultsKey.reduceMotion, "reduceMotion", reduceMotionEnabled) }
    private func saveAndApply(_ key: String, _ jsKey: String, _ value: Bool) { UserDefaults.standard.set(value, forKey: key); applySetting(jsKey, value: value) }

    @objc private func toggleFocusFromMenu(_ sender: Any?) {
        focusEnabled.toggle(); focusSwitch.state = focusEnabled ? .on : .off; saveAndApply(DefaultsKey.focus, "focus", focusEnabled)
    }

    private func installF1Handler() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 122 { self.toggleInfoPanel(nil); return nil }
            return event
        }
    }

    @objc private func toggleInfoPanel(_ sender: Any?) {
        panelVisible.toggle()
        sidePanelTrailing.constant = panelVisible ? -18 : 440
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func showWelcomeIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.welcome) else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "DieCloude 3.5"
        alert.informativeText = "Добавлена гибкая система оформления: современный дизайн, стеклянные панели, карточки, переходы, hover-эффекты, свечение, вращение обложки, волна Play, компактный режим и управление интенсивностью анимаций."
        alert.addButton(withTitle: "Начать слушать")
        alert.beginSheetModal(for: window) { _ in defaults.set(true, forKey: DefaultsKey.welcome) }
    }


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
        if vpnController == nil {
            let controller = VPNWindowController()
            controller.onProxyChanged = { [weak self] enabled, port in self?.applyPerAppProxy(enabled: enabled, port: port) }
            vpnController = controller
        }
        vpnController?.showWindow(nil)
        vpnController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPerAppProxy(enabled: Bool, port: Int) {
        guard #available(macOS 14.0, *) else {
            let alert = NSAlert(); alert.messageText = "Для встроенного VPN нужна macOS 14 или новее"; alert.informativeText = "Сам DieCloude продолжает работать на macOS 12–13, но публичный WebKit API для отдельного прокси доступен только в новых версиях macOS."; alert.runModal(); XrayManager.shared.stop(); return
        }
        let store = webView.configuration.websiteDataStore
        if enabled {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            store.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)]
        } else { store.proxyConfigurations = [] }
        webView.reload()
    }

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

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled { showError(nsError) }
    }

    private func showError(_ error: NSError) {
        let alert = NSAlert()
        alert.messageText = "Не удалось открыть SoundCloud"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Повторить")
        alert.addButton(withTitle: "Закрыть")
        if alert.runModal() == .alertFirstButtonReturn { loadHome(nil) }
    }

    private func featureJavaScript() -> String {
        let settings = "{adBlock:\(adBlockEnabled),focus:\(focusEnabled),theme:\(themeEnabled),ambient:\(ambientEnabled),visualizer:\(visualizerEnabled),modernDesign:\(modernDesignEnabled),glassPanels:\(glassPanelsEnabled),roundedCards:\(roundedCardsEnabled),hoverAnimations:\(hoverAnimationsEnabled),pageTransitions:\(pageTransitionsEnabled),buttonGlow:\(buttonGlowEnabled),spinningArtwork:\(spinningArtworkEnabled),playWave:\(playWaveEnabled),compactMode:\(compactModeEnabled),smoothScrolling:\(smoothScrollingEnabled),reduceMotion:\(reduceMotionEnabled)}"
        return #"""
        (() => {
          const initial = __SETTINGS__;
          if (window.__diecloude) { window.__diecloude.setAll(initial); return; }

          const root = document.documentElement;
          const dc = {
            settings: initial,
            observer: null,
            frame: 0,
            artworkTimer: 0,
            lastArtwork: '',
            adSelectors: '[class*=adBanner i],[class*=advertisement i],[class*=sponsored i],[class*=upsell i],[data-testid*=advert i],[data-testid*=upsell i],[aria-label*=advertisement i],[aria-label*=реклама i],iframe[src*=doubleclick],iframe[src*=googlesyndication]'
          };

          const style = document.createElement('style');
          style.id = 'dc-style';
          style.textContent = `
            :root{--dc-accent:#ff5500;--dc-artwork:none}
            html.dc-theme a,html.dc-theme button[aria-pressed=true],html.dc-theme [role=slider]{accent-color:var(--dc-accent)!important}
            #dc-ambient{position:fixed;inset:-50px;z-index:2147480000;pointer-events:none;opacity:0;transition:opacity .5s ease;background-image:linear-gradient(rgba(8,8,10,.66),rgba(8,8,10,.84)),var(--dc-artwork);background-size:cover;background-position:center;filter:blur(38px) saturate(1.25);transform:scale(1.06)}
            html.dc-ambient #dc-ambient{opacity:.36}
            html.dc-ambient body>*:not(#dc-ambient):not(#dc-visualizer){position:relative;z-index:1}
            html.dc-focus [class*=sidebar],html.dc-focus [class*=related],html.dc-focus [class*=comments],html.dc-focus [class*=commentForm],html.dc-focus [class*=rightSidebar],html.dc-focus [class*=streamSidebar],html.dc-focus aside{display:none!important}
            html.dc-focus [class*=l-fluid-fixed],html.dc-focus [class*=l-container],html.dc-focus main{max-width:1120px!important;margin-left:auto!important;margin-right:auto!important}
            html.dc-adblock ${dc.adSelectors}{display:none!important;visibility:hidden!important;max-height:0!important}
            #dc-visualizer{position:fixed;left:50%;bottom:76px;transform:translateX(-50%);z-index:2147483640;display:none;align-items:flex-end;gap:4px;height:34px;padding:7px 11px;border-radius:17px;background:rgba(12,12,14,.42);backdrop-filter:blur(14px);pointer-events:none}
            html.dc-visualizer #dc-visualizer{display:flex}#dc-visualizer i{display:block;width:4px;height:7px;border-radius:4px;background:var(--dc-accent);animation:dcbar .95s ease-in-out infinite alternate;animation-play-state:paused}html.dc-playing #dc-visualizer i{animation-play-state:running}
            #dc-visualizer i:nth-child(2n){animation-duration:.72s}#dc-visualizer i:nth-child(3n){animation-duration:1.15s}@keyframes dcbar{from{height:5px;opacity:.55}to{height:30px;opacity:1}}
            html.dc-modern body{background:linear-gradient(145deg,#0d0d10,#17171c)!important}html.dc-modern [class*=header],html.dc-modern [class*=playControls]{border-color:rgba(255,255,255,.08)!important}
            html.dc-glass [class*=header],html.dc-glass [class*=playControls],html.dc-glass [class*=sidebar],html.dc-glass [role=dialog]{background:rgba(20,20,24,.72)!important;backdrop-filter:blur(20px) saturate(1.3)!important;-webkit-backdrop-filter:blur(20px) saturate(1.3)!important}
            html.dc-rounded [class*=soundList__item],html.dc-rounded [class*=stream__list] li,html.dc-rounded [class*=trackItem],html.dc-rounded [class*=systemPlaylist],html.dc-rounded article{border-radius:16px!important;overflow:hidden!important}
            html.dc-hover [class*=soundList__item],html.dc-hover [class*=trackItem],html.dc-hover article,html.dc-hover button{transition:transform .2s ease,box-shadow .2s ease,filter .2s ease!important}html.dc-hover [class*=soundList__item]:hover,html.dc-hover [class*=trackItem]:hover,html.dc-hover article:hover{transform:translateY(-2px);box-shadow:0 10px 30px rgba(0,0,0,.25)}html.dc-hover button:hover{transform:scale(1.045)}
            html.dc-transitions main,html.dc-transitions [role=main]{animation:dcPageIn .28s ease both}@keyframes dcPageIn{from{opacity:.25;transform:translateY(6px)}to{opacity:1;transform:none}}
            html.dc-glow button[title*=Play i],html.dc-glow button[aria-label*=Play i],html.dc-glow button[title*=Воспроизвести i],html.dc-glow button[aria-label*=Воспроизвести i]{filter:drop-shadow(0 0 10px color-mix(in srgb,var(--dc-accent),transparent 30%))}
            html.dc-spin.dc-playing [class*=playbackSoundBadge] img,html.dc-spin.dc-playing [class*=playbackSoundBadge] [style*=background-image]{border-radius:50%!important;animation:dcSpin 14s linear infinite!important}@keyframes dcSpin{to{transform:rotate(360deg)}}
            html.dc-wave button[title*=Play i]::after,html.dc-wave button[aria-label*=Play i]::after{content:'';position:absolute;inset:-5px;border:2px solid var(--dc-accent);border-radius:50%;opacity:0;animation:dcWave 1.8s ease-out infinite;pointer-events:none}@keyframes dcWave{0%{transform:scale(.7);opacity:.65}100%{transform:scale(1.45);opacity:0}}
            html.dc-compact [class*=soundList__item],html.dc-compact [class*=trackItem]{padding-top:6px!important;padding-bottom:6px!important}html.dc-compact [class*=image]{max-width:88px!important;max-height:88px!important}html.dc-compact [class*=header]{min-height:42px!important}
            html.dc-smooth{scroll-behavior:smooth!important}html.dc-smooth *{scroll-behavior:smooth!important}
            html.dc-reduced *,html.dc-reduced *::before,html.dc-reduced *::after{animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important;scroll-behavior:auto!important}
            @media (prefers-reduced-motion:reduce){#dc-visualizer i{animation:none!important;height:10px}html:not(.dc-reduced) *{animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important}}
          `;
          (document.head || root).appendChild(style);

          const ambient = document.createElement('div'); ambient.id = 'dc-ambient';
          const viz = document.createElement('div'); viz.id = 'dc-visualizer'; viz.innerHTML = '<i></i>'.repeat(12);
          (document.body || root).prepend(ambient);
          (document.body || root).appendChild(viz);

          const visible = element => element?.isConnected && element.getClientRects().length > 0;
          const media = () => document.querySelector('audio:not([paused]),video:not([paused])') || document.querySelector('audio,video');
          const updatePlaying = () => {
            const item = media();
            root.classList.toggle('dc-playing', !!item && !item.paused && !document.hidden);
          };

          const removeAdsFrom = node => {
            if (!dc.settings.adBlock || !(node instanceof Element)) return;
            if (node.matches(dc.adSelectors)) { node.remove(); return; }
            node.querySelectorAll(dc.adSelectors).forEach(element => element.remove());
          };

          const updateArtwork = () => {
            dc.artworkTimer = 0;
            if (!dc.settings.theme && !dc.settings.ambient) return;
            let best = null, bestArea = 0;
            for (const image of document.images) {
              if (!visible(image) || image.naturalWidth < 200 || image.naturalHeight < 200) continue;
              const area = image.clientWidth * image.clientHeight;
              if (area > bestArea) { best = image; bestArea = area; }
            }
            const url = best?.currentSrc || '';
            if (!url || url === dc.lastArtwork) return;
            dc.lastArtwork = url;
            root.style.setProperty('--dc-artwork', `url("${url.replaceAll('"','%22')}")`);
            if (dc.settings.theme) {
              let hash = 0;
              for (const character of url) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
              root.style.setProperty('--dc-accent', `hsl(${hash % 360} 78% 58%)`);
            }
          };

          const scheduleArtwork = () => {
            if (dc.artworkTimer) return;
            dc.artworkTimer = window.setTimeout(updateArtwork, 700);
          };

          const applyClasses = () => {
            root.classList.toggle('dc-adblock', !!dc.settings.adBlock);
            root.classList.toggle('dc-focus', !!dc.settings.focus);
            root.classList.toggle('dc-theme', !!dc.settings.theme);
            root.classList.toggle('dc-ambient', !!dc.settings.ambient);
            root.classList.toggle('dc-visualizer', !!dc.settings.visualizer);
            root.classList.toggle('dc-modern', !!dc.settings.modernDesign);
            root.classList.toggle('dc-glass', !!dc.settings.glassPanels);
            root.classList.toggle('dc-rounded', !!dc.settings.roundedCards);
            root.classList.toggle('dc-hover', !!dc.settings.hoverAnimations && !dc.settings.reduceMotion);
            root.classList.toggle('dc-transitions', !!dc.settings.pageTransitions && !dc.settings.reduceMotion);
            root.classList.toggle('dc-glow', !!dc.settings.buttonGlow);
            root.classList.toggle('dc-spin', !!dc.settings.spinningArtwork && !dc.settings.reduceMotion);
            root.classList.toggle('dc-wave', !!dc.settings.playWave && !dc.settings.reduceMotion);
            root.classList.toggle('dc-compact', !!dc.settings.compactMode);
            root.classList.toggle('dc-smooth', !!dc.settings.smoothScrolling && !dc.settings.reduceMotion);
            root.classList.toggle('dc-reduced', !!dc.settings.reduceMotion);
            updatePlaying();
            scheduleArtwork();
          };

          const scheduleApply = () => {
            if (dc.frame) return;
            dc.frame = requestAnimationFrame(() => { dc.frame = 0; applyClasses(); });
          };

          dc.set = (key, value) => { dc.settings[key] = !!value; applyClasses(); if (key === 'adBlock' && value) removeAdsFrom(document.body); };
          dc.setAll = values => { Object.assign(dc.settings, values || {}); applyClasses(); if (dc.settings.adBlock) removeAdsFrom(document.body); };
          window.__diecloude = dc;

          dc.observer = new MutationObserver(records => {
            let needsArtwork = false;
            for (const record of records) {
              for (const node of record.addedNodes) {
                removeAdsFrom(node);
                if (node instanceof HTMLImageElement || node.querySelector?.('img')) needsArtwork = true;
              }
            }
            if (needsArtwork) scheduleArtwork();
            scheduleApply();
          });
          dc.observer.observe(document.body || root, { subtree: true, childList: true });

          document.addEventListener('play', updatePlaying, true);
          document.addEventListener('pause', updatePlaying, true);
          document.addEventListener('visibilitychange', updatePlaying);
          window.addEventListener('pagehide', () => {
            dc.observer?.disconnect();
            if (dc.frame) cancelAnimationFrame(dc.frame);
            if (dc.artworkTimer) clearTimeout(dc.artworkTimer);
          }, { once: true });

          if (dc.settings.adBlock) removeAdsFrom(document.body);
          applyClasses();
        })();
        """#.replacingOccurrences(of: "__SETTINGS__", with: settings)
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        observations.removeAll()
    }
}


let application = NSApplication.shared
application.setActivationPolicy(.regular)
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
