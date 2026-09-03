import Foundation
import Network
import WebKit

/// A per-session proxy. Parsing accepts the same link formats as Sessions X `proxy.js`:
///   socks5://host:port:user:pass · http://user:pass@host:port · host:port:user:pass · host:port
struct ProxyConfig: Codable, Equatable, Hashable {
    enum Scheme: String, Codable, CaseIterable {
        case http
        case socks5
    }

    var scheme: Scheme
    var host: String
    var port: Int
    var user: String
    var pass: String

    var label: String { "\(scheme.rawValue)://\(host):\(port)" }

    /// Sessions X `proxyToText` form: scheme://host:port[:user:pass]
    var text: String {
        let auth = (user.isEmpty && pass.isEmpty) ? "\(host):\(port)" : "\(host):\(port):\(user):\(pass)"
        return "\(scheme.rawValue)://\(auth)"
    }

    static func parse(_ raw: String) -> ProxyConfig? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        str = str.replacingOccurrences(of: "\u{FEFF}", with: "")
        str = str.trimmingCharacters(in: CharacterSet(charactersIn: "|> \t"))
        guard !str.isEmpty else { return nil }

        var scheme: Scheme = .http
        var rest = str
        let lower = str.lowercased()
        for (prefix, s) in [("socks5://", Scheme.socks5), ("socks4://", .socks5), ("https://", .http), ("http://", .http)] {
            if lower.hasPrefix(prefix) {
                scheme = s
                rest = String(str.dropFirst(prefix.count))
                break
            }
        }

        // user:pass@host:port
        if let at = rest.lastIndex(of: "@") {
            let cred = String(rest[..<at])
            let hp = String(rest[rest.index(after: at)...])
            let hpParts = hp.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard hpParts.count == 2, let port = Int(hpParts[1]), !hpParts[0].isEmpty else { return nil }
            let credParts = cred.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let user = credParts.first ?? ""
            let pass = credParts.count > 1 ? credParts[1] : ""
            return ProxyConfig(scheme: scheme, host: hpParts[0], port: port, user: user, pass: pass)
        }

        let parts = rest.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 4 {
            guard let port = Int(parts[1]), !parts[0].isEmpty else { return nil }
            return ProxyConfig(scheme: scheme, host: parts[0], port: port, user: parts[2], pass: parts[3...].joined(separator: ":"))
        }
        if parts.count == 2, let port = Int(parts[1]), !parts[0].isEmpty {
            return ProxyConfig(scheme: scheme, host: parts[0], port: port, user: "", pass: "")
        }
        return nil
    }

    /// WKWebView proxying requires iOS 17 (`WKWebsiteDataStore.proxyConfigurations`).
    static var isSupported: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    @available(iOS 17.0, *)
    func makeProxyConfiguration() -> ProxyConfiguration? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), !host.isEmpty else { return nil }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        var cfg: ProxyConfiguration
        switch scheme {
        case .http:
            cfg = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        case .socks5:
            cfg = ProxyConfiguration(socksv5Proxy: endpoint)
        }
        if !user.isEmpty || !pass.isEmpty {
            cfg.applyCredential(username: user, password: pass)
        }
        return cfg
    }

    /// Applies (or clears) this proxy on a data store. No-op below iOS 17.
    static func apply(_ proxy: ProxyConfig?, to store: WKWebsiteDataStore) {
        if #available(iOS 17.0, *) {
            if let proxy = proxy, let cfg = proxy.makeProxyConfiguration() {
                store.proxyConfigurations = [cfg]
            } else {
                store.proxyConfigurations = []
            }
        }
    }
}
