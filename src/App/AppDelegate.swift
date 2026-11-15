import AppKit
import WebKit
import QuartzCore
import Network

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var progress: NSProgressIndicator!
    private var titleLabel: NSTextField!
    private var sidePanel: NSVisualEffectView!
    private var sidePanelTrailing: NSLayoutConstraint!
    private var observations: [NSKeyValueObservation] = []
    private var keyEventMonitor: Any?
    private var adBlockRuleList: WKContentRuleList?
    private var vpnController: VPNWindowController?
    private let updateManager = UpdateManager()
    private var vpnHealthTimer: Timer?
    private let settings = SettingsState()
    private let nowPlaying = NowPlayingController()
    private let discordRPC = DiscordRPC()

    private lazy var themeEngineSource: String = Self.loadThemeEngineSource()
    private var isAppProxyEnabled = false
    private var adBlockToolbarButton: NSButton?
    private var needsSettingsSync = false
    private var panelVisible = false

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
        NSApp.mainMenu = AppMenuBuilder.buildMainMenu(target: self)
        buildWindow()
        installKeyboardMonitor()
        wireNowPlaying()
        compileAdBlockRules()
        loadHome(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWelcomeIfNeeded()
        configureBackgroundServices()
        startVPNHealthCheck()
    }

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
            self?.runPlayerScript(PlayerScripts.seekTo(position))
        }
        nowPlaying.onPlayerMissing = { [weak self] in self?.setEngineStatus(found: false) }
        nowPlaying.onPlayerFound = { [weak self] in self?.setEngineStatus(found: true) }
        nowPlaying.onVolumeChanged = { [weak self] vol, muted in
            self?.settings.setVolume(vol, muted: muted)
        }
        nowPlaying.onEscapePressed = { [weak self] in
            guard let self, self.panelVisible else { return }
            self.setPanelVisible(false)
        }
        nowPlaying.onPlaybackChanged = { [weak self] playback in
            self?.discordRPC.update(playback)
        }
        discordRPC.setClientID(settings.discordClientID)
        discordRPC.setEnabled(settings.value(for: "discordRPC") == true)
        nowPlaying.enableRemoteCommands()
    }

    private func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.darkThemeFix) else { return }
        defaults.set(true, forKey: DefaultsKey.modernDesign)
        defaults.set(false, forKey: DefaultsKey.glassPanels)
        defaults.set(true, forKey: DefaultsKey.roundedCards)
        defaults.set(true, forKey: DefaultsKey.artworkHover)
        defaults.set(true, forKey: DefaultsKey.theme)
        defaults.set(true, forKey: DefaultsKey.darkThemeFix)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: - Локальный монитор клавиш (Esc и защита текстовых полей)

    private func installKeyboardMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.panelVisible, event.window === self.window {
                self.setPanelVisible(false)
                return nil
            }
            return event
        }
    }

    // MARK: - Окно и тулбар

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppConfig.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = AppConfig.minSize
        window.collectionBehavior = [.fullScreenPrimary]
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

        let adBlock = SettingsSidePanelBuilder.symbolButton(
            "hand.raised.fill",
            action: #selector(toggleAdBlockFromMenu(_:)),
            target: self,
            tooltip: "Режим без рекламы (⌘⇧A)"
        )
        adBlockToolbarButton = adBlock
        syncAdBlockToolbarButton()
        let vpn = SettingsSidePanelBuilder.symbolButton(
            "lock.shield.fill",
            action: #selector(openVPN(_:)),
            target: self,
            tooltip: "VPN — только DieCloude"
        )
        let info = SettingsSidePanelBuilder.symbolButton(
            "slider.horizontal.3",
            action: #selector(toggleInfoPanel(_:)),
            target: self,
            tooltip: "Настройки (⌘,)"
        )

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
        // Инъекция на .atDocumentStart позволяет перехватить new Audio() и применить громкость до старта бандлов SoundCloud
        configuration.userContentController.addUserScript(
            WKUserScript(source: featureJavaScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        nowPlaying.register(on: configuration.userContentController)

        webView = WKWebView(frame: .zero, configuration: configuration)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)
        buildStatusBanner(in: root)
        buildErrorOverlay(in: root)
        observeWebView()

        let sidePanelOutput = SettingsSidePanelBuilder.build(
            in: root,
            above: webView,
            settings: settings,
            target: self,
            toggleAction: #selector(toggleFlag(_:)),
            accentAction: #selector(changeAccent(_:)),
            equalizerAction: #selector(changeEqualizer(_:)),
            discordIdAction: #selector(changeDiscordClientID(_:)),
            openVPNAction: #selector(openVPN(_:)),
            resetAction: #selector(resetDesignSettings(_:)),
            checkUpdatesAction: #selector(checkForUpdates(_:)),
            closeAction: #selector(toggleInfoPanel(_:))
        )
        sidePanel = sidePanelOutput.panel
        sidePanelTrailing = sidePanelOutput.trailingConstraint
        engineStatusLabel = sidePanelOutput.engineStatusLabel

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

    // MARK: - Блокировка рекламы (без перезагрузки страницы)

    private func compileAdBlockRules() {
        AdBlockService.compile { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                self.adBlockRuleList = list
                self.applyContentRuleLists(enabled: self.settings.value(for: "adBlock") == true)
            }
        }
    }

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
        applySetting("adBlock", value: enabled)
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
            if result == nil { self?.needsSettingsSync = true }
        }
    }

    private func applySetting(_ jsKey: String, value: Bool) {
        let payload = (try? JSONSerialization.data(withJSONObject: [jsKey: value])) ?? Data()
        let json = String(data: payload, encoding: .utf8) ?? "{}"
        webView.evaluateJavaScript("window.__diecloude?.setAll(\(json))") { [weak self] result, _ in
            guard let self else { return }
            if result == nil {
                self.needsSettingsSync = true
                self.ensureThemeEngine { _ in self.pushAllSettings() }
            }
        }
    }

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
            if jsKey == "discordRPC" { discordRPC.setEnabled(on) }
            applySetting(jsKey, value: on)
        }
    }

    @objc private func changeEqualizer(_ sender: NSControl) {
        if let toggle = sender as? NSSwitch {
            if toggle.tag == -2 {
                settings.setEqualizer(normalization: toggle.state == .on)
            } else {
                settings.setEqualizer(enabled: toggle.state == .on)
            }
        } else if let popup = sender as? NSPopUpButton {
                let keys = SettingsState.equalizerPresetKeys
            if keys.indices.contains(popup.indexOfSelectedItem),
               let bands = SettingsState.equalizerPresets[keys[popup.indexOfSelectedItem]] {
                settings.setEqualizer(bands: bands)
            }
        } else if let slider = sender as? NSSlider {
            var bands = settings.equalizerBands
            guard bands.indices.contains(slider.tag) else { return }
            bands[slider.tag] = slider.doubleValue
            settings.setEqualizer(bands: bands)
        }
        settings.syncEqualizerControls()
        pushAllSettings()
    }

    @objc private func changeDiscordClientID(_ sender: NSTextField) {
        settings.customDiscordClientID = sender.stringValue
        let effectiveID = settings.discordClientID
        discordRPC.setClientID(effectiveID)
        sender.stringValue = settings.customDiscordClientID
    }

    @objc private func resetDesignSettings(_ sender: Any?) {
        settings.resetDesign()
        pushAllSettings()
    }

    @objc func toggleFocusFromMenu(_ sender: Any?) {
        let newValue = !(settings.value(for: "focus") ?? false)
        settings.setValue(newValue, for: "focus")
        settings.syncButton(for: "focus")
        applySetting("focus", value: newValue)
    }

    @objc func toggleAdBlockFromMenu(_ sender: Any?) {
        setAdBlockEnabled(!(settings.value(for: "adBlock") ?? false))
    }

    @objc func toggleInfoPanel(_ sender: Any?) {
        setPanelVisible(!panelVisible)
    }

    private func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        sidePanelTrailing.constant = visible ? -18 : 500
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            sidePanel.animator().alphaValue = visible ? 1 : 0
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

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
            label.stringValue = "● Применяется сразу, без перезагрузки"
            if !statusBanner.isHidden { hideStatusBanner(nil) }
        } else {
            label.stringValue = "Панель плеера не найдена — SoundCloud изменил разметку"
            if !playerMissingAnnounced {
                playerMissingAnnounced = true
                showStatusBanner("DieCloude не нашёл панель плеера: SoundCloud изменил разметку. Оформление может применяться не полностью.")
            }
        }
    }

    // MARK: - Баннер и оверлей ошибки

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
            statusBanner.topAnchor.constraint(equalTo: root.topAnchor, constant: 60),
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

    // MARK: - Управление плеером (Space / ⌥Space / ⌘← / ⌘→ / ⌥← / ⌥→ / ⌘↑ / ⌘↓ / ⌘⌥M / ⌘L)

    @objc func playerTogglePlay(_ sender: Any?) {
        if let responder = window.firstResponder, responder is NSTextView {
            responder.insertText(" ")
            return
        }
        runPlayerScript(PlayerScripts.togglePlay)
    }
    @objc func playerNextTrack(_ sender: Any?) { runPlayerScript(PlayerScripts.nextTrack) }
    @objc func playerPreviousTrack(_ sender: Any?) { runPlayerScript(PlayerScripts.previousTrack) }
    @objc func playerSeekForward(_ sender: Any?) { runPlayerScript(PlayerScripts.seekBy(10)) }
    @objc func playerSeekBackward(_ sender: Any?) { runPlayerScript(PlayerScripts.seekBy(-10)) }
    @objc func playerVolumeUp(_ sender: Any?) { runPlayerScript(PlayerScripts.changeVolume(0.05)) }
    @objc func playerVolumeDown(_ sender: Any?) { runPlayerScript(PlayerScripts.changeVolume(-0.05)) }
    @objc func playerToggleMute(_ sender: Any?) { runPlayerScript(PlayerScripts.toggleMute) }
    @objc func playerToggleLike(_ sender: Any?) { runPlayerScript(PlayerScripts.toggleLike) }

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

    @objc func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates(presenting: window, silentWhenCurrent: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        connectionRetryWorkItem?.cancel()
        vpnHealthTimer?.invalidate()
        vpnHealthTimer = nil
        discordRPC.setEnabled(false)
        nowPlaying.disableRemoteCommands()
        nowPlaying.unregister()
        if isAppProxyEnabled {
            isAppProxyEnabled = false
            webView?.configuration.websiteDataStore.proxyConfigurations = []
        }
        XrayManager.shared.stop()
    }

    private func startVPNHealthCheck() {
        vpnHealthTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isAppProxyEnabled else { return }
            if XrayManager.shared.isRunning { return }
            NSLog("DieCloude: Xray process gone, clearing per-app proxy")
            self.applyPerAppProxy(enabled: false, port: XrayManager.shared.localPort)
            self.vpnController?.markDisconnected(reason: "VPN отключён — процесс прокси завершился")
        }
        vpnHealthTimer?.tolerance = 2
    }

    @objc private func openVPN(_ sender: Any?) {
        vpnController?.showWindow(nil)
        vpnController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPerAppProxy(enabled: Bool, port: Int) {
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

    @objc func loadHome(_ sender: Any?) { webView.load(URLRequest(url: AppConfig.homeURL)) }
    @objc func goBack(_ sender: Any?) { if webView.canGoBack { webView.goBack() } }
    @objc func goForward(_ sender: Any?) { if webView.canGoForward { webView.goForward() } }
    @objc func reloadPage(_ sender: Any?) { webView.reload() }

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
        needsSettingsSync = false
        ensureThemeEngine { [weak self] _ in self?.pushAllSettings() }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
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
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor) }
        connectionRetryWorkItem?.cancel()
        vpnHealthTimer?.invalidate()
        observations.removeAll()
        nowPlaying.disableRemoteCommands()
        nowPlaying.unregister()
    }
}
