<div align="center">
  <img src="resources/DieCloudeIcon.png" width="144" alt="DieCloude">

# DieCloude

Нативная оболочка SoundCloud для macOS с фирменным монохромным интерфейсом.

**Версия 4.0.0 · сборка 32 · macOS 14+**

[Скачать последнюю версию](https://github.com/siemens33/DieCloud-MacOS/releases/latest)
</div>

## Что нового в 4.0.0

- Глобальное обновление
## Возможности

- отдельное нативное окно macOS на Swift, AppKit и WebKit;
- фирменная тёмная тема и белый акцент;
- матовая нижняя панель проигрывателя;
- аккуратное скругление обложек и мягкий hover;
- Focus Mode и noAds V8;
- медиаклавиши и навигация macOS;
- VPN-прокси только для DieCloude (macOS 14+);
- проверка обновлений через GitHub Releases;
- сборки для Apple Silicon и Intel.

## Настройки

Нажмите **⌘,** или кнопку с ползунками в верхней панели. Настройки сохраняются автоматически и применяются только внутри DieCloude.

## Установка

1. Скачайте `DieCloude.dmg` из раздела Releases.
2. Перетащите `DieCloude.app` в папку «Программы».
3. Для неподписанной сборки (ad-hoc, без Developer ID) один раз запустите `Первый запуск DieCloude.command` из DMG.

## Сборка из исходников

Требуются macOS 14+ и Xcode Command Line Tools.

```bash
chmod +x "scripts/Создать установщик.command"
./"scripts/Создать установщик.command"
```

Готовый DMG появится в папке `build`. Все helper-скрипты лежат в папке `scripts/` (см. `scripts/README.md`).



## Примечание

DieCloude — неофициальный клиент и не связан с SoundCloud. Названия и товарные знаки принадлежат их владельцам. Сведения о сторонних компонентах находятся в [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
