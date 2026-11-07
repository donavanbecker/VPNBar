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

    @ObservationIgnored private var pending: [String: (connect: Bool, since: Date)] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private init() {}

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
                let fast = self?.needsFastPolling ?? false
                try? await Task.sleep(for: .seconds(fast ? 1 : 5))
            }
        }
    }

    func setConnected(_ connect: Bool, id: String) async {
        errors[id] = nil
        pending[id] = (connect, .now)
        SharedStore.lastUsedID = id
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

    private func refresh() async {
        let result = await Scutil.run("--nc", "list")
        guard result.succeeded else { return }
        apply(ScutilParser.parseList(result.output))
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
