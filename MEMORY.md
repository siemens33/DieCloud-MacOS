# MEMORY — постоянные правила DieCloude (запомнить)

1. Минимальный таргет — macOS 14+. Ветвлений `#available(macOS 14)` для VPN больше нет.
2. Язык — Swift AppKit + WebKit. Не переписывать на Electron/другое: Swift самый холодный.
3. Xray остаётся в бандле (`xray-arm64` + `xray-x86_64`). При бампе обновлять `XRAY_TAG` в `build.sh` + версию в `THIRD_PARTY_NOTICES.md` + sha-проверку.
4. Подписи Developer ID нет — всегда ad-hoc `codesign -s -` + `scripts/Первый запуск DieCloude.command`.
5. Версия — единый источник: `Info.plist` + `AppConfig.version/build` + `package-dmg.sh VERSION` + `README/CHANGELOG/RELEASE_NOTES`. Бампить всё вместе.
6. Окно «Что нового» (`showWelcomeIfNeeded`) читает `RELEASE_NOTES.md` из бандла. Ключ `DefaultsKey.welcome` вычисляется автоматически из `AppConfig.version` (`DieCloudeWelcomeV<версия>Shown`), поэтому окно показывается при каждом обновлении версии — ничего бампить вручную не нужно.
7. Публикация для репозитория — папка `dist/repo-publish/` (см. RELEASE_PROCESS.md). Именно её содержимое пользователь заливает в GitHub.
8. Хоткей настроек — Cmd+, (пункт «Настройки…» в app-меню). F1 больше не используется. Плеер: ⌘P пауза, ⌘← / ⌘→ треки (PlayerScripts в main.swift).
9. noAds — трёхуровневый: `resources/adblock-rules.json` (network) + `theme-engine.js` (cosmetic + audio skip) + `src/AdBlockService.swift`. Правило-лист ID версионируется `DieCloudeAdBlockRulesV<N>` (сейчас V9).
10. Helper-команды живут в `scripts/` (5 `.command` файлов), в корне их нет. Ссылки: `package-dmg.sh` берёт Первый запуск из `scripts/` с fallback на корень, CI chmod чинит `scripts/*.command`.
11. Заморозка: версию 4.0.0 (build 31) и 4.0.1 (build 32) не бампить. Скрипт `scripts/Заменить на последнюю сборку.command` меняет только файлы установленной программы, не версию.
12. README — только нововведения: заголовок, строка версии, ссылка на релиз, «Что нового в X», короткое «Раньше». Никаких установок/сборок/воды. Паттерны `**Версия X · сборка Y · macOS Z+**` и `## Что нового в X` не ломать — их правит скрипт публикации. Обновлять с каждой новой версией.
13. Настройки — единый реестр `SettingsState` в `src/main.swift`: один список (UserDefaults-ключ, jsKey, заголовок, тултип, дефолт). Новый эффект добавляется одной строкой в init; чекбоксы, сброс и JS-инъекция строятся из него же.
14. Матово-стеклянный плеер — двухслойный: внешняя плита (`[data-dc-playerbar]`/footer) держит blur+saturate, внутренняя планка (`[data-dc-player]`) — только вуаль без собственного blur. Не складывать blur дважды.
15. Скрипт публикации бампит сборку (+1) только если сам поднял patch-версию; если версия уже изменена в файлах — сборка берётся из файлов как есть.
