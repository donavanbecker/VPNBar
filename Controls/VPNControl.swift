import AppIntents
import SwiftUI
import WidgetKit

@main
struct VPNControlBundle: WidgetBundle {
    var body: some Widget {
        VPNControl()
    }
}

/// A Control Center toggle. Add it more than once to get one toggle per VPN.
struct VPNControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: SharedStore.controlKind,
            provider: Provider()
        ) { state in
            ControlWidgetToggle(
                isOn: state.isOn,
                action: ToggleVPNIntent(id: state.id)
            ) {
                Label(state.name, systemImage: state.isOn ? "lock.shield.fill" : "lock.shield")
            } valueLabel: { _ in
                Text(state.detail)
            }
        }
        .displayName("VPN")
        .description("Connect to a VPN configured on this Mac.")
    }
}

extension VPNControl {
    struct State {
        var id: String
        var name: String
        var detail: String
        var isOn: Bool

        static let placeholder = State(id: "", name: "VPN", detail: "Disconnected", isOn: false)
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectVPNIntent) -> State {
            State(id: "", name: configuration.vpn?.name ?? "VPN", detail: "Disconnected", isOn: false)
        }

        func currentValue(configuration: SelectVPNIntent) async throws -> State {
            let connections = SharedStore.connections

            if let selected = configuration.vpn {
                // Don't fall back to another VPN: the user chose this one for this toggle.
                guard let connection = connections.first(where: { $0.id == selected.id }) else {
                    return State(id: "", name: selected.name, detail: "Not available", isOn: false)
                }
                return State(connection)
            }

            // No VPN chosen: follow the most recently used one.
            let connection = connections.first { $0.id == SharedStore.lastUsedID }
                ?? connections.first { $0.status.isOn }
                ?? connections.first
            guard let connection else {
                return State(id: "", name: "VPN", detail: "None configured", isOn: false)
            }
            return State(connection)
        }
    }
}

private extension VPNControl.State {
    init(_ connection: VPNConnection) {
        self.init(
            id: connection.id,
            name: connection.name,
            detail: connection.status.label,
            isOn: connection.status.isOn
        )
    }
}
