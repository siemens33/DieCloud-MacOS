# DieCloud 5.0 (Global Release)

<div align="center">

**Версия 5.0.0 · Dual-Platform (macOS 14+ & Windows 10/11)**

*Флагманский нативный плеер SoundCloud для macOS и Windows. Быстрый, легковесный, без Electron.*

[![Platform macOS](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Universal)-000000?logo=apple&logoColor=white)](https://github.com/siemens33/DieCloud-MacOS/releases/latest)
[![Platform Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11%20(.NET%208)-0078D6?logo=windows&logoColor=white)](https://github.com/siemens33/DieCloud-MacOS/releases/latest)
[![Engine macOS](https://img.shields.io/badge/Engine-Native%20WebKit-007AFF)](https://developer.apple.com/documentation/webkit)
[![Engine Windows](https://img.shields.io/badge/Engine-Edge%20WebView2%20(Chromium)-0078D6)](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
[![Audio](https://img.shields.io/badge/Audio-10--Band%20EQ%20%2B%20CORS-FF5500)](https://soundcloud.com)
[![VPN](https://img.shields.io/badge/VPN-Xray--core%20(Isolated)-28A745)](https://github.com/XTLS/Xray-core)
[![Discord](https://img.shields.io/badge/Discord-Rich%20Presence-5865F2?logo=discord&logoColor=white)](https://discord.com)

[**Скачать релизы (DMG для macOS / Portable ZIP & EXE для Windows)**](https://github.com/siemens33/DieCloud-MacOS/releases/latest)

</div>

---

## 🎧 О проекте DieCloud

**DieCloud** — это высокопроизводительный нативный десктопный клиент для **SoundCloud**. 

В отличие от стандартных веб-приложений на базе громоздкого **Electron**, DieCloud использует **системные движки рендеринга**:
- На **macOS** — нативный **WebKit (`WKWebView`)** на чистом **Swift/AppKit**, потребляющий минимум памяти и не нагружающий батарею MacBook.
- На **Windows** — **Microsoft Edge WebView2 (Chromium)** на базе **C# .NET 8 (WPF)** с аппаратным ускорением и эффектом **Windows 11 Mica**.

---

## 🚀 Архитектура и как всё устроено

```
┌────────────────────────────────────────────────────────────────────────┐
│                        DieCloud Desktop Shell                          │
├───────────────────────────────────┬────────────────────────────────────┤
│         macOS (Swift/AppKit)      │       Windows (C# .NET 8 / WPF)    │
│  • NSWindow (Liquid Glass/Mica)   │  • Frameless Window (DWM Mica/Dark)│
│  • MPNowPlayingInfoCenter / Remote│  • SystemMediaTransportControls    │
│  • AppKit Native Settings Panel   │  • Slide-Out XAML Settings Panel   │
│  • Global Hotkeys & Native Menus  │  • Keyboard Shortcuts & Media Keys │
├───────────────────────────────────┴────────────────────────────────────┤
│                   Web Core & Injection Engine                          │
│  • WKWebView (macOS) / Microsoft.Web.WebView2 (Windows)                │
│  • theme-engine.js (автоматическая инъекция на создание документа)     │
│    ├── 10-полосный эквалайзер Web Audio API (32 Гц - 16 кГц, ±12 дБ)  │
│    ├── CORS-роутинг и динамический компрессор нормализации             │
│    ├── AdBlock (умная фильтрация баннеров без нарушения аудиоплеера)   │
│    ├── Современные стили (Минимализм, Скругление обложек, Темы)        │
│    └── Двусторонний IPC-мост метаданных и управления воспроизведением  │
├────────────────────────────────────────────────────────────────────────┤
│                     Изолированные фоновые сервисы                      │
│  • Xray-Core Service (Автономный VPN на порту 127.0.0.1:17890)        │
│    (Трафик SoundCloud изолированно проксируется; система не затрагивается)│
│  • Discord Rich Presence (Трансляция трека, автора и обложки в Discord)│
│  • UpdateManager (Фоновая тихая проверка релизов через GitHub API)     │
└────────────────────────────────────────────────────────────────────────┘
```

### 1. Единый скриптовый слой (`theme-engine.js`)
Скрипт автоматически внедряется при открытии страниц SoundCloud:
- **Перехват звука и Web Audio API**: строит цепочку из 10 фильтров `BiquadFilterNode` и `DynamicsCompressorNode`. Автоматически поддерживает активность `AudioContext` даже при сворачивании окна или смене вкладок.
- **Оформление**: применяет тёмный матовый стиль, скругляет карточки, убирает визуальный шум и промо-блоки.
- **Синхронизация состояния**: отправляет метаданные (название, автор, обложка, ссылка, позиция и длительность) в нативную оболочку по IPC-каналу.

### 2. Изолированный VPN (`XrayService`, порт `17890`)
- Включает встроенный бинарник `xray-core`.
- Запускает локальный HTTP/SOCKS5 прокси на `127.0.0.1:17890`.
- Вся маршрутизация действует **исключительно на плеер DieCloud**, не затрагивая остальные программы, мессенджеры и браузеры на компьютере.
- Поддерживает импорт конфигураций VLESS, VMess, Trojan и Shadowsocks.

### 3. Интеграция с системой (Now Playing & SMTC)
- **macOS**: полная интеграция с `MPNowPlayingInfoCenter` и `MPRemoteCommandCenter` — управление с клавиатуры Mac (F7/F8/F9) и Bluetooth-наушников.
- **Windows**: поддержка `SystemMediaTransportControls` (SMTC) и аппаратных мультимедиа-клавиш Windows — трек отображается во всплывающем системном оверлее громкости Windows 10/11.

### 4. Discord Rich Presence
- Отображает текущий трек, исполнителя, альбомную обложку и таймкод в статусе вашего профиля Discord.
- Позволяет указать собственный `Discord Client ID` прямо в интерфейсе настроек без перезапуска.

---

## ⌨️ Горячие клавиши

| Действие | macOS | Windows |
|---|---|---|
| **Воспроизведение / Пауза** | `Пробел` или `⌘P` | `Пробел` или `Ctrl + P` / `MediaPlayPause` |
| **Следующий трек** | `⌘→` | `Ctrl + →` / `MediaNext` |
| **Предыдущий трек** | `⌘←` | `Ctrl + ←` / `MediaPrevious` |
| **Перемотка на 10 сек** | `⌘⇧→` / `⌘⇧←` | `Ctrl + Shift + →` / `Ctrl + Shift + ←` |
| **Громче / Тише** | `⌥↑` / `⌥↓` | `Alt + ↑` / `Alt + ↓` / `VolumeUp` / `VolumeDown` |
| **Включить / Выключить звук** | `⌥M` | `Alt + M` / `VolumeMute` |
| **Нравится (Лайк)** | `⌘L` | `Ctrl + L` |
| **Открыть настройки** | `⌘,` | Кнопка ⚙️ в заголовке окна |
| **Закрыть панель / оверлей** | `Esc` | `Esc` |

---

## 📦 Установка

### Для macOS:
1. Загрузите актуальный `DieCloude.dmg` со [страницы релизов](https://github.com/siemens33/DieCloud-MacOS/releases/latest).
2. Перетащите `DieCloude.app` в папку **«Программы»**.
3. При первом запуске выполните `Первый запуск DieCloude.command` для автоматического снятия карантина Gatekeeper.

### Для Windows:
1. Загрузите `DieCloud.exe` (инсталлятор) или `DieCloud-Windows-Portable.zip` со [страницы релизов](https://github.com/siemens33/DieCloud-MacOS/releases/latest).
2. Распакуйте и запустите `DieCloud.exe`.
3. *(Для Windows 10)* Убедитесь, что установлен [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (в Windows 11 он встроен в ОС).

---

## 💡 Идеи для будущих версий
- [ ] **Mini-Player (PiP)**: плавающее компактное окно поверх всех окон с минималистичным управлением.
- [ ] **Adaptive Accent**: адаптивный цвет кнопок и волны, автоматически подстраивающийся под преобладающий цвет обложки текущего трека.
- [ ] **Аудио-визуализатор**: анимированный спектрограф Web Audio в шапке окна.
- [ ] **Палитра быстрых команд (`Ctrl+K` / `⌘K`)**: мгновенный поиск музыки и переключение пресетов без мыши.
- [ ] **Таймер сна**: автоматическая плавная остановка воспроизведения через заданное время.

---

<div align="center">

by siemens · 2026

</div>
