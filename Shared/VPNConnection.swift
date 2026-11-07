import Foundation

/// A VPN service configured in macOS (System Settings > VPN).
struct VPNConnection: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case connected, connecting, disconnecting, disconnected, unknown

        init(scutilValue: String) {
            switch scutilValue.lowercased() {
            case "connected": self = .connected
            case "connecting": self = .connecting
            case "disconnecting": self = .disconnecting
            case "disconnected": self = .disconnected
            default: self = .unknown
            }
        }

        /// Whether a toggle for this VPN should read as "on".
        var isOn: Bool { self == .connected || self == .connecting }

        var isTransitioning: Bool { self == .connecting || self == .disconnecting }

        var label: String {
            switch self {
            case .connected: "Connected"
            case .connecting: "Connecting…"
            case .disconnecting: "Disconnecting…"
            case .disconnected: "Disconnected"
            case .unknown: "Unknown"
            }
        }
    }

    /// The service UUID macOS assigned. Stable across renames.
    let id: String
    var name: String
    var status: Status
    var isEnabled: Bool
}

enum ScutilParser {
    // Matches lines such as:
    // * (Disconnected)   FF84824E-016F-4C07-AB80-61E72FB8C2FC VPN (com.example) "Office"   [VPN:com.example]
    private static let line = /^(\*)?\s*\(([^)]+)\)\s+([0-9A-Fa-f-]{36})\s+.*?"(.*)"\s+\[[^\]]*\]\s*$/

    /// Parses the output of `scutil --nc list`, sorted by name.
    static func parseList(_ output: String) -> [VPNConnection] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { row -> VPNConnection? in
                guard let match = String(row).wholeMatch(of: line) else { return nil }
                return VPNConnection(
                    id: String(match.3),
                    name: String(match.4),
                    status: .init(scutilValue: String(match.2)),
                    isEnabled: match.1 != nil
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
