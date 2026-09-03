import Foundation

/// Per-session device / account tokens in the "Key: value" block format used by account
/// tooling (Android ID, IDFV/IDFA, X-MID, IG-U-DS-USER-ID, ...). Identity values are stored
/// and exported with the session; header-type values are injected into requests to the
/// configured hosts (top-level navigations natively, fetch/XHR through the page script).
struct DeviceTokens: Codable, Equatable {
    static let noData = "No data available"

    var username: String = ""
    var androidID: String = ""
    var deviceID: String = ""
    var idfv: String = ""
    var idfa: String = ""
    var authorization: String = ""
    var igUserID: String = ""          // IG-U-DS-USER-ID
    var igIntendedUserID: String = ""  // IG-INTENDED-USER-ID
    var xMID: String = ""              // X-MID
    var xIGWWWClaim: String = ""       // X-IG-WWW-Claim

    /// Whether the header-type tokens are sent on requests.
    var injectHeaders: Bool = true
    /// Hosts (and their subdomains) that receive the header-type tokens.
    var headerHosts: [String] = ["instagram.com"]

    var isEmpty: Bool {
        [username, androidID, deviceID, idfv, idfa, authorization, igUserID, igIntendedUserID, xMID, xIGWWWClaim]
            .allSatisfy { $0.isEmpty }
    }

    // MARK: Field table (drives parsing, export and the editor)

    enum Field: String, CaseIterable, Identifiable {
        case username = "Username"
        case androidID = "Android ID"
        case deviceID = "Device ID"
        case idfv = "IDFV"
        case idfa = "IDFA"
        case authorization = "Authorization"
        case igUserID = "IG-U-DS-USER-ID"
        case igIntendedUserID = "IG-INTENDED-USER-ID"
        case xMID = "X-MID"
        case xIGWWWClaim = "X-IG-WWW-Claim"

        var id: String { rawValue }

        /// Header-type tokens are the ones sent on requests, using their label as header name.
        var isHeader: Bool {
            switch self {
            case .authorization, .igUserID, .igIntendedUserID, .xMID, .xIGWWWClaim: return true
            default: return false
            }
        }

        var canGenerate: Bool {
            switch self {
            case .androidID, .deviceID, .idfv, .idfa, .xMID: return true
            default: return false
            }
        }

        var hint: String {
            switch self {
            case .username: return "account handle"
            case .androidID: return "android-" + String(repeating: "x", count: 16)
            case .deviceID: return "UUID (lowercase)"
            case .idfv, .idfa: return "UUID (uppercase)"
            case .authorization: return "Bearer IGT:2:…"
            case .igUserID, .igIntendedUserID: return "numeric user id"
            case .xMID: return "28-char machine id"
            case .xIGWWWClaim: return "hmac.AR…"
            }
        }
    }

    subscript(field: Field) -> String {
        get {
            switch field {
            case .username: return username
            case .androidID: return androidID
            case .deviceID: return deviceID
            case .idfv: return idfv
            case .idfa: return idfa
            case .authorization: return authorization
            case .igUserID: return igUserID
            case .igIntendedUserID: return igIntendedUserID
            case .xMID: return xMID
            case .xIGWWWClaim: return xIGWWWClaim
            }
        }
        set {
            // Not trimmed here so live editing (e.g. "Bearer " + token) works; parse() trims.
            let v = newValue
            switch field {
            case .username: username = v
            case .androidID: androidID = v
            case .deviceID: deviceID = v
            case .idfv: idfv = v
            case .idfa: idfa = v
            case .authorization: authorization = v
            case .igUserID: igUserID = v
            case .igIntendedUserID: igIntendedUserID = v
            case .xMID: xMID = v
            case .xIGWWWClaim: xIGWWWClaim = v
            }
        }
    }

    // MARK: Text block <-> tokens

    /// Parses lines like `Android ID: android-278da90d972ed9a6`. Unknown lines are ignored,
    /// "No data available" (or "-", "null", "none") clears the field. Keys match case-insensitively
    /// and tolerate underscores/spaces/dashes differences (e.g. `x_mid`, `ig_u_ds_user_id`).
    static func parse(_ block: String, into base: DeviceTokens = DeviceTokens()) -> DeviceTokens {
        var result = base
        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let sep = line.firstIndex(of: ":") else { continue }
            let key = normalizeKey(String(line[..<sep]))
            var value = String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
            if ["no data available", "-", "null", "none", "n/a"].contains(value.lowercased()) { value = "" }
            guard let field = Field.allCases.first(where: { normalizeKey($0.rawValue) == key }) else { continue }
            result[field] = value
        }
        return result
    }

    private static func normalizeKey(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Same block format back, with empty fields written as "No data available".
    var textBlock: String {
        Field.allCases.map { f in
            let v = self[f]
            return "\(f.rawValue): \(v.isEmpty ? DeviceTokens.noData : v)"
        }.joined(separator: "\n")
    }

    /// Header name → value for the non-empty header-type tokens.
    var headers: [String: String] {
        guard injectHeaders else { return [:] }
        var h: [String: String] = [:]
        for f in Field.allCases where f.isHeader {
            let v = self[f].trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { h[f.rawValue] = v }
        }
        return h
    }

    var normalizedHosts: [String] {
        headerHosts
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    func matches(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return normalizedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Generators

    static func generate(_ field: Field) -> String {
        switch field {
        case .androidID:
            return "android-" + randomHex(16)
        case .deviceID:
            return UUID().uuidString.lowercased()
        case .idfv, .idfa:
            return UUID().uuidString.uppercased()
        case .xMID:
            // 28 chars from the URL-safe base64 alphabet, like a real `mid`.
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            return String((0..<28).map { _ in alphabet.randomElement()! })
        default:
            return ""
        }
    }

    private static func randomHex(_ count: Int) -> String {
        let digits = Array("0123456789abcdef")
        return String((0..<count).map { _ in digits.randomElement()! })
    }

    /// Fills every generatable field that is still empty.
    mutating func fillMissingGenerated() {
        for f in Field.allCases where f.canGenerate && self[f].isEmpty {
            self[f] = DeviceTokens.generate(f)
        }
    }
}
