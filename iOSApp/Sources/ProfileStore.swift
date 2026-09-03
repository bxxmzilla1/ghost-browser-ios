import Foundation
import Combine

/// Persists the active fingerprint profile and browser preferences.
final class ProfileStore: ObservableObject {
    private enum Keys {
        static let profile = "ghost.profile.v1"
        static let privateMode = "ghost.privateMode"
        static let homeURL = "ghost.homeURL"
    }

    @Published var profile: FingerprintProfile {
        didSet { persistProfile() }
    }

    @Published var privateMode: Bool {
        didSet { UserDefaults.standard.set(privateMode, forKey: Keys.privateMode) }
    }

    @Published var homeURL: String {
        didSet { UserDefaults.standard.set(homeURL, forKey: Keys.homeURL) }
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.profile),
           let saved = try? JSONDecoder().decode(FingerprintProfile.self, from: data) {
            profile = saved
        } else {
            profile = FingerprintProfile.iphoneSafari
        }
        privateMode = defaults.object(forKey: Keys.privateMode) as? Bool ?? false
        homeURL = defaults.string(forKey: Keys.homeURL) ?? "https://duckduckgo.com"
    }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Keys.profile)
        }
    }
}
