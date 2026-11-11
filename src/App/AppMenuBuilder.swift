import AppKit

/// Конструктор главного меню приложения с неконфликтующими шорткатами.
enum AppMenuBuilder {
    static func buildMainMenu(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()

        // 1. Меню приложения
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppConfig.name)
        appMenu.addItem(withTitle: "О программе \(AppConfig.name)", action: #selector(AppDelegate.toggleInfoPanel(_:)), keyEquivalent: "")
        let prefs = NSMenuItem(title: "Настройки…", action: #selector(AppDelegate.toggleInfoPanel(_:)), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = .command
        appMenu.addItem(prefs)
        appMenu.addItem(withTitle: "Проверить обновления…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть \(AppConfig.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Завершить \(AppConfig.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // 2. Меню Плеер
        // Space обрабатывается на уровне WebView/JS (с защитой полей ввода), а в меню назначен ⌥Space
        // чтобы не перехватывать пробел во время набора поискового запроса.
        let playerItem = NSMenuItem()
        let playerMenu = NSMenu(title: "Плеер")

        let togglePlay = NSMenuItem(title: "Пауза / Воспроизведение (Space)", action: #selector(AppDelegate.playerTogglePlay(_:)), keyEquivalent: " ")
        togglePlay.keyEquivalentModifierMask = .option
        togglePlay.target = target
        playerMenu.addItem(togglePlay)

        let nextTrack = NSMenuItem(title: "Следующий трек", action: #selector(AppDelegate.playerNextTrack(_:)), keyEquivalent: arrowKey(.rightArrow))
        nextTrack.keyEquivalentModifierMask = .command
        nextTrack.target = target
        playerMenu.addItem(nextTrack)

        let prevTrack = NSMenuItem(title: "Предыдущий трек", action: #selector(AppDelegate.playerPreviousTrack(_:)), keyEquivalent: arrowKey(.leftArrow))
        prevTrack.keyEquivalentModifierMask = .command
        prevTrack.target = target
        playerMenu.addItem(prevTrack)

        let seekFwd = NSMenuItem(title: "Перемотать вперёд (+10 сек)", action: #selector(AppDelegate.playerSeekForward(_:)), keyEquivalent: arrowKey(.rightArrow))
        seekFwd.keyEquivalentModifierMask = .option
        seekFwd.target = target
        playerMenu.addItem(seekFwd)

        let seekBack = NSMenuItem(title: "Перемотать назад (-10 сек)", action: #selector(AppDelegate.playerSeekBackward(_:)), keyEquivalent: arrowKey(.leftArrow))
        seekBack.keyEquivalentModifierMask = .option
        seekBack.target = target
        playerMenu.addItem(seekBack)

        playerMenu.addItem(.separator())

        let volUp = NSMenuItem(title: "Громче (+5%)", action: #selector(AppDelegate.playerVolumeUp(_:)), keyEquivalent: arrowKey(.upArrow))
        volUp.keyEquivalentModifierMask = .command
        volUp.target = target
        playerMenu.addItem(volUp)

        let volDown = NSMenuItem(title: "Тише (-5%)", action: #selector(AppDelegate.playerVolumeDown(_:)), keyEquivalent: arrowKey(.downArrow))
        volDown.keyEquivalentModifierMask = .command
        volDown.target = target
        playerMenu.addItem(volDown)

        let muteItem = NSMenuItem(title: "Без звука (Mute)", action: #selector(AppDelegate.playerToggleMute(_:)), keyEquivalent: "m")
        muteItem.keyEquivalentModifierMask = [.command, .option]
        muteItem.target = target
        playerMenu.addItem(muteItem)

        playerMenu.addItem(.separator())

        let likeItem = NSMenuItem(title: "Нравится (Like)", action: #selector(AppDelegate.playerToggleLike(_:)), keyEquivalent: "l")
        likeItem.keyEquivalentModifierMask = .command
        likeItem.target = target
        playerMenu.addItem(likeItem)

        playerItem.submenu = playerMenu
        mainMenu.addItem(playerItem)

        // 3. Меню Правка
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // 4. Меню Вид
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Вид")
        viewMenu.addItem(withTitle: "Назад", action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Вперёд", action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Обновить", action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Домой", action: #selector(AppDelegate.loadHome(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(AppDelegate.toggleFocusFromMenu(_:)), keyEquivalent: "")
        let adBlockItem = NSMenuItem(title: "Режим без рекламы", action: #selector(AppDelegate.toggleAdBlockFromMenu(_:)), keyEquivalent: "a")
        adBlockItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(adBlockItem)
        viewMenu.addItem(withTitle: "Настройки (⌘,)", action: #selector(AppDelegate.toggleInfoPanel(_:)), keyEquivalent: "")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        return mainMenu
    }

    private static func arrowKey(_ key: NSEvent.SpecialKey) -> String {
        guard let scalar = Unicode.Scalar(key.rawValue) else { return "" }
        return String(Character(scalar))
    }
}
