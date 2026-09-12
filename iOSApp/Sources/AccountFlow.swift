import Foundation

/// "Make a new account" helpers: each attempt is a brand-new session (fresh identity, empty cookie
/// jar) that opens straight on the signup page, plus detection of Google's send-to-verify dead end.
enum AccountFlow {
    /// Google's web signup entry point. On a desktop-class identity Google asks for a phone number
    /// and *texts a code to it* (MT) — the flow a rented number can complete. On phone identities it
    /// often falls back to "send an SMS from this device" (MO), which receive-only numbers can't.
    static let gmailSignupURL = "https://accounts.google.com/signup/v2/createaccount?flowName=GlifWebSignIn&flowEntry=SignUp&hl=en"

    /// Recommended device family for Gmail: desktop Chrome gets the type-a-number flow.
    static let recommendedFamily: DeviceFamily = .desktop

    /// A fresh session for one signup attempt. The persona is pinned to the USA (language + time
    /// zone) so it agrees with the USA numbers the Heavenzy SMS panel rents.
    static func makeSession(family: DeviceFamily, index: Int) -> BrowserSession {
        var p = FingerprintProfile.random(family: family)
        if let us = DevicePools.locales.filter({ $0.lang == "en-US" }).randomElement() {
            p.language = us.lang
            p.languages = us.langs
            p.timeZone = us.tz
        }
        p.name = "Gmail #\(index) · \(p.deviceLabel)"
        var s = BrowserSession(name: "Gmail #\(index)", profile: p)
        s.lastURL = gmailSignupURL
        return s
    }

    static func isAccountSession(_ s: BrowserSession) -> Bool { s.name.hasPrefix("Gmail #") }
}

/// A parsed `sms:` link (what Google's "Send SMS" button opens). Recipient is the short code, the
/// body carries a one-time token the *device* is supposed to send — mobile-originated verification.
struct SMSIntent: Identifiable, Equatable {
    let id = UUID()
    let recipient: String
    let body: String

    /// The bracketed token inside the body, e.g. "(0b6c05WV3pr3)" → "0b6c05WV3pr3".
    var token: String? {
        guard let r = body.range(of: #"\(([A-Za-z0-9]+)\)"#, options: .regularExpression) else { return nil }
        return String(body[r].dropFirst().dropLast())
    }

    /// Rebuild the link so it can still be handed to Messages on request.
    var url: URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let b = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sms:\(recipient)&body=\(b)")
    }

    /// Accepts `sms:110&body=…`, `sms:110?body=…`, `sms://110;body=…`.
    static func parse(_ url: URL) -> SMSIntent? {
        guard url.scheme?.lowercased() == "sms" else { return nil }
        var rest = Substring(url.absoluteString.dropFirst("sms:".count))
        if rest.hasPrefix("//") { rest = rest.dropFirst(2) }
        var recipient = String(rest)
        var query = Substring("")
        if let idx = rest.firstIndex(where: { "?&;".contains($0) }) {
            recipient = String(rest[..<idx])
            query = rest[rest.index(after: idx)...]
        }
        var body = ""
        for pair in query.split(whereSeparator: { "&;".contains($0) }) {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, kv[0].lowercased() == "body" else { continue }
            let raw = String(kv[1]).replacingOccurrences(of: "+", with: " ")
            body = raw.removingPercentEncoding ?? raw
        }
        return SMSIntent(recipient: recipient.removingPercentEncoding ?? recipient, body: body)
    }
}
