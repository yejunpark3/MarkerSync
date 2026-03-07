/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Connection type definitions and type aliases for peer-to-peer networking.
*/
// MARK: - Shared/Networking/NetworkTypes.swift

import Foundation
import Network

// Type aliases for connections.
public typealias ConnectionID = String
public typealias QuicConnection = NetworkConnection<QUIC>

public typealias QuicStream<Message: PeerToPeerMessage> = QUIC.Stream<Coder<Message, Message, NetworkJSONCoder>>

/// Events that occur during client-server life cycle and connection state changes.
public enum NetworkEvent: Sendable {
    case browserRunning
    case connecting
    case browserStopped(NWError?)

    case listenerRunning
    case listenerStopped(NWError?)
    case tlsFailed(TLSError?)
    case connection(ConnectionEvent)

    public enum ConnectionEvent: Sendable {
        case ready
        case stopped(NWError?)
    }
}

/// UI-friendly connection states mapped from `NetworkEvent`.
public enum NetworkState: String, Sendable {
    case stopped
    case tlsFailed
    case connected
    case connecting
    case waitingForConnection
    case cancelled
}

/// Constants for Bonjour service discovery and QUIC connection.
public enum NetworkServiceConstants {
    /// Application-Layer Protocol Negotiation (ALPN). Must match on both devices.
    public static let alpn = "markersync"

    /// Bonjour service type: `_example` (ALPN) + `._udp` (transport protocol).
    public static let serviceType = "_markersync._udp"

    /// A human-readable name, shown in network browser results.
    public static let listenerName = "markersync-listener"

    /// TXT record key for filtering endpoints by matching the device ID.
    public static let deviceIdentifier = "device-identifier"

    /// Keep the connection alive during inactivity (5 minutes prevents premature drops for this sample).
    public static let idleTimeoutInterval: Int = 300_000
}

/// Errors for the TLS handshake.
public enum TLSError: Error {
    /// Couldn't verify a peer's certificate.
    case certificateVerificationFailed
    /// Couldn't create or find a local identity.
    case localIdentityDoesNotExist
}
