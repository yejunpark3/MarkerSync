import Foundation
import ARKit

/// AR-specific errors
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
        }
    }
}

/// App state machine
enum AppState: Equatable {
    case initializing           // ARKit setup, authorization
    case waitingForSharePlay    // Ready to start SharePlay
    case waitingForHost         // In session, no anchors yet
    case hostMode               // Scanning for marker
    case viewingModel           // Displaying 3D model
    case error(String)          // Error state with message
}

/// User role in collaboration
enum UserRole: Equatable {
    case undetermined  // Not yet decided
    case host          // Created anchor by scanning marker
    case participant   // Received anchor from another user
}

/// Metadata for shared anchors
struct SharedAnchorInfo: Identifiable, Equatable {
    let id: UUID
    let anchor: WorldAnchor
    let creatorId: String?      // nil if received from remote
    let timestamp: Date
    var isActive: Bool = true   // false if tracking lost

    static func == (lhs: SharedAnchorInfo, rhs: SharedAnchorInfo) -> Bool {
        lhs.id == rhs.id
    }
}
