# scripts/ — helper-команды DieCloude

Двойной клик в Finder запускает скрипт в Терминале (`.command`).

| Файл | Назначение |
|---|---|
| `Создать установщик.command` | Сборка универсального app + DMG через `../package-dmg.sh`. |
| `Первый запуск DieCloude.command` | Снятие карантина, права 755, ad-hoc подпись. Его копия кладётся в DMG. |
| `Опубликовать обновление.command` | Синхронизация версии, commit, тег `vX.Y.Z`, ожидание GitHub Actions. |
| `Настроить GitHub.command` | Запись `DieCloudeGitHubOwner/Repository` в `../Info.plist`. |

Все скрипты сами находят корень репозитория (`../Info.plist`), поэтому работают и из `scripts/`, и из корня.
Версия приложения при переезде не менялась: 4.0.0 build 31.
