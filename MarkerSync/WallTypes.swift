import Foundation
import ARKit

struct DetectedWall: Identifiable, Equatable {
    let id: UUID
    let normal: SIMD3<Float>
    let position: SIMD3<Float>
    let distance: Float
    let sourceAnchorID: UUID
}

extension DetectedWall {
    var formattedPosition: String {
        String(format: "(%.2f, %.2f, %.2f)", position.x, position.y, position.z)
    }

    var formattedNormal: String {
        String(format: "(%.2f, %.2f, %.2f)", normal.x, normal.y, normal.z)
    }
}
