import Foundation
import Observation

@Observable final class AppSettings {

    // MARK: - Plex Server

    var plexServerURL: String {
        didSet { UserDefaults.standard.set(plexServerURL, forKey: "plexServerURL") }
    }

    var plexLibrarySectionID: String {
        didSet { UserDefaults.standard.set(plexLibrarySectionID, forKey: "plexLibrarySectionID") }
    }

    var plexMachineIdentifier: String {
        didSet { UserDefaults.standard.set(plexMachineIdentifier, forKey: "plexMachineIdentifier") }
    }

    // MARK: - Token (UserDefaults — token de Plex es revocable desde plex.tv)

    var plexToken: String {
        didSet { UserDefaults.standard.set(plexToken, forKey: "plexToken") }
    }

    var isAuthenticated: Bool { !plexToken.isEmpty }

    // MARK: - Sound

    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // MARK: - Path Mapping

    var localPathPrefix: String {
        didSet { UserDefaults.standard.set(localPathPrefix, forKey: "localPathPrefix") }
    }

    var plexPathPrefix: String {
        didSet { UserDefaults.standard.set(plexPathPrefix, forKey: "plexPathPrefix") }
    }

    // MARK: - Init

    init() {
        self.plexServerURL         = UserDefaults.standard.string(forKey: "plexServerURL") ?? ""
        self.plexLibrarySectionID  = UserDefaults.standard.string(forKey: "plexLibrarySectionID") ?? ""
        self.plexMachineIdentifier = UserDefaults.standard.string(forKey: "plexMachineIdentifier") ?? ""
        self.soundEnabled          = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        self.localPathPrefix       = UserDefaults.standard.string(forKey: "localPathPrefix") ?? ""
        self.plexPathPrefix        = UserDefaults.standard.string(forKey: "plexPathPrefix") ?? ""
        // Migrar token viejo desde Keychain si existe
        if let legacy = KeychainHelper.load(forKey: "plexToken") {
            UserDefaults.standard.set(legacy, forKey: "plexToken")
            KeychainHelper.delete(forKey: "plexToken")
        }
        self.plexToken = UserDefaults.standard.string(forKey: "plexToken") ?? ""
    }

    func clearAuth() {
        plexToken = ""
        UserDefaults.standard.removeObject(forKey: "plexToken")
    }
}
