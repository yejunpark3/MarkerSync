//
//  TankModels.swift
//  MarkerSync
//
//  Tank color and option models
//

import SwiftUI
import Foundation

enum TankColor: String, CaseIterable, Codable {
    case desertTan = "사막 황갈색"
    case forestGreen = "삼림 녹색"
    case urbanGray = "도심 회색"
    case winterWhite = "동계 백색"

    var uiColor: Color {
        switch self {
        case .desertTan:
            return Color(red: 0.76, green: 0.60, blue: 0.42)
        case .forestGreen:
            return Color(red: 0.13, green: 0.37, blue: 0.31)
        case .urbanGray:
            return Color(red: 0.42, green: 0.45, blue: 0.48)
        case .winterWhite:
            return Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }

    var displayName: String {
        rawValue
    }
}

struct TankOptions: Codable {
    var aps: Bool = false
    var smokeDischarger: Bool = true
    var minePlow: Bool = false
    var additionalArmor: Bool = false
}
