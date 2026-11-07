import Foundation
import Observation

/// Options shown in the menu, stored in the app's own defaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var notifyOnChanges: Bool {
        didSet {
            defaults.set(notifyOnChanges, forKey: Key.notifyOnChanges)
            if notifyOnChanges { Notifier.shared.requestAuthorization() }
        }
    }

    var reconnectDroppedVPNs: Bool {
        didSet { defaults.set(reconnectDroppedVPNs, forKey: Key.reconnectDroppedVPNs) }
    }

    var shortcutEnabled: Bool {
        didSet {
            defaults.set(shortcutEnabled, forKey: Key.shortcutEnabled)
            HotKey.shared.setEnabled(shortcutEnabled)
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let notifyOnChanges = "notifyOnChanges"
        static let reconnectDroppedVPNs = "reconnectDroppedVPNs"
        static let shortcutEnabled = "shortcutEnabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.notifyOnChanges: true,
            Key.reconnectDroppedVPNs: false,
            Key.shortcutEnabled: true,
        ])
        notifyOnChanges = defaults.bool(forKey: Key.notifyOnChanges)
        reconnectDroppedVPNs = defaults.bool(forKey: Key.reconnectDroppedVPNs)
        shortcutEnabled = defaults.bool(forKey: Key.shortcutEnabled)
    }
}
