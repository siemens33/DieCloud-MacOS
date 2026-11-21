import AppKit

enum AppConfig {
    static let name = "DieCloude"
    static let version = "5.0.1"
    static let build = "51"
    static let author = "by siemens"
    static let homeURL = URL(string: "https://soundcloud.com/")!
    static let minSize = NSSize(width: 900, height: 600)
}

enum DefaultsKey {
    static let adBlock = "DieCloudeAdBlockEnabled"
    static let focus = "DieCloudeFocusModeEnabled"
    static let theme = "DieCloudeDynamicThemeEnabled"
    static let modernDesign = "DieCloudeModernDesignEnabled"
    static let glassPanels = "DieCloudeGlassPanelsEnabled"
    static let roundedCards = "DieCloudeRoundedCardsEnabled"
    static let artworkHover = "DieCloudeArtworkHoverEnabled"
    static let accent = "DieCloudeAccentTheme"
    static let playerVolume = "DieCloudePlayerVolume"
    static let playerMuted = "DieCloudePlayerMuted"
    static let darkThemeFix = "DieCloudeVisualSystemV400Build31"

    static var welcome: String {
        "DieCloudeWelcomeV" + AppConfig.version.replacingOccurrences(of: ".", with: "") + "Shown"
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
