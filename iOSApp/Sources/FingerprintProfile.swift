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

/// Everything the injected script needs to present a consistent fake identity.
struct FingerprintProfile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var kind: BrowserKind

    // Feature toggles
    var spoofNavigator: Bool = true
    var spoofScreen: Bool = true
    var spoofTimezone: Bool = true
    var spoofWebGL: Bool = true
    var spoofCanvas: Bool = true
    var spoofAudio: Bool = true

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
        // "X11; Linux x86_64; rv:130.0" -> "Linux x86_64"; "Windows NT 10.0; Win64; x64; rv:..." -> "Windows NT 10.0; Win64; x64"
        let filtered = parts.filter { !$0.hasPrefix("rv:") && $0 != "X11" }
        return filtered.joined(separator: "; ")
    }

    /// Desktop-class identities get WebKit's desktop layout viewport (like "Request Desktop Site").
    var isDesktopLike: Bool {
        !userAgent.contains("Mobile") && !userAgent.contains("iPhone")
    }

    var summary: String {
        "\(screenWidth)x\(screenHeight) @\(devicePixelRatio.cleanString)x • \(hardwareConcurrency) cores • \(timeZone)"
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

// MARK: - Presets

extension FingerprintProfile {
    static let iphoneSafari = FingerprintProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "iPhone • Safari 18",
        kind: .safari,
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1",
        platform: "iPhone",
        vendor: "Apple Computer, Inc.",
        language: "en-US",
        languages: ["en-US", "en"],
        hardwareConcurrency: 4,
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

    // MARK: Randomizer

    private struct ScreenSpec {
        let w: Int, h: Int, dpr: Double
    }

    private static let desktopScreens: [ScreenSpec] = [
        .init(w: 1920, h: 1080, dpr: 1), .init(w: 2560, h: 1440, dpr: 1), .init(w: 1536, h: 864, dpr: 1.25),
        .init(w: 1440, h: 900, dpr: 2), .init(w: 1680, h: 1050, dpr: 1), .init(w: 1366, h: 768, dpr: 1),
        .init(w: 3840, h: 2160, dpr: 2), .init(w: 1728, h: 1117, dpr: 2), .init(w: 1512, h: 982, dpr: 2)
    ]

    private static let phoneScreens: [ScreenSpec] = [
        .init(w: 393, h: 852, dpr: 3), .init(w: 390, h: 844, dpr: 3), .init(w: 430, h: 932, dpr: 3),
        .init(w: 375, h: 812, dpr: 3), .init(w: 412, h: 915, dpr: 2.625), .init(w: 360, h: 800, dpr: 3),
        .init(w: 384, h: 854, dpr: 2.8125), .init(w: 414, h: 896, dpr: 2)
    ]

    private static let locales: [(lang: String, langs: [String], tz: String)] = [
        ("en-US", ["en-US", "en"], "America/New_York"),
        ("en-US", ["en-US", "en"], "America/Chicago"),
        ("en-US", ["en-US", "en"], "America/Denver"),
        ("en-US", ["en-US", "en"], "America/Los_Angeles"),
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

    private static let chromeDesktopGPUs: [(String, String)] = [
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002503) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (NVIDIA)", "ANGLE (NVIDIA, NVIDIA GeForce RTX 4070 (0x00002786) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) UHD Graphics 770 (0x00004680) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (Intel)", "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x000046A6) Direct3D11 vs_5_0 ps_5_0, D3D11)"),
        ("Google Inc. (AMD)", "ANGLE (AMD, AMD Radeon RX 6700 XT (0x000073DF) Direct3D11 vs_5_0 ps_5_0, D3D11)")
    ]

    private static let chromeMobileGPUs: [(String, String)] = [
        ("Google Inc. (ARM)", "ANGLE (ARM, Mali-G715-Immortalis MC10, OpenGL ES 3.2)"),
        ("Google Inc. (Qualcomm)", "ANGLE (Qualcomm, Adreno (TM) 740, OpenGL ES 3.2)"),
        ("Google Inc. (Qualcomm)", "ANGLE (Qualcomm, Adreno (TM) 750, OpenGL ES 3.2)"),
        ("Google Inc. (Samsung Electronics Co., Ltd.)", "ANGLE (Samsung Electronics Co., Ltd., Samsung Xclipse 940, OpenGL ES 3.2)")
    ]

    private static let firefoxGPUs: [(String, String)] = [
        ("Mesa", "Mesa Intel(R) UHD Graphics 630 (CFL GT2)"),
        ("AMD", "AMD Radeon RX 6600 (radeonsi, navi23, LLVM 17.0.6, DRM 3.54, 6.5.0-generic)"),
        ("NVIDIA Corporation", "NVIDIA GeForce GTX 1660/PCIe/SSE2"),
        ("Mesa", "Mesa Intel(R) Iris(R) Xe Graphics (TGL GT2)")
    ]

    private static let appleGPUs = ["Apple GPU", "Apple M1", "Apple M2", "Apple M2 Pro", "Apple M3", "Apple M3 Max"]

    private static let androidDevices: [(String, String)] = [
        ("14", "Pixel 8"), ("14", "Pixel 8 Pro"), ("15", "Pixel 9"), ("14", "SM-S928B"), ("14", "SM-S921B"),
        ("13", "SM-A546B"), ("14", "2312DRA50G"), ("14", "CPH2609")
    ]

    static func random() -> FingerprintProfile {
        var base = presets.randomElement()!
        base.id = UUID()
        base.rerollSeed()
        base.name = "Random #\(String(base.seed % 10000).leftPadded(to: 4))"

        let loc = locales.randomElement()!
        base.language = loc.lang
        base.languages = loc.langs
        base.timeZone = loc.tz

        let mobile = base.maxTouchPoints > 0 && !base.userAgent.contains("Macintosh")
        let screen = (mobile ? phoneScreens : desktopScreens).randomElement()!
        base.screenWidth = screen.w
        base.screenHeight = screen.h
        base.availWidth = screen.w
        base.availHeight = mobile ? screen.h : screen.h - [0, 40, 48, 72].randomElement()!
        base.devicePixelRatio = screen.dpr
        base.hardwareConcurrency = mobile ? [4, 8].randomElement()! : [4, 6, 8, 12, 16].randomElement()!

        switch base.kind {
        case .chrome:
            base.deviceMemory = [4, 8, 16, 32].randomElement()!
            if mobile {
                let dev = androidDevices.randomElement()!
                let major = [136, 137, 138, 139].randomElement()!
                base.userAgent = "Mozilla/5.0 (Linux; Android \(dev.0); \(dev.1)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Mobile Safari/537.36"
                let gpu = chromeMobileGPUs.randomElement()!
                base.webglVendor = gpu.0
                base.webglRenderer = gpu.1
            } else {
                let major = [136, 137, 138, 139].randomElement()!
                base.userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36"
                let gpu = chromeDesktopGPUs.randomElement()!
                base.webglVendor = gpu.0
                base.webglRenderer = gpu.1
            }
        case .firefox:
            let major = [128, 129, 130, 131].randomElement()!
            base.userAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:\(major).0) Gecko/20100101 Firefox/\(major).0"
            let gpu = firefoxGPUs.randomElement()!
            base.webglVendor = gpu.0
            base.webglRenderer = gpu.1
        case .safari:
            base.webglVendor = "Apple Inc."
            base.webglRenderer = mobile ? "Apple GPU" : appleGPUs.randomElement()!
            if mobile {
                let ver = ["17_6", "18_0", "18_5", "18_6"].randomElement()!
                base.userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(ver) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(ver.replacingOccurrences(of: "_", with: ".")) Mobile/15E148 Safari/604.1"
            }
        }
        return base
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
