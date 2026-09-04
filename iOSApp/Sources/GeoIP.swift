import Foundation

/// Resolves "where does this session appear to be?" from the proxy's exit IP, the way Camoufox's
/// `geoip` option does: the lookup is made *through* the session proxy so the answering service
/// sees the proxy's public address, and its geo (lat/lon, IANA time zone, country) is what the
/// identity should report. With no proxy the real connection is used.
enum GeoIP {
    struct Result {
        var ip: String
        var latitude: Double
        var longitude: Double
        var timeZone: String?
        var countryCode: String?
        var city: String?
        /// BCP-47 language for the country, e.g. "de-DE" (nil when unknown).
        var locale: String? { countryCode.flatMap { GeoIP.locale(forCountry: $0) } }

        var label: String {
            var parts: [String] = [ip]
            if let c = city, !c.isEmpty { parts.append(c) }
            if let cc = countryCode, !cc.isEmpty { parts.append(cc) }
            return parts.joined(separator: " · ")
        }
    }

    enum Failure: LocalizedError {
        case network(String)
        case noProvider

        var errorDescription: String? {
            switch self {
            case .network(let m): return m
            case .noProvider: return "No geolocation service answered through this connection."
            }
        }
    }

    /// Two HTTPS, key-less providers; the second is a fallback for rate limits / outages.
    private static let providers: [URL] = [
        URL(string: "https://ipwho.is/")!,
        URL(string: "https://ipapi.co/json/")!
    ]

    static func resolve(through proxy: ProxyConfig?, completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"]
        if let p = proxy { config.connectionProxyDictionary = proxyDictionary(for: p) }

        let delegate = ProxyAuthDelegate(proxy: proxy)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        attempt(session: session, index: 0, lastError: nil) { result in
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func attempt(session: URLSession, index: Int, lastError: Error?, completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        guard index < providers.count else {
            completion(.failure(lastError ?? Failure.noProvider))
            return
        }
        let url = providers[index]
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                attempt(session: session, index: index + 1, lastError: Failure.network(error.localizedDescription), completion: completion)
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let parsed = parse(json, from: url) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                attempt(session: session, index: index + 1, lastError: Failure.network("\(url.host ?? "provider") returned HTTP \(code)"), completion: completion)
                return
            }
            completion(.success(parsed))
        }.resume()
    }

    private static func parse(_ j: [String: Any], from url: URL) -> Result? {
        func dbl(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return Double(s) }
            return nil
        }
        // ipwho.is reports failures with HTTP 200 + success:false.
        if let ok = j["success"] as? Bool, ok == false { return nil }
        guard let lat = dbl(j["latitude"]), let lon = dbl(j["longitude"]) else { return nil }
        var tz: String?
        if let t = j["timezone"] as? String { tz = t }                              // ipapi.co
        else if let t = j["timezone"] as? [String: Any] { tz = t["id"] as? String } // ipwho.is
        if let t = tz, TimeZone(identifier: t) == nil { tz = nil }
        return Result(
            ip: (j["ip"] as? String) ?? "?",
            latitude: lat, longitude: lon,
            timeZone: tz,
            countryCode: (j["country_code"] as? String)?.uppercased(),
            city: j["city"] as? String
        )
    }

    /// CFNetwork proxy dictionary for URLSession. String keys are used because the HTTPS/SOCKS
    /// constants are not all exported on iOS; the values are what CFNetwork reads.
    private static func proxyDictionary(for p: ProxyConfig) -> [AnyHashable: Any] {
        switch p.scheme {
        case .http:
            return [
                "HTTPEnable": 1, "HTTPProxy": p.host, "HTTPPort": p.port,
                "HTTPSEnable": 1, "HTTPSProxy": p.host, "HTTPSPort": p.port
            ]
        case .socks5:
            var d: [AnyHashable: Any] = ["SOCKSEnable": 1, "SOCKSProxy": p.host, "SOCKSPort": p.port]
            if !p.user.isEmpty { d["SOCKSUser"] = p.user }
            if !p.pass.isEmpty { d["SOCKSPassword"] = p.pass }
            return d
        }
    }

    /// Representative locale for a country (what a local user's browser most likely sends).
    static func locale(forCountry cc: String) -> String? {
        let map: [String: String] = [
            "US": "en-US", "GB": "en-GB", "CA": "en-CA", "AU": "en-AU", "NZ": "en-NZ", "IE": "en-IE", "SG": "en-SG",
            "IN": "en-IN", "PH": "en-PH", "ZA": "en-ZA", "NG": "en-NG", "KE": "en-KE",
            "DE": "de-DE", "AT": "de-AT", "CH": "de-CH", "FR": "fr-FR", "BE": "fr-BE", "ES": "es-ES", "MX": "es-MX",
            "AR": "es-AR", "CO": "es-CO", "CL": "es-CL", "PE": "es-PE", "VE": "es-VE", "IT": "it-IT", "PT": "pt-PT",
            "BR": "pt-BR", "NL": "nl-NL", "SE": "sv-SE", "NO": "nb-NO", "DK": "da-DK", "FI": "fi-FI", "PL": "pl-PL",
            "CZ": "cs-CZ", "HU": "hu-HU", "RO": "ro-RO", "GR": "el-GR", "TR": "tr-TR", "UA": "uk-UA", "RU": "ru-RU",
            "IL": "he-IL", "AE": "ar-AE", "SA": "ar-SA", "EG": "ar-EG", "JP": "ja-JP", "KR": "ko-KR", "CN": "zh-CN",
            "TW": "zh-TW", "HK": "zh-HK", "TH": "th-TH", "VN": "vi-VN", "ID": "id-ID", "MY": "ms-MY"
        ]
        return map[cc]
    }

    /// Accept-Language style list for a locale: "de-DE" → ["de-DE", "de", "en"].
    static func languages(for locale: String) -> [String] {
        let base = locale.split(separator: "-").first.map(String.init) ?? locale
        var list = [locale]
        if base != locale { list.append(base) }
        if base != "en" { list.append("en") }
        return list
    }
}

extension FingerprintProfile {
    /// Pins this identity to a geoip result (coordinates, time zone, language). Returns a short list
    /// of what changed, for UI messages.
    @discardableResult
    mutating func pin(geo: GeoIP.Result) -> [String] {
        latitude = (geo.latitude * 10000).rounded() / 10000
        longitude = (geo.longitude * 10000).rounded() / 10000
        if geoAccuracy == nil { geoAccuracy = Double(20 + Int(seed % 100)) }
        var changed = ["coordinates"]
        if let tz = geo.timeZone {
            timeZone = tz
            spoofTimezone = true
            changed.append("time zone \(tz)")
        }
        if let loc = geo.locale, loc != language {
            language = loc
            languages = GeoIP.languages(for: loc)
            changed.append("language \(loc)")
        }
        return changed
    }
}

/// Answers the proxy's authentication challenge (HTTP CONNECT proxies with user/pass).
private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate {
    private let proxy: ProxyConfig?
    init(proxy: ProxyConfig?) { self.proxy = proxy }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.isProxy(), let p = proxy, !(p.user.isEmpty && p.pass.isEmpty), challenge.previousFailureCount < 2 {
            completionHandler(.useCredential, URLCredential(user: p.user, password: p.pass, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
