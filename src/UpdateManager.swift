import AppKit

final class UpdateManager {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
        }
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, assets
        }
    }

    func checkForUpdates(presenting window: NSWindow?, silentWhenCurrent: Bool) {
        guard let owner = Bundle.main.object(forInfoDictionaryKey: "DieCloudeGitHubOwner") as? String,
              let repository = Bundle.main.object(forInfoDictionaryKey: "DieCloudeGitHubRepository") as? String,
              !owner.isEmpty, !repository.isEmpty,
              owner != "CHANGE_ME", repository != "CHANGE_ME" else {
            if !silentWhenCurrent { showMessage("Обновления не настроены", "Укажи DieCloudeGitHubOwner и DieCloudeGitHubRepository в Info.plist перед сборкой.", window) }
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DieCloude/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { if !silentWhenCurrent { self.showMessage("Не удалось проверить обновления", error.localizedDescription, window) }; return }
                guard let data, let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if !silentWhenCurrent { self.showMessage("Не удалось проверить обновления", "GitHub вернул неподдерживаемый ответ.", window) }
                    return
                }
                let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard self.isNewer(remote, than: AppConfig.version) else {
                    if !silentWhenCurrent { self.showMessage("Обновлений нет", "Установлена актуальная версия \(AppConfig.version).", window) }
                    return
                }
                self.offer(release, remoteVersion: remote, window: window)
            }
        }.resume()
    }

    private func offer(_ release: Release, remoteVersion: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Доступна DieCloude \(remoteVersion)"
        let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = notes.isEmpty ? "Можно скачать новую версию с GitHub." : String(notes.prefix(1200))
        alert.addButton(withTitle: "Скачать и открыть")
        alert.addButton(withTitle: "Позже")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.downloadBestAsset(from: release, remoteVersion: remoteVersion, window: window)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: completion) } else { completion(alert.runModal()) }
    }

    private func downloadBestAsset(from release: Release, remoteVersion: String, window: NSWindow?) {
        let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
            ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
        guard let asset else { NSWorkspace.shared.open(release.htmlURL); return }
        URLSession.shared.downloadTask(with: asset.browserDownloadURL) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                if let error { self?.showMessage("Ошибка загрузки", error.localizedDescription, window); return }
                guard let tempURL else { return }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destination = self?.uniqueURL(downloads.appendingPathComponent(asset.name)) ?? downloads.appendingPathComponent(asset.name)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    NSWorkspace.shared.open(destination)
                } catch { self?.showMessage("Не удалось сохранить обновление", error.localizedDescription, window) }
            }
        }.resume()
    }

    private func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...99 {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url.deletingLastPathComponent().appendingPathComponent("\(base)-\(UUID().uuidString)").appendingPathExtension(ext)
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let av = index < a.count ? a[index] : 0
            let bv = index < b.count ? b[index] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    private func showMessage(_ title: String, _ text: String, _ window: NSWindow?) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text; alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
