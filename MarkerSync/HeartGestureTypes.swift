import Foundation
import ARKit

// MARK: - Heart Gesture Configuration

/// 하트 제스처 감지 설정
enum HeartGestureConfig {
    /// 손가락 간격 임계값 (4cm, HappyBeam 기준)
    static let fingerDistanceThreshold: Float = 0.04

    /// 제스처 감지 스무딩 윈도우 (프레임 수)
    static let smoothingWindow: Int = 24

    /// 로그 출력 간격 (초) - 로그 스팸 방지
    static let logThrottleInterval: TimeInterval = 0.5
}

// MARK: - Gesture Detection State

/// 제스처 감지 추적 상태
enum GestureDetectionState: Equatable {
    case notTracking    // 추적 비활성화
    case searching      // 양손 탐색 중
    case detected       // 제스처 감지됨

    var displayText: String {
        switch self {
        case .notTracking:
            return "제스처 추적 비활성화"
        case .searching:
            return "손 탐색 중..."
        case .detected:
            return "❤️ 하트 제스처 감지됨"
        }
    }
}

// MARK: - Hands Data

/// 양손 anchor 저장 구조체
struct HandsData {
    var left: HandAnchor?
    var right: HandAnchor?

    /// 양손이 모두 추적되고 있는지 확인
    var bothHandsTracked: Bool {
        guard let left = left, let right = right else {
            return false
        }
        return left.isTracked && right.isTracked
    }

    /// 초기화
    init() {
        self.left = nil
        self.right = nil
    }
}
