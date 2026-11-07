import ServiceManagement
import SwiftUI

@main
struct VPNBarApp: App {
    init() {
        VPNManager.shared.start()
        _ = AppUpdater.shared
    }

    var body: some Scene {
        MenuBarExtra {
            VPNMenu(manager: .shared, updater: .shared)
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if manager.connections.isEmpty {
            Text("No VPNs configured")
        }

        ForEach(manager.connections) { connection in
            Toggle(title(for: connection), isOn: binding(for: connection))
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

    private func title(for connection: VPNConnection) -> String {
        connection.status.isTransitioning
            ? "\(connection.name) (\(connection.status.label))"
            : connection.name
    }

    private func binding(for connection: VPNConnection) -> Binding<Bool> {
        Binding {
            connection.status.isOn
        } set: { connect in
            Task { await manager.setConnected(connect, id: connection.id) }
        }
    }
}
