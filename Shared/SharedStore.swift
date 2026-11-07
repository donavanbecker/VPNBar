import Foundation

/// A connect or disconnect request from the Control Center extension to the app.
struct VPNCommand: Codable, Sendable {
    let connect: Bool
    let issued: Date
}

/// State shared by the app and the sandboxed extension through their App Group.
///
/// The app owns the truth: it reads VPN state from macOS and publishes it here.
/// The extension can't control VPNs from its sandbox, so it leaves commands here
/// and posts a Darwin notification to wake the app.
enum SharedStore {
    static let commandNotification = "com.donavanbecker.VPNBar.command" as CFString
    static let controlKind = "com.donavanbecker.VPNBar.toggle"
    static let appBundleID = "com.donavanbecker.VPNBar"

    /// Commands older than this are dropped, so a late app launch can't flip a VPN unexpectedly.
    private static let commandLifetime: TimeInterval = 30

    private static let defaults: UserDefaults = {
        let group = Bundle.main.object(forInfoDictionaryKey: "VPNBarAppGroup") as? String
        guard let group, let defaults = UserDefaults(suiteName: group) else {
            fatalError("VPNBarAppGroup is missing from Info.plist")
        }
        return defaults
    }()

    private enum Key {
        static let connections = "connections"
        static let lastUsedID = "lastUsedID"
        static let commands = "commands"
    }

    static var connections: [VPNConnection] {
        get { decode([VPNConnection].self, forKey: Key.connections) ?? [] }
        set { encode(newValue, forKey: Key.connections) }
    }

    static var lastUsedID: String? {
        get { defaults.string(forKey: Key.lastUsedID) }
        set { defaults.set(newValue, forKey: Key.lastUsedID) }
    }

    /// Queues a command. A newer command for the same VPN replaces an older one.
    static func enqueue(_ command: VPNCommand, for id: String) {
        var commands = decode([String: VPNCommand].self, forKey: Key.commands) ?? [:]
        commands[id] = command
        encode(commands, forKey: Key.commands)
    }

    /// Removes and returns every queued command that is still fresh.
    static func drainCommands(now: Date = .now) -> [String: VPNCommand] {
        let commands = decode([String: VPNCommand].self, forKey: Key.commands) ?? [:]
        defaults.removeObject(forKey: Key.commands)
        return commands.filter { now.timeIntervalSince($0.value.issued) < commandLifetime }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
