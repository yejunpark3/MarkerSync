import Foundation
import ARKit

// MARK: - Sampling Configuration

/// 샘플링 설정 상수
enum SamplingConfig {
    static let requiredSamples = 5                      // 필요한 샘플 수
    static let stabilizationDelay: TimeInterval = 0.5   // World Tracking 안정화 대기 시간
    static let sampleInterval: TimeInterval = 0.2       // 샘플 간 최소 간격
    static let maxPositionVariance: Float = 0.1         // 최대 허용 분산 (10cm)
    static let maxDistanceFromOrigin: Float = 10.0      // 원점에서 최대 거리
    static let minHeight: Float = -1.0                  // 최소 높이
    static let maxHeight: Float = 3.0                   // 최대 높이
}

// MARK: - Tracking Status

/// 마커 추적 상태 (UI 표시용)
enum TrackingStatus: Equatable {
    case notStarted                             // 초기 대기 상태
    case searching                              // 마커 탐색 중
    case stabilizing                            // World Tracking 안정화 대기
    case sampling(current: Int, total: Int)     // 위치 샘플링 진행 중
    case found                                  // 안정된 위치 확정
    case anchored                               // WorldAnchor 생성 완료
    case error(String)                          // 오류 발생
    
    var displayText: String {
        switch self {
        case .notStarted:
            return "준비 중..."
        case .searching:
            return "마커를 찾는 중..."
        case .stabilizing:
            return "위치 안정화 중..."
        case .sampling(let current, let total):
            return "위치 확인 중 \(current)/\(total)"
        case .found:
            return "위치 확정됨"
        case .anchored:
            return "앵커 생성 완료"
        case .error(let message):
            return "오류: \(message)"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .searching, .stabilizing, .sampling:
            return true
        default:
            return false
        }
    }
    
    var canConfirm: Bool {
        self == .found
    }
}

// MARK: - Transform Sample

/// Transform 샘플 데이터
struct TransformSample {
    let transform: simd_float4x4
    let timestamp: Date
    
    /// 위치 벡터 추출
    var position: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    /// 높이 (Y축)
    var height: Float {
        transform.columns.3.y
    }
    
    /// 원점으로부터의 거리
    var distanceFromOrigin: Float {
        simd_length(position)
    }
    
    /// 위치 유효성 검증
    var isValid: Bool {
        // 거리 검증
        guard distanceFromOrigin <= SamplingConfig.maxDistanceFromOrigin else {
            return false
        }
        // 높이 검증
        guard height >= SamplingConfig.minHeight && height <= SamplingConfig.maxHeight else {
            return false
        }
        // Transform 행렬 유효성
        let det = simd_determinant(transform)
        guard abs(det) > 0.001 else {
            return false
        }
        // NaN/Inf 검증
        for i in 0..<4 {
            for j in 0..<4 {
                guard transform[i][j].isFinite else {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - Sample Collection

/// 샘플 수집 결과
struct SampleCollectionResult {
    let samples: [TransformSample]
    let averageTransform: simd_float4x4
    let positionVariance: Float
    let isStable: Bool
    
    /// 샘플들로부터 결과 계산
    static func calculate(from samples: [TransformSample]) -> SampleCollectionResult? {
        guard samples.count >= SamplingConfig.requiredSamples else {
            return nil
        }
        
        // 평균 위치 계산
        var avgPosition = SIMD3<Float>.zero
        for sample in samples {
            avgPosition += sample.position
        }
        avgPosition /= Float(samples.count)
        
        // 분산 계산
        var variance: Float = 0
        for sample in samples {
            let diff = sample.position - avgPosition
            variance += simd_length_squared(diff)
        }
        variance /= Float(samples.count)
        let stdDev = sqrt(variance)
        
        // 평균 Transform 생성 (위치만 평균, 회전은 마지막 샘플 사용)
        var avgTransform = samples.last!.transform
        avgTransform.columns.3 = SIMD4(avgPosition.x, avgPosition.y, avgPosition.z, 1.0)
        
        let isStable = stdDev < SamplingConfig.maxPositionVariance
        
        return SampleCollectionResult(
            samples: samples,
            averageTransform: avgTransform,
            positionVariance: stdDev,
            isStable: isStable
        )
    }
}

// MARK: - AR Errors

/// AR 관련 오류
enum ARError: LocalizedError {
    case referenceImageLoadFailed
    case sessionInitializationFailed(String)
    case worldAnchorCreationFailed(String)
    case imageTrackingUnavailable
    case worldTrackingUnavailable
    case authorizationDenied(String)
    case invalidTransform
    case anchorNotTracked
    case noActiveSharePlaySession
    case positionUnstable(variance: Float)
    case positionOutOfRange(distance: Float)
    case heightOutOfRange(height: Float)
    case samplingTimeout
    
    var errorDescription: String? {
        switch self {
        case .referenceImageLoadFailed:
            return "마커 이미지를 로드할 수 없습니다"
        case .sessionInitializationFailed(let message):
            return "세션 초기화 실패: \(message)"
        case .worldAnchorCreationFailed(let message):
            return "WorldAnchor 생성 실패: \(message)"
        case .imageTrackingUnavailable:
            return "이미지 트래킹을 사용할 수 없습니다"
        case .worldTrackingUnavailable:
            return "월드 트래킹을 사용할 수 없습니다"
        case .authorizationDenied(let permission):
            return "\(permission) 권한이 거부되었습니다"
        case .invalidTransform:
            return "변환 행렬이 유효하지 않습니다"
        case .anchorNotTracked:
            return "앵커가 추적되지 않고 있습니다"
        case .noActiveSharePlaySession:
            return "활성화된 SharePlay 세션이 없습니다"
        case .positionUnstable(let variance):
            return String(format: "위치가 불안정합니다 (분산: %.2fm)", variance)
        case .positionOutOfRange(let distance):
            return String(format: "마커가 너무 멉니다 (거리: %.1fm)", distance)
        case .heightOutOfRange(let height):
            return String(format: "마커 높이가 범위를 벗어났습니다 (%.1fm)", height)
        case .samplingTimeout:
            return "위치 샘플링 시간이 초과되었습니다"
        }
    }
}

// MARK: - App State

/// 앱 전체 상태 머신
enum AppState: Equatable {
    case initializing           // ARKit 설정 및 권한 요청
    case waitingForSharePlay    // SharePlay 시작 대기
    case waitingForHost         // 세션 참가 완료, Host 대기
    case hostMode               // Host 모드 - 마커 스캔 중
    case viewingModel           // 3D 모델 표시 중
    case error(String)          // 오류 상태
}

// MARK: - User Role

/// 협업 세션에서의 사용자 역할
enum UserRole: Equatable {
    case undetermined   // 아직 결정되지 않음
    case host           // 마커 스캔으로 앵커 생성
    case participant    // 다른 사용자로부터 앵커 수신
}

// MARK: - Shared Anchor Info

/// 공유 앵커 메타데이터
struct SharedAnchorInfo: Identifiable, Equatable {
    let id: UUID
    let anchor: WorldAnchor
    let creatorId: String?      // nil이면 원격에서 수신
    let timestamp: Date
    var isActive: Bool = true   // 추적 상실 시 false
    var lastUpdateTime: Date?   // 마지막 업데이트 시간
    
    static func == (lhs: SharedAnchorInfo, rhs: SharedAnchorInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    /// 업데이트된 복사본 생성
    func updated(with anchor: WorldAnchor, isActive: Bool) -> SharedAnchorInfo {
        var copy = self
        copy.isActive = isActive
        copy.lastUpdateTime = Date()
        return SharedAnchorInfo(
            id: self.id,
            anchor: anchor,
            creatorId: self.creatorId,
            timestamp: self.timestamp,
            isActive: isActive,
            lastUpdateTime: Date()
        )
    }
}

// MARK: - Position Hint

/// 사용자에게 보여줄 위치 힌트
enum PositionHint {
    case none
    case lookDown           // 아래를 보세요
    case lookUp             // 위를 보세요
    case moveCloser         // 더 가까이 가세요
    case moveBack           // 뒤로 물러나세요
    case holdStill          // 가만히 계세요
    
    var message: String {
        switch self {
        case .none:
            return ""
        case .lookDown:
            return "⬇️ 아래쪽을 확인하세요"
        case .lookUp:
            return "⬆️ 위쪽을 확인하세요"
        case .moveCloser:
            return "📍 마커에 더 가까이 가세요"
        case .moveBack:
            return "↩️ 조금 뒤로 물러나세요"
        case .holdStill:
            return "✋ 잠시 가만히 계세요"
        }
    }
    
    /// 위치 기반 힌트 생성
    static func hint(for sample: TransformSample, userDistance: Float? = nil) -> PositionHint {
        // 높이 기반 힌트
        if sample.height < SamplingConfig.minHeight + 0.5 {
            return .lookDown
        }
        if sample.height > SamplingConfig.maxHeight - 0.5 {
            return .lookUp
        }
        
        // 거리 기반 힌트
        if let distance = userDistance {
            if distance > 3.0 {
                return .moveCloser
            }
            if distance < 0.5 {
                return .moveBack
            }
        }
        
        return .none
    }
}