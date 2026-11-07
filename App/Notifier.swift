import Foundation
import Observation
import UserNotifications

/// Posts notifications when VPNs connect, disconnect or drop.
@MainActor
@Observable
final class Notifier {
    static let shared = Notifier()

    /// False when the person turned VPN Bar's notifications off in System Settings.
    private(set) var isAllowed = true

    @ObservationIgnored private let delegate = Delegate()
    private var center: UNUserNotificationCenter { .current() }

    private init() {}

    func start() {
        center.delegate = delegate
        if AppSettings.shared.notifyOnChanges { requestAuthorization() }
    }

    func requestAuthorization() {
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            isAllowed = granted
        }
    }

    /// Picks up a change made in System Settings since the last check.
    func refreshAuthorization() async {
        guard AppSettings.shared.notifyOnChanges else { return }
        let status = await center.notificationSettings().authorizationStatus
        isAllowed = status != .denied
    }

    /// Shows a notification, replacing any earlier one about the same VPN.
    /// An urgent notification plays a sound.
    func post(about id: String, title: String, body: String? = nil, urgent: Bool = false) {
        guard AppSettings.shared.notifyOnChanges else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        if urgent { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        // Show notifications even while the menu is open and VPN Bar is the active app.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
}
