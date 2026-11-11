import AppKit

/// Проверка обновлений через GitHub Releases.
///
/// Берём список последних релизов, а не /releases/latest: latest-эндпоинт
/// игнорирует релизы, случайно оставленные как prerelease, и возвращает 404,
/// если стабильных релизов нет вообще. Список позволяет выбрать самый новый
/// полноценный релиз с DMG и объяснить пользователю, что именно случилось.
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
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, draft, prerelease, assets
        }

        var isPublished: Bool { draft != true && prerelease != true }
        var dmgAsset: Asset? {
            assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
        }
    }

    private static let skippedVersionKey = "DieCloudeSkippedVersion"

    func checkForUpdates(presenting window: NSWindow?, silentWhenCurrent: Bool) {
        guard let owner = Bundle.main.object(forInfoDictionaryKey: "DieCloudeGitHubOwner") as? String,
              let repository = Bundle.main.object(forInfoDictionaryKey: "DieCloudeGitHubRepository") as? String,
              !owner.isEmpty, !repository.isEmpty,
              owner != "CHANGE_ME", repository != "CHANGE_ME" else {
            if !silentWhenCurrent { showMessage("Обновления не настроены", "Укажи DieCloudeGitHubOwner и DieCloudeGitHubRepository в Info.plist перед сборкой.", window) }
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases?per_page=10") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DieCloude/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    if !silentWhenCurrent { self.showMessage("Не удалось проверить обновления", error.localizedDescription, window) }
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    if !silentWhenCurrent { self.showMessage("Не удалось проверить обновления", "GitHub вернул пустой ответ.", window) }
                    return
                }
                guard http.statusCode == 200 else {
                    if !silentWhenCurrent {
                        let text: String
                        switch http.statusCode {
                        case 403, 429: text = "GitHub ограничил количество запросов (лимит API). Попробуй через пару минут."
                        case 404: text = "Релизы в репозитории не найдены — проверь, что релиз опубликован и не помечен как черновик."
                        default: text = "GitHub ответил ошибкой HTTP \(http.statusCode)."
                        }
                        self.showMessage("Не удалось проверить обновления", text, window)
                    }
                    return
                }
                guard let data, let releases = try? JSONDecoder().decode([Release].self, from: data) else {
                    if !silentWhenCurrent { self.showMessage("Не удалось проверить обновления", "GitHub вернул неподдерживаемый ответ.", window) }
                    return
                }
                // Самый новый полноценный релиз, в котором есть файл для установки.
                guard let release = releases.first(where: { $0.isPublished && $0.dmgAsset != nil }) else {
                    if !silentWhenCurrent { self.showMessage("Обновлений нет", "В репозитории пока нет опубликованных релизов с DMG.", window) }
                    return
                }
                let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard self.isNewer(remote, than: AppConfig.version) else {
                    if !silentWhenCurrent { self.showMessage("Обновлений нет", "Установлена актуальная версия \(AppConfig.version).", window) }
                    return
                }
                if UserDefaults.standard.string(forKey: Self.skippedVersionKey) == remote {
                    // Эту версию пользователь решил пропустить — не напоминаем,
                    // но больший номер версии покажем как обычно.
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
        alert.addButton(withTitle: "Пропустить эту версию")
        alert.addButton(withTitle: "Позже")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.downloadAsset(from: release, window: window)
            case .alertSecondButtonReturn:
                UserDefaults.standard.set(remoteVersion, forKey: Self.skippedVersionKey)
            default:
                break
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: completion) } else { completion(alert.runModal()) }
    }

    private func downloadAsset(from release: Release, window: NSWindow?) {
        guard let asset = release.dmgAsset else { NSWorkspace.shared.open(release.htmlURL); return }
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
