import Foundation

/// Bridge between a GhostBrowser web session on instagram.com and the sideloaded native
/// Instagram app (the Blaze-patched IPA). It turns the web login cookies into the tokens the
/// native tooling consumes — including the mobile `Bearer IGT:2:…` Authorization header
/// reconstructed from `sessionid` + `ds_user_id` — and maps web URLs to `instagram://` deep
/// links so the native app can pick up from where the web view is.
enum InstagramBridge {

    static let queriedSchemes = ["instagram", "instagram-stories"]

    static func isInstagram(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    // MARK: Deep links (web URL -> native app)

    struct DeepLink: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let url: URL
    }

    /// Deep links offered for a given instagram.com web URL. Always includes "Open Instagram",
    /// plus a contextual target (profile / hashtag) when the path makes one obvious.
    static func deepLinks(for url: URL?) -> [DeepLink] {
        var links: [DeepLink] = []
        if let u = URL(string: "instagram://app") {
            links.append(DeepLink(title: "Open Instagram", systemImage: "arrow.up.forward.app", url: u))
        }
        guard let url = url, isInstagram(url) else { return links }

        let parts = url.path.split(separator: "/").map(String.init)
        // /explore/tags/<name>/
        if parts.count >= 3, parts[0] == "explore", parts[1] == "tags",
           let enc = parts[2].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: "instagram://tag?name=\(enc)") {
            links.append(DeepLink(title: "Open #\(parts[2]) in app", systemImage: "number", url: u))
        } else if let username = profileUsername(parts),
                  let enc = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let u = URL(string: "instagram://user?username=\(enc)") {
            links.append(DeepLink(title: "Open @\(username) in app", systemImage: "person.crop.circle", url: u))
        }
        if let u = URL(string: "instagram://camera") {
            links.append(DeepLink(title: "Open camera in app", systemImage: "camera", url: u))
        }
        return links
    }

    /// A single path segment that isn't a reserved route is treated as a profile handle.
    private static func profileUsername(_ parts: [String]) -> String? {
        guard parts.count == 1 else { return nil }
        let reserved: Set<String> = ["explore", "reels", "reel", "p", "tv", "stories", "direct",
                                     "accounts", "about", "developer", "legal", "web", "sessions"]
        let handle = parts[0]
        guard !reserved.contains(handle.lowercased()), !handle.isEmpty else { return nil }
        return handle
    }

    // MARK: Session (web cookies -> native tokens)

    struct Session {
        var sessionid = ""
        var dsUserID = ""
        var csrftoken = ""
        var mid = ""
        var igDid = ""
        var rur = ""

        var hasLogin: Bool { !sessionid.isEmpty && !dsUserID.isEmpty }

        /// Mobile API Authorization header, rebuilt from the web session. Instagram's app sends
        /// `Bearer IGT:2:<base64 json>`; the JSON carries ds_user_id + sessionid. This is the
        /// value account tools store as "Authorization".
        var authorizationHeader: String? {
            guard hasLogin else { return nil }
            // sessionid arrives URL-encoded in cookies; the app expects it decoded.
            let sid = sessionid.removingPercentEncoding ?? sessionid
            let payload: [String: Any] = [
                "ds_user_id": dsUserID,
                "sessionid": sid,
                "should_use_header_over_cookies": true
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
            return "Bearer IGT:2:" + data.base64EncodedString()
        }

        /// The "Key: value" block matching the account-tooling format ("No data available" for
        /// anything the web session can't provide, e.g. IDFA/IDFV which are native-only).
        var tokenBlock: String {
            func v(_ s: String) -> String { s.isEmpty ? "No data available" : s }
            return """
            IG-U-DS-USER-ID: \(v(dsUserID))
            IG-INTENDED-USER-ID: \(v(dsUserID))
            X-MID: \(v(mid))
            X-IG-WWW-Claim: No data available
            Authorization: \(authorizationHeader ?? "No data available")
            Device ID: \(v(igDid))
            IDFV: No data available
            IDFA: No data available
            Android ID: No data available
            csrftoken: \(v(csrftoken))
            sessionid: \(v(sessionid))
            rur: \(v(rur))
            """
        }

        /// Raw `name=value; …` cookie header for tools that want cookies rather than tokens.
        var cookieHeader: String {
            var pairs: [String] = []
            func add(_ k: String, _ v: String) { if !v.isEmpty { pairs.append("\(k)=\(v)") } }
            add("sessionid", sessionid)
            add("ds_user_id", dsUserID)
            add("csrftoken", csrftoken)
            add("mid", mid)
            add("ig_did", igDid)
            add("rur", rur)
            return pairs.joined(separator: "; ")
        }
    }

    /// Pulls the Instagram-relevant values out of the session's cookies.
    static func session(from cookies: [CookieRecord]) -> Session {
        var s = Session()
        for c in cookies where c.domain.lowercased().contains("instagram.com") {
            switch c.name.lowercased() {
            case "sessionid": s.sessionid = c.value
            case "ds_user_id": s.dsUserID = c.value
            case "csrftoken": s.csrftoken = c.value
            case "mid": s.mid = c.value
            case "ig_did": s.igDid = c.value
            case "rur": s.rur = c.value
            default: break
            }
        }
        return s
    }

    // MARK: Import (pasted block -> cookies)

    /// Parses a pasted blob into instagram.com cookies. Accepts, in order:
    ///  1. A JSON array of cookie objects (Sessions X / EditThisCookie style).
    ///  2. A `name=value; name2=value2` cookie header.
    ///  3. A "Key: value" block (sessionid / ds_user_id / csrftoken / mid / ig_did / rur, or the
    ///     IG-U-DS-USER-ID / X-MID token labels).
    static func parseCookies(_ text: String) -> [CookieRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. JSON cookie array
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let records = try? JSONDecoder().decode([CookieRecord].self, from: data) {
            return records.filter { $0.domain.lowercased().contains("instagram.com") }
        }

        var values: [String: String] = [:]
        func setKnown(_ rawKey: String, _ rawValue: String) {
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !["no data available", "-", "null", "none", "n/a"].contains(value.lowercased()) else { return }
            let key = rawKey.lowercased().filter { $0.isLetter || $0.isNumber }
            switch key {
            case "sessionid": values["sessionid"] = value
            case "dsuserid", "iguserid", "igudsuserid", "igintendeduserid": values["ds_user_id"] = value
            case "csrftoken": values["csrftoken"] = value
            case "mid", "xmid": values["mid"] = value
            case "igdid", "deviceid": values["ig_did"] = value
            case "rur": values["rur"] = value
            default: break
            }
        }

        if trimmed.contains(":") && !trimmed.contains(";") {
            // 3. Key: value block
            for line in trimmed.components(separatedBy: .newlines) {
                guard let sep = line.firstIndex(of: ":") else { continue }
                setKnown(String(line[..<sep]), String(line[line.index(after: sep)...]))
            }
        } else {
            // 2. Cookie header (also handles "Authorization: Bearer IGT..." embedded elsewhere)
            for pair in trimmed.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
                guard let eq = pair.firstIndex(of: "=") else { continue }
                setKnown(String(pair[..<eq]), String(pair[pair.index(after: eq)...]))
            }
        }

        return values.compactMap { name, value in
            CookieRecord(instagramName: name, value: value)
        }
    }
}

extension CookieRecord {
    /// Builds a domain-wide instagram.com cookie from a name/value pair.
    init(instagramName name: String, value: String) {
        self.name = name
        self.value = value
        self.domain = ".instagram.com"
        self.hostOnly = false
        self.path = "/"
        self.secure = true
        self.httpOnly = (name.lowercased() == "sessionid")
        self.session = false
        // Roughly one year out so the imported login persists.
        self.expirationDate = Date().addingTimeInterval(60 * 60 * 24 * 365).timeIntervalSince1970
        self.sameSite = "lax"
    }
}
