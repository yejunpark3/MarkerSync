/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Protocols that define the connection actor interface for peer-to-peer messaging and the message type for communication.
*/

import Foundation
import Network
import OSLog

/// Message type for peer-to-peer communication. Must be JSON-encodable and thread-safe.
public protocol PeerToPeerMessage: Codable, Sendable, Hashable {}

/// Actor interface for client-server implementing peer-to-peer messaging.
/// Actors provide thread-safe networking operations isolated from the UI.
public protocol PeerMessagingManager<Message>: Actor where Message: PeerToPeerMessage {
    associatedtype Message: PeerToPeerMessage

    /// Stream of messages received from the connected peer.
    var receivedMessages: AsyncStream<Message> { get }
    /// Stream of network life cycle events (connecting, connected, stopped, and so on.).
    var networkUpdateEvents: AsyncStream<NetworkEvent> { get }

    /// Send a message to the connected peer.
    func send(_ message: Message) async
    /// Clean up connection resources.
    func invalidate()
    /// Start the client or server with the device ID for pairing.
    func start(with id: String) async throws

    init()
}
