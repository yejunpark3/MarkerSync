import ARKit

extension ARManager {
    // MARK: - World Anchor Observation (Phase 8+)
    
    /// Monitor shared anchor updates for drift correction
    func startWorldAnchorObservation() {
        worldTrackingTask?.cancel()
        
        print("👁️ Starting World Anchor observation...")
        
        worldTrackingTask = Task { [weak self] in
            guard let self = self,
                  let worldTracking = self.worldTracking else {
                print("⚠️ WorldTracking not available for observation")
                return
            }
            
            for await update in worldTracking.anchorUpdates {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.handleAnchorUpdate(update)
                }
            }
        }
    }
    
    /// Handle anchor events (added, updated, removed)
    private func handleAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) {
        let anchor = update.anchor
        
        switch update.event {
        case .added:
            handleAnchorAdded(anchor)
            
        case .updated:
            handleAnchorUpdated(anchor)
            
        case .removed:
            handleAnchorRemoved(anchor)
        }
    }
    
    // MARK: - Anchor Event Handlers
    
    /// 새 앵커 추가됨 (원격에서 수신 또는 로컬에서 생성)
    private func handleAnchorAdded(_ anchor: WorldAnchor) {
        guard anchor.isTracked else {
            print("⚠️ Added anchor not tracked: \(anchor.id)")
            return
        }
        
        // 이미 존재하는 앵커면 스킵 (로컬에서 생성한 경우)
        if sharedAnchors[anchor.id] != nil {
            print("ℹ️ Anchor already exists locally: \(anchor.id)")
            return
        }
        
        // 원격에서 수신한 앵커
        let anchorInfo = SharedAnchorInfo(
            id: anchor.id,
            anchor: anchor,
            creatorId: nil,  // 원격 수신
            timestamp: Date()
        )
        sharedAnchors[anchor.id] = anchorInfo
        
        // 역할 결정 (아직 미정이면 Participant)
        if userRole == .undetermined {
            userRole = .participant
            appState = .viewingModel
            print("👤 Role set to participant")
        }
        
        let position = SIMD3<Float>(
            anchor.originFromAnchorTransform.columns.3.x,
            anchor.originFromAnchorTransform.columns.3.y,
            anchor.originFromAnchorTransform.columns.3.z
        )
        print("📥 Received shared anchor: \(anchor.id)")
        print("   Position: \(position)")
        
        // Notification 발송
        NotificationCenter.default.post(
            name: .worldAnchorAdded,
            object: anchor
        )
    }
    
    /// 앵커 업데이트됨 (Drift 보정)
    private func handleAnchorUpdated(_ anchor: WorldAnchor) {
        guard var anchorInfo = sharedAnchors[anchor.id] else {
            print("⚠️ Updated anchor not found: \(anchor.id)")
            return
        }
        
        // 이전 위치 저장 (드리프트 계산용)
        let oldPosition = SIMD3<Float>(
            anchorInfo.anchor.originFromAnchorTransform.columns.3.x,
            anchorInfo.anchor.originFromAnchorTransform.columns.3.y,
            anchorInfo.anchor.originFromAnchorTransform.columns.3.z
        )
        
        // 새 위치
        let newPosition = SIMD3<Float>(
            anchor.originFromAnchorTransform.columns.3.x,
            anchor.originFromAnchorTransform.columns.3.y,
            anchor.originFromAnchorTransform.columns.3.z
        )
        
        // Drift 크기 계산
        let driftDistance = simd_distance(oldPosition, newPosition)
        
        // SharedAnchorInfo 업데이트
        anchorInfo = anchorInfo.updated(with: anchor, isActive: anchor.isTracked)
        sharedAnchors[anchor.id] = anchorInfo
        
        // Drift 보정 적용 (등록된 Entity가 있으면)
        applyDriftCorrection(for: anchor.id, newTransform: anchor.originFromAnchorTransform)
        
        // 유의미한 드리프트만 로그 (1mm 이상)
        if driftDistance > 0.001 {
            print("📐 Anchor drift detected: \(anchor.id)")
            print("   Drift: \(String(format: "%.4f", driftDistance))m")
            print("   Old: \(oldPosition)")
            print("   New: \(newPosition)")
        }
        
        // Notification 발송
        NotificationCenter.default.post(
            name: .worldAnchorUpdated,
            object: anchor,
            userInfo: ["driftDistance": driftDistance]
        )
    }
    
    /// 앵커 제거됨
    private func handleAnchorRemoved(_ anchor: WorldAnchor) {
        if var anchorInfo = sharedAnchors[anchor.id] {
            anchorInfo = anchorInfo.updated(with: anchor, isActive: false)
            sharedAnchors[anchor.id] = anchorInfo
        }
        
        print("🗑️ Anchor removed: \(anchor.id)")
        
        // Notification 발송
        NotificationCenter.default.post(
            name: .worldAnchorRemoved,
            object: anchor
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let worldAnchorAdded = Notification.Name("worldAnchorAdded")
    static let worldAnchorUpdated = Notification.Name("worldAnchorUpdated")
    static let worldAnchorRemoved = Notification.Name("worldAnchorRemoved")
}