import AppKit

/// Единый источник флагов настроек, акцента и состояния громкости:
/// тумблеры панели, UserDefaults и JS-движок работают с одной моделью.
final class SettingsState {
    struct Flag {
        let key: String
        let jsKey: String
        let title: String
        let tooltip: String
        let defaultValue: Bool
        var value: Bool
        weak var control: NSControl?
    }

    private(set) var flags: [Flag]
    /// Цветовой акцент: mono / amber / blue / system.
    private(set) var accent: String
    /// Сохранённая громкость (0.0 ... 1.0) и состояние Mute.
    private(set) var volume: Double
    private(set) var isMuted: Bool
    private(set) var equalizerEnabled: Bool
    private(set) var equalizerBands: [Double]
    private(set) var equalizerNormalization: Bool
    static let defaultDiscordClientID = "1305221998971486258"
    private static let discordClientIDKey = "DiscordClientID"

    var customDiscordClientID: String {
        get {
            UserDefaults.standard.string(forKey: Self.discordClientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            let digits = newValue.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
            if digits.isEmpty || digits == Self.defaultDiscordClientID {
                UserDefaults.standard.removeObject(forKey: Self.discordClientIDKey)
            } else {
                UserDefaults.standard.set(digits, forKey: Self.discordClientIDKey)
            }
        }
    }

    var discordClientID: String {
        let custom = customDiscordClientID
        return custom.isEmpty ? Self.defaultDiscordClientID : custom
    }

    static let equalizerFrequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let equalizerPresetKeys = ["flat", "bassBoost", "electronic", "rock", "vocal", "acoustic"]
    static let equalizerPresetTitles = ["Ровно", "Басы", "Электронная", "Рок", "Вокал", "Акустика"]
    static let equalizerPresets: [String: [Double]] = [
        "flat": Array(repeating: 0, count: 10),
        "bassBoost": [6, 5, 4, 3, 1, 0, 0, 0, 1, 2],
        "electronic": [4, 3, 2, 0, -1, 2, 4, 3, 4, 5],
        "rock": [4, 2, 1, -1, -2, 1, 3, 4, 4, 3],
        "vocal": [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        "acoustic": [2, 2, 1, 2, 3, 2, 1, 2, 3, 3]
    ]
    private static let equalizerEnabledKey = "equalizerEnabled"
    private static let equalizerBandsKey = "equalizerBands"
    private static let equalizerNormalizationKey = "equalizerNormalization"
    var equalizerSliders: [NSSlider] = []
    weak var equalizerPresetControl: NSPopUpButton?

    func syncEqualizerControls() {
        for slider in equalizerSliders where equalizerBands.indices.contains(slider.tag) {
            slider.doubleValue = equalizerBands[slider.tag]
        }
        let index = Self.equalizerPresetKeys.firstIndex { Self.equalizerPresets[$0] == equalizerBands } ?? Self.equalizerPresetKeys.count - 1
        equalizerPresetControl?.selectItem(at: index)
    }

    func setEqualizer(enabled: Bool? = nil, bands: [Double]? = nil, normalization: Bool? = nil) {
        if let enabled {
            equalizerEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: Self.equalizerEnabledKey)
        }
        if let normalization {
            equalizerNormalization = normalization
            UserDefaults.standard.set(normalization, forKey: Self.equalizerNormalizationKey)
        }
        if let bands, bands.count == Self.equalizerFrequencies.count, bands.allSatisfy(\.isFinite) {
            equalizerBands = bands.map { max(-12, min(12, $0)) }
            UserDefaults.standard.set(equalizerBands, forKey: Self.equalizerBandsKey)
        }
    }

    init() {
        let initial: [(key: String, jsKey: String, title: String, tooltip: String, defaultValue: Bool)] = [
            (DefaultsKey.modernDesign, "modernDesign", "Минималистичный интерфейс DieCloude",
             "Тёмный матовый плеер, стеклянная шапка и чистые карточки", true),
            (DefaultsKey.theme, "theme", "Белый фирменный акцент",
             "Кнопки и акценты — белый вместо оранжевого", true),
            (DefaultsKey.roundedCards, "roundedCards", "Аккуратное скругление обложек",
             "Скругляет только обложки треков, альбомов и плейлистов", true),
            (DefaultsKey.artworkHover, "artworkHover", "Мягкий эффект при наведении",
             "Слегка подсвечивает только обложку, не двигая карточку", true),
            (DefaultsKey.focus, "focus", "Режим фокуса — скрыть рекомендации",
             "Убирает сайдбар, комментарии и промо", false),
            (DefaultsKey.adBlock, "adBlock", "Режим без рекламы",
             "Блокирует рекламные запросы, промо-треки и аудиопрероллы", true),
            ("discordRPC", "discordRPC", "Discord Rich Presence",
             "Показывать текущий трек в профиле Discord", false)
        ]
        flags = initial.map {
            Flag(key: $0.key, jsKey: $0.jsKey, title: $0.title, tooltip: $0.tooltip,
                 defaultValue: $0.defaultValue, value: $0.defaultValue)
        }
        let defaults = UserDefaults.standard
        let savedAccent = defaults.string(forKey: DefaultsKey.accent)
        accent = Self.accentValues.contains(savedAccent ?? "") ? savedAccent! : "mono"

        if defaults.object(forKey: DefaultsKey.playerVolume) != nil {
            volume = max(0.0, min(1.0, defaults.double(forKey: DefaultsKey.playerVolume)))
        } else {
            volume = 0.8
        }
        isMuted = defaults.bool(forKey: DefaultsKey.playerMuted)
        equalizerEnabled = defaults.object(forKey: Self.equalizerEnabledKey) == nil ? false : defaults.bool(forKey: Self.equalizerEnabledKey)
        equalizerNormalization = defaults.bool(forKey: Self.equalizerNormalizationKey)
        let savedBands = (defaults.array(forKey: Self.equalizerBandsKey) as? [NSNumber])?.map(\.doubleValue)
        if let savedBands, savedBands.count == Self.equalizerFrequencies.count, savedBands.allSatisfy(\.isFinite) {
            equalizerBands = savedBands.map { max(-12, min(12, $0)) }
        } else {
            equalizerBands = Array(repeating: 0, count: Self.equalizerFrequencies.count)
        }

        load()
    }

    var json: String {
        var dict: [String: Any] = Dictionary(uniqueKeysWithValues: flags.map { ($0.jsKey, $0.value) })
        dict["accent"] = accent
        dict["volume"] = volume
        dict["isMuted"] = isMuted
        dict["equalizerEnabled"] = equalizerEnabled
        dict["equalizerBands"] = equalizerBands
        dict["equalizerNormalization"] = equalizerNormalization
        if accent == "system" { dict["accentHex"] = NSColor.controlAccentColor.hexString }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func value(for jsKey: String) -> Bool? {
        flags.first { $0.jsKey == jsKey }?.value
    }

    func setValue(_ value: Bool, for jsKey: String) {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return }
        flags[index].value = value
        UserDefaults.standard.set(value, forKey: flags[index].key)
    }

    func setVolume(_ newVolume: Double?, muted newMuted: Bool?) {
        let defaults = UserDefaults.standard
        if let newVolume {
            let clamped = max(0.0, min(1.0, newVolume))
            volume = clamped
            defaults.set(clamped, forKey: DefaultsKey.playerVolume)
        }
        if let newMuted {
            isMuted = newMuted
            defaults.set(newMuted, forKey: DefaultsKey.playerMuted)
        }
    }

    func jsKey(of control: NSControl) -> String? {
        flags.first { $0.control === control }?.jsKey
    }

    func syncButton(for jsKey: String) {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return }
        applyValue(flags[index].value, to: flags[index].control)
    }

    private func applyValue(_ value: Bool, to control: NSControl?) {
        let state: NSControl.StateValue = value ? .on : .off
        if let sw = control as? NSSwitch {
            sw.state = state
        } else if let button = control as? NSButton {
            button.state = state
        }
    }

    /// Сброс дизайн-настроек (не трогает focus, adBlock и громкость).
    func resetDesign() {
        for index in flags.indices where flags[index].jsKey != "focus" && flags[index].jsKey != "adBlock" {
            let defVal = flags[index].defaultValue
            flags[index].value = defVal
            UserDefaults.standard.set(defVal, forKey: flags[index].key)
            applyValue(defVal, to: flags[index].control)
        }
        setAccent("mono")
        accentSegmented?.selectedSegment = 0
        accentPopup?.selectItem(at: 0)
    }

    private static let accentTitles = ["Монохром (белый)", "Янтарный", "Синий", "Как в системе"]
    private static let accentValues = ["mono", "amber", "blue", "system"]
    private(set) weak var accentPopup: NSPopUpButton?
    private(set) weak var accentSegmented: NSSegmentedControl?

    func makeAccentControl(action: Selector, target: AnyObject) -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["Белый", "Янтарь", "Синий", "macOS"],
                                     trackingMode: .selectOne,
                                     target: target,
                                     action: action)
        seg.controlSize = .small
        seg.segmentStyle = .texturedRounded
        let index = Self.accentValues.firstIndex(of: accent) ?? 0
        seg.selectedSegment = index
        accentSegmented = seg
        return seg
    }

    func makeAccentPopup(action: Selector, target: AnyObject) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.accentTitles)
        popup.selectItem(at: Self.accentValues.firstIndex(of: accent) ?? 0)
        popup.target = target
        popup.action = action
        popup.toolTip = "Цвет кнопок, шкалы времени и громкости"
        accentPopup = popup
        return popup
    }

    var accentPopupIndex: Int? {
        guard let popup = accentPopup else { return nil }
        let index = popup.indexOfSelectedItem
        return Self.accentValues.indices.contains(index) ? index : nil
    }

    func setAccent(_ value: String) {
        accent = Self.accentValues.contains(value) ? value : "mono"
        UserDefaults.standard.set(accent, forKey: DefaultsKey.accent)
    }

    func makeSwitch(for jsKey: String, action: Selector, target: AnyObject) -> NSSwitch? {
        guard let index = flags.firstIndex(where: { $0.jsKey == jsKey }) else { return nil }
        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = flags[index].value ? .on : .off
        sw.target = target
        sw.action = action
        flags[index].control = sw
        return sw
    }

    func title(for jsKey: String) -> String {
        flags.first { $0.jsKey == jsKey }?.title ?? jsKey
    }

    func subtitle(for jsKey: String) -> String {
        flags.first { $0.jsKey == jsKey }?.tooltip ?? ""
    }

    private func load() {
        let defaults = UserDefaults.standard
        for index in flags.indices {
            flags[index].value = defaults.object(forKey: flags[index].key) == nil
                ? flags[index].defaultValue
                : defaults.bool(forKey: flags[index].key)
        }
    }
}

extension NSColor {
    /// Hex системного акцента macOS для передачи в CSS.
    var hexString: String {
        guard let c = usingColorSpace(.deviceRGB) else { return "#ffffff" }
        let r = Int(round(c.redComponent * 255)), g = Int(round(c.greenComponent * 255)), b = Int(round(c.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
