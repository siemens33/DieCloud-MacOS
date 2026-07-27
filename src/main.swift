import AppKit
import WebKit
import QuartzCore
import Network

enum AppConfig {
    static let name = "DieCloude"
    static let version = "3.5.2"
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
    static let welcome = "DieCloudeWelcomeV352PolishShown"
    static let darkThemeFix = "DieCloudeVisualSystemV352Build29"
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
    private var modernDesignEnabled = true
    private var glassPanelsEnabled = false
    private var roundedCardsEnabled = true
    private var artworkHoverEnabled = true
    private var compactModeEnabled = false
    private var panelVisible = false

    private var adBlockSwitch: NSButton!
    private var focusSwitch: NSButton!
    private var themeSwitch: NSButton!
    private var modernDesignSwitch: NSButton!
    private var glassPanelsSwitch: NSButton!
    private var roundedCardsSwitch: NSButton!
    private var artworkHoverSwitch: NSButton!
    private var compactModeSwitch: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        // 3.5.2 visual polish migration: preserve the stable theme and enable
        // corrected artwork rounding plus lightweight interface animations.
        if !defaults.bool(forKey: DefaultsKey.darkThemeFix) {
            defaults.set(true, forKey: DefaultsKey.modernDesign)
            defaults.set(false, forKey: DefaultsKey.glassPanels)
            defaults.set(true, forKey: DefaultsKey.roundedCards)
            defaults.set(true, forKey: DefaultsKey.artworkHover)
            defaults.set(false, forKey: DefaultsKey.compactMode)
            defaults.set(true, forKey: DefaultsKey.theme)
            defaults.set(true, forKey: DefaultsKey.darkThemeFix)
        }
        adBlockEnabled = defaults.object(forKey: DefaultsKey.adBlock) == nil ? true : defaults.bool(forKey: DefaultsKey.adBlock)
        focusEnabled = defaults.bool(forKey: DefaultsKey.focus)
        themeEnabled = defaults.object(forKey: DefaultsKey.theme) == nil ? true : defaults.bool(forKey: DefaultsKey.theme)
        modernDesignEnabled = defaults.object(forKey: DefaultsKey.modernDesign) == nil ? true : defaults.bool(forKey: DefaultsKey.modernDesign)
        glassPanelsEnabled = defaults.object(forKey: DefaultsKey.glassPanels) == nil ? false : defaults.bool(forKey: DefaultsKey.glassPanels)
        roundedCardsEnabled = defaults.object(forKey: DefaultsKey.roundedCards) == nil ? true : defaults.bool(forKey: DefaultsKey.roundedCards)
        artworkHoverEnabled = defaults.object(forKey: DefaultsKey.artworkHover) == nil ? true : defaults.bool(forKey: DefaultsKey.artworkHover)
        compactModeEnabled = defaults.bool(forKey: DefaultsKey.compactMode)

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
        sidePanel.material = .hudWindow
        sidePanel.appearance = NSAppearance(named: .darkAqua)
        sidePanel.blendingMode = .withinWindow
        sidePanel.state = .active
        sidePanel.wantsLayer = true
        sidePanel.layer?.cornerRadius = 22
        sidePanel.layer?.masksToBounds = true
        sidePanel.layer?.borderWidth = 1
        sidePanel.layer?.borderColor = NSColor.separatorColor.cgColor
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidePanel, positioned: .above, relativeTo: webView)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: AppConfig.name)
        name.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Настройте внешний вид и поведение SoundCloud")
        subtitle.textColor = .secondaryLabelColor

        let designTitle = sectionLabel("Дизайн")
        modernDesignSwitch = checkbox("Минималистичный интерфейс DieCloude", state: modernDesignEnabled, action: #selector(toggleModernDesign(_:)))
        roundedCardsSwitch = checkbox("Аккуратное скругление обложек", state: roundedCardsEnabled, action: #selector(toggleRoundedCards(_:)))
        roundedCardsSwitch.toolTip = "Скругляет только обложки треков, альбомов и плейлистов"
        artworkHoverSwitch = checkbox("Мягкий эффект при наведении", state: artworkHoverEnabled, action: #selector(toggleArtworkHover(_:)))
        artworkHoverSwitch.toolTip = "Слегка увеличивает и подсвечивает только обложку, не двигая карточку"
        compactModeSwitch = checkbox("Компактная плотность интерфейса", state: compactModeEnabled, action: #selector(toggleCompactMode(_:)))
        compactModeSwitch.toolTip = "Уменьшает лишние вертикальные отступы без перестройки сетки SoundCloud"
        themeSwitch = checkbox("Белый фирменный акцент", state: themeEnabled, action: #selector(toggleTheme(_:)))

        let listeningTitle = sectionLabel("Прослушивание")
        focusSwitch = checkbox("Режим фокуса — скрыть рекомендации", state: focusEnabled, action: #selector(toggleFocus(_:)))
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

        let reset = NSButton(title: "Восстановить стандартный дизайн", target: self, action: #selector(resetDesignSettings(_:)))
        reset.bezelStyle = .rounded
        let stack = NSStackView(views: [icon, name, subtitle, s1, designTitle, modernDesignSwitch, themeSwitch, roundedCardsSwitch, artworkHoverSwitch, compactModeSwitch, reset, s3, listeningTitle, focusSwitch, adBlockSwitch, version, author])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

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
            sidePanel.widthAnchor.constraint(equalToConstant: 470),
            sidePanelTrailing,
            scroll.topAnchor.constraint(equalTo: sidePanel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidePanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            close.topAnchor.constraint(equalTo: sidePanel.topAnchor, constant: 14),
            close.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor, constant: -14)
        ])
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
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
    @objc private func toggleModernDesign(_ sender: NSButton) { modernDesignEnabled = sender.state == .on; saveAndApply(DefaultsKey.modernDesign, "modernDesign", modernDesignEnabled) }
    @objc private func toggleRoundedCards(_ sender: NSButton) { roundedCardsEnabled = sender.state == .on; saveAndApply(DefaultsKey.roundedCards, "roundedCards", roundedCardsEnabled) }
    @objc private func toggleArtworkHover(_ sender: NSButton) { artworkHoverEnabled = sender.state == .on; saveAndApply(DefaultsKey.artworkHover, "artworkHover", artworkHoverEnabled) }
    @objc private func toggleCompactMode(_ sender: NSButton) { compactModeEnabled = sender.state == .on; saveAndApply(DefaultsKey.compactMode, "compactMode", compactModeEnabled) }

    @objc private func resetDesignSettings(_ sender: Any?) {
        modernDesignEnabled = true
        themeEnabled = true
        roundedCardsEnabled = true
        artworkHoverEnabled = true
        compactModeEnabled = false
        modernDesignSwitch.state = .on
        themeSwitch.state = .on
        roundedCardsSwitch.state = .on
        artworkHoverSwitch.state = .on
        compactModeSwitch.state = .off
        let values: [(String, String, Bool)] = [
            (DefaultsKey.modernDesign, "modernDesign", true),
            (DefaultsKey.theme, "theme", true),
            (DefaultsKey.roundedCards, "roundedCards", true),
            (DefaultsKey.artworkHover, "artworkHover", true),
            (DefaultsKey.compactMode, "compactMode", false)
        ]
        for (defaultsKey, jsKey, value) in values {
            UserDefaults.standard.set(value, forKey: defaultsKey)
            applySetting(jsKey, value: value)
        }
    }
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
        sidePanelTrailing.constant = panelVisible ? -18 : 500
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
        alert.messageText = "DieCloude 3.5.2"
        alert.informativeText = "Обновлённый матовый плеер, исправленные скругления обложек и лёгкие надёжные анимации интерфейса."
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
        let settings = "{adBlock:\(adBlockEnabled),focus:\(focusEnabled),theme:\(themeEnabled),modernDesign:\(modernDesignEnabled),roundedCards:\(roundedCardsEnabled),artworkHover:\(artworkHoverEnabled),compactMode:\(compactModeEnabled)}"
        guard let url = Bundle.main.url(forResource: "theme-engine", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("DieCloude: resources/theme-engine.js not found")
            return "window.__diecloudeThemeEngineError = 'theme-engine.js missing';"
        }
        return source.replacingOccurrences(of: "__SETTINGS__", with: settings)
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
