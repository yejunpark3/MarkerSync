/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Class for validating incoming TLS certificates. Uses a trust on first use (TOFU) model.
*/

import CryptoKit
import Foundation
import OSLog
import Security

/// Implements trust on first use certificate validation.
/// This protects against intermediary attacks after establishing the first connection, and is simple to implement for demo purposes.
/// CA-based PKI is preferred for production. Trust only certificates signed by trusted authority.
/// This code doesn't implement a revocation method. Use `removeTrustedPeer` if you would like to implement this.
public final class CertificateTrustManager: Sendable {
    private static let logger = Logger(subsystem: "com.apple-samplecode.PeerToPeerMessaging", category: "CertificateTrustManager")
    private static let keychainService = "com.markersync.trusted-certs"

    /// Verify a given certificate. Returns true if the certificate is recognized.
    public static func verifyCertificate(metadata: sec_protocol_metadata_t, trustResult: sec_trust_t) -> Bool {
        logger.log("Certificate validation callback initiated")
        logger.log("Trust result: \(trustResult.description)")

        // Get peer certificate from metadata.
        let trust = sec_trust_copy_ref(trustResult).takeRetainedValue()
        guard let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let peerCert = certChain.first else {
            logger.log("Failed to extract peer certificate")
            return false
        }

        // Log peer certificate details.
        if let summary = SecCertificateCopySubjectSummary(peerCert) {
            logger.log("Peer cert subject: \(summary)")
        }

        // Use peer's certificate subject as identifier.
        let peerIdentifier: String
        if let summary = SecCertificateCopySubjectSummary(peerCert) as String? {
            peerIdentifier = summary
        } else {
            peerIdentifier = "unknown-peer"
        }

        // Validate that the certificate either has been seen before or is the first use, so it's trusted.
        let isValid = validateCertificate(peerCert, for: peerIdentifier)

        if isValid {
            logger.log("Certificate validation worked - accepting connection")
        } else {
            logger.log("Certificate validation failed")
        }

        return isValid
    }

    /// Validate certificate using trust on first use. Reject if the certificate changed since the first connection.
    /// - Parameters:
    ///   - certificate: The peer's certificate to validate.
    ///   - peerIdentifier: A unique identifier for the peer (such as the device name or an endpoint).
    /// - Returns: Returns true to trust the certificate; otherwise, false.
    private static func validateCertificate(_ certificate: SecCertificate, for peerIdentifier: String) -> Bool {
        logger.log("Validating certificate for peer: \(peerIdentifier)")

        // Calculate the fingerprint of the presented certificate.
        guard let presentedFingerprint = certificateFingerprint(certificate) else {
            logger.log("Failed to calculate certificate fingerprint")
            return false
        }

        logger.log("Presented fingerprint: \(presentedFingerprint)")

        // Check if there is a trusted fingerprint for this peer.
        if let trustedFingerprint = retrieveTrustedFingerprint(for: peerIdentifier) {
            // Known peer - verify fingerprint matches.
            logger.log("Known fingerprint: \(trustedFingerprint)")

            if presentedFingerprint == trustedFingerprint {
                logger.log("Certificate matches trusted fingerprint")
                return true
            } else {
                logger.log("Certificate fingerprint mismatch. Is not valid.")
                return false
            }
        } else {
            // First connection: Trust and save the fingerprint for future validation.
            logger.log("First connection from this peer")

            if storeTrustedFingerprint(presentedFingerprint, for: peerIdentifier) {
                logger.log("Stored fingerprint and accepting connection")
                return true
            } else {
                logger.log("Failed to store fingerprint")
                return false
            }
        }
    }

    /// Calculate a SHA-256 fingerprint of a certificate to save rather than saving the entire certificate.
    private static func certificateFingerprint(_ certificate: SecCertificate) -> String? {
        guard let certData = SecCertificateCopyData(certificate) as Data? else {
            return nil
        }

        let hash = SHA256.hash(data: certData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Store a trusted certificate fingerprint in the keychain.
    private static func storeTrustedFingerprint(_ fingerprint: String, for peerIdentifier: String) -> Bool {
        logger.log("Storing trusted fingerprint for peer: \(peerIdentifier)")
        logger.log("Fingerprint: \(fingerprint)")

        let key = "trusted-\(peerIdentifier)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: fingerprint.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete the existing entry, if present.
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            logger.log("Successfully stored fingerprint")
            return true
        } else {
            logger.log("Failed to store fingerprint: \(status)")
            return false
        }
    }

    /// Retrieve a trusted certificate fingerprint from the keychain.
    private static func retrieveTrustedFingerprint(for peerIdentifier: String) -> String? {
        let key = "trusted-\(peerIdentifier)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let fingerprint = String(data: data, encoding: .utf8) {
            logger.log("Found existing trusted fingerprint for peer: \(peerIdentifier)")
            return fingerprint
        } else {
            logger.log("No existing fingerprint found for peer: \(peerIdentifier)")
            return nil
        }
    }

    /// Removes a trusted peer's certificate fingerprint from keychain.
    /// This method isn't used in this sample but can be utilized to remove a trusted device..
    ///
    /// After calling this function, treat the next connection from this peer as a first connection
    /// and save the new certificate's fingerprint.
    static func removeTrustedPeer(_ peerIdentifier: String) -> Bool {
        logger.log("Removing trusted peer: \(peerIdentifier)")

        let key = "trusted-\(peerIdentifier)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.log("Successfully removed trusted peer")
            return true
        } else {
            logger.log("Failed to remove trusted peer: \(status)")
            return false
        }
    }
}
