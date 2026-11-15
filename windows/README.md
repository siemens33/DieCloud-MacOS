# DieCloud (Windows Edition)

<div align="center">

**Версия 5.0.0 · Windows 10 / 11 · 64-bit & ARM64**

*Высокопроизводительный нативный клиент SoundCloud для Windows без Electron.*

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white)](https://github.com/siemens33/DieCloud-MacOS)
[![.NET](https://img.shields.io/badge/.NET-8.0%20WPF-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com/)
[![WebView2](https://img.shields.io/badge/Engine-Microsoft%20WebView2-008AD7?logo=microsoftedge&logoColor=white)](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
[![Audio](https://img.shields.io/badge/Sound-10--Band%20EQ%20%2B%20CORS-FF5500)](https://soundcloud.com)
[![Discord](https://img.shields.io/badge/Discord-Rich%20Presence-5865F2?logo=discord&logoColor=white)](https://discord.com)

</div>

---

## О проекте

**DieCloud** — это быстрый, минималистичный и функциональный клиент для SoundCloud. 

В отличие от большинства веб-обёрток, DieCloud не использует ресурсоёмкий Electron. На Windows приложение построено на базе **WPF (.NET 8)** и системного движка **Microsoft WebView2 (Chromium)** с поддержкой эффектов размытия **Windows 11 Mica / Acrylic**, что обеспечивает молниеносный запуск, плавные 60/120 FPS и минимальный расход оперативной памяти.

---

## Ключевые возможности

- ⚡ **0% Electron**: Использование встроенного в систему рантайма WebView2. Потребление памяти в 3–5 раз ниже браузерной вкладки.
- 🎛️ **10-полосный студийный эквалайзер**: Аппаратная обработка Web Audio API (от 32 Гц до 16 кГц) с готовыми пресетами (*Басы, Рок, Электроника, Вокал*) и динамической нормализацией звука (Compressor).
- 🔄 **Гарантированный CORS-роутинг**: Автоматический перехват `<audio>` элементов с заголовком `anonymous` открывает эквалайзер для **100% треков** без искажений и тишины.
- 💬 **Discord Rich Presence**: Трансляция названия трека, автора, обложки и прямой ссылки в ваш статус Discord через нативные Windows Named Pipes. Работает «из коробки» (ID встроен) с возможностью указать свой Client ID.
- 🎚️ **System Media Transport Controls (SMTC)**: Полная интеграция с Windows — мультимедийные клавиши клавиатуры и гарнитур (Play/Pause, Next, Prev), оверлей громкости и управление на экране блокировки.
- 🛡️ **Изолированный VPN (Xray)**: Встроенное ядро Xray-core перенаправляет трафик через VLESS, VMess, Trojan или Shadowsocks **только внутри DieCloud**, не затрагивая браузеры и другие программы.
- 🚫 **Умный блокировщик рекламы**: Автоматически подавляет рекламные баннеры, аудиопрероллы и спонсорские карточки.
- 🎨 **Современный интерфейс в стиле Fluent / Mica**: Тёмная матовая тема, аккуратная полупрозрачная шапка, скругление обложек треков и выезжающая панель настроек.

---

## Горячие клавиши

| Действие | Сочетание клавиш |
|---|---|
| **Пауза / Воспроизведение** | `Пробел` или `Ctrl + P` |
| **Следующий трек** | `Ctrl + →` |
| **Предыдущий трек** | `Ctrl + ←` |
| **Громче / Тише** | `Alt + ↑` / `Alt + ↓` |
| **Включить / Выключить звук** | `Alt + M` |
| **Закрыть панель / оверлей** | `Esc` |

---

## Установка и запуск

1. Скачайте свежий `DieCloud-Windows.zip` или единый исполняемый файл `DieCloud.exe` со [страницы релизов](https://github.com/siemens33/DieCloud-MacOS/releases).
2. Распакуйте в удобное место и запустите `DieCloud.exe`.
3. Приложение портативно: настройки сохраняются в `%APPDATA%\DieCloud`, а кэш браузера — в `%LOCALAPPDATA%\DieCloud`.

---

## Сборка из исходников

Для сборки автономного бинарника потребуется [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

### Вариант 1: Через командную строку (Windows)
```cmd
build.bat
```

### Вариант 2: Через PowerShell
```powershell
.\build.ps1
```

Скрипт автоматически скачает бинарник Xray-core v26.3.27 и скомпилирует самодостаточный единый файл `build\DieCloud.exe` со всеми упакованными библиотеками.

---

## Архитектура проекта

```text
DieCloud-Windows/
├── src/
│   ├── App/
│   │   ├── Program.cs             # Проверка единственного экземпляра (Mutex), DPI
│   │   ├── App.xaml / .cs         # Стили и ресурсы приложения
│   │   └── MainWindow.xaml / .cs  # Безрамочное окно Mica, горячие клавиши, панель настроек
│   ├── Models/
│   │   └── SettingsState.cs       # Хранение параметров в JSON (%APPDATA%\DieCloud)
│   ├── Services/
│   │   ├── DiscordRPC.cs          # IPC по Named Pipes (\\.\pipe\discord-ipc-0)
│   │   ├── NowPlayingSMTC.cs      # Интеграция с SystemMediaTransportControls
│   │   └── XrayService.cs         # Фоновый прокси на базе встроенного Xray-core
│   └── Web/
│       └── WebViewBridge.cs       # Двусторонний мост между C# и theme-engine.js
├── resources/
│   ├── theme-engine.js            # Модульный JS-движок стилизации, эквалайзера и CORS
│   ├── adblock-rules.json         # Правила блокировки рекламы
│   └── DieCloudIcon.ico           # Мульти-размерная иконка приложения
├── build.bat                      # Скрипт сборки под Windows (CMD)
├── build.ps1                      # Скрипт сборки под Windows (PowerShell)
└── DieCloud.csproj                # Конфигурация проекта .NET 8 / WPF
```

---

<div align="center">

Разработано с ❤️ для ценителей качественного звука.  
*DieCloud Project · 2026*

</div>
