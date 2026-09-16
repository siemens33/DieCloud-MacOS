# Как опубликовать новую версию в репозиторий

Этот файл + папка `dist/repo-publish/` — то, что ассистент присылает отдельно от программы.

## Что лежит в dist/repo-publish/

Копия исходников 4.0.0 без `build/`, `.git/`, `dist/`:

- `src/` (main.swift, VPN.swift, UpdateManager.swift, AdBlockService.swift)
- `resources/` (theme-engine.js, adblock-rules.json, DieCloudeIcon.png)
- `Info.plist`, `build.sh`, `package-dmg.sh`
- `README.md`, `CHANGELOG.md`, `RELEASE_NOTES.md`, `ROADMAP.md`, `FAQ.md`
- `THIRD_PARTY_NOTICES.md`, `MEMORY.md`, `RELEASE_PROCESS.md`
- `.github/workflows/release.yml`
- `scripts/` — 4 `.command` скрипта + `scripts/README.md`

## Шаги публикации

1. Распаковать `repo-publish-4.0.0.zip` (или скопировать папку).
2. В локальном клоне `DieCloud-MacOS` заменить файлы содержимым папки.
3. Проверить версию:
   - `Info.plist` → 4.0.0 / 31
   - `src/main.swift AppConfig` → 4.0.0 / 31
   - `package-dmg.sh VERSION` → 4.0.0
4. Commit + тег:
   ```bash
   git add -A
   git commit -m "DieCloude 4.0.0 build 31: macOS 14, noAds V8, Cmd+, Xray v26.3.27"
   git tag v4.0.0
   git push origin main --tags
   ```
   Либо запустить `./"scripts/Опубликовать обновление.command"`.
5. GitHub Actions соберёт `DieCloude-4.0.0.dmg` и создаст Release из `RELEASE_NOTES.md`.

## Проверка после релиза

- Скачать DMG, перетащить в Программы, запустить `Первый запуск` один раз.
- Проверить: настройки по ⌘,, noAds скрывает промо, VPN подключается, окно «Что нового» показалось один раз.
