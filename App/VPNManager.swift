import Foundation
import Observation
import WidgetKit

/// Reads VPN state from macOS, performs connects and disconnects, and publishes
/// the result to the menu and the Control Center extension.
@MainActor
@Observable
final class VPNManager {
    static let shared = VPNManager()

    private(set) var connections: [VPNConnection] = []
    private(set) var errors: [String: String] = [:]

    var anyConnected: Bool { connections.contains { $0.status == .connected } }

    /// How long a VPN may ignore a request, without reporting a transition, before it counts as failed.
    @ObservationIgnored private let startupGrace: TimeInterval = 8
    /// How long a VPN may stay in a transition before it counts as failed.
    @ObservationIgnored private let transitionLimit: TimeInterval = 60
    /// Seconds to wait before each reconnection attempt.
    @ObservationIgnored private let reconnectDelays: [Int] = [2, 10, 30]

    @ObservationIgnored private var pending: [String: (connect: Bool, since: Date)] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// VPNs that were connected through VPN Bar and not disconnected through it since.
    /// One of these disconnecting counts as a drop.
    @ObservationIgnored private var keepConnected: Set<String> {
        didSet { defaults.set(Array(keepConnected), forKey: Key.keepConnected) }
    }
    /// VPNs macOS last reported as connected. Nil until the first report.
    @ObservationIgnored private var up: Set<String>?
    @ObservationIgnored private var reconnectTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var reconnecting: Set<String> = []
    @ObservationIgnored private var lastAuthorizationCheck = Date.now

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let keepConnected = "keepConnected"
    }

    private init() {
        keepConnected = Set(defaults.stringArray(forKey: Key.keepConnected) ?? [])
    }

    func start() {
        guard pollTask == nil else { return }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in await VPNManager.shared.processCommands() }
            },
            SharedStore.commandNotification,
            nil,
            .deliverImmediately
        )

        pollTask = Task { [weak self] in
            await self?.processCommands()
            while !Task.isCancelled {
                await self?.refresh()
                await self?.tick()
                let fast = self?.needsFastPolling ?? false
                try? await Task.sleep(for: .seconds(fast ? 1 : 5))
            }
        }
    }

    /// Connects or disconnects a VPN because the person asked to.
    func setConnected(_ connect: Bool, id: String) async {
        if connect { keepConnected.insert(id) } else { keepConnected.remove(id) }
        stopReconnecting(id)
        SharedStore.lastUsedID = id
        await request(connect, id: id)
    }

    /// Flips the most recently used VPN, or the first one available.
    func toggleMostRecent() async {
        let target = connections.first { $0.id == SharedStore.lastUsedID && $0.isEnabled }
            ?? connections.first { $0.status.isOn }
            ?? connections.first { $0.isEnabled }
        guard let target, !target.status.isTransitioning else { return }
        await setConnected(!target.status.isOn, id: target.id)
    }

    private func request(_ connect: Bool, id: String) async {
        errors[id] = nil
        pending[id] = (connect, .now)
        apply(connections)

        let result = await Scutil.run("--nc", connect ? "start" : "stop", id)
        if !result.succeeded {
            pending[id] = nil
            errors[id] = result.message ?? "Couldn't \(connect ? "connect" : "disconnect")."
        }
        await refresh()
    }

    private var needsFastPolling: Bool {
        !pending.isEmpty || connections.contains { $0.status.isTransitioning }
    }

    private func processCommands() async {
        for (id, command) in SharedStore.drainCommands() {
            await setConnected(command.connect, id: id)
        }
    }

    /// Once a minute, picks up notification permission changes made in System Settings.
    private func tick() async {
        guard Date.now.timeIntervalSince(lastAuthorizationCheck) >= 60 else { return }
        lastAuthorizationCheck = .now
        await Notifier.shared.refreshAuthorization()
    }

    private func refresh() async {
        let result = await Scutil.run("--nc", "list")
        guard result.succeeded else { return }
        let reported = ScutilParser.parseList(result.output)
        noteChanges(in: reported)
        apply(reported)
    }

    /// Reacts to VPNs coming up or going down.
    private func noteChanges(in reported: [VPNConnection]) {
        let isFirstReport = up == nil
        var up = self.up ?? []

        for connection in reported {
            let id = connection.id
            switch connection.status {
            case .connected where !up.contains(id):
                up.insert(id)
                if !isFirstReport { didConnect(connection) }
            case .disconnected:
                if up.remove(id) != nil, !isFirstReport { didDisconnect(connection) }
            default:
                break
            }
        }

        // Forget VPNs that were removed from macOS.
        let ids = Set(reported.map(\.id))
        up.formIntersection(ids)
        if !keepConnected.isSubset(of: ids) { keepConnected.formIntersection(ids) }
        for id in reconnectTasks.keys where !ids.contains(id) { stopReconnecting(id) }

        self.up = up
    }

    private func didConnect(_ connection: VPNConnection) {
        let verb = reconnecting.contains(connection.id) ? "reconnected" : "connected"
        Notifier.shared.post(about: connection.id, title: "\(connection.name) \(verb)")
    }

    private func didDisconnect(_ connection: VPNConnection) {
        let id = connection.id
        guard keepConnected.contains(id), pending[id]?.connect != false else {
            Notifier.shared.post(about: id, title: "\(connection.name) disconnected")
            return
        }

        let reconnect = AppSettings.shared.reconnectDroppedVPNs
        Notifier.shared.post(
            about: id,
            title: "\(connection.name) disconnected unexpectedly",
            body: reconnect ? "Reconnecting…" : "Connect again from the menu bar or Control Center.",
            urgent: true
        )
        if reconnect { startReconnecting(id) }
    }

    private func startReconnecting(_ id: String) {
        stopReconnecting(id)
        reconnecting.insert(id)
        reconnectTasks[id] = Task { [weak self] in await self?.reconnect(id) }
    }

    private func stopReconnecting(_ id: String) {
        reconnectTasks.removeValue(forKey: id)?.cancel()
        reconnecting.remove(id)
    }

    private func reconnect(_ id: String) async {
        // A cancelled attempt was replaced or stopped, and leaves the bookkeeping to whoever did that.
        defer {
            if !Task.isCancelled {
                reconnectTasks[id] = nil
                reconnecting.remove(id)
            }
        }

        for delay in reconnectDelays {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, AppSettings.shared.reconnectDroppedVPNs, keepConnected.contains(id),
                  let connection = connections.first(where: { $0.id == id }), connection.isEnabled
            else { return }
            if connection.status == .connected { return }

            if connection.status == .disconnected { await request(true, id: id) }
            while pending[id] != nil, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
            if connections.first(where: { $0.id == id })?.status == .connected { return }
        }

        guard !Task.isCancelled, let connection = connections.first(where: { $0.id == id }) else { return }
        errors[id] = "Couldn't reconnect. Try connecting again."
        Notifier.shared.post(
            about: id,
            title: "Couldn't reconnect \(connection.name)",
            body: "VPN Bar tried \(reconnectDelays.count) times.",
            urgent: true
        )
    }

    /// Reconciles what macOS reports with requests still in flight, then publishes the result.
    private func apply(_ reported: [VPNConnection]) {
        let now = Date.now
        let merged = reported.map { connection -> VPNConnection in
            guard let request = pending[connection.id] else { return connection }
            var connection = connection
            let elapsed = now.timeIntervalSince(request.since)
            let target: VPNConnection.Status = request.connect ? .connected : .disconnected

            if connection.status == target {
                pending[connection.id] = nil
            } else if connection.status.isTransitioning, elapsed < transitionLimit {
                // Still on its way.
            } else if elapsed < startupGrace {
                // macOS hasn't reported the transition yet, so show it as underway.
                connection.status = request.connect ? .connecting : .disconnecting
            } else {
                pending[connection.id] = nil
                errors[connection.id] = request.connect
                    ? "Couldn't connect. Try connecting from System Settings or the VPN's own app."
                    : "Couldn't disconnect."
            }
            return connection
        }

        // Forget state for VPNs that were removed from macOS.
        let ids = Set(merged.map(\.id))
        pending = pending.filter { ids.contains($0.key) }
        errors = errors.filter { ids.contains($0.key) }

        // Compare with what's published rather than `connections`: the extension
        // writes optimistic state there, and it must be corrected if it was wrong.
        let changedForExtension = merged != SharedStore.connections
        if merged != connections { connections = merged }
        if changedForExtension {
            SharedStore.connections = merged
            ControlCenter.shared.reloadControls(ofKind: SharedStore.controlKind)
        }
    }
}

private enum Scutil {
    struct Result: Sendable {
        let succeeded: Bool
        let output: String

        /// The failure text, when there is any.
        var message: String? {
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    static func run(_ arguments: String...) async -> Result {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/scutil")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return Result(succeeded: false, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(
                succeeded: process.terminationStatus == 0,
                output: String(decoding: data, as: UTF8.self)
            )
        }.value
    }
}
