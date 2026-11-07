import Combine
import Observation
import Sparkle

/// Checks for new versions in the background and offers to install them.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let userDriverDelegate = UserDriverDelegate()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: AnyCancellable?

    private init() {
        // Debug builds don't check, so running from Xcode can't replace your work with a release.
        #if DEBUG
        let startsUpdater = false
        #else
        let startsUpdater = true
        #endif

        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Sparkle asks menu bar apps to opt in to its reminders for updates found in the
/// background, because they have no Dock icon to draw attention with.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
