import ServiceManagement
import SwiftUI

@main
struct VPNBarApp: App {
    init() {
        VPNManager.shared.start()
        Notifier.shared.start()
        HotKey.shared.onPress = { Task { await VPNManager.shared.toggleMostRecent() } }
        HotKey.shared.setEnabled(AppSettings.shared.shortcutEnabled)
        _ = AppUpdater.shared
    }

    var body: some Scene {
        MenuBarExtra {
            VPNMenu(manager: .shared, updater: .shared, settings: .shared)
        } label: {
            VPNMenuIcon(manager: .shared)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct VPNMenuIcon: View {
    let manager: VPNManager

    var body: some View {
        Image(systemName: manager.anyConnected ? "lock.shield.fill" : "lock.shield")
            .accessibilityLabel(manager.anyConnected ? "VPN connected" : "VPN disconnected")
    }
}

private struct VPNMenu: View {
    let manager: VPNManager
    let updater: AppUpdater
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if manager.connections.isEmpty {
            Text("No VPNs configured")
        }

        // Read here rather than inside ForEach, so a new minute redraws the menu
        // even when no VPN changed.
        let now = manager.now
        let connectedSince = manager.connectedSince

        ForEach(manager.connections) { connection in
            Toggle(title(for: connection, connectedSince: connectedSince[connection.id], now: now),
                   isOn: binding(for: connection))
                .disabled(!connection.isEnabled || connection.status.isTransitioning)

            if let error = manager.errors[connection.id] {
                Text(error)
            }
        }

        Divider()

        Button("VPN Settings…") {
            let url = "x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"
            NSWorkspace.shared.open(URL(string: url)!)
        }

        Divider()

        Toggle("Notify When VPNs Connect or Drop", isOn: $settings.notifyOnChanges)

        if settings.notifyOnChanges, !Notifier.shared.isAllowed {
            Button("Allow Notifications in System Settings…") {
                let url = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(SharedStore.appBundleID)"
                NSWorkspace.shared.open(URL(string: url)!)
            }
        }

        Toggle("Reconnect Dropped VPNs", isOn: $settings.reconnectDroppedVPNs)

        Toggle("Toggle Last VPN with \(HotKey.label)", isOn: $settings.shortcutEnabled)

        if settings.shortcutEnabled, !HotKey.shared.isRegistered {
            Text("Another app is using \(HotKey.label)")
        }

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)

        Button("Quit VPN Bar") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(for connection: VPNConnection, connectedSince: Date?, now: Date) -> String {
        if connection.status.isTransitioning {
            return "\(connection.name) (\(connection.status.label))"
        }
        if connection.status == .connected, let connectedSince {
            return "\(connection.name) · \(Self.duration(from: connectedSince, to: now))"
        }
        return connection.name
    }

    /// A short duration such as "<1m", "12m", "1h 12m" or "2d 3h".
    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let (days, hours) = (minutes / 1440, minutes / 60 % 24)
        if days > 0 { return "\(days)d \(hours)h" }
        if minutes >= 60 { return "\(hours)h \(minutes % 60)m" }
        return minutes == 0 ? "<1m" : "\(minutes)m"
    }

    private func binding(for connection: VPNConnection) -> Binding<Bool> {
        Binding {
            connection.status.isOn
        } set: { connect in
            Task { await manager.setConnected(connect, id: connection.id) }
        }
    }
}
