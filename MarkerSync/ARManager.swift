import ARKit
import RealityKit
import GroupActivities
import Combine
import SwiftUI

struct SelectableMeshItem: Identifiable, Equatable {
    let id: String
    let entityKey: String
    let sourceName: String
    let displayName: String
    var isVisible: Bool
}

@MainActor
@Observable
class ARManager {
    // MARK: - App State (UI Observable)
    var appState: AppState = .initializing
    var userRole: UserRole = .undetermined
    var isConnected: Bool = false
    var errorMessage: String?
    
    // MARK: - Tracking State (UI Observable)
    var trackingStatus: TrackingStatus = .notStarted
    var positionHint: PositionHint = .none
    var currentImageAnchor: ImageAnchor?
    
    // MARK: - Shared Anchors
    var sharedAnchors: [UUID: SharedAnchorInfo] = [:]

    // MARK: - Wall Tracking (RoomAnchor)
    var detectedWalls: [DetectedWall] = []
    var selectedWall: DetectedWall?
    var isWallSelectionCompleted: Bool = false
    var isMarkerTrackingActive: Bool = false
    let wallVisualizationRoot = Entity()
    var wallTrackingTask: Task<Void, Never>?
    var roomTracking: RoomTrackingProvider?
    var wallsByID: [UUID: DetectedWall] = [:]
    var wallEntities: [UUID: ModelEntity] = [:]
    var wallArrowEntities: [UUID: Entity] = [:]
    var anchorToWallIDs: [UUID: [UUID]] = [:]

    // MARK: - Tank Customization State
    var selectedTankColor: TankColor = .desertTan
    var selectedTankOptions = TankOptions()
    var tankScale: Float = 0.1
    var selectableMeshItems: [SelectableMeshItem] = []
    var selectableMeshVisibilityByKey: [String: Bool] = [:]

    // MARK: - Sampling State
    var samples: [TransformSample] = []
    var firstDetectionTime: Date?
    var isWorldTrackingStable: Bool = false
    private var worldTrackingStartTime: Date?
    
    // MARK: - Entity Management (Drift 보정용)
    /// WorldAnchor ID와 연결된 Entity 매핑
    var anchorEntities: [UUID: Entity] = [:]
    
    // MARK: - ARKit Components
    var session = ARKitSession()
    var worldTracking: WorldTrackingProvider?
    var imageTracking: ImageTrackingProvider?

    // MARK: - Hand Tracking Components
    var handTracking: HandTrackingProvider?
    var handTrackingTask: Task<Void, Never>?

    // MARK: - Gesture State
    var handsData: HandsData = HandsData()
    var gestureDetectionState: GestureDetectionState = .notTracking
    var lastGestureTime: Date?

    // MARK: - SharePlay Components
    var groupSession: GroupSession<ARCollaborationActivity>?
    var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Task Management (Memory Safety)
    var imageTrackingTask: Task<Void, Never>?
    var worldTrackingTask: Task<Void, Never>?
    var groupSessionTask: Task<Void, Never>?
    private var stabilizationTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    /// 현재 샘플링 진행률
    var samplingProgress: (current: Int, total: Int) {
        (samples.count, SamplingConfig.requiredSamples)
    }
    
    /// 샘플링 완료 여부
    var isSamplingComplete: Bool {
        samples.count >= SamplingConfig.requiredSamples
    }
    
    /// 마지막 샘플의 위치
    var lastSamplePosition: SIMD3<Float>? {
        samples.last?.position
    }

    func setSelectableMeshes(_ items: [SelectableMeshItem]) {
        selectableMeshItems = items
    }

    func setSelectableMeshVisibility(key: String, isVisible: Bool) {
        selectableMeshVisibilityByKey[key] = isVisible

        guard let index = selectableMeshItems.firstIndex(where: { $0.entityKey == key }) else {
            return
        }

        selectableMeshItems[index].isVisible = isVisible
    }

    func visibilityForSelectableMesh(key: String) -> Bool {
        selectableMeshVisibilityByKey[key] ?? true
    }
    
    // MARK: - Lifecycle
    
    /// Initialize ARKit and start observing SharePlay
    func initialize() async {
        appState = .initializing
        trackingStatus = .notStarted
        
        do {
            try await requestAuthorization()
            try await setupProviders()

            // 기존 영구 저장된 anchor 정리 (Host/Guest 모두)
            await cleanupPersistedAnchors()

            observeGroupSessions()
            startWorldAnchorObservation()
            startWallTracking()

            // Start monitoring loops for tracking (providers already running from setupProviders)
            do {
                try await startImageTracking()  // Start the monitoring task
            } catch {
                print("⚠️ Image tracking monitoring unavailable: \(error)")
            }

            do {
                try await startHandTracking()  // Start the monitoring task
            } catch {
                print("⚠️ Hand tracking monitoring unavailable: \(error)")
                // Non-fatal - continue without gesture detection
            }

            appState = .waitingForSharePlay
            print("✅ ARManager initialized successfully")
        } catch let error as ARError {
            appState = .error(error.localizedDescription)
            trackingStatus = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            print("❌ ARManager initialization failed: \(error.localizedDescription)")
        } catch {
            let message = "초기화 실패: \(error.localizedDescription)"
            appState = .error(message)
            trackingStatus = .error(message)
            errorMessage = message
            print("❌ ARManager initialization failed: \(error.localizedDescription)")
        }
    }
    
    /// Request ARKit permissions
    private func requestAuthorization() async throws {
        print("🔐 Requesting ARKit authorization...")
        let authResult = await session.requestAuthorization(for: [.worldSensing])
        
        for (dataType, status) in authResult {
            switch status {
            case .denied:
                print("❌ Authorization denied for: \(dataType)")
                throw ARError.authorizationDenied("\(dataType)")
            case .allowed:
                print("✅ Authorization allowed for: \(dataType)")
            case .notDetermined:
                print("⚠️ Authorization not determined for: \(dataType)")
            @unknown default:
                continue
            }
        }
    }
    
    /// Setup WorldTracking and ImageTracking providers
    func setupProviders() async throws {
        print("🔧 Setting up AR providers...")

        // WorldTracking (shared anchors enabled by default in visionOS)
        worldTracking = WorldTrackingProvider()

        // ImageTracking with reference images
        let refImages = ReferenceImage.loadReferenceImages(inGroupNamed: "AR Resources")
        print("📷 Loaded \(refImages.count) reference images")
        imageTracking = ImageTrackingProvider(referenceImages: refImages)

        // HandTracking for palm-up gesture detection
        handTracking = HandTrackingProvider()
        print("✅ HandTracking provider initialized")

        // RoomTracking for wall detection
        if RoomTrackingProvider.isSupported {
            roomTracking = RoomTrackingProvider()
            print("✅ RoomTracking provider initialized")
        } else {
            roomTracking = nil
            print("⚠️ RoomTracking is not supported on this device")
        }

        // Start session with ALL providers at once
        guard let worldTracking = worldTracking else {
            throw ARError.worldTrackingUnavailable
        }

        // Build provider array with all available providers
        var providers: [any DataProvider] = [worldTracking]
        if let imageTracking = imageTracking {
            providers.append(imageTracking)
        }
        if let handTracking = handTracking {
            providers.append(handTracking)
        }
        if let roomTracking = roomTracking {
            providers.append(roomTracking)
        }

        try await session.run(providers)
        worldTrackingStartTime = Date()

        print("✅ All providers started: WorldTracking, ImageTracking, HandTracking, RoomTracking")

        // World Tracking 안정화 대기 시작
        startWorldTrackingStabilization()
    }
    
    /// World Tracking 안정화 대기
    private func startWorldTrackingStabilization() {
        stabilizationTask?.cancel()
        
        stabilizationTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 안정화 대기 시간
            try? await Task.sleep(for: .seconds(SamplingConfig.stabilizationDelay))
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.isWorldTrackingStable = true
                    print("✅ World Tracking stabilized after \(SamplingConfig.stabilizationDelay)s")
                }
            }
        }
    }
    
    // MARK: - Sampling Management
    
    /// 샘플링 상태 초기화
    func resetSampling() {
        samples.removeAll()
        firstDetectionTime = nil
        trackingStatus = .searching
        positionHint = .none
        currentImageAnchor = nil
        print("🔄 Sampling state reset")
    }
    
    /// 새 샘플 추가
    /// - Returns: 샘플 추가 성공 여부
    @discardableResult
    func addSample(from transform: simd_float4x4) -> Bool {
        let sample = TransformSample(transform: transform, timestamp: Date())
        
        // 유효성 검증
        guard sample.isValid else {
            print("⚠️ Invalid sample rejected - distance: \(sample.distanceFromOrigin), height: \(sample.height)")
            
            // 위치 힌트 업데이트
            positionHint = PositionHint.hint(for: sample)
            return false
        }
        
        // 첫 감지 시간 기록
        if firstDetectionTime == nil {
            firstDetectionTime = Date()
            print("📍 First detection recorded")
        }
        
        // 샘플 간 최소 간격 확인
        if let lastSample = samples.last {
            let elapsed = sample.timestamp.timeIntervalSince(lastSample.timestamp)
            if elapsed < SamplingConfig.sampleInterval {
                return false
            }
        }
        
        samples.append(sample)
        positionHint = .holdStill
        
        // 상태 업데이트
        trackingStatus = .sampling(
            current: samples.count,
            total: SamplingConfig.requiredSamples
        )
        
        print("📊 Sample \(samples.count)/\(SamplingConfig.requiredSamples) added - position: \(sample.position)")
        
        return true
    }
    
    /// 샘플링 결과 계산 및 검증
    func finalizeSampling() -> Result<SampleCollectionResult, ARError> {
        guard isSamplingComplete else {
            return .failure(.samplingTimeout)
        }
        
        guard let result = SampleCollectionResult.calculate(from: samples) else {
            return .failure(.invalidTransform)
        }
        
        // 안정성 검증
        guard result.isStable else {
            print("⚠️ Position unstable - variance: \(result.positionVariance)")
            return .failure(.positionUnstable(variance: result.positionVariance))
        }
        
        trackingStatus = .found
        print("✅ Sampling complete - variance: \(result.positionVariance)m")
        
        return .success(result)
    }
    
    // MARK: - Entity Management (Drift 보정)
    
    /// Anchor와 Entity 연결 등록
    func registerEntity(_ entity: Entity, for anchorId: UUID) {
        anchorEntities[anchorId] = entity
        print("🔗 Entity registered for anchor: \(anchorId)")
    }
    
    /// Anchor와 연결된 Entity 해제
    func unregisterEntity(for anchorId: UUID) {
        anchorEntities.removeValue(forKey: anchorId)
        print("🔓 Entity unregistered for anchor: \(anchorId)")
    }
    
    /// Drift 보정 - Anchor 업데이트 시 Entity Transform 자동 조정
    func applyDriftCorrection(for anchorId: UUID, newTransform: simd_float4x4) {
        guard let entity = anchorEntities[anchorId] else {
            return
        }
        
        let oldPosition = entity.position
        entity.transform = Transform(matrix: newTransform)
        let newPosition = entity.position
        
        let drift = simd_distance(oldPosition, newPosition)
        if drift > 0.001 { // 1mm 이상 변화 시 로그
            print("📐 Drift correction applied for anchor \(anchorId): \(String(format: "%.3f", drift))m")
        }
    }
    
    // MARK: - Cleanup
    
    /// Cleanup resources
    func cleanup() async {
        print("🧹 Cleaning up ARManager resources...")
        
        // Task 취소
        imageTrackingTask?.cancel()
        worldTrackingTask?.cancel()
        groupSessionTask?.cancel()
        stabilizationTask?.cancel()
        handTrackingTask?.cancel()
        wallTrackingTask?.cancel()

        imageTrackingTask = nil
        worldTrackingTask = nil
        groupSessionTask = nil
        stabilizationTask = nil
        handTrackingTask = nil
        wallTrackingTask = nil
        
        // SharePlay 정리
        groupSession?.leave()
        groupSession = nil
        subscriptions.removeAll()
        
        // 상태 초기화
        sharedAnchors.removeAll()
        anchorEntities.removeAll()
        isConnected = false
        detectedWalls.removeAll()
        wallsByID.removeAll()
        wallEntities.values.forEach { $0.removeFromParent() }
        wallArrowEntities.values.forEach { $0.removeFromParent() }
        wallEntities.removeAll()
        wallArrowEntities.removeAll()
        anchorToWallIDs.removeAll()
        selectedWall = nil
        isWallSelectionCompleted = false
        isMarkerTrackingActive = false
        tankScale = 0.1
        
        // 샘플링 상태 초기화
        resetSampling()
        isWorldTrackingStable = false
        worldTrackingStartTime = nil

        // 제스처 상태 초기화
        gestureDetectionState = .notTracking

        print("✅ ARManager cleanup complete")
    }
    
    /// Retry after error
    func retry() async {
        print("🔄 Retrying ARManager initialization...")
        await cleanup()
        await initialize()
    }
}

// MARK: - Debug Helpers

extension ARManager {
    /// 현재 상태 디버그 출력
    func printDebugState() {
        print("""
        ========== ARManager State ==========
        App State: \(appState)
        Tracking Status: \(trackingStatus)
        User Role: \(userRole)
        Is Connected: \(isConnected)
        World Tracking Stable: \(isWorldTrackingStable)
        Samples: \(samples.count)/\(SamplingConfig.requiredSamples)
        Shared Anchors: \(sharedAnchors.count)
        Registered Entities: \(anchorEntities.count)
        =====================================
        """)
    }
}
