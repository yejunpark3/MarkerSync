import SwiftUI
import RealityKit
import ARKit

struct MarkerTrackingView: View {
    @Environment(ARManager.self) var arManager
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var detectedAnchor: ImageAnchor?
    @State private var trackingError: String?
    @State private var isProcessing = false
    @State private var currentBoxEntity: Entity?
    @State private var attachmentAdded = false

    var body: some View {
        RealityView { content, attachments in
            // Initial setup
        } update: { content, attachments in
            // detectedAnchor가 nil이거나 tracking이 false면 박스 제거
            if detectedAnchor == nil || detectedAnchor?.isTracked == false {
                if let existing = currentBoxEntity {
                    content.remove(existing)
                    // State 수정을 Task로 감싸기
                    Task { @MainActor in
                        currentBoxEntity = nil
                        attachmentAdded = false
                    }
                }
                return
            }

            // detectedAnchor가 있고 tracked인 경우
            if let imageAnchor = detectedAnchor, imageAnchor.isTracked {
                let newTransform = Transform(matrix: imageAnchor.originFromAnchorTransform)

                // 기존 박스가 있으면 transform만 업데이트 (깜빡거림 방지)
                if let existing = currentBoxEntity {
                    existing.transform = newTransform

                    // attachment를 한 번만 추가 (깜빡거림 방지)
                    if !attachmentAdded, let attachmentEntity = attachments.entity(for: "confirmUI") {
                        // 위치: 마커에서 30cm 위로
                        attachmentEntity.position = [0, 0.3, 0]

                        // 카메라를 항상 향하도록 billboard 설정
                        // X축 기준 -30도 기울임 (약간 위를 보도록)
                        let tiltAngle: Float = -30 * .pi / 180
                        let tiltRotation = simd_quatf(angle: tiltAngle, axis: [1, 0, 0])
                        attachmentEntity.orientation = tiltRotation

                        // Billboard 컴포넌트 추가 (자동으로 카메라를 향함)
                        attachmentEntity.components.set(BillboardComponent())

                        existing.addChild(attachmentEntity)

                        // State 수정을 Task로 감싸기
                        Task { @MainActor in
                            attachmentAdded = true
                        }
                    }
                } else {
                    // 박스가 없으면 새로 생성
                    let boxEntity = createWhiteBox(size: imageAnchor.referenceImage.physicalSize)
                    boxEntity.name = "markerBox"
                    boxEntity.transform = newTransform

                    if let attachmentEntity = attachments.entity(for: "confirmUI") {
                        // 위치: 마커에서 30cm 위로
                        attachmentEntity.position = [0, 0.3, 0]

                        // 카메라를 항상 향하도록 billboard 설정
                        // X축 기준 -30도 기울임 (약간 위를 보도록)
                        let tiltAngle: Float = -30 * .pi / 180
                        let tiltRotation = simd_quatf(angle: tiltAngle, axis: [1, 0, 0])
                        attachmentEntity.orientation = tiltRotation

                        // Billboard 컴포넌트 추가 (자동으로 카메라를 향함)
                        attachmentEntity.components.set(BillboardComponent())

                        boxEntity.addChild(attachmentEntity)
                    }

                    content.add(boxEntity)

                    // State 수정을 Task로 감싸기
                    Task { @MainActor in
                        currentBoxEntity = boxEntity
                        attachmentAdded = true
                    }
                }
            }
        } attachments: {
            Attachment(id: "confirmUI") {
                VStack(spacing: 16) {
                    if let error = trackingError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                            Button("다시 시도") {
                                trackingError = nil
                                Task { await startImageTracking() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    } else if isProcessing {
                        ProgressView("WorldAnchor 생성 중...")
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                    } else {
                        VStack(spacing: 12) {
                            Text("이 위치를 월드 앵커로 설정하시겠습니까?")
                                .font(.title3)
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)

                            HStack(spacing: 12) {
                                Button("취소") {
                                    detectedAnchor = nil
                                }
                                .buttonStyle(.bordered)

                                Button("확인") {
                                    Task { await confirmAnchor() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(detectedAnchor == nil)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .task {
            arManager.appState = .hostMode
            await startImageTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageAnchorDetected)) { notification in
            if let anchor = notification.object as? ImageAnchor {
                // 추적 중인 경우에만 저장
                if anchor.isTracked {
                    detectedAnchor = anchor
                } else {
                    // 추적이 끊기면 nil로 설정하여 박스 제거
                    detectedAnchor = nil
                }
            }
        }
        .onDisappear {
            arManager.stopImageTracking()
        }
    }

    func startImageTracking() async {
        do {
            try await arManager.startImageTracking()
        } catch {
            trackingError = "마커 인식 실패: \(error.localizedDescription)"
        }
    }

    func confirmAnchor() async {
        guard let anchor = detectedAnchor else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await arManager.createSharedWorldAnchor(from: anchor)

            arManager.stopImageTracking()

            await dismissImmersiveSpace()
            arManager.appState = .viewingModel
            await openImmersiveSpace(id: "model")

        } catch {
            trackingError = "앵커 생성 실패: \(error.localizedDescription)"
        }
    }

    func createWhiteBox(size: CGSize) -> Entity {
        let mesh = MeshResource.generateBox(
            width: Float(size.width),
            height: 0.01,
            depth: Float(size.height)
        )
        let material = SimpleMaterial(color: .white.withAlphaComponent(0.5), isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        return entity
    }
}
