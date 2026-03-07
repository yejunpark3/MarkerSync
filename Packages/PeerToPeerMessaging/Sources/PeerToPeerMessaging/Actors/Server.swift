/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Server actor for handling peer-to-peer connections in the Companion app target.
*/

import Network
import OSLog
import SwiftUI

/// Server runs on iPadOS to accept incoming connections from the visionOS client.
/// Actor isolation ensures thread-safe network operations without data races.
public actor Server<Message: PeerToPeerMessage>: PeerMessagingManager {
    private let logger = Logger(subsystem: "com.apple-samplecode.Companion", category: "Server")

    /// TLS identity for this device, cached and reused across connections.
    private var localIdentity: sec_identity_t?
    /// Current device ID, used to detect when to regenerate the identity.
    private var currentDeviceID: String?

    /// The current connection, and stream if any.
    /// This sample only connects to one peer at a time, but multiple streams can be open over one connection.
    private var currentConnectionInfo: (connection: QuicConnection, stream: QuicStream<Message>)? = nil

    /// The task that receives messages from the connected peer.
    private var messageReceiveTask: Task<Void, Never>? = nil

    // Received messages.
    public let receivedMessages: AsyncStream<Message>
    private let receivedMessageContinuation: AsyncStream<Message>.Continuation

    // General state update events for the `NetworkListener` and `NetworkConnection`.
    public let networkUpdateEvents: AsyncStream<NetworkEvent>
    private let networkUpdateContinuation: AsyncStream<NetworkEvent>.Continuation

    public init() {
        // Create more than one asynchronous stream for pushing events and messages to the controller.
        // Continuations let the actor relay values, and streams let the controller consume them.
        (self.networkUpdateEvents, self.networkUpdateContinuation) = AsyncStream.makeStream(of: NetworkEvent.self)
        (self.receivedMessages, self.receivedMessageContinuation) = AsyncStream.makeStream(of: Message.self)
    }

    /// Publishes the Bonjour service and waits for incoming client connections.
    /// - Parameter id: The ID of the iPad, which must match the ID of the Apple Vision Pro.
    public func start(with id: String) async throws {
        // Get the TLS local identity before running the `NetworkListener`.
        fetchLocalIdentity(for: id)

        // Use cached local identity.
        guard let localIdentity else {
            networkUpdateContinuation.yield(.tlsFailed(TLSError.localIdentityDoesNotExist))
            return
        }

        // Create the `NetworkListener` using Bonjour and QUIC, and use the local identity to configure TLS.
        try await NetworkListener(
            for: .bonjour(
                name: NetworkServiceConstants.listenerName,
                type: NetworkServiceConstants.serviceType,
                txtRecord: createTXTRecord(with: id)
            ), using: .parameters {
                QUIC(alpn: [NetworkServiceConstants.alpn])
                    .idleTimeout(NetworkServiceConstants.idleTimeoutInterval)
                    .tls.localIdentity(localIdentity)
                    .tls.peerAuthentication(.required)
                    .tls.certificateValidator { metadata, trustResult in
                        let isVerified = CertificateTrustManager.verifyCertificate(metadata: metadata, trustResult: trustResult)
                        if !isVerified {
                            self.networkUpdateContinuation.yield(.tlsFailed(TLSError.certificateVerificationFailed))
                        }
                        return isVerified
                    }
            }
                .peerToPeerIncluded(true)
                .multipathServiceType(.disabled)
        )
        .onStateUpdate { _, state in
            self.handleListenerStateUpdates(state)
        }
        .run { connection in

            // This sample only connects to one peer, so it uses the first connection it sees.
            // This guards against handling multiple connections that might arrive
            // over different network paths to the same endpoint.
            if self.currentConnectionInfo == nil {

                // Observe the state update of the connection to know when it cancels or fails.
                connection.onStateUpdate { connection, state in
                    switch state {
                    case .cancelled:
                        self.networkUpdateContinuation.yield(.connection(.stopped(nil)))
                    case .failed(let error):
                        self.networkUpdateContinuation.yield(.connection(.stopped(error)))
                    default: break
                    }
                }
                // Get streams on the connection.
                await self.getInboundStreams(on: connection)
            }
        }
    }

    /// Waits for the client to open the inbound stream, then sets up message receiving.
    /// The server doesn't open streams; it accepts streams opened by the client.
    private func getInboundStreams(on connection: QuicConnection) async {
            do {
                // Create a `Coder` that automatically encodes and decodes `NetworkCommand` as JSON.
                try await connection.inboundStreams { stack in
                    Coder(Message.self, using: .json) {
                        stack
                    }
                } _: { stream in
                    // Set the current connection and stream.
                    self.currentConnectionInfo = (connection, stream)
                    self.networkUpdateContinuation.yield(.connection(.ready))

                    // Start receiving messages on the stream.
                    self.messageReceiveTask = self.receiveMessages(on: stream)
                }
            } catch {
                // Because this sample only connects to one peer, stop the connection when the stream fails.
                logger.error("Stream error: \(error.localizedDescription)")
                networkUpdateContinuation.yield(.connection(.stopped(error as? NWError)))
            }
    }

    /// Relays messages based on the given `NetworkListener` state.
    private func handleListenerStateUpdates(_ state: NetworkListener<QUIC>.State) {
        switch state {
        case .ready:
            networkUpdateContinuation.yield(.listenerRunning)
        case .failed(let error):
            networkUpdateContinuation.yield(.listenerStopped(error))
        case .cancelled:
            networkUpdateContinuation.yield(.listenerStopped(nil))
        default:
            break
        }
    }

    /// Invalidate the current connection if it fails or someone cancels it.
    public func invalidate() {
        messageReceiveTask?.cancel()
        messageReceiveTask = nil
        currentConnectionInfo = nil
    }

    deinit {
        currentConnectionInfo = nil
        messageReceiveTask?.cancel()
        messageReceiveTask = nil
        receivedMessageContinuation.finish()
        networkUpdateContinuation.finish()
    }
}

// MARK: - Sending and receiving
extension Server {

    /// Sends messages over QUIC stream.
    /// Stops the connection if message sending throws; the sample only connects to one peer.
    public func send(_ message: Message) async {
        do {
            try await currentConnectionInfo?.stream.send(message)
        } catch {
            networkUpdateContinuation.yield(.connection(.stopped(nil)))
        }
    }

    /// Returns a task that continuously receives messages from the given stream.
    /// You don't need to perform JSON decoding; the protocol stack with `Coder` automatically decodes messages.
    private func receiveMessages(on stream: QuicStream<Message>) -> Task<Void, Never> {
        return Task {
            do {
                // Iterate through incoming messages from the QUIC stream and relay them using `receivedMessageContinuation`.
                for try await (message, metadata) in stream.messages {
                    logger.log("Received: \(String(describing: message))")
                    self.receivedMessageContinuation.yield(message)
                    // The stream has ended, stop the connection as this sample only connects to one peer at a time.
                    if metadata.lastMessage {
                        self.networkUpdateContinuation.yield(.connection(.stopped(nil)))
                    }
                }
            } catch {
                logger.error("Error receiving messages: \(error.localizedDescription)")
                networkUpdateContinuation.yield(.connection(.stopped(error as? NWError)))
            }
        }
    }
}

// MARK: - Helper methods
extension Server {
    /// Create an `NWTXTRecord` with the device ID for Bonjour discovery filtering.
    private func createTXTRecord(with id: String) -> NWTXTRecord {
        var record = NWTXTRecord()
        record[NetworkServiceConstants.deviceIdentifier] = id
        return record
    }

    /// Fetches the TLS local identity of the device on first run or if the stored device ID changes.
    private func fetchLocalIdentity(for id: String) {
        if currentDeviceID != id {
            guard let identity = TLSIdentity.getLocalIdentity(label: id) else {
                // If getting the local identity fails, relay the error. This updates the UI.
                networkUpdateContinuation.yield(.tlsFailed(TLSError.localIdentityDoesNotExist))
                return
            }
            localIdentity = identity
            currentDeviceID = id
        }
    }

}
