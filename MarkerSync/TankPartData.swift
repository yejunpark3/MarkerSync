//
//  TankPartData.swift
//  MarkerSync
//
//  K2 Tank part definitions for billboard annotations.
//  All positions are in the LOCAL coordinate space of "k2_tank_model"
//  (the USDA scene entity root), BEFORE tankScale is applied.
//  Tune values after first device run.
//

import Foundation
import simd

/// A single annotatable part on the K2 tank model.
struct TankPart: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let specs: [(label: String, value: String)]
    /// The point ON the model surface in k2_tank_model local (unscaled) space.
    let localPosition: SIMD3<Float>
    /// Displacement from localPosition to where the billboard card should float.
    let billboardOffset: SIMD3<Float>

    /// The billboard's position in model-local space.
    var billboardPosition: SIMD3<Float> {
        localPosition + billboardOffset
    }
}

/// Single source of truth for all annotatable parts.
/// Positions are in k2_tank_model's local coordinate space (before tankScale).
/// The USDA scene has Leopard_2A6_Free scaled at 0.0025, giving a model
/// roughly 0.7m tall and 1.0m long in this local space.
enum TankPartRegistry {
    static let all: [TankPart] = [
        TankPart(
            id: "turret",
            displayName: "포탑",
            description: "360도 회전 가능한 포탑. 120mm 활강포를 탑재하며 자동 장전 시스템을 갖추고 있습니다.",
            specs: [("회전 속도", "40°/s"), ("장갑", "복합 장갑")],
            localPosition: SIMD3<Float>(0, 0.50, 0),
            billboardOffset: SIMD3<Float>(0.6, 0.3, 0)
        ),
        TankPart(
            id: "mainGun",
            displayName: "120mm 활강포",
            description: "CN08 120mm 활강포. APFSDS 및 다목적 성형작약탄을 발사합니다.",
            specs: [("구경", "120mm"), ("유효사거리", "약 4km")],
            localPosition: SIMD3<Float>(0, 0.48, 0.5),
            billboardOffset: SIMD3<Float>(0.5, 0.35, 0.3)
        ),
        TankPart(
            id: "hull",
            displayName: "차체",
            description: "복합장갑과 반응장갑으로 보호되는 K2의 주 차체. 승무원 3명이 탑승합니다.",
            specs: [("전장", "10.8m"), ("중량", "55톤")],
            localPosition: SIMD3<Float>(0, 0.20, 0),
            billboardOffset: SIMD3<Float>(-0.7, 0.2, 0)
        ),
        TankPart(
            id: "tracks",
            displayName: "궤도",
            description: "고무 패드 장착 강철 궤도. 험지 주파 성능 최적화 설계.",
            specs: [("접지압", "0.92 kg/cm²"), ("최고속도", "70 km/h")],
            localPosition: SIMD3<Float>(0.3, 0.05, 0),
            billboardOffset: SIMD3<Float>(0.6, -0.1, 0)
        ),
        TankPart(
            id: "engine",
            displayName: "파워팩",
            description: "두산 인프라코어 DV27K 1500마력 디젤 엔진과 자동변속기를 결합한 파워팩.",
            specs: [("출력", "1,500 HP"), ("변속기", "자동 6단")],
            localPosition: SIMD3<Float>(0, 0.20, -0.4),
            billboardOffset: SIMD3<Float>(-0.6, 0.3, -0.3)
        ),
    ]
}
