import WebKit

/// DieCloude 4.0.2 — трёхуровневый noAds V9:
/// 1. Network: WKContentRuleList (adblock-rules.json, V9)
/// 2. Cosmetic CSS + DOM removal: theme-engine.js (selectors.ads)
/// 3. Audio: пропуск/мут first-party прероллов в JS
enum AdBlockService {
    static let ruleListIdentifier = "DieCloudeAdBlockRulesV9"

    /// Загружает JSON-правила из бандла (Resources/adblock-rules.json),
    /// fallback — минимальный встроенный набор чтобы noAds не молчал.
    static func encodedRules() -> String {
        if let url = Bundle.main.url(forResource: "adblock-rules", withExtension: "json"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // Fallback без дизъюнкций (WebKit их не поддерживает — из-за этого молчал V6)
        return #"[{"trigger":{"url-filter":".*doubleclick\\.net.*","load-type":["third-party"],"resource-type":["document","image","style-sheet","script","font","media","raw","popup"]},"action":{"type":"block"}},{"trigger":{"url-filter":".*googlesyndication\\.com.*","load-type":["third-party"],"resource-type":["document","image","style-sheet","script","font","media","raw","popup"]},"action":{"type":"block"}},{"trigger":{"url-filter":".*soundcloud\\.com.*upsell.*","resource-type":["script","media","raw","image"]},"action":{"type":"block"}}]"#
    }

    static func compile(completion: @escaping (WKContentRuleList?) -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListIdentifier,
            encodedContentRuleList: encodedRules()
        ) { list, error in
            if let error {
                NSLog("DieCloude ad-block V8 error: \(error)")
                completion(nil)
                return
            }
            completion(list)
        }
    }
}
