import Foundation

/// Wspólny kontener aplikacji i rozszerzenia klawiatury (App Group).
/// Rozszerzenie ma do niego dostęp tylko przy włączonym „Pełnym dostępie”.
enum AppGroup {
    static let id = "group.pl.mm.klawiatura"
    static let cloudContainerID = "iCloud.pl.mm.klawiatura"
    static let urlScheme = "klawiaturamm"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}

enum SharedSettings {
    private static let autocorrectKey = "autocorrectEnabled"
    private static let pendingDictationKey = "pendingDictation"

    static var autocorrectEnabled: Bool {
        get { AppGroup.defaults?.object(forKey: autocorrectKey) as? Bool ?? true }
        set { AppGroup.defaults?.set(newValue, forKey: autocorrectKey) }
    }

    /// Tekst podyktowany w aplikacji, czekający na wstawienie przez klawiaturę.
    static var pendingDictation: String? {
        get { AppGroup.defaults?.string(forKey: pendingDictationKey) }
        set {
            if let newValue, !newValue.isEmpty {
                AppGroup.defaults?.set(newValue, forKey: pendingDictationKey)
            } else {
                AppGroup.defaults?.removeObject(forKey: pendingDictationKey)
            }
        }
    }
}
