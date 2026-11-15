import Foundation
import Network

/// Discord's local IPC transport. All connection state is confined to `queue`.
final class DiscordRPC {
    struct Playback {
        var title = ""
        var artist = ""
        var artwork = ""
        var trackURL = ""
        var playing = false
        var position: Double = 0
        var duration: Double = 0
    }

    private let queue = DispatchQueue(label: "app.diecloude.discord-rpc")
    private var clientID: String
    private var enabled = false
    private var connection: NWConnection?
    private var retry: DispatchWorkItem?
    private var generation = 0
    private var socketIndex = 0
    private let socketPaths: [String]
    private var connectionTimeout: DispatchWorkItem?
    private var ready = false
    private var buffer = Data()
    private var playback = Playback()
    private var lastActivity = ""
    private var lastSentAt = Date.distantPast

    init(clientID: String = "") {
        let saved = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = !saved.isEmpty ? saved : (UserDefaults.standard.string(forKey: "DiscordClientID")?.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber) ?? "")
        self.clientID = !effective.isEmpty ? effective : SettingsState.defaultDiscordClientID
        let env = ProcessInfo.processInfo.environment
        var directories: [String] = []
        for directory in [env["XDG_RUNTIME_DIR"], env["TMPDIR"], env["TMP"], env["TEMP"], "/tmp"] {
            guard let directory, directory.hasPrefix("/") else { continue }
            let normalized = (directory as NSString).standardizingPath
            if !directories.contains(normalized) { directories.append(normalized) }
        }
        if directories.isEmpty { directories = ["/tmp"] }
        socketPaths = directories.flatMap { directory in
            (0..<10).map { (directory as NSString).appendingPathComponent("discord-ipc-\($0)") }
        }
    }

    func setClientID(_ value: String) {
        queue.async {
            let digits = value.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            let newID = digits.isEmpty ? SettingsState.defaultDiscordClientID : digits
            guard self.clientID != newID else { return }
            self.clientID = newID
            if self.enabled {
                if self.ready { self.sendActivity(nil) }
                self.disconnect()
                guard !self.clientID.isEmpty, self.clientID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                    NSLog("DieCloude: configure a numeric DiscordClientID before enabling Discord RPC")
                    return
                }
                self.socketIndex = 0
                self.connect()
            }
        }
    }

    func setEnabled(_ value: Bool) {
        queue.async {
            guard self.enabled != value else { return }
            self.enabled = value
            if value {
                guard !self.clientID.isEmpty, self.clientID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                    NSLog("DieCloude: configure a numeric DiscordClientID before enabling Discord RPC")
                    return
                }
                self.socketIndex = 0
                self.connect()
            } else {
                if self.ready { self.sendActivity(nil) }
                self.disconnect()
            }
        }
    }

    func update(_ playback: Playback) {
        queue.async {
            self.playback = playback
            self.publish()
        }
    }

    private func connect() {
        guard enabled, connection == nil else { return }
        let path = socketPaths[socketIndex]
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        generation += 1
        let current = generation
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.generation == current else { return }
            switch state {
            case .ready:
                self.sendFrame(opcode: 0, object: ["v": 1, "client_id": self.clientID])
                self.receive(connection, generation: current)
            case .waiting, .failed, .cancelled:
                self.reconnect(generation: current)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.reconnect(generation: current) }
        connectionTimeout = timeout
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        connection.start(queue: queue)
    }

    private func receive(_ connection: NWConnection, generation: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.generation == generation else { return }
            if let data { self.buffer.append(data) }
            guard self.consumeFrames() else { self.reconnect(generation: generation); return }
            if complete || error != nil { self.reconnect(generation: generation); return }
            self.receive(connection, generation: generation)
        }
    }

    private func consumeFrames() -> Bool {
        while buffer.count >= 8 {
            let bytes = [UInt8](buffer.prefix(8))
            let opcode = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let length = Int(UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24)
            guard length <= 1_048_576 else { return false }
            guard buffer.count >= 8 + length else { return true }
            let payload = buffer.subdata(in: 8..<(8 + length))
            buffer.removeSubrange(0..<(8 + length))
            switch opcode {
            case 1:
                if let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
                   object["evt"] as? String == "READY" {
                    ready = true
                    connectionTimeout?.cancel()
                    connectionTimeout = nil
                    lastActivity = ""
                    publish()
                }
            case 2: return false
            case 3: sendFrame(opcode: 4, data: payload)
            default: break
            }
        }
        return true
    }

    private func publish() {
        guard ready else { return }
        guard playback.playing, !playback.title.isEmpty else {
            if lastActivity != "clear" { sendActivity(nil); lastActivity = "clear" }
            return
        }
        var activity: [String: Any] = ["details": String(playback.title.prefix(128)),
                                       "state": String((playback.artist.isEmpty ? "SoundCloud" : playback.artist).prefix(128))]
        if let trackURL = validatedTrackURL(playback.trackURL) {
            activity["buttons"] = [["label": "Open on SoundCloud", "url": trackURL]]
        }
        if let url = URL(string: playback.artwork), url.scheme == "https", url.host != nil {
            activity["assets"] = ["large_image": playback.artwork]
        }
        let position = playback.position.isFinite ? max(0, playback.position) : 0
        let duration = playback.duration.isFinite ? max(0, playback.duration) : 0
        let key = "\(playback.title)\n\(playback.artist)\n\(playback.artwork)\n\(playback.trackURL)\n\(duration)"
        // Normal progress updates should not flood Discord; resend periodically to account for seeks.
        if key == lastActivity && Date().timeIntervalSince(lastSentAt) < 15 { return }
        if duration > position && duration < 604800 {
            let now = Date().timeIntervalSince1970
            activity["timestamps"] = ["start": Int(now - position), "end": Int(now + duration - position)]
        }
        sendActivity(activity)
        lastActivity = key
        lastSentAt = Date()
    }

    private func validatedTrackURL(_ value: String) -> String? {
        guard value.utf8.count <= 512,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "soundcloud.com" || host == "www.soundcloud.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.split(separator: "/").count >= 2 else { return nil }
        return components.url?.absoluteString
    }

    private func sendActivity(_ activity: [String: Any]?) {
        sendFrame(opcode: 1, object: ["cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity as Any? ?? NSNull()], "nonce": UUID().uuidString])
    }

    private func sendFrame(opcode: UInt32, object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        sendFrame(opcode: opcode, data: data)
    }

    private func sendFrame(opcode: UInt32, data: Data) {
        var op = opcode.littleEndian
        var length = UInt32(data.count).littleEndian
        var frame = Data(bytes: &op, count: 4)
        frame.append(Data(bytes: &length, count: 4))
        frame.append(data)
        let current = generation
        connection?.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self, error != nil else { return }
            self.reconnect(generation: current)
        })
    }

    private func reconnect(generation: Int) {
        guard self.generation == generation else { return }
        disconnect()
        guard enabled, !socketPaths.isEmpty else { return }
        socketIndex = (socketIndex + 1) % socketPaths.count
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retry = work
        queue.asyncAfter(deadline: .now() + (socketIndex == 0 ? 5 : 0.2), execute: work)
    }

    private func disconnect() {
        generation += 1
        retry?.cancel()
        retry = nil
        connectionTimeout?.cancel()
        connectionTimeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        ready = false
        buffer.removeAll()
        lastActivity = ""
    }
}
