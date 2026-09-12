import Foundation

/// Talks to the Heavenzy tweak that is injected into this app. The tweak reads its settings from
/// this app's own container (Library/Preferences/com.heavenzy.plist), so the browser can hand it
/// hints by merging keys into that file:
///
/// - `smsBrand`: which service the SMS panel should rent a number for. Heavenzy normally derives
///   it from the host app's name ("ghostbrowser" → nothing useful); here it follows the site being
///   visited instead (accounts.google.com → "google").
enum HeavenzyBridge {
    private static var prefsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/com.heavenzy.plist")
    }

    /// Host substring → brand key understood by Heavenzy's provider maps (GrizzlySMS/DiddySMS).
    private static let hostBrands: [(needle: String, brand: String)] = [
        ("google", "google"), ("gmail", "google"), ("youtube", "google"),
        ("instagram", "instagram"), ("threads.net", "instagram"),
        ("facebook", "facebook"), ("fb.com", "facebook"),
        ("tiktok", "tiktok"), ("discord", "discord"), ("telegram", "telegram"), ("whatsapp", "whatsapp"),
        ("twitter", "twitter"), ("x.com", "twitter"), ("snapchat", "snapchat"), ("reddit", "reddit"),
        ("microsoft", "microsoft"), ("live.com", "microsoft"), ("outlook", "microsoft"), ("hotmail", "microsoft"),
        ("yahoo", "yahoo"), ("amazon", "amazon"), ("apple.com", "apple"), ("icloud", "apple"),
        ("tinder", "tinder"), ("bumble", "bumble"), ("signal", "signal"), ("linkedin", "linkedin"),
        ("pinterest", "pinterest"), ("twitch", "twitch"), ("paypal", "paypal"), ("netflix", "netflix")
    ]

    static func brand(forHost host: String?) -> String? {
        guard let h = host?.lowercased() else { return nil }
        return hostBrands.first { h.contains($0.needle) }?.brand
    }

    private static let queue = DispatchQueue(label: "ghost.heavenzy-bridge", qos: .utility)
    private static var lastBrand: String? = "\u{0}"   // sentinel so the first sync always writes

    /// Point the SMS panel at the service that matches `url`'s host (cleared when unknown).
    static func syncSMSBrand(for url: URL?) {
        let brand = brand(forHost: url?.host)
        guard brand != lastBrand else { return }
        lastBrand = brand
        queue.async {
            var dict = NSDictionary(contentsOf: prefsURL) as? [String: Any] ?? [:]
            if let b = brand { dict["smsBrand"] = b } else { dict.removeValue(forKey: "smsBrand") }
            try? FileManager.default.createDirectory(at: prefsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            (dict as NSDictionary).write(to: prefsURL, atomically: true)
        }
    }
}
