import Carbon.HIToolbox
import Observation

/// The system-wide shortcut that connects or disconnects the most recently used VPN.
/// Carbon hot keys work without Accessibility permission.
@MainActor
@Observable
final class HotKey {
    static let shared = HotKey()
    static let label = "⌃⌥V"

    /// False when the shortcut is on but another app already claimed it.
    private(set) var isRegistered = false

    @ObservationIgnored var onPress: (() -> Void)?
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?

    private init() {}

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKey == nil else { return }

        if handler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKey.shared.onPress?() }
                return noErr
            }, 1, &pressed, nil, &handler)
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x5650_4E42, id: 1), // "VPNB"
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKey = status == noErr ? ref : nil
        isRegistered = hotKey != nil
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isRegistered = false
    }
}
