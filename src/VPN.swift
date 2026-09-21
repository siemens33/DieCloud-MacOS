import AppKit
import Darwin
import WebKit
import Network
import Security

struct VPNServer: Hashable, Codable {
    var id = UUID()
    var name: String
    var scheme: String
    var host: String
    var port: Int
    var rawURI: String
    var pingMS: Int?
}

final class KeychainStore {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "DieCloude",
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { NSLog("DieCloude keychain save error: \(status)") }
    }
    static func load(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "DieCloude",
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SubscriptionParser {
    static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8), text.contains("://") { return text }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        if let decoded = Data(base64Encoded: padded), let text = String(data: decoded, encoding: .utf8) { return text }
        return raw
    }

    static func parse(_ text: String) -> [VPNServer] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: String) -> VPNServer? {
        if line.hasPrefix("vmess://") { return parseVMess(line) }
        guard let components = URLComponents(string: line), let scheme = components.scheme?.lowercased() else { return nil }
        guard ["vless", "trojan", "socks"].contains(scheme) else { return nil }
        let host = components.host ?? ""
        let port = components.port ?? defaultPort(scheme)
        guard !host.isEmpty, port > 0 else { return nil }
        let fragment = components.fragment?.removingPercentEncoding
        return VPNServer(name: fragment?.isEmpty == false ? fragment! : "\(host):\(port)", scheme: scheme, host: host, port: port, rawURI: line, pingMS: nil)
    }

    private static func parseVMess(_ line: String) -> VPNServer? {
        let encoded = String(line.dropFirst("vmess://".count))
        let normalized = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = object["add"] as? String else { return nil }
        let port = Int(object["port"] as? String ?? "") ?? (object["port"] as? Int ?? 443)
        let name = (object["ps"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(host):\(port)"
        return VPNServer(name: name, scheme: "vmess", host: host, port: port, rawURI: line, pingMS: nil)
    }

    private static func defaultPort(_ scheme: String) -> Int { scheme == "socks" ? 1080 : 443 }
}

final class XrayManager {
    static let shared = XrayManager()
    private(set) var process: Process?
    let localPort = 17890

    var isRunning: Bool { process?.isRunning == true }

    func stop() {
        // Держим ссылку на процесс: если просто terminate и забыть,
        // зависшее ядро Xray могло остаться жить в системе.
        guard let p = process else { return }
        process = nil
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if p.isRunning { p.interrupt() }
        }
        try? FileManager.default.removeItem(at: configURL)
    }

    func start(server: VPNServer) throws {
        stop()
        let binaryName = ProcessInfo.processInfo.machineHardwareName.contains("arm64") ? "xray-arm64" : "xray-x86_64"
        guard let binary = Bundle.main.url(forResource: binaryName, withExtension: nil) else {
            throw NSError(domain: "DieCloudeVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ядро Xray не найдено в приложении. Пересобери DieCloude при подключённом интернете."])
        }
        let config = try makeConfig(server)
        try config.write(to: configURL, options: [.atomic])
        // 0600 — в конфиге UUID/пароль
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        let task = Process()
        task.executableURL = binary
        task.arguments = ["run", "-config", configURL.path]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        // Меньше нагрева: низкий QoS для фонового прокси-процесса
        task.qualityOfService = .utility
        try task.run()
        process = task
        // Healthcheck вместо Thread.sleep: ждём порт до 2с
        if !waitForPort(port: localPort, timeout: 2.0) || !task.isRunning {
            stop()
            throw NSError(domain: "DieCloudeVPN", code: 2, userInfo: [NSLocalizedDescriptionKey: "Xray не смог запуститься с выбранной конфигурацией."])
        }
    }

    private func waitForPort(port: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
            if fd < 0 { return false }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr = in_addr(s_addr: 0x0100007F) // 127.0.0.1
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(fd)
            if result == 0 { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private var configURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("diecloude-xray.json") }

    private func makeConfig(_ server: VPNServer) throws -> Data {
        let outbound = try outboundObject(server.rawURI)
        let root: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [["listen": "127.0.0.1", "port": localPort, "protocol": "http", "settings": ["timeout": 30]]],
            "outbounds": [outbound, ["protocol": "freedom", "tag": "direct"]]
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func outboundObject(_ uri: String) throws -> [String: Any] {
        if uri.hasPrefix("vmess://") { return try vmessOutbound(uri) }
        guard let c = URLComponents(string: uri), let scheme = c.scheme?.lowercased(), let host = c.host, let port = c.port else { throw invalidKey() }
        let query = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let network = query["type"] ?? "tcp"
        let security = query["security"] ?? (query["tls"] == "tls" ? "tls" : "none")
        var stream: [String: Any] = ["network": network, "security": security]
        if security == "tls" || security == "reality" {
            var tls: [String: Any] = ["serverName": query["sni"] ?? host]
            if security == "reality" { tls["publicKey"] = query["pbk"] ?? ""; tls["shortId"] = query["sid"] ?? ""; tls["fingerprint"] = query["fp"] ?? "chrome"; stream["realitySettings"] = tls }
            else { stream["tlsSettings"] = tls }
        }
        if network == "ws" { stream["wsSettings"] = ["path": query["path"]?.removingPercentEncoding ?? "/", "headers": ["Host": query["host"] ?? host]] }
        if scheme == "vless" {
            let id = c.user ?? ""
            return ["protocol": "vless", "tag": "proxy", "settings": ["vnext": [["address": host, "port": port, "users": [["id": id, "encryption": query["encryption"] ?? "none", "flow": query["flow"] ?? ""]]]]], "streamSettings": stream]
        }
        if scheme == "trojan" {
            return ["protocol": "trojan", "tag": "proxy", "settings": ["servers": [["address": host, "port": port, "password": c.user ?? ""]]], "streamSettings": stream]
        }
        if scheme == "socks" {
            return ["protocol": "socks", "tag": "proxy", "settings": ["servers": [["address": host, "port": port]]]]
        }
        throw NSError(domain: "DieCloudeVPN", code: 4, userInfo: [NSLocalizedDescriptionKey: "Этот формат пока не поддерживается встроенным модулем: \(scheme)"])
    }

    private func vmessOutbound(_ uri: String) throws -> [String: Any] {
        let encoded = String(uri.dropFirst("vmess://".count))
        let normalized = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = j["add"] as? String, let id = j["id"] as? String else { throw invalidKey() }
        let port = Int(j["port"] as? String ?? "") ?? 443
        let network = j["net"] as? String ?? "tcp"; let tls = j["tls"] as? String ?? ""
        var stream: [String: Any] = ["network": network, "security": tls.isEmpty ? "none" : "tls"]
        if !tls.isEmpty { stream["tlsSettings"] = ["serverName": j["sni"] as? String ?? host] }
        if network == "ws" { stream["wsSettings"] = ["path": j["path"] as? String ?? "/", "headers": ["Host": j["host"] as? String ?? host]] }
        return ["protocol": "vmess", "tag": "proxy", "settings": ["vnext": [["address": host, "port": port, "users": [["id": id, "alterId": Int(j["aid"] as? String ?? "0") ?? 0, "security": j["scy"] as? String ?? "auto"]]]]], "streamSettings": stream]
    }

    private func invalidKey() -> NSError { NSError(domain: "DieCloudeVPN", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось разобрать выбранный сервер."]) }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var size: Int = 0; sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size); sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

final class VPNWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var servers: [VPNServer] = []
    private let keyField = NSSecureTextField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "VPN выключен")
    private let statusDot = NSView()
    private let connectButton = NSButton(title: "Подключить", target: nil, action: nil)
    private let autoConnectSwitch = NSSwitch()
    private enum VPNDefaults {
        static let autoConnect = "DieCloudeVPNAutoConnect"
        static let servers = "DieCloudeVPNServers"
        static let selectedURI = "DieCloudeVPNSelectedServerURI"
    }
    var onProxyChanged: ((Bool, Int) -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = "VPN — только DieCloude"; window.minSize = NSSize(width: 600, height: 400)
        // Контроллер владеет окном: после закрытия крестиком оно должно
        // корректно открываться снова через showWindow.
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window); buildUI(); restoreState()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        // Frosty-фон в тон приложению
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 680, height: 480))
        content.material = .underWindowBackground
        content.blendingMode = .behindWindow
        content.state = .active
        window?.contentView = content

        let label = sectionHeader("ПОДПИСКА")
        keyField.placeholderString = "Вставь subscription URL или ключ"
        keyField.stringValue = KeychainStore.load(account: "happ-subscription") ?? ""
        // Enter в поле ключа = «Обновить ключ»
        keyField.target = self; keyField.action = #selector(refreshKey)

        let refresh = NSButton(title: "Обновить ключ", target: self, action: #selector(refreshKey))
        refresh.bezelStyle = .inline
        refresh.controlSize = .small
        refresh.contentTintColor = .secondaryLabelColor
        let ping = NSButton(title: "Проверить пинг", target: self, action: #selector(pingAll))
        ping.bezelStyle = .inline
        ping.controlSize = .small
        ping.contentTintColor = .secondaryLabelColor
        let keyButtons = NSStackView(views: [refresh, ping])
        keyButtons.orientation = .horizontal
        keyButtons.spacing = 14

        let autoRow = settingsRow(title: "Автоподключение при запуске",
                                  subtitle: "Вернётся к выбранному серверу автоматически",
                                  control: autoConnectSwitch)
        autoConnectSwitch.controlSize = .small
        autoConnectSwitch.target = self; autoConnectSwitch.action = #selector(autoConnectChanged(_:))
        autoConnectSwitch.state = UserDefaults.standard.bool(forKey: VPNDefaults.autoConnect) ? .on : .off

        connectButton.target = self; connectButton.action = #selector(toggleConnection)
        connectButton.bezelStyle = .rounded
        connectButton.keyEquivalent = "\r"

        let serversHeader = sectionHeader("СЕРВЕРЫ")
        for (title, width) in [("Сервер",360.0),("Протокол",100.0),("Пинг",90.0)] { let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title)); c.title=title; c.width=width; table.addTableColumn(c) }
        table.headerView = NSTableHeaderView(); table.delegate=self; table.dataSource=self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 28
        table.style = .inset
        table.doubleAction = #selector(connectFromTable(_:))    // двойной клик = подключить
        table.target = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        scroll.layer?.masksToBounds = true

        let hint = NSTextField(labelWithString: "Двойной клик по серверу — подключить.")
        hint.textColor = .tertiaryLabelColor; hint.font = .systemFont(ofSize: 11)

        statusDot.wantsLayer = true
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        let statusRow = NSStackView(views: [statusDot, status, NSView(), connectButton])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [label, keyField, keyButtons, autoRow, separator(), serversHeader, scroll, hint, statusRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: keyField)
        stack.setCustomSpacing(14, after: keyButtons)
        stack.setCustomSpacing(14, after: autoRow)
        stack.setCustomSpacing(14, after: serversHeader)
        stack.setCustomSpacing(6, after: scroll)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            keyField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            autoRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            refresh.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        setStatus("VPN выключен")
    }

    /// Заголовок секции: маленький капс, приглушённый.
    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        if let attributed = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attributed.addAttribute(.kern, value: 1.2, range: NSRange(location: 0, length: attributed.length))
            label.attributedStringValue = attributed
        }
        return label
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// Строка настройки: текст слева, элемент управления справа.
    private func settingsRow(title: String, subtitle: String, control: NSControl) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
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
        return row
    }

    @objc private func connectFromTable(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < servers.count else { return }
        connect(server: servers[row])
    }

    @objc private func refreshKey() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !key.isEmpty else { setStatus("Вставь ключ или ссылку подписки") ; return }
        KeychainStore.save(key, account: "happ-subscription"); setStatus("Обновление…")
        if let url = URL(string:key), ["http","https"].contains(url.scheme?.lowercased() ?? "") {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("DieCloude/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with:req) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error { self.setStatus(error.localizedDescription); return }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        self.setStatus("Сервер подписки вернул ошибку"); return
                    }
                    guard let data, data.count < 2_000_000 else {
                        self.setStatus("Подписка слишком большая"); return
                    }
                    self.loadServers(from: SubscriptionParser.decodeText(data))
                }
            }.resume()
        } else { loadServers(from: SubscriptionParser.decodeText(Data(key.utf8))) }
    }

    private func loadServers(from text:String) {
        servers = SubscriptionParser.parse(text)
        persistServers()
        table.reloadData()
        restoreSelection()
        setStatus(servers.isEmpty ? "Совместимые серверы не найдены" : "Найдено серверов: \(servers.count)")
    }

    @objc private func pingAll() {
        guard !servers.isEmpty else { refreshKey(); return }
        setStatus("Проверка задержки…")
        // Лимит параллелизма: не греем сеть/CPU, максимум 6 одновременно
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 6)
        for index in servers.indices {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                semaphore.wait()
                self.measure(index: index) {
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.sortByPing()
            self.setStatus("Проверка завершена")
        }
    }

    /// Быстрые серверы — наверх; не ответившие — в конец.
    private func sortByPing() {
        let selected = UserDefaults.standard.string(forKey: VPNDefaults.selectedURI)
        servers.sort { a, b in
            switch (a.pingMS, b.pingMS) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
        persistServers()
        table.reloadData()
        if let selected, let row = servers.firstIndex(where: { $0.rawURI == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    private func measure(index: Int, done: @escaping () -> Void) {
        guard index < servers.count,
              let port = NWEndpoint.Port(rawValue: UInt16(servers[index].port)) else { done(); return }
        let server = servers[index]
        let queue = DispatchQueue(label: "DieCloude.Ping.\(index)", qos: .utility)
        let connection = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: .tcp)
        let start = DispatchTime.now()
        var finished = false

        func finish(_ value: Int) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { [weak self] in
                guard let self, index < self.servers.count else { done(); return }
                self.servers[index].pingMS = value
                self.table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integersIn: 0..<self.table.numberOfColumns))
                done()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                finish(Int(elapsed / 1_000_000))
            case .failed, .cancelled:
                finish(9999)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { finish(9999) }
    }

    @objc private func toggleConnection() {
        if XrayManager.shared.isRunning { XrayManager.shared.stop(); onProxyChanged?(false,XrayManager.shared.localPort); connectButton.title="Подключить"; setStatus("VPN выключен"); return }
        let row=table.selectedRow; guard row>=0,row<servers.count else {setStatus("Выбери сервер");return}
        connect(server: servers[row])
    }

    @objc private func autoConnectChanged(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: VPNDefaults.autoConnect)
    }

    func attemptAutoConnect() {
        guard UserDefaults.standard.bool(forKey: VPNDefaults.autoConnect) else { return }
        if servers.isEmpty { restoreState() }
        guard let raw = UserDefaults.standard.string(forKey: VPNDefaults.selectedURI),
              let server = servers.first(where: { $0.rawURI == raw }) else { return }
        connect(server: server)
    }

    private func connect(server: VPNServer) {
        connectButton.isEnabled = false
        setStatus("Подключение: \(server.name)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try XrayManager.shared.start(server: server)
                DispatchQueue.main.async {
                    guard let self else { return }
                    UserDefaults.standard.set(server.rawURI, forKey: VPNDefaults.selectedURI)
                    if let row = self.servers.firstIndex(where: { $0.rawURI == server.rawURI }) {
                        self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    }
                    self.onProxyChanged?(true, XrayManager.shared.localPort)
                    self.connectButton.title = "Отключить"
                    self.connectButton.isEnabled = true
                    self.setStatus("Подключено: \(server.name)")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.connectButton.isEnabled = true
                    self?.setStatus(error.localizedDescription)
                }
            }
        }
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(data, forKey: VPNDefaults.servers) }
    }

    private func restoreState() {
        if let data = UserDefaults.standard.data(forKey: VPNDefaults.servers),
           let decoded = try? JSONDecoder().decode([VPNServer].self, from: data) {
            servers = decoded
            table.reloadData()
            restoreSelection()
        }
        // Ключ сохранён, а списка ещё нет — подтягиваем подписку сразу,
        // чтобы не жать «Обновить ключ» вручную при каждом открытии.
        if servers.isEmpty,
           let key = KeychainStore.load(account: "happ-subscription"), !key.isEmpty {
            refreshKey()
        }
    }

    private func restoreSelection() {
        guard let raw = UserDefaults.standard.string(forKey: VPNDefaults.selectedURI),
              let row = servers.firstIndex(where: { $0.rawURI == raw }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func setStatus(_ text: String) {
        status.stringValue = text
        // Точка статуса: зелёная — соединено, серая — выключено
        statusDot.layer?.backgroundColor = (XrayManager.shared.isRunning
            ? NSColor.systemGreen
            : NSColor.systemGray).withAlphaComponent(0.9).cgColor
    }
    func numberOfRows(in tableView:NSTableView)->Int{servers.count}
    func tableView(_ tableView:NSTableView, viewFor tableColumn:NSTableColumn?, row:Int)->NSView? { let id=tableColumn?.identifier.rawValue ?? ""; let field=NSTextField(labelWithString: id=="Сервер" ? servers[row].name : id=="Протокол" ? servers[row].scheme.uppercased() : (servers[row].pingMS.map{$0>=9999 ? "тайм-аут" : "\($0) ms"} ?? "—")); field.lineBreakMode = .byTruncatingTail; return field }
}
