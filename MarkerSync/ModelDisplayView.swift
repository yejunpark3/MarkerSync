import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ModelDisplayView: View {
    @Environment(ARManager.self) var arManager
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var modelEntities: [UUID: Entity] = [:]
    @State private var selectedAnchorId: UUID?
    @State private var connectionLost = false

    var body: some View {
        ZStack {
            RealityView { content in
                // Initial setup
            } update: { content in
                updateModels(in: content)
            }

            // Connection status
            if connectionLost {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("연결이 끊어졌습니다. 재연결 시도 중...")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.bottom, 50)
                }
            }

            // Anchor selector (if multiple)
            if arManager.sharedAnchors.count > 1 {
                VStack {
                    Text("앵커 선택")
                        .font(.headline)
                    ForEach(Array(arManager.sharedAnchors.values)) { anchorInfo in
                        Button(action: {
                            selectedAnchorId = anchorInfo.id
                        }) {
                            HStack {
                                Text("앵커 \(anchorInfo.id.uuidString.prefix(8))...")
                                if anchorInfo.id == selectedAnchorId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .position(x: 200, y: 100)
            }
        }
        .task {
            print("📍 ModelDisplayView task started")
            print("📍 SharedAnchors count: \(arManager.sharedAnchors.count)")
            if let firstAnchor = arManager.sharedAnchors.values.first {
                selectedAnchorId = firstAnchor.id
                print("📍 Selected anchor: \(firstAnchor.id)")
            } else {
                print("⚠️ No anchors available")
            }
        }
        .onChange(of: arManager.isConnected) { _, isConnected in
            connectionLost = !isConnected
        }
        .onChange(of: arManager.sharedAnchors) { _, anchors in
            print("📍 SharedAnchors changed, count: \(anchors.count)")
            if selectedAnchorId == nil, let first = anchors.values.first {
                selectedAnchorId = first.id
                print("📍 Selected first anchor: \(first.id)")
            }
        }
        .onDisappear {
            modelEntities.removeAll()
        }
    }

    func updateModels(in content: RealityViewContent) {
        // 앵커가 없으면 모든 모델 제거
        guard let anchorId = selectedAnchorId,
              let anchorInfo = arManager.sharedAnchors[anchorId],
              anchorInfo.isActive else {
            // State 수정을 Task로 감싸서 경고 방지
            Task { @MainActor in
                for (_, entity) in modelEntities {
                    content.remove(entity)
                }
                modelEntities.removeAll()
                print("⚠️ No active anchor, models removed")
            }
            return
        }

        print("🎯 updateModels called - anchorId: \(anchorId), isActive: \(anchorInfo.isActive)")

        // 이미 모델이 있으면 transform만 업데이트 (state 수정 없음)
        if let existingModel = modelEntities[anchorId] {
            existingModel.transform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)
            print("✅ Model transform updated for anchor: \(anchorId)")
        } else {
            // 모델이 없으면 새로 로드
            print("📦 Loading model for anchor: \(anchorId)")

            Task { @MainActor in
                do {
                    // 컨테이너 Entity 생성 (앵커 위치에 배치)
                    let container = Entity()
                    container.transform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)
                    container.name = "anchor_container_\(anchorId.uuidString)"

                    // 모델 로드 및 컨테이너에 추가
                    let model = try await Entity(named: "Immersive", in: realityKitContentBundle)
                    model.position = [0, 0, 0]  // 컨테이너 기준 원점
                    model.name = "model"

                    container.addChild(model)

                    print("📐 Anchor transform: \(anchorInfo.anchor.originFromAnchorTransform)")
                    print("📐 Container position: \(container.position)")
                    print("📐 Model local position: \(model.position)")

                    content.add(container)
                    modelEntities[anchorId] = container
                    print("✅ Model added to scene at anchor location")
                } catch {
                    print("❌ Failed to load model: \(error)")
                }
            }
        }
    }
}
