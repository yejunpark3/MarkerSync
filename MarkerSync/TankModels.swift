//
//  TankModels.swift
//  MarkerSync
//
//  Tank color and option models
//

import SwiftUI
import Foundation

enum TankColor: String, CaseIterable, Codable, Sendable, Hashable {
    case red = "Red"
    case blue = "Blue"

    var uiColor: Color {
        switch self {
        case .red:
            return Color.red
        case .blue:
            return Color.blue
        }
    }

    var displayName: String {
        switch self {
        case .red:
            return "빨강"
        case .blue:
            return "파랑"
        }
    }
}

struct TankOptions: Codable, Sendable, Hashable {
    var aps: Bool = false
    var smokeDischarger: Bool = true
    var minePlow: Bool = false
    var additionalArmor: Bool = false
}

enum TankScalePreset: String, CaseIterable {
    case small
    case medium
    case large

    var scale: Float {
        switch self {
        case .small:
            return 0.1
        case .medium:
            return 0.5
        case .large:
            return 1.0
        }
    }

    var label: String {
        switch self {
        case .small:
            return "소형"
        case .medium:
            return "중형"
        case .large:
            return "대형"
        }
    }

    var iconName: String {
        switch self {
        case .small:
            return "shippingbox"
        case .medium:
            return "cube"
        case .large:
            return "cube.fill"
        }
    }
}

enum TankScaleConfig {
    static let minScale: Float = 0.05
    static let maxScale: Float = 1.5
    static let referenceLengthMeters: Float = 10.8
    static let animationDuration: TimeInterval = 0.2

    static func estimatedSize(_ scale: Float) -> String {
        let clampedScale = min(max(scale, minScale), maxScale)
        let meters = clampedScale * referenceLengthMeters

        if meters >= 1.0 {
            return String(format: "%.1fm", meters)
        }

        return "\(Int((meters * 100).rounded()))cm"
    }
}

enum TankRotationPreset: Float, CaseIterable {
    case zero = 0
    case quarter = 90
    case half = 180
    case threeQuarter = 270

    var label: String {
        switch self {
        case .zero: return "0°"
        case .quarter: return "90°"
        case .half: return "180°"
        case .threeQuarter: return "270°"
        }
    }

    var iconName: String {
        switch self {
        case .zero: return "arrow.up"
        case .quarter: return "arrow.right"
        case .half: return "arrow.down"
        case .threeQuarter: return "arrow.left"
        }
    }
}

enum TankRotationConfig {
    static let minDegrees: Float = 0
    static let maxDegrees: Float = 359
    static let animationDuration: TimeInterval = 0.3
}
