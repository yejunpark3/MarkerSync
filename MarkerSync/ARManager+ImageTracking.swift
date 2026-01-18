import ARKit
import Foundation

extension ARManager {
    // MARK: - Image Tracking (Scene 1)

    /// Start detecting markers
    func startImageTracking() async throws {
        guard let imageTracking = imageTracking else {
            throw ARError.imageTrackingUnavailable
        }

        imageTrackingTask?.cancel()

        // Add ImageTracking to session
        try await session.run([worldTracking!, imageTracking])

        // Monitor anchor updates
        imageTrackingTask = Task { [weak self] in
            guard let self = self else { return }

            for await update in imageTracking.anchorUpdates {
                if Task.isCancelled { break }

                await MainActor.run {
                    // 모든 이벤트 전달 (added, updated, removed)
                    // MarkerTrackingView에서 isTracked 상태를 확인함
                    NotificationCenter.default.post(
                        name: .imageAnchorDetected,
                        object: update.anchor
                    )
                }
            }
        }
    }

    /// Stop image tracking (called when transitioning to Scene 2)
    func stopImageTracking() {
        imageTrackingTask?.cancel()
        imageTrackingTask = nil

        Task {
            if let worldTracking = worldTracking {
                try? await session.run([worldTracking])
            }
        }
    }

    /// Create shared WorldAnchor from ImageAnchor
    func createSharedWorldAnchor(from imageAnchor: ImageAnchor) async throws {
        guard imageAnchor.isTracked else {
            throw ARError.anchorNotTracked
        }

        let transform = imageAnchor.originFromAnchorTransform
        try validateTransform(transform)

        let worldAnchor = WorldAnchor(originFromAnchorTransform: transform)

        guard let worldTracking = worldTracking else {
            throw ARError.worldTrackingUnavailable
        }

        try await worldTracking.addAnchor(worldAnchor)

        let anchorInfo = SharedAnchorInfo(
            id: worldAnchor.id,
            anchor: worldAnchor,
            creatorId: UUID().uuidString,  // Generate unique creator ID
            timestamp: Date()
        )

        sharedAnchors[worldAnchor.id] = anchorInfo
        userRole = .host

        print("✅ Shared WorldAnchor created: \(worldAnchor.id)")
    }

    /// Validate transform matrix
    private func validateTransform(_ transform: simd_float4x4) throws {
        let det = simd_determinant(transform)
        guard abs(det) > 0.001 else {
            throw ARError.invalidTransform
        }

        for i in 0..<4 {
            for j in 0..<4 {
                let value = transform[i][j]
                guard value.isFinite else {
                    throw ARError.invalidTransform
                }
            }
        }
    }
}

extension Notification.Name {
    static let imageAnchorDetected = Notification.Name("imageAnchorDetected")
}
