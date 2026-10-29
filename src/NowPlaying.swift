import AppKit
import MediaPlayer
import WebKit

/// WKUserContentController держит handler сильно — без weak-прокси
/// NowPlayingController не освобождается до конца жизни процесса.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Мост «страница → приложение» и системный Now Playing.
///
/// JS-движок темы шлёт состояние плеера через message handler "diecloudeBridge"
/// (state / meta / playerMissing), а команды системного плеера — медиа-клавиши
/// F7–F9, кнопки наушников, экран блокировки — возвращаются в страницу
/// кликами по кнопкам SoundCloud.
final class NowPlayingController: NSObject, WKScriptMessageHandler {
    enum PlayerAction { case togglePlay, next, previous }
    static let bridgeName = "diecloudeBridge"

    /// Выполняется в главном потоке; устанавливается AppDelegate после сборки окна.
    var performAction: ((PlayerAction) -> Void)?
    var performSeek: ((Double) -> Void)?
    var onPlayerMissing: (() -> Void)?
    var onPlayerFound: (() -> Void)?

    private var info: [String: Any] = [:]
    private var artworkTask: URLSessionDataTask?
    private var artworkURLString = ""
    private var hasState = false
    private var bridgeProxy: WeakScriptMessageHandler?
    private weak var contentController: WKUserContentController?

    func register(on contentController: WKUserContentController) {
        // Повторная регистрация того же имени крашит WebKit — снимаем старый.
        contentController.removeScriptMessageHandler(forName: Self.bridgeName)
        let proxy = WeakScriptMessageHandler(target: self)
        bridgeProxy = proxy
        self.contentController = contentController
        contentController.add(proxy, name: Self.bridgeName)
    }

    func unregister() {
        contentController?.removeScriptMessageHandler(forName: Self.bridgeName)
        contentController = nil
        bridgeProxy = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    deinit {
        disableRemoteCommands()
        unregister()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        // Сообщения уже приходят на main в WKWebView; лишний async не нужен,
        // но оставляем на случай вызова из другого контекста.
        let work = { [weak self] in
            switch type {
            case "state": self?.handleState(body)
            case "meta": self?.handleMeta(body)
            case "playerMissing": self?.onPlayerMissing?()
            case "playerFound": self?.onPlayerFound?()
            default: break
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Состояние из страницы

    private func handleState(_ body: [String: Any]) {
        hasState = true
        let playing = body["playing"] as? Bool ?? false
        let position = body["position"] as? Double ?? 0
        let duration = body["duration"] as? Double ?? 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        publish()
    }

    private func handleMeta(_ body: [String: Any]) {
        let title = body["title"] as? String ?? ""
        let artist = body["artist"] as? String ?? ""
        if !title.isEmpty { info[MPMediaItemPropertyTitle] = title }
        info[MPMediaItemPropertyArtist] = artist.isEmpty ? "SoundCloud" : artist
        let artwork = body["artwork"] as? String ?? ""
        if artwork != artworkURLString {
            artworkURLString = artwork
            loadArtwork(from: artwork)
        }
        publish()
    }

    private func publish() {
        // Без трека системный плеер показывает пустую карточку — не публикуем.
        guard (info[MPMediaItemPropertyTitle] as? String)?.isEmpty == false, hasState else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Обложка

    private func loadArtwork(from urlString: String) {
        artworkTask?.cancel()
        info[MPMediaItemPropertyArtwork] = nil
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return }
        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURLString == urlString else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.info[MPMediaItemPropertyArtwork] = artwork
                self.publish()
            }
        }
        artworkTask?.resume()
    }

    // MARK: - Команды системы

    private var remoteTargets: [Any] = []

    func enableRemoteCommands() {
        // Не копить обработчики при повторном вызове (перезапуск окна / тесты).
        disableRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        remoteTargets = [
            center.playCommand.addTarget { [weak self] _ in self?.runAction(.togglePlay); return .success },
            center.pauseCommand.addTarget { [weak self] _ in self?.runAction(.togglePlay); return .success },
            center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.runAction(.togglePlay); return .success },
            center.nextTrackCommand.addTarget { [weak self] _ in self?.runAction(.next); return .success },
            center.previousTrackCommand.addTarget { [weak self] _ in self?.runAction(.previous); return .success },
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                self?.performSeek?(event.positionTime)
                return .success
            }
        ]
    }

    func disableRemoteCommands() {
        guard !remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        // Снимаем только наши обработчики (токены от addTarget).
        for target in remoteTargets {
            center.playCommand.removeTarget(target)
            center.pauseCommand.removeTarget(target)
            center.togglePlayPauseCommand.removeTarget(target)
            center.nextTrackCommand.removeTarget(target)
            center.previousTrackCommand.removeTarget(target)
            center.changePlaybackPositionCommand.removeTarget(target)
        }
        remoteTargets.removeAll()
    }

    private func runAction(_ action: PlayerAction) {
        DispatchQueue.main.async { [weak self] in
            self?.performAction?(action)
        }
    }
}
