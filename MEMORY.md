# MEMORY — постоянные правила DieCloude (запомнить)

1. Минимальный таргет — macOS 14+. Ветвлений `#available(macOS 14)` для VPN больше нет.
2. Язык — Swift AppKit + WebKit. Не переписывать на Electron/другое: Swift самый холодный.
3. Xray остаётся в бандле (`xray-arm64` + `xray-x86_64`). При бампе обновлять `XRAY_TAG` в `build.sh` + версию в `THIRD_PARTY_NOTICES.md` + sha-проверку.
4. Подписи Developer ID нет — всегда ad-hoc `codesign -s -` + `scripts/Первый запуск DieCloude.command`.
5. Версия — единый источник: `Info.plist` + `AppConfig.version/build` + `package-dmg.sh VERSION` + `README/CHANGELOG/RELEASE_NOTES`. Бампить всё вместе.
6. Окно «Что нового» (`showWelcomeIfNeeded`) обязано читать `RELEASE_NOTES.md` из бандла. Ключ `DefaultsKey.welcome` версионируется: `DieCloudeWelcomeV<версия>Shown`.
7. Публикация для репозитория — папка `dist/repo-publish/` (см. RELEASE_PROCESS.md). Именно её содержимое пользователь заливает в GitHub.
8. Хоткей настроек — Cmd+, (пункт «Настройки…» в app-меню). F1 больше не используется.
9. noAds — трёхуровневый: `resources/adblock-rules.json` (network V8) + `theme-engine.js` (cosmetic + audio skip) + `src/AdBlockService.swift`. Правило-лист ID версионируется `DieCloudeAdBlockRulesV<N>`.
10. Helper-команды живут в `scripts/` (5 `.command` файлов), в корне их нет. Ссылки: `package-dmg.sh` берёт Первый запуск из `scripts/` с fallback на корень, CI chmod чинит `scripts/*.command`.
11. Заморозка: версию 4.0.0 и сборку 31 не бампить. Скрипт `scripts/Заменить на последнюю сборку.command` меняет только файлы установленной программы, не версию.
12. README — только нововведения: заголовок, строка версии, ссылка на релиз, «Что нового в X», короткое «Раньше». Никаких установок/сборок/воды. Паттерны `**Версия X · сборка Y · macOS Z+**` и `## Что нового в X` не ломать — их правит скрипт публикации. Обновлять с каждой новой версией.
