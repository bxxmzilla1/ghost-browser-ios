import Foundation
import Combine

/// Holds every saved session (fingerprint + cookies + proxy + last URL), which one is
/// active, and browser preferences. Persisted as JSON in Application Support.
final class ProfileStore: ObservableObject {
    private enum Keys {
        static let legacyProfile = "ghost.profile.v1"
        static let privateMode = "ghost.privateMode"
        static let homeURL = "ghost.homeURL"
        static let activeID = "ghost.activeSession"
    }

    static let defaultHomeURL = "https://www.google.com"

    @Published private(set) var sessions: [BrowserSession] = []
    @Published private(set) var activeID: UUID

    /// Bumped whenever the live web view must be rebuilt (profile / proxy / private mode edits).
    @Published private(set) var revision: Int = 0

    @Published var privateMode: Bool {
        didSet {
            UserDefaults.standard.set(privateMode, forKey: Keys.privateMode)
            revision += 1
        }
    }

    @Published var homeURL: String {
        didSet { UserDefaults.standard.set(homeURL, forKey: Keys.homeURL) }
    }

    private var saveWorkItem: DispatchWorkItem?

    // MARK: Active session accessors

    var active: BrowserSession {
        sessions.first(where: { $0.id == activeID }) ?? sessions[0]
    }

    var profile: FingerprintProfile {
        get { active.profile }
        set {
            guard newValue != active.profile else { return }
            // Explicitly choosing an identity ends "Desktop site" mode: the new one is the real identity.
            mutateActive { $0.profile = newValue; $0.mobileProfileBackup = nil }
            revision += 1
        }
    }

    /// "Desktop site" for the active session: swaps in a desktop-class identity (same seed,
    /// locale, time zone) and parks the current one so it can be restored exactly.
    var desktopSite: Bool {
        get { active.isDesktopSite }
        set {
            guard newValue != active.isDesktopSite else { return }
            mutateActive { s in
                if newValue {
                    s.mobileProfileBackup = s.profile
                    s.profile = s.profile.desktopCounterpart()
                } else if let original = s.mobileProfileBackup {
                    s.profile = original
                    s.mobileProfileBackup = nil
                }
            }
            revision += 1
        }
    }

    var proxy: ProxyConfig? {
        get { active.proxy }
        set {
            guard newValue != active.proxy else { return }
            mutateActive { $0.proxy = newValue }
            revision += 1
        }
    }

    // MARK: Init / persistence

    init() {
        let defaults = UserDefaults.standard
        privateMode = defaults.object(forKey: Keys.privateMode) as? Bool ?? false
        // Treat the old built-in default as "unset" so existing installs pick up the new home page.
        let savedHome = defaults.string(forKey: Keys.homeURL)
        homeURL = (savedHome == nil || savedHome == "https://duckduckgo.com") ? ProfileStore.defaultHomeURL : savedHome!

        var loaded: [BrowserSession] = []
        if let data = try? Data(contentsOf: ProfileStore.fileURL),
           let saved = try? JSONDecoder().decode([BrowserSession].self, from: data) {
            loaded = saved
        }
        if loaded.isEmpty {
            // Migrate the pre-sessions single profile, or start with a fresh iPhone identity.
            let profile: FingerprintProfile
            if let data = defaults.data(forKey: Keys.legacyProfile),
               let p = try? JSONDecoder().decode(FingerprintProfile.self, from: data) {
                profile = p
            } else {
                profile = FingerprintProfile.iphoneSafari
            }
            loaded = [BrowserSession(name: profile.name, profile: profile)]
        }
        sessions = loaded

        if let raw = defaults.string(forKey: Keys.activeID), let id = UUID(uuidString: raw),
           loaded.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = loaded[0].id
        }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ghost-sessions.json")
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = sessions
        let item = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: ProfileStore.fileURL, options: .atomic)
            }
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: ProfileStore.fileURL, options: .atomic)
        }
    }

    // MARK: Mutations

    private func mutateActive(_ change: (inout BrowserSession) -> Void) {
        mutate(id: activeID, change)
    }

    func mutate(id: UUID, _ change: (inout BrowserSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        var s = sessions[idx]
        change(&s)
        s.updatedAt = Date()
        sessions[idx] = s
        scheduleSave()
    }

    /// Called by the browser after navigations / before switching to keep the session current.
    func snapshot(cookies: [CookieRecord]?, url: URL?, for id: UUID) {
        mutate(id: id) { s in
            if let cookies = cookies { s.cookies = cookies }
            if let url = url, let scheme = url.scheme, scheme.hasPrefix("http") { s.lastURL = url.absoluteString }
        }
    }

    @discardableResult
    func add(_ session: BrowserSession, activate: Bool = false) -> BrowserSession {
        sessions.append(session)
        scheduleSave()
        if activate { setActive(session.id) }
        return session
    }

    func newSession(family: DeviceFamily?) -> BrowserSession {
        let profile = family.map { FingerprintProfile.random(family: $0) } ?? FingerprintProfile.random()
        return BrowserSession(name: profile.deviceLabel, profile: profile)
    }

    func duplicateActive() -> BrowserSession {
        var copy = active
        copy.id = UUID()
        copy.uid = BrowserSession.makeUID()
        copy.name = active.name + " (copy)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id: id) { $0.name = trimmed }
    }

    func remove(id: UUID) {
        guard sessions.count > 1 else {
            // Never leave the store empty: replace the last session with a fresh one instead.
            let fresh = newSession(family: .ios)
            sessions = [fresh]
            activeID = fresh.id
            persistActiveID()
            scheduleSave()
            revision += 1
            return
        }
        sessions.removeAll { $0.id == id }
        scheduleSave()
        if activeID == id {
            activeID = sessions[0].id
            persistActiveID()
        }
    }

    /// Marks a session active. The browser view performs the cookie swap and rebuild.
    func setActive(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeID = id
        persistActiveID()
    }

    private func persistActiveID() {
        UserDefaults.standard.set(activeID.uuidString, forKey: Keys.activeID)
    }

    // MARK: Import / export

    func exportData(for id: UUID) -> Data? {
        guard let s = sessions.first(where: { $0.id == id }) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(SessionsXPayload(session: s))
    }

    /// Imports a Sessions X / GhostBrowser JSON payload (or a bare cookie array).
    func importSession(from data: Data) throws -> BrowserSession {
        let payload = try SessionsXPayload.decode(data)
        var session = payload.toSession()
        // Keep ids unique even when re-importing the same file.
        session.id = UUID()
        if sessions.contains(where: { $0.uid == session.uid }) { session.uid = BrowserSession.makeUID() }
        return add(session)
    }
}
