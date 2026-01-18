import ARKit
import RealityKit
import GroupActivities
import Combine
import SwiftUI

@MainActor
@Observable
class ARManager {
    // MARK: - State (UI Observable)
    var appState: AppState = .initializing
    var userRole: UserRole = .undetermined
    var sharedAnchors: [UUID: SharedAnchorInfo] = [:]
    var isConnected: Bool = false
    var errorMessage: String?

    // MARK: - ARKit Components
    var session = ARKitSession()
    var worldTracking: WorldTrackingProvider?
    var imageTracking: ImageTrackingProvider?

    // MARK: - SharePlay Components
    var groupSession: GroupSession<ARCollaborationActivity>?
    var subscriptions = Set<AnyCancellable>()

    // MARK: - Task Management (Memory Safety)
    var imageTrackingTask: Task<Void, Never>?
    var worldTrackingTask: Task<Void, Never>?
    var groupSessionTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Initialize ARKit and start observing SharePlay
    func initialize() async {
        appState = .initializing

        do {
            try await requestAuthorization()
            try await setupProviders()
            observeGroupSessions()
            startWorldAnchorObservation()

            appState = .waitingForSharePlay
        } catch let error as ARError {
            appState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        } catch {
            appState = .error("초기화 실패: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Request ARKit permissions
    private func requestAuthorization() async throws {
        let authResult = await session.requestAuthorization(for: [.worldSensing])

        for (dataType, status) in authResult {
            switch status {
            case .denied:
                throw ARError.authorizationDenied("\(dataType)")
            case .allowed, .notDetermined:
                continue
            @unknown default:
                continue
            }
        }
    }

    /// Setup WorldTracking and ImageTracking providers
    func setupProviders() async throws {
        // WorldTracking (shared anchors enabled by default in visionOS)
        worldTracking = WorldTrackingProvider()

        // ImageTracking with reference images
        let refImages = try ReferenceImage.loadReferenceImages(inGroupNamed: "AR Resources")
        imageTracking = ImageTrackingProvider(referenceImages: refImages)

        // Start session with WorldTracking only
        guard let worldTracking = worldTracking else {
            throw ARError.worldTrackingUnavailable
        }
        try await session.run([worldTracking])
    }

    /// Cleanup resources
    func cleanup() async {
        imageTrackingTask?.cancel()
        worldTrackingTask?.cancel()
        groupSessionTask?.cancel()

        imageTrackingTask = nil
        worldTrackingTask = nil
        groupSessionTask = nil

        // Stop session
        // Note: ARKitSession doesn't have a pause() method in visionOS 2.x

        groupSession?.leave()
        groupSession = nil

        subscriptions.removeAll()
        sharedAnchors.removeAll()
        isConnected = false
    }

    /// Retry after error
    func retry() async {
        await cleanup()
        await initialize()
    }
}
