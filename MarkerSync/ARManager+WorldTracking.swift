import ARKit

extension ARManager {
    // MARK: - World Anchor Observation (Scene 2)

    /// Monitor shared anchor updates
    func startWorldAnchorObservation() {
        worldTrackingTask?.cancel()

        worldTrackingTask = Task { [weak self] in
            guard let self = self,
                  let worldTracking = self.worldTracking else { return }

            for await update in worldTracking.anchorUpdates {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.handleAnchorUpdate(update)
                }
            }
        }
    }

    /// Handle anchor events
    private func handleAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) {
        let anchor = update.anchor

        switch update.event {
        case .added:
            if anchor.isTracked {
                let anchorInfo = SharedAnchorInfo(
                    id: anchor.id,
                    anchor: anchor,
                    creatorId: nil,  // Received from remote
                    timestamp: Date()
                )
                sharedAnchors[anchor.id] = anchorInfo

                if userRole == .undetermined {
                    userRole = .participant
                    appState = .viewingModel
                }

                print("📥 Received shared anchor: \(anchor.id)")
            }

        case .updated:
            if var anchorInfo = sharedAnchors[anchor.id] {
                anchorInfo = SharedAnchorInfo(
                    id: anchor.id,
                    anchor: anchor,
                    creatorId: anchorInfo.creatorId,
                    timestamp: anchorInfo.timestamp,
                    isActive: anchor.isTracked
                )
                sharedAnchors[anchor.id] = anchorInfo
            }

        case .removed:
            sharedAnchors[anchor.id]?.isActive = false
            print("🗑️ Anchor removed: \(anchor.id)")
        }
    }
}
