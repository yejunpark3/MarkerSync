import ARKit
import Foundation

extension ARManager {
    // MARK: - Image Tracking (Phase 2-3)
    
    /// Start detecting markers
    /// Phase 2: 권한 및 준비 → Phase 3: 마커 탐색
    func startImageTracking() async throws {
        guard let imageTracking = imageTracking else {
            throw ARError.imageTrackingUnavailable
        }

        // 샘플링 상태 초기화
        resetSampling()
        trackingStatus = .searching

        imageTrackingTask?.cancel()

        print("🔍 Starting image tracking...")

        // Note: ImageTracking provider is already running from setupProviders()
        // No need to call session.run() again

        // World Tracking 안정화 대기
        trackingStatus = .stabilizing
        print("⏳ Waiting for World Tracking stabilization...")

        try await waitForWorldTrackingStabilization()

        trackingStatus = .searching
        print("✅ World Tracking stable, searching for marker...")

        // Anchor 업데이트 모니터링 시작
        imageTrackingTask = Task { [weak self] in
            guard let self = self else { return }

            for await update in imageTracking.anchorUpdates {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.handleImageAnchorUpdate(update)
                }
            }
        }
    }
    
    /// World Tracking 안정화 대기 (Phase 2)
    private func waitForWorldTrackingStabilization() async throws {
        // 이미 안정화되어 있으면 스킵
        if isWorldTrackingStable {
            print("✅ World Tracking already stable")
            return
        }
        
        // 최대 2초까지 대기
        let timeout: TimeInterval = 2.0
        let startTime = Date()
        
        while !isWorldTrackingStable {
            if Date().timeIntervalSince(startTime) > timeout {
                // 타임아웃이어도 계속 진행 (경고만 출력)
                print("⚠️ World Tracking stabilization timeout, proceeding anyway")
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    
    /// Image Anchor 업데이트 처리 (Phase 4-6)
    private func handleImageAnchorUpdate(_ update: AnchorUpdate<ImageAnchor>) {
        let anchor = update.anchor
        
        switch update.event {
        case .added, .updated:
            if anchor.isTracked {
                processTrackedAnchor(anchor)
            } else {
                handleTrackingLost()
            }
            
        case .removed:
            handleTrackingLost()
        }
        
        // Notification 전달 (기존 MarkerTrackingView 호환)
        NotificationCenter.default.post(
            name: .imageAnchorDetected,
            object: anchor
        )
    }
    
    /// 추적 중인 마커 처리 (Phase 4-6)
    private func processTrackedAnchor(_ anchor: ImageAnchor) {
        // 이미 완료된 상태면 처리하지 않음
        guard trackingStatus != .found && trackingStatus != .anchored else {
            return
        }

        currentImageAnchor = anchor
        let transform = anchor.originFromAnchorTransform
        
        // Phase 4: 위치 합리성 검증
        let sample = TransformSample(transform: transform, timestamp: Date())
        
        guard sample.isValid else {
            // 위치가 범위를 벗어남 - 힌트 제공
            positionHint = PositionHint.hint(for: sample)
            
            if sample.distanceFromOrigin > SamplingConfig.maxDistanceFromOrigin {
                print("⚠️ Marker too far: \(String(format: "%.2f", sample.distanceFromOrigin))m")
            }
            if sample.height < SamplingConfig.minHeight || sample.height > SamplingConfig.maxHeight {
                print("⚠️ Marker height out of range: \(String(format: "%.2f", sample.height))m")
            }
            return
        }
        
        // Phase 5: 첫 감지 후 안정화 대기
        if firstDetectionTime == nil {
            firstDetectionTime = Date()
            print("📍 Marker first detected at position: \(sample.position)")
            print("   Height: \(String(format: "%.2f", sample.height))m")
            print("   Distance from origin: \(String(format: "%.2f", sample.distanceFromOrigin))m")
        }
        
        // 첫 감지 후 최소 대기 시간 확인
        guard let firstTime = firstDetectionTime,
              Date().timeIntervalSince(firstTime) >= SamplingConfig.sampleInterval else {
            return
        }
        
        // Phase 5: 샘플 수집
        let added = addSample(from: transform)
        
        if added {
            print("📊 Sample collected: \(samples.count)/\(SamplingConfig.requiredSamples)")
            
            // Phase 6: 샘플링 완료 확인
            if isSamplingComplete {
                evaluateSamplingResult()
            }
        }
    }
    
    /// 샘플링 결과 평가 (Phase 6)
    private func evaluateSamplingResult() {
        let result = finalizeSampling()
        
        switch result {
        case .success(let collectionResult):
            print("✅ STABLE MARKER POSITION CONFIRMED!")
            print("   Average position: \(SIMD3<Float>(collectionResult.averageTransform.columns.3.x, collectionResult.averageTransform.columns.3.y, collectionResult.averageTransform.columns.3.z))")
            print("   Position variance: \(String(format: "%.4f", collectionResult.positionVariance))m")
            
            trackingStatus = .found
            positionHint = .none
            
        case .failure(let error):
            print("⚠️ Sampling failed: \(error.localizedDescription)")
            
            if case .positionUnstable(let variance) = error {
                print("   Variance too high: \(String(format: "%.4f", variance))m (max: \(SamplingConfig.maxPositionVariance)m)")
                print("   Restarting sampling...")
                
                // 분산이 너무 크면 샘플링 재시작
                resetSampling()
                trackingStatus = .searching
                positionHint = .holdStill
            }
        }
    }
    
    /// 추적 상실 처리
    private func handleTrackingLost() {
        currentImageAnchor = nil
        
        // 샘플링 중이었다면 경고
        if !samples.isEmpty && !isSamplingComplete {
            print("⚠️ Tracking lost during sampling (\(samples.count)/\(SamplingConfig.requiredSamples))")
        }
        
        // Found 상태가 아니면 searching으로 복귀
        if trackingStatus != .found && trackingStatus != .anchored {
            // 샘플 유지 - 다시 마커가 보이면 이어서 수집
            if case .sampling = trackingStatus {
                print("⏸️ Sampling paused, waiting for marker...")
            }
        }
    }
    
    // MARK: - Stop Image Tracking
    
    /// Stop image tracking (Phase 7 이후)
    func stopImageTracking() {
        print("🛑 Stopping image tracking...")
        
        imageTrackingTask?.cancel()
        imageTrackingTask = nil
        currentImageAnchor = nil
        
        Task {
            if let worldTracking = worldTracking {
                try? await session.run([worldTracking])
                print("✅ Session now running WorldTracking only")
            }
        }
    }

    // MARK: - Cleanup Persisted Anchors

    /// 앱 시작 시 기존 영구 저장된 World Anchor 모두 삭제
    func cleanupPersistedAnchors() async {
        guard let worldTracking = worldTracking else {
            print("⚠️ WorldTracking not available for cleanup")
            return
        }
        
        print("🧹 Cleaning up persisted anchors...")
        
        var removedCount = 0
        
        // 타임아웃이 있는 Task로 감싸기
        let cleanupTask = Task {
            for await update in worldTracking.anchorUpdates {
                if Task.isCancelled { break }
                
                if update.event == .added {
                    do {
                        try await worldTracking.removeAnchor(forID: update.anchor.id)
                        removedCount += 1
                        print("🗑️ Removed persisted anchor: \(update.anchor.id)")
                    } catch {
                        print("❌ Failed to remove anchor \(update.anchor.id): \(error)")
                    }
                }
            }
        }
        
        // 1초 후 강제 종료
        try? await Task.sleep(for: .seconds(1))
        cleanupTask.cancel()
        
        // sharedAnchors 딕셔너리도 초기화
        sharedAnchors.removeAll()
        
        if removedCount > 0 {
            print("🧹 Cleanup complete: removed \(removedCount) anchors")
        } else {
            print("✅ No persisted anchors to clean up")
        }
    }
    
    // MARK: - Create World Anchor (Phase 7)
    
    /// 샘플링 결과로부터 WorldAnchor 생성
    func createWorldAnchorFromSamples() async throws -> WorldAnchor {
        // 샘플링 완료 확인
        guard isSamplingComplete else {
            throw ARError.samplingTimeout
        }
        
        // 결과 계산
        guard let result = SampleCollectionResult.calculate(from: samples) else {
            throw ARError.invalidTransform
        }
        
        // 안정성 검증
        guard result.isStable else {
            throw ARError.positionUnstable(variance: result.positionVariance)
        }

        guard let worldTracking = worldTracking else {
            throw ARError.worldTrackingUnavailable
        }
        
        // 기존 anchor 정리 (새로 만들기 전에)
        await cleanupPersistedAnchors()
        
        // WorldAnchor 생성
        let worldAnchor = WorldAnchor(originFromAnchorTransform: result.averageTransform)
        
        print("🎯 Creating WorldAnchor at averaged position...")
        try await worldTracking.addAnchor(worldAnchor)
        
        // 상태 업데이트
        let anchorInfo = SharedAnchorInfo(
            id: worldAnchor.id,
            anchor: worldAnchor,
            creatorId: UUID().uuidString,
            timestamp: Date()
        )
        
        sharedAnchors[worldAnchor.id] = anchorInfo
        userRole = .host
        trackingStatus = .anchored
        
        print("✅ WorldAnchor created: \(worldAnchor.id)")
        print("   Position: \(SIMD3<Float>(result.averageTransform.columns.3.x, result.averageTransform.columns.3.y, result.averageTransform.columns.3.z))")
        
        return worldAnchor
    }
    
    /// 기존 호환용 - ImageAnchor로부터 직접 WorldAnchor 생성 (샘플링 우회)
    func createSharedWorldAnchor(from imageAnchor: ImageAnchor) async throws {
        guard imageAnchor.isTracked else {
            throw ARError.anchorNotTracked
        }
        
        let transform = imageAnchor.originFromAnchorTransform
        
        // Transform 검증
        let sample = TransformSample(transform: transform, timestamp: Date())
        guard sample.isValid else {
            if sample.distanceFromOrigin > SamplingConfig.maxDistanceFromOrigin {
                throw ARError.positionOutOfRange(distance: sample.distanceFromOrigin)
            }
            if sample.height < SamplingConfig.minHeight || sample.height > SamplingConfig.maxHeight {
                throw ARError.heightOutOfRange(height: sample.height)
            }
            throw ARError.invalidTransform
        }
        
        let worldAnchor = WorldAnchor(originFromAnchorTransform: transform)
        
        guard let worldTracking = worldTracking else {
            throw ARError.worldTrackingUnavailable
        }
        
        try await worldTracking.addAnchor(worldAnchor)
        
        let anchorInfo = SharedAnchorInfo(
            id: worldAnchor.id,
            anchor: worldAnchor,
            creatorId: UUID().uuidString,
            timestamp: Date()
        )
        
        sharedAnchors[worldAnchor.id] = anchorInfo
        userRole = .host
        trackingStatus = .anchored
        
        print("✅ Shared WorldAnchor created (direct): \(worldAnchor.id)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let imageAnchorDetected = Notification.Name("imageAnchorDetected")
    static let samplingProgressUpdated = Notification.Name("samplingProgressUpdated")
    static let samplingCompleted = Notification.Name("samplingCompleted")
}
