import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable {
    case safari
    case chrome
    case firefox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safari: return "Safari (WebKit)"
        case .chrome: return "Chrome (Blink)"
        case .firefox: return "Firefox (Gecko)"
        }
    }
}

enum WebRTCPolicy: String, Codable, CaseIterable, Identifiable {
    case allow
    case maskLocal
    case block

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return "Allow"
        case .maskLocal: return "Hide LAN candidates"
        case .block: return "Block WebRTC"
        }
    }
}

/// Device family used by the per-type randomizers (mirrors Sessions X `generateFingerprint(device)`).
enum DeviceFamily: String, Codable, CaseIterable, Identifiable {
    case ios
    case android
    case desktop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ios: return "iPhone · Safari"
        case .android: return "Android · Chrome"
        case .desktop: return "Desktop · Chrome"
        }
    }
}

/// Everything the injected script needs to present a consistent fake identity.
struct FingerprintProfile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var kind: BrowserKind
    /// Human device model (e.g. "iPhone 15 Pro"), used for labels and Android UA/model hints.
    var deviceName: String = ""

    // Feature toggles
    var spoofNavigator: Bool = true
    var spoofScreen: Bool = true
    var spoofTimezone: Bool = true
    var spoofWebGL: Bool = true
    var spoofCanvas: Bool = true
    var spoofAudio: Bool = true
    /// Rewrite Accept-Language / Sec-CH-UA on top-level navigations to match the identity.
    var spoofHeaders: Bool = true
    /// Re-encode images picked into <input type=file> with fresh noise/geometry/EXIF.
    var uploadSpoof: Bool = true
    var webrtcPolicy: WebRTCPolicy = .maskLocal

    // navigator.*
    var userAgent: String
    var platform: String
    var vendor: String
    var language: String
    var languages: [String]
    var hardwareConcurrency: Int
    var deviceMemory: Int?
    var maxTouchPoints: Int
    var doNotTrack: Bool = false

    // screen.*
    var screenWidth: Int
    var screenHeight: Int
    var availWidth: Int
    var availHeight: Int
    var colorDepth: Int = 24
    var devicePixelRatio: Double

    // Misc
    var timeZone: String
    var webglVendor: String
    var webglRenderer: String
    var seed: UInt32 = UInt32.random(in: 1...UInt32.max)

    // MARK: Memberwise init (kept explicit so Codable customisation below doesn't remove it)

    init(id: UUID = UUID(), name: String, kind: BrowserKind, deviceName: String = "",
         userAgent: String, platform: String, vendor: String, language: String, languages: [String],
         hardwareConcurrency: Int, deviceMemory: Int?, maxTouchPoints: Int,
         screenWidth: Int, screenHeight: Int, availWidth: Int, availHeight: Int, colorDepth: Int = 24,
         devicePixelRatio: Double, timeZone: String, webglVendor: String, webglRenderer: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.deviceName = deviceName
        self.userAgent = userAgent
        self.platform = platform
        self.vendor = vendor
        self.language = language
        self.languages = languages
        self.hardwareConcurrency = hardwareConcurrency
        self.deviceMemory = deviceMemory
        self.maxTouchPoints = maxTouchPoints
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.availWidth = availWidth
        self.availHeight = availHeight
        self.colorDepth = colorDepth
        self.devicePixelRatio = devicePixelRatio
        self.timeZone = timeZone
        self.webglVendor = webglVendor
        self.webglRenderer = webglRenderer
    }

    // MARK: Codable (tolerant of older saved profiles that lack newer keys)

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, deviceName
        case spoofNavigator, spoofScreen, spoofTimezone, spoofWebGL, spoofCanvas, spoofAudio, spoofHeaders, uploadSpoof, webrtcPolicy
        case userAgent, platform, vendor, language, languages, hardwareConcurrency, deviceMemory, maxTouchPoints, doNotTrack
        case screenWidth, screenHeight, availWidth, availHeight, colorDepth, devicePixelRatio
        case timeZone, webglVendor, webglRenderer, seed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(BrowserKind.self, forKey: .kind) ?? .safari
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        spoofNavigator = try c.decodeIfPresent(Bool.self, forKey: .spoofNavigator) ?? true
        spoofScreen = try c.decodeIfPresent(Bool.self, forKey: .spoofScreen) ?? true
        spoofTimezone = try c.decodeIfPresent(Bool.self, forKey: .spoofTimezone) ?? true
        spoofWebGL = try c.decodeIfPresent(Bool.self, forKey: .spoofWebGL) ?? true
        spoofCanvas = try c.decodeIfPresent(Bool.self, forKey: .spoofCanvas) ?? true
        spoofAudio = try c.decodeIfPresent(Bool.self, forKey: .spoofAudio) ?? true
        spoofHeaders = try c.decodeIfPresent(Bool.self, forKey: .spoofHeaders) ?? true
        uploadSpoof = try c.decodeIfPresent(Bool.self, forKey: .uploadSpoof) ?? true
        webrtcPolicy = try c.decodeIfPresent(WebRTCPolicy.self, forKey: .webrtcPolicy) ?? .maskLocal
        userAgent = try c.decode(String.self, forKey: .userAgent)
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "iPhone"
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? "Apple Computer, Inc."
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en-US"
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? [language, "en"]
        hardwareConcurrency = try c.decodeIfPresent(Int.self, forKey: .hardwareConcurrency) ?? 4
        deviceMemory = try c.decodeIfPresent(Int.self, forKey: .deviceMemory)
        maxTouchPoints = try c.decodeIfPresent(Int.self, forKey: .maxTouchPoints) ?? 5
        doNotTrack = try c.decodeIfPresent(Bool.self, forKey: .doNotTrack) ?? false
        screenWidth = try c.decodeIfPresent(Int.self, forKey: .screenWidth) ?? 393
        screenHeight = try c.decodeIfPresent(Int.self, forKey: .screenHeight) ?? 852
        availWidth = try c.decodeIfPresent(Int.self, forKey: .availWidth) ?? screenWidth
        availHeight = try c.decodeIfPresent(Int.self, forKey: .availHeight) ?? screenHeight
        colorDepth = try c.decodeIfPresent(Int.self, forKey: .colorDepth) ?? 24
        devicePixelRatio = try c.decodeIfPresent(Double.self, forKey: .devicePixelRatio) ?? 3
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? TimeZone.current.identifier
        webglVendor = try c.decodeIfPresent(String.self, forKey: .webglVendor) ?? "Apple Inc."
        webglRenderer = try c.decodeIfPresent(String.self, forKey: .webglRenderer) ?? "Apple GPU"
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? UInt32.random(in: 1...UInt32.max)
    }

    // MARK: Derived values

    var appVersion: String {
        userAgent.hasPrefix("Mozilla/") ? String(userAgent.dropFirst("Mozilla/".count)) : userAgent
    }

    var productSub: String { kind == .firefox ? "20100101" : "20030107" }

    var oscpu: String? {
        guard kind == .firefox,
              let open = userAgent.firstIndex(of: "("),
              let close = userAgent.firstIndex(of: ")"),
              open < close else { return nil }
        let inner = userAgent[userAgent.index(after: open)..<close]
        let parts = inner.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let filtered = parts.filter { !$0.hasPrefix("rv:") && $0 != "X11" }
        return filtered.joined(separator: "; ")
    }

    /// Desktop-class identities get WebKit's desktop layout viewport (like "Request Desktop Site").
    var isDesktopLike: Bool {
        !userAgent.contains("Mobile") && !userAgent.contains("iPhone")
    }

    var isMobileUA: Bool { userAgent.contains("Mobile") || userAgent.contains("Android") }

    var family: DeviceFamily {
        if userAgent.contains("iPhone") || userAgent.contains("iPad") { return .ios }
        if userAgent.contains("Android") { return .android }
        return .desktop
    }

    /// Sessions X style label: "iPhone · iPhone 15 Pro", "Android · Pixel 7", "Desktop · Chrome".
    var deviceLabel: String {
        switch family {
        case .ios: return deviceName.isEmpty ? "iPhone · Safari" : "iPhone · \(deviceName)"
        case .android: return deviceName.isEmpty ? "Android · Chrome" : "Android · \(deviceName)"
        case .desktop:
            let engine: String
            switch kind {
            case .chrome: engine = "Chrome"
            case .firefox: engine = "Firefox"
            case .safari: engine = "Safari"
            }
            return deviceName.isEmpty ? "Desktop · \(engine)" : "\(deviceName) · \(engine)"
        }
    }

    var summary: String {
        "\(screenWidth)x\(screenHeight) @\(devicePixelRatio.cleanString)x • \(hardwareConcurrency) cores • \(timeZone)"
    }

    /// Chrome major/full version parsed from the UA (nil for non-Chrome identities).
    var chromeVersion: (major: String, full: String)? {
        guard let range = userAgent.range(of: #"Chrome/([\d.]+)"#, options: .regularExpression) else { return nil }
        let full = String(userAgent[range].dropFirst("Chrome/".count))
        let major = full.split(separator: ".").first.map(String.init) ?? full
        return (major, full)
    }

    /// Request headers that should accompany this identity (Sessions X `buildSpoofHeaders`).
    var spoofedRequestHeaders: [String: String] {
        var h: [String: String] = [:]
        var accept = language
        let extras = languages.filter { $0 != language }
        var q = 0.9
        for l in extras.prefix(4) {
            accept += ",\(l);q=\(String(format: "%.1f", q))"
            q = max(0.1, q - 0.1)
        }
        if extras.isEmpty { accept += ",en;q=0.9" }
        h["Accept-Language"] = accept
        if kind == .chrome, let v = chromeVersion {
            h["Sec-CH-UA"] = "\"Chromium\";v=\"\(v.major)\", \"Not)A;Brand\";v=\"8\", \"Google Chrome\";v=\"\(v.major)\""
            h["Sec-CH-UA-Mobile"] = isMobileUA ? "?1" : "?0"
            let platformHint: String
            if userAgent.contains("Android") { platformHint = "Android" }
            else if userAgent.contains("Windows") { platformHint = "Windows" }
            else if userAgent.contains("Mac") { platformHint = "macOS" }
            else if userAgent.contains("CrOS") { platformHint = "Chrome OS" }
            else { platformHint = "Linux" }
            h["Sec-CH-UA-Platform"] = "\"\(platformHint)\""
        }
        return h
    }

    mutating func rerollSeed() {
        seed = UInt32.random(in: 1...UInt32.max)
    }
}

extension Double {
    var cleanString: String {
        self == floor(self) ? String(Int(self)) : String(format: "%.3g", self)
    }
}

// MARK: - Device pools (ported from Sessions X spoof.js)

struct IOSDeviceSpec {
    let name: String
    let ios: String      // "17_5"
    let safari: String   // "17.5"
    let width: Int
    let height: Int
    let dpr: Double
    let cores: Int
}

struct AndroidDeviceSpec {
    let name: String
    let android: String
    let width: Int
    let height: Int
    let dpr: Double
    let memory: Int
    let glVendor: String
    let glRenderer: String
}

enum DevicePools {
    /// Broad pool of recent iPhones. `cores` is bound to the model — a real device always reports
    /// the same count — rather than randomised per session.
    static let iphones: [IOSDeviceSpec] = [
        IOSDeviceSpec(name: "iPhone 16 Pro Max", ios: "18_6", safari: "18.6", width: 440, height: 956, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 16 Pro", ios: "18_6", safari: "18.6", width: 402, height: 874, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 16 Plus", ios: "18_5", safari: "18.5", width: 430, height: 932, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 16", ios: "18_5", safari: "18.5", width: 393, height: 852, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 15 Pro Max", ios: "18_4", safari: "18.4", width: 430, height: 932, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 15 Pro", ios: "17_5", safari: "17.5", width: 393, height: 852, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 15 Plus", ios: "17_4", safari: "17.4", width: 430, height: 932, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 15", ios: "18_3", safari: "18.3", width: 393, height: 852, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 14 Pro Max", ios: "17_3", safari: "17.3", width: 430, height: 932, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 14 Pro", ios: "16_6", safari: "16.6", width: 393, height: 852, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 14 Plus", ios: "16_6", safari: "16.6", width: 428, height: 926, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 14", ios: "17_4", safari: "17.4", width: 390, height: 844, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 13 Pro Max", ios: "16_6", safari: "16.6", width: 428, height: 926, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 13 Pro", ios: "17_5", safari: "17.5", width: 390, height: 844, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 13", ios: "17_5", safari: "17.5", width: 390, height: 844, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 13 mini", ios: "17_2", safari: "17.2", width: 375, height: 812, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 12 Pro", ios: "16_7", safari: "16.6", width: 390, height: 844, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 12", ios: "16_7", safari: "16.6", width: 390, height: 844, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 12 mini", ios: "16_7", safari: "16.6", width: 375, height: 812, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone SE (3rd generation)", ios: "17_5", safari: "17.5", width: 375, height: 667, dpr: 2, cores: 6),
        IOSDeviceSpec(name: "iPhone 11 Pro Max", ios: "16_7", safari: "16.6", width: 414, height: 896, dpr: 3, cores: 6),
        IOSDeviceSpec(name: "iPhone 11", ios: "16_7", safari: "16.6", width: 414, height: 896, dpr: 2, cores: 6),
        IOSDeviceSpec(name: "iPhone XR", ios: "16_7", safari: "16.6", width: 414, height: 896, dpr: 2, cores: 4)
    ]

    static let androids: [AndroidDeviceSpec] = [
        AndroidDeviceSpec(name: "Pixel 8", android: "14", width: 412, height: 915, dpr: 2.625, memory: 8,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G715-Immortalis MC10, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "Pixel 8 Pro", android: "14", width: 448, height: 998, dpr: 2.8125, memory: 8,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G715-Immortalis MC10, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "Pixel 7", android: "14", width: 412, height: 915, dpr: 2.625, memory: 8,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G710, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "Pixel 6", android: "13", width: 412, height: 915, dpr: 2.625, memory: 8,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G78, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "SM-S928B", android: "14", width: 384, height: 832, dpr: 3.75, memory: 12,
                          glVendor: "Google Inc. (Qualcomm)", glRenderer: "ANGLE (Qualcomm, Adreno (TM) 750, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "SM-S921B", android: "14", width: 360, height: 780, dpr: 3, memory: 8,
                          glVendor: "Google Inc. (Samsung Electronics Co., Ltd.)", glRenderer: "ANGLE (Samsung Electronics Co., Ltd., Samsung Xclipse 940, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "SM-S911B", android: "14", width: 360, height: 780, dpr: 3, memory: 8,
                          glVendor: "Google Inc. (Qualcomm)", glRenderer: "ANGLE (Qualcomm, Adreno (TM) 740, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "SM-A546B", android: "14", width: 360, height: 800, dpr: 3, memory: 6,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G68 MC4, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "SM-A536B", android: "13", width: 360, height: 800, dpr: 3, memory: 6,
                          glVendor: "Google Inc. (ARM)", glRenderer: "ANGLE (ARM, Mali-G68, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "2312DRA50G", android: "14", width: 393, height: 873, dpr: 2.75, memory: 12,
                          glVendor: "Google Inc. (Qualcomm)", glRenderer: "ANGLE (Qualcomm, Adreno (TM) 750, OpenGL ES 3.2)"),
        AndroidDeviceSpec(name: "CPH2609", android: "14", width: 360, height: 804, dpr: 3, memory: 8,
                          glVendor: "Google Inc. (Qualcomm)", glRenderer: "ANGLE (Qualcomm, Adreno (TM) 720, OpenGL ES 3.2)")
    ]

    static let chromeMajors = ["136", "137", "138", "139"]

    struct DesktopScreen { let w: Int; let h: Int; let dpr: Double; let taskbar: Int }
    static let desktopScreens: [DesktopScreen] = [
        DesktopScreen(w: 1920, h: 1080, dpr: 1, taskbar: 40), DesktopScreen(w: 1920, h: 1080, dpr: 1.25, taskbar: 48),
        DesktopScreen(w: 2560, h: 1440, dpr: 1, taskbar: 40), DesktopScreen(w: 1536, h: 864, dpr: 1.25, taskbar: 48),
        DesktopScreen(w: 1366, h: 768, dpr: 1, taskbar: 40), DesktopScreen(w: 1680, h: 1050, dpr: 1, taskbar: 40),
        DesktopScreen(w: 3840, h: 2160, dpr: 2, taskbar: 48), DesktopScreen(w: 1440, h: 900, dpr: 2, taskbar: 25),
        DesktopScreen(w: 1728, h: 1117, dpr: 2, taskbar: 38), DesktopScreen(w: 1512, h: 982, dpr: 2, taskbar: 38)
    ]

    static let chromeDesktopGPUs: [(String, String)] = [
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002503) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 4070 (0x00002786) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 3050 (0x00002507) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) UHD Graphics 770 (0x00004680) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x000046A6) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon RX 6700 XT (0x000073DF) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon(TM) Graphics (0x00001681) Direct3D11 vs_5_0 ps_5_0, D3D11)")
    ]

    static let firefoxGPUs: [(String, String)] = [
        ("Mesa", "Mesa Intel(R) UHD Graphics 630 (CFL GT2)"),
        ("AMD", "AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.54, 6.5.0-generic)"),
        ("NVIDIA Corporation", "NVIDIA GeForce GTX 1660/PCIe/SSE2"),
        ("Mesa", "Mesa Intel(R) Iris(R) Xe Graphics (TGL GT2)")
    ]

    static let appleGPUs = ["Apple M1", "Apple M2", "Apple M2 Pro", "Apple M3", "Apple M3 Max", "Apple M4"]

    static let locales: [(lang: String, langs: [String], tz: String)] = [
        ("en-US", ["en-US", "en"], "America/New_York"),
        ("en-US", ["en-US", "en"], "America/Chicago"),
        ("en-US", ["en-US", "en"], "America/Denver"),
        ("en-US", ["en-US", "en"], "America/Los_Angeles"),
        ("en-US", ["en-US", "en"], "America/Phoenix"),
        ("en-GB", ["en-GB", "en"], "Europe/London"),
        ("en-CA", ["en-CA", "en-US", "en"], "America/Toronto"),
        ("en-AU", ["en-AU", "en"], "Australia/Sydney"),
        ("de-DE", ["de-DE", "de", "en"], "Europe/Berlin"),
        ("fr-FR", ["fr-FR", "fr", "en"], "Europe/Paris"),
        ("es-ES", ["es-ES", "es", "en"], "Europe/Madrid"),
        ("nl-NL", ["nl-NL", "nl", "en"], "Europe/Amsterdam"),
        ("pt-BR", ["pt-BR", "pt", "en"], "America/Sao_Paulo"),
        ("ja-JP", ["ja-JP", "ja", "en"], "Asia/Tokyo"),
        ("en-SG", ["en-SG", "en"], "Asia/Singapore")
    ]
}

// MARK: - Presets

extension FingerprintProfile {
    static let iphoneSafari = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "iPhone • Safari 18",
        kind: .safari,
        deviceName: "iPhone 15",
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1",
        platform: "iPhone",
        vendor: "Apple Computer, Inc.",
        language: "en-US",
        languages: ["en-US", "en"],
        hardwareConcurrency: 6,
        deviceMemory: nil,
        maxTouchPoints: 5,
        screenWidth: 393, screenHeight: 852, availWidth: 393, availHeight: 852,
        devicePixelRatio: 3,
        timeZone: "America/New_York",
        webglVendor: "Apple Inc.",
        webglRenderer: "Apple GPU"
    )

    static let ipadSafari = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "iPad Pro • Safari 18",
        kind: .safari,
        deviceName: "iPad Pro",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15",
        platform: "MacIntel",
        vendor: "Apple Computer, Inc.",
        language: "en-US",
        languages: ["en-US", "en"],
        hardwareConcurrency: 8,
        deviceMemory: nil,
        maxTouchPoints: 5,
        screenWidth: 1024, screenHeight: 1366, availWidth: 1024, availHeight: 1366,
        devicePixelRatio: 2,
        timeZone: "America/Los_Angeles",
        webglVendor: "Apple Inc.",
        webglRenderer: "Apple GPU"
    )

    static let macSafari = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "MacBook Pro • Safari 18",
        kind: .safari,
        deviceName: "MacBook Pro",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15",
        platform: "MacIntel",
        vendor: "Apple Computer, Inc.",
        language: "en-US",
        languages: ["en-US", "en"],
        hardwareConcurrency: 10,
        deviceMemory: nil,
        maxTouchPoints: 0,
        screenWidth: 1728, screenHeight: 1117, availWidth: 1728, availHeight: 1079,
        colorDepth: 30,
        devicePixelRatio: 2,
        timeZone: "America/Los_Angeles",
        webglVendor: "Apple Inc.",
        webglRenderer: "Apple M2 Pro"
    )

    static let windowsChrome = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Windows 11 • Chrome 139",
        kind: .chrome,
        deviceName: "Windows PC",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
        platform: "Win32",
        vendor: "Google Inc.",
        language: "en-US",
        languages: ["en-US", "en"],
        hardwareConcurrency: 8,
        deviceMemory: 8,
        maxTouchPoints: 0,
        screenWidth: 1920, screenHeight: 1080, availWidth: 1920, availHeight: 1032,
        devicePixelRatio: 1,
        timeZone: "America/Chicago",
        webglVendor: "Google Inc. (NVIDIA)",
        webglRenderer: "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002503) Direct3D11 vs_5_0 ps_5_0, D3D11)"
    )

    static let androidChrome = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Pixel 8 • Chrome 139",
        kind: .chrome,
        deviceName: "Pixel 8",
        userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36",
        platform: "Linux armv81",
        vendor: "Google Inc.",
        language: "en-GB",
        languages: ["en-GB", "en"],
        hardwareConcurrency: 8,
        deviceMemory: 8,
        maxTouchPoints: 5,
        screenWidth: 412, screenHeight: 915, availWidth: 412, availHeight: 915,
        devicePixelRatio: 2.625,
        timeZone: "Europe/London",
        webglVendor: "Google Inc. (ARM)",
        webglRenderer: "ANGLE (ARM, Mali-G715-Immortalis MC10, OpenGL ES 3.2)"
    )

    static let linuxFirefox = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Linux • Firefox 130",
        kind: .firefox,
        deviceName: "Linux PC",
        userAgent: "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
        platform: "Linux x86_64",
        vendor: "",
        language: "de-DE",
        languages: ["de-DE", "de", "en-US", "en"],
        hardwareConcurrency: 8,
        deviceMemory: nil,
        maxTouchPoints: 0,
        screenWidth: 1920, screenHeight: 1080, availWidth: 1920, availHeight: 1053,
        devicePixelRatio: 1,
        timeZone: "Europe/Berlin",
        webglVendor: "Mesa",
        webglRenderer: "Mesa Intel(R) UHD Graphics 630 (CFL GT2)"
    )

    static let presets: [FingerprintProfile] = [
        iphoneSafari, ipadSafari, macSafari, windowsChrome, androidChrome, linuxFirefox
    ]

    // MARK: Randomizers (Sessions X `generateFingerprint(device)` semantics)

    /// A random, internally consistent identity of the given family.
    static func random(family: DeviceFamily) -> FingerprintProfile {
        let loc = DevicePools.locales.randomElement()!
        var p: FingerprintProfile
        switch family {
        case .ios:
            let d = DevicePools.iphones.randomElement()!
            p = FingerprintProfile(
                name: d.name,
                kind: .safari,
                deviceName: d.name,
                userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS \(d.ios) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(d.safari) Mobile/15E148 Safari/604.1",
                platform: "iPhone",
                vendor: "Apple Computer, Inc.",
                language: loc.lang,
                languages: loc.langs,
                hardwareConcurrency: d.cores,
                deviceMemory: nil,
                maxTouchPoints: 5,
                screenWidth: d.width, screenHeight: d.height, availWidth: d.width, availHeight: d.height,
                devicePixelRatio: d.dpr,
                timeZone: loc.tz,
                webglVendor: "Apple Inc.",
                webglRenderer: "Apple GPU"
            )
        case .android:
            let d = DevicePools.androids.randomElement()!
            let major = DevicePools.chromeMajors.randomElement()!
            p = FingerprintProfile(
                name: d.name,
                kind: .chrome,
                deviceName: d.name,
                userAgent: "Mozilla/5.0 (Linux; Android \(d.android); \(d.name)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Mobile Safari/537.36",
                platform: "Linux armv81",
                vendor: "Google Inc.",
                language: loc.lang,
                languages: loc.langs,
                hardwareConcurrency: [8, 8, 6].randomElement()!,
                deviceMemory: d.memory,
                maxTouchPoints: 5,
                screenWidth: d.width, screenHeight: d.height, availWidth: d.width, availHeight: d.height,
                devicePixelRatio: d.dpr,
                timeZone: loc.tz,
                webglVendor: d.glVendor,
                webglRenderer: d.glRenderer
            )
        case .desktop:
            let s = DevicePools.desktopScreens.randomElement()!
            let major = DevicePools.chromeMajors.randomElement()!
            let gpu = DevicePools.chromeDesktopGPUs.randomElement()!
            p = FingerprintProfile(
                name: "Windows PC",
                kind: .chrome,
                deviceName: "Windows PC",
                userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36",
                platform: "Win32",
                vendor: "Google Inc.",
                language: loc.lang,
                languages: loc.langs,
                hardwareConcurrency: [8, 12, 16].randomElement()!,
                deviceMemory: [8, 16].randomElement()!,
                maxTouchPoints: 0,
                screenWidth: s.w, screenHeight: s.h, availWidth: s.w, availHeight: s.h - s.taskbar,
                devicePixelRatio: s.dpr,
                timeZone: loc.tz,
                webglVendor: gpu.0,
                webglRenderer: gpu.1
            )
        }
        p.name = "\(p.name) #\(String(p.seed % 10000).leftPadded(to: 4))"
        return p
    }

    /// Fully random identity across all families and engines (also covers Firefox / Mac Safari).
    static func random() -> FingerprintProfile {
        let roll = Int.random(in: 0..<10)
        if roll < 4 { return random(family: .ios) }
        if roll < 6 { return random(family: .android) }
        if roll < 8 { return random(family: .desktop) }
        let loc = DevicePools.locales.randomElement()!
        let s = DevicePools.desktopScreens.randomElement()!
        if roll == 8 {
            let major = [128, 129, 130, 131].randomElement()!
            let gpu = DevicePools.firefoxGPUs.randomElement()!
            var p = FingerprintProfile(
                name: "Linux PC", kind: .firefox, deviceName: "Linux PC",
                userAgent: "Mozilla/5.0 (X11; Linux x86_64; rv:\(major).0) Gecko/20100101 Firefox/\(major).0",
                platform: "Linux x86_64", vendor: "", language: loc.lang, languages: loc.langs,
                hardwareConcurrency: [4, 8, 12, 16].randomElement()!, deviceMemory: nil, maxTouchPoints: 0,
                screenWidth: s.w, screenHeight: s.h, availWidth: s.w, availHeight: s.h - s.taskbar,
                devicePixelRatio: s.dpr, timeZone: loc.tz, webglVendor: gpu.0, webglRenderer: gpu.1
            )
            p.name = "\(p.name) #\(String(p.seed % 10000).leftPadded(to: 4))"
            return p
        }
        return randomMacSafari(locale: loc)
    }

    /// Random Mac · Safari desktop identity (WebKit engine, so it matches the real renderer).
    static func randomMacSafari(locale loc: (lang: String, langs: [String], tz: String)? = nil) -> FingerprintProfile {
        let loc = loc ?? DevicePools.locales.randomElement()!
        let s = DevicePools.desktopScreens.randomElement()!
        var p = FingerprintProfile(
            name: "Mac", kind: .safari, deviceName: "MacBook Pro",
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15",
            platform: "MacIntel", vendor: "Apple Computer, Inc.", language: loc.lang, languages: loc.langs,
            hardwareConcurrency: [8, 10, 12].randomElement()!, deviceMemory: nil, maxTouchPoints: 0,
            screenWidth: s.w, screenHeight: s.h, availWidth: s.w, availHeight: s.h - 38, colorDepth: 30,
            devicePixelRatio: 2, timeZone: loc.tz, webglVendor: "Apple Inc.",
            webglRenderer: DevicePools.appleGPUs.randomElement()!
        )
        p.name = "\(p.name) #\(String(p.seed % 10000).leftPadded(to: 4))"
        return p
    }

    /// The "Desktop site" identity for this profile: a desktop-class device that keeps everything
    /// that identifies the *person* (seed, locale, time zone, feature toggles) and only swaps the
    /// device. iPhone identities become Mac · Safari (same WebKit engine); Android becomes Windows · Chrome.
    func desktopCounterpart() -> FingerprintProfile {
        var d: FingerprintProfile
        switch family {
        case .desktop:
            return self
        case .android:
            d = FingerprintProfile.random(family: .desktop)
        case .ios:
            d = FingerprintProfile.randomMacSafari()
        }
        d.seed = seed
        d.language = language
        d.languages = languages
        d.timeZone = timeZone
        d.doNotTrack = doNotTrack
        d.spoofNavigator = spoofNavigator
        d.spoofScreen = spoofScreen
        d.spoofTimezone = spoofTimezone
        d.spoofWebGL = spoofWebGL
        d.spoofCanvas = spoofCanvas
        d.spoofAudio = spoofAudio
        d.spoofHeaders = spoofHeaders
        d.uploadSpoof = uploadSpoof
        d.webrtcPolicy = webrtcPolicy
        d.name = "\(name) · Desktop"
        return d
    }
}

extension String {
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}

// MARK: - Time zones offered in the editor

enum TimeZones {
    static let common: [String] = [
        "America/New_York", "America/Chicago", "America/Denver", "America/Phoenix", "America/Los_Angeles",
        "America/Anchorage", "Pacific/Honolulu", "America/Toronto", "America/Vancouver", "America/Mexico_City",
        "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "Europe/London", "Europe/Dublin", "Europe/Paris",
        "Europe/Berlin", "Europe/Madrid", "Europe/Rome", "Europe/Amsterdam", "Europe/Stockholm", "Europe/Warsaw",
        "Europe/Kyiv", "Europe/Istanbul", "Europe/Moscow", "Africa/Johannesburg", "Africa/Lagos", "Asia/Dubai",
        "Asia/Kolkata", "Asia/Bangkok", "Asia/Singapore", "Asia/Hong_Kong", "Asia/Shanghai", "Asia/Tokyo",
        "Asia/Seoul", "Australia/Sydney", "Australia/Melbourne", "Australia/Perth", "Pacific/Auckland", "UTC"
    ]
}
