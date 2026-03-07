/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Controller managing the UI state updates for the `NetworkBrowser`, `NetworkListener`, and `NetworkConnections` and received messages.
*/

import Network
import OSLog
import SwiftUI

/// Bridges actor-isolated networking (client-server) with `MainActor` UI updates.
/// - Network operations run in an actor (thread-safe, isolated).
/// - UI state updates run on `MainActor` (synchronous UI updates).
/// - Messages broadcast to multiple views using `AsyncStream` continuations.
@MainActor @Observable
final public class PeerMessagingController<Manager: PeerMessagingManager> {
    private let logger = Logger(subsystem: "com.apple-samplecode.iPadCompanionApp", category: "PeerMessagingController")

    /// Network connection actor for isolated network operations, either client or server.
    let peerMessagingManager: Manager

    /// Current connection state for UI binding.
    public private(set) var connectionState: NetworkState = .cancelled
    public private(set) var errorMessage: String?

    // Tasks for monitoring state.
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Error>?

    /// Broadcast incoming messages to multiple consumers (such as multiple views).
    /// Each consumer gets its own `AsyncStream` with a unique continuation; this is important for larger projects.
    private var incomingMessageContinuations: [UUID: AsyncStream<Manager.Message>.Continuation] = [:]

    /// Creates a new message stream for each view that needs to receive messages.
    /// Multiple views can independently consume the same messages from the actor.
    public var incomingMessages: AsyncStream<Manager.Message> {
        AsyncStream { continuation in
            let id = UUID()
            self.incomingMessageContinuations[id] = continuation

            // Clean up when the consumer stops listening.
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.incomingMessageContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    public init() {
        // Either the client or server.
        self.peerMessagingManager = Manager()
        // Monitor both state events and messages concurrently using structured concurrency.
        // `TaskGroup` ensures both tasks are canceled when the controller deinitializes.
        self.monitorTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.monitorStateEvents() }
                group.addTask { await self.broadcastMessages() }
            }
        }
    }

    /// Starts the `NetworkBrowser` or `NetworkListener`, depending on the manager.
    public func start(with id: String) -> Task<Void, Error>? {
        networkTask = Task {
            _ = await withTaskCancellationHandler {
                do {
                    try await peerMessagingManager.start(with: id)
                } catch {
                    logger.log("An error has occurred: \(error.localizedDescription)")
                    self.connectionState = .stopped
                }
            } onCancel: {
                Task { @MainActor in
                    // After canceling the task, move the state to stopped.
                    logger.log("The task has been canceled.")
                    self.connectionState = .stopped
                }
            }
        }
        return networkTask
    }

    /// Sends a message through the manager.
    public func send(_ command: Manager.Message) async {
        await peerMessagingManager.send(command)
    }

    isolated deinit {
        monitorTask?.cancel()
        monitorTask = nil
        networkTask?.cancel()
        networkTask = nil
        incomingMessageContinuations.removeAll()
    }
}

// MARK: - Private monitoring methods
extension PeerMessagingController {
    /// Monitors state events from the manager and updates connection state.
    private func monitorStateEvents() async {
        for await event in await peerMessagingManager.networkUpdateEvents {
            await handleStateEvent(event)
        }
    }
    
    /// Broadcasts messages to all subscribed consumers.
    private func broadcastMessages() async {
        for await command in await peerMessagingManager.receivedMessages {
            // Relay the message to all active view consumers.
            for continuation in incomingMessageContinuations.values {
                continuation.yield(command)
            }
        }
    }

    /// Handles state events from the manager.
    private func handleStateEvent(_ event: NetworkEvent) async {
        switch event {
        case .browserRunning, .listenerRunning:
            connectionState = .waitingForConnection
        case .connecting:
            connectionState = .connecting
        case .browserStopped(let error):
            logger.log("Client stopped: error is \(String(describing: error))")
            self.errorMessage = "Client stopped"

        case .listenerStopped(let error):
            logger.log("Server stopped: error is \(String(describing: error))")
            connectionState = .stopped
            self.errorMessage = "Server stopped"
        case .tlsFailed(let error):
            logger.log("TLS handshake failed: error is \(String(describing: error))")
            connectionState = .tlsFailed
            self.errorMessage = "TLS handshake failed. This peer has been seen before under a different ID. Choose a new ID."
        case .connection(let connectionEvent):
            await handleConnectionEvent(connectionEvent)
        }
    }
    
    /// Handles connection-specific events.
    private func handleConnectionEvent(_ connectionEvent: NetworkEvent.ConnectionEvent) async {
        switch connectionEvent {
        case .ready:
            connectionState = .connected
        case .stopped(let error):
            logger.log("The connection was stopped: \(String(describing: error))")
            networkTask?.cancel()
            networkTask = nil
            await peerMessagingManager.invalidate()
            self.connectionState = .stopped
            self.errorMessage = "The connection was invalidated."
        }
    }
}
