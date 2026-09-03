import Foundation

/// Cookie in the Electron/Chromium JSON shape used by Sessions X exports, so files
/// move between the desktop app and this browser without conversion.
struct CookieRecord: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var hostOnly: Bool?
    var path: String?
    var secure: Bool?
    var httpOnly: Bool?
    var session: Bool?
    var expirationDate: Double?
    /// 'unspecified' | 'no_restriction' | 'lax' | 'strict'
    var sameSite: String?

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        hostOnly = !cookie.domain.hasPrefix(".")
        path = cookie.path
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        session = cookie.expiresDate == nil
        expirationDate = cookie.expiresDate?.timeIntervalSince1970
        if let policy = cookie.sameSitePolicy, policy == .sameSiteLax {
            sameSite = "lax"
        } else if let policy = cookie.sameSitePolicy, policy == .sameSiteStrict {
            sameSite = "strict"
        } else {
            sameSite = cookie.isSecure ? "no_restriction" : "unspecified"
        }
    }

    func makeHTTPCookie() -> HTTPCookie? {
        var domainValue = domain
        if hostOnly == true, domainValue.hasPrefix(".") {
            domainValue.removeFirst()
        } else if hostOnly == false, !domainValue.hasPrefix(".") {
            domainValue = "." + domainValue
        }
        guard !domainValue.isEmpty, !name.isEmpty else { return nil }

        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domainValue,
            .path: (path?.isEmpty == false ? path! : "/")
        ]
        if secure == true { props[.secure] = "TRUE" }
        if httpOnly == true { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let exp = expirationDate, exp > 0 { props[.expires] = Date(timeIntervalSince1970: exp) }
        switch sameSite {
        case "lax": props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
        case "strict": props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
        default: break
        }
        return HTTPCookie(properties: props)
    }
}

/// An isolated browsing identity: fingerprint + cookies + proxy + last URL.
struct BrowserSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var uid: String = BrowserSession.makeUID()
    var name: String
    var profile: FingerprintProfile
    var proxy: ProxyConfig?
    var cookies: [CookieRecord] = []
    var lastURL: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Optional so sessions saved before this field existed still decode.
    var tokens: DeviceTokens?

    var deviceTokens: DeviceTokens {
        get { tokens ?? DeviceTokens() }
        set { tokens = newValue }
    }

    var deviceLabel: String { profile.deviceLabel }
    var proxyLabel: String { proxy?.label ?? "direct" }

    /// Sessions X `genUid()` shape.
    static func makeUID() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt64.random(in: 0...UInt64.max), radix: 36).prefix(8)
        return "c\(t)\(r)"
    }
}

// MARK: - Sessions X v3 payload (import / export)

/// Fingerprint object as produced by Sessions X `generateFingerprint`.
struct SessionsXFingerprint: Codable {
    struct Screen: Codable { var width: Int; var height: Int; var availWidth: Int?; var availHeight: Int? }
    struct WebGL: Codable { var vendor: String; var renderer: String }

    var device: String?
    var deviceName: String?
    var userAgent: String
    var platform: String?
    var vendor: String?
    var language: String?
    var hardwareConcurrency: Int?
    var deviceMemory: Int?
    var devicePixelRatio: Double?
    var screen: Screen?
    var webgl: WebGL?
    var maxTouchPoints: Int?
    var androidModel: String?
    var androidVersion: String?
    var seed: Int?

    init(profile p: FingerprintProfile) {
        switch p.family {
        case .ios: device = "ios"
        case .android: device = "android"
        case .desktop: device = "desktop"
        }
        deviceName = p.deviceName.isEmpty ? nil : p.deviceName
        userAgent = p.userAgent
        platform = p.platform
        vendor = p.vendor
        language = p.language
        hardwareConcurrency = p.hardwareConcurrency
        deviceMemory = p.deviceMemory ?? 8
        devicePixelRatio = p.devicePixelRatio
        screen = Screen(width: p.screenWidth, height: p.screenHeight, availWidth: p.availWidth, availHeight: p.availHeight)
        webgl = WebGL(vendor: p.webglVendor, renderer: p.webglRenderer)
        maxTouchPoints = p.maxTouchPoints
        if p.family == .android {
            androidModel = p.deviceName
            if let r = p.userAgent.range(of: #"Android ([\d.]+)"#, options: .regularExpression) {
                androidVersion = String(p.userAgent[r].dropFirst("Android ".count))
            }
        }
        seed = Int(p.seed & 0x7fff_ffff)
    }

    func toProfile() -> FingerprintProfile {
        let dev = (device ?? "ios").lowercased()
        let ua = userAgent
        let isIOS = dev == "ios" || ua.contains("iPhone")
        let isAndroid = dev == "android" || ua.contains("Android")
        let isFirefox = ua.contains("Firefox/")
        let kind: BrowserKind = isIOS || (ua.contains("Safari") && !ua.contains("Chrome")) ? .safari : (isFirefox ? .firefox : .chrome)
        let lang = language ?? "en-US"
        let w = screen?.width ?? (isIOS ? 393 : 1920)
        let h = screen?.height ?? (isIOS ? 852 : 1080)
        var p = FingerprintProfile(
            name: deviceName ?? (isIOS ? "iPhone" : isAndroid ? "Android" : "Desktop"),
            kind: kind,
            deviceName: deviceName ?? androidModel ?? "",
            userAgent: ua,
            platform: platform ?? (isIOS ? "iPhone" : isAndroid ? "Linux armv81" : "Win32"),
            vendor: vendor ?? (kind == .safari ? "Apple Computer, Inc." : kind == .chrome ? "Google Inc." : ""),
            language: lang,
            languages: lang == "en" ? ["en"] : [lang, "en"],
            hardwareConcurrency: hardwareConcurrency ?? (isIOS ? 6 : 8),
            deviceMemory: kind == .chrome ? (deviceMemory ?? 8) : nil,
            maxTouchPoints: maxTouchPoints ?? ((isIOS || isAndroid) ? 5 : 0),
            screenWidth: w, screenHeight: h,
            availWidth: screen?.availWidth ?? w, availHeight: screen?.availHeight ?? h,
            devicePixelRatio: devicePixelRatio ?? (isIOS ? 3 : 1),
            timeZone: TimeZone.current.identifier,
            webglVendor: webgl?.vendor ?? (isIOS ? "Apple Inc." : "Google Inc. (NVIDIA)"),
            webglRenderer: webgl?.renderer ?? (isIOS ? "Apple GPU" : "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 Direct3D11 vs_5_0 ps_5_0, D3D11)")
        )
        // Sessions X never spoofs the zone (it relies on the proxy's locale); keep the device zone.
        p.spoofTimezone = false
        if let s = seed, s > 0 { p.seed = UInt32(truncatingIfNeeded: s) }
        return p
    }
}

struct SessionsXPayload: Codable {
    struct Spoof: Codable {
        var device: String?
        var deviceLabel: String?
        var fingerprint: SessionsXFingerprint?
    }
    struct Ghost: Codable {
        var profile: FingerprintProfile
        var proxy: ProxyConfig?
        var tokens: DeviceTokens?
    }

    var version: Int?
    var uid: String?
    var exportedAt: String?
    var name: String?
    var label: String?
    var url: String?
    var proxy: String?
    var spoof: Spoof?
    var cookies: [CookieRecord]?
    var twofaSecret: String?
    /// Device / account tokens in "Key: value" block form (human readable, tool friendly).
    var deviceTokens: String?
    /// Lossless extra for round-tripping GhostBrowser profiles (ignored by Sessions X).
    var ghost: Ghost?

    init(session s: BrowserSession) {
        version = 3
        uid = s.uid
        exportedAt = ISO8601DateFormatter().string(from: Date())
        name = s.name
        label = s.deviceLabel
        url = s.lastURL
        proxy = s.proxy?.text
        spoof = Spoof(device: SessionsXFingerprint(profile: s.profile).device, deviceLabel: s.deviceLabel,
                      fingerprint: SessionsXFingerprint(profile: s.profile))
        cookies = s.cookies
        twofaSecret = ""
        deviceTokens = s.tokens.flatMap { $0.isEmpty ? nil : $0.textBlock }
        ghost = Ghost(profile: s.profile, proxy: s.proxy, tokens: s.tokens)
    }

    func toSession() -> BrowserSession {
        let profile: FingerprintProfile
        if let g = ghost {
            profile = g.profile
        } else if let fp = spoof?.fingerprint {
            profile = fp.toProfile()
        } else {
            profile = FingerprintProfile.random(family: .ios)
        }
        var s = BrowserSession(name: name ?? label ?? profile.deviceLabel, profile: profile)
        if let uid = uid, !uid.isEmpty { s.uid = uid }
        s.proxy = ghost?.proxy ?? proxy.flatMap { ProxyConfig.parse($0) }
        s.cookies = cookies ?? []
        s.lastURL = url ?? ""
        if let t = ghost?.tokens {
            s.tokens = t
        } else if let block = deviceTokens, !block.isEmpty {
            s.tokens = DeviceTokens.parse(block)
        }
        return s
    }

    /// Accepts a full payload or a bare cookies array (Sessions X import does the same).
    static func decode(_ data: Data) throws -> SessionsXPayload {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(SessionsXPayload.self, from: data),
           payload.cookies != nil || payload.spoof != nil || payload.ghost != nil {
            return payload
        }
        let cookies = try decoder.decode([CookieRecord].self, from: data)
        var p = SessionsXPayload(session: BrowserSession(name: "Imported cookies", profile: FingerprintProfile.random(family: .ios)))
        p.cookies = cookies
        p.ghost = nil
        p.spoof = nil
        p.uid = nil
        return p
    }
}
