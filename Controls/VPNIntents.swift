import AppIntents
import AppKit
import WidgetKit

/// A VPN offered in the control's configuration picker. The list comes from
/// whatever the app last read from macOS, so it follows VPNs as they're added or removed.
struct VPNEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "VPN"
    static let defaultQuery = VPNEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct VPNEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [VPNEntity] {
        allEntities.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [VPNEntity] {
        allEntities
    }

    private var allEntities: [VPNEntity] {
        SharedStore.connections.map { VPNEntity(id: $0.id, name: $0.name) }
    }
}

/// Chooses which VPN a Control Center toggle controls.
struct SelectVPNIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Select VPN"
    static let isDiscoverable = false

    @Parameter(title: "VPN", description: "Leave empty to follow the most recently used VPN.")
    var vpn: VPNEntity?

    func perform() async throws -> some IntentResult { .result() }
}

/// Runs in the sandboxed extension, so it hands the work to the app.
struct ToggleVPNIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Connect or Disconnect VPN"
    static let isDiscoverable = false

    @Parameter(title: "VPN ID")
    var id: String

    @Parameter(title: "Connected")
    var value: Bool

    init() {}

    init(id: String) {
        self.id = id
    }

    func perform() async throws -> some IntentResult {
        guard !id.isEmpty else {
            launchAppIfNeeded()
            return .result()
        }

        SharedStore.enqueue(VPNCommand(connect: value, issued: .now), for: id)
        showTransition()
        launchAppIfNeeded()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(SharedStore.commandNotification),
            nil,
            nil,
            true
        )
        return .result()
    }

    /// Updates shared state right away so the control doesn't flip back while the
    /// app works. The app replaces this with the real status on its next refresh.
    private func showTransition() {
        var connections = SharedStore.connections
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].status = value ? .connecting : .disconnecting
        SharedStore.connections = connections
    }

    /// The app picks up queued commands when it launches.
    private func launchAppIfNeeded() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SharedStore.appBundleID).isEmpty else {
            return
        }
        // <App>.app/Contents/PlugIns/<Extension>.appex
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
