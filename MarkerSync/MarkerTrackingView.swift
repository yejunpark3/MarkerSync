import SwiftUI
import RealityKit
import ARKit

struct MarkerTrackingView: View {
    @Environment(ARManager.self) var arManager
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - Local State
    @State private var detectedAnchor: ImageAnchor?
    @State private var currentBoxEntity: Entity?
    @State private var attachmentAdded = false
    @State private var isCreatingAnchor = false
    @State private var showDebugInfo = true

    // MARK: - Debug Manager
    @State private var debugManager = DebugElementManager()
    
    var body: some View {
        RealityView { content, attachments in
            // 초기 설정 - 고정 참조 오브젝트 (디버그용)
            if showDebugInfo {
                addDebugReferenceObjects(to: content)
            }
        } update: { content, attachments in
            updateMarkerVisualization(content: content, attachments: attachments)
        } attachments: {
            // 상태별 UI 어태치먼트
            Attachment(id: "statusUI") {
                StatusOverlayView(
                    trackingStatus: arManager.trackingStatus,
                    positionHint: arManager.positionHint,
                    samplingProgress: arManager.samplingProgress,
                    isCreatingAnchor: isCreatingAnchor,
                    onConfirm: { Task { await confirmAnchor() } },
                    onCancel: { cancelTracking() },
                    onRetry: { Task { await retryTracking() } }
                )
            }
            
            // 디버그 정보 (선택적)
            if showDebugInfo {
                Attachment(id: "debugUI") {
                    DebugInfoView(
                        anchor: detectedAnchor,
                        samplesCount: arManager.samplingProgress.current,
                        lastPosition: arManager.lastSamplePosition
                    )
                }
            }
        }
        .task {
            arManager.appState = .hostMode
            await startImageTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageAnchorDetected)) { notification in
            handleAnchorNotification(notification)
        }
        .onDisappear {
            cleanup()
        }
        .gesture(
            TapGesture(count: 3).onEnded {
                showDebugInfo.toggle()
            }
        )
    }
    
    // MARK: - Marker Visualization
    
    private func updateMarkerVisualization(content: RealityViewContent, attachments: RealityViewAttachments) {
        // 마커가 없거나 추적 중이 아니면 시각화 제거
        guard let imageAnchor = detectedAnchor, imageAnchor.isTracked else {
            removeMarkerVisualization(from: content)
            return
        }
        
        let newTransform = Transform(matrix: imageAnchor.originFromAnchorTransform)
        
        if let existing = currentBoxEntity {
            // 기존 박스 업데이트
            existing.transform = newTransform
            addAttachmentIfNeeded(to: existing, attachments: attachments)
        } else {
            // 새 박스 생성
            createMarkerVisualization(
                for: imageAnchor,
                transform: newTransform,
                content: content,
                attachments: attachments
            )
        }
    }
    
    private func createMarkerVisualization(
        for imageAnchor: ImageAnchor,
        transform: Transform,
        content: RealityViewContent,
        attachments: RealityViewAttachments
    ) {
        let container = Entity()
        container.name = "markerContainer"
        container.transform = transform
        
        // 마커 표시 박스 (상태에 따라 색상 변경)
        let boxEntity = createMarkerBox(
            size: imageAnchor.referenceImage.physicalSize,
            status: arManager.trackingStatus
        )
        container.addChild(boxEntity)
        
        // 좌표축 표시 (디버그용)
        if showDebugInfo {
            let axes = createCoordinateAxes()
            container.addChild(axes)
        }
        
        // 상태 UI 어태치먼트
        if let statusAttachment = attachments.entity(for: "statusUI") {
            configureAttachment(statusAttachment, yOffset: 0.35)
            container.addChild(statusAttachment)
        }
        
        // 디버그 UI 어태치먼트
        if showDebugInfo, let debugAttachment = attachments.entity(for: "debugUI") {
            configureAttachment(debugAttachment, yOffset: 0.6)
            container.addChild(debugAttachment)
        }
        
        content.add(container)
        
        Task { @MainActor in
            currentBoxEntity = container
            attachmentAdded = true
        }
    }
    
    private func removeMarkerVisualization(from content: RealityViewContent) {
        guard let existing = currentBoxEntity else { return }
        content.remove(existing)
        
        Task { @MainActor in
            currentBoxEntity = nil
            attachmentAdded = false
        }
    }
    
    private func addAttachmentIfNeeded(to entity: Entity, attachments: RealityViewAttachments) {
        guard !attachmentAdded else { return }
        
        if let statusAttachment = attachments.entity(for: "statusUI") {
            configureAttachment(statusAttachment, yOffset: 0.35)
            entity.addChild(statusAttachment)
            
            Task { @MainActor in
                attachmentAdded = true
            }
        }
    }
    
    private func configureAttachment(_ attachment: Entity, yOffset: Float) {
        attachment.position = [0, yOffset, 0]
        
        // 약간 위를 향하도록 기울임
        let tiltAngle: Float = -20 * .pi / 180
        let tiltRotation = simd_quatf(angle: tiltAngle, axis: [1, 0, 0])
        attachment.orientation = tiltRotation
        
        // Billboard - 항상 카메라를 향함
        attachment.components.set(BillboardComponent())
    }
    
    // MARK: - Entity Creation
    
    private func createMarkerBox(size: CGSize, status: TrackingStatus) -> Entity {
        let mesh = MeshResource.generateBox(
            width: Float(size.width),
            height: 0.005,
            depth: Float(size.height)
        )
        
        // 상태에 따른 색상
        let color: UIColor = switch status {
        case .searching, .stabilizing:
            .systemYellow.withAlphaComponent(0.5)
        case .sampling:
            .systemBlue.withAlphaComponent(0.5)
        case .found:
            .systemGreen.withAlphaComponent(0.6)
        case .anchored:
            .systemGreen.withAlphaComponent(0.8)
        case .error:
            .systemRed.withAlphaComponent(0.5)
        case .notStarted:
            .white.withAlphaComponent(0.3)
        }
        
        let material = SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "markerBox"
        
        return entity
    }
    
    private func createCoordinateAxes() -> Entity {
        let container = Entity()
        container.name = "coordinateAxes"
        
        let axisLength: Float = 0.3
        let axisThickness: Float = 0.005
        
        // X축 (빨강)
        let xAxis = ModelEntity(
            mesh: .generateBox(width: axisLength, height: axisThickness, depth: axisThickness),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = [axisLength / 2, 0, 0]
        container.addChild(xAxis)
        
        // Y축 (초록)
        let yAxis = ModelEntity(
            mesh: .generateBox(width: axisThickness, height: axisLength, depth: axisThickness),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = [0, axisLength / 2, 0]
        container.addChild(yAxis)
        
        // Z축 (파랑)
        let zAxis = ModelEntity(
            mesh: .generateBox(width: axisThickness, height: axisThickness, depth: axisLength),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = [0, 0, axisLength / 2]
        container.addChild(zAxis)
        
        return container
    }
    
    private func addDebugReferenceObjects(to content: RealityViewContent) {
        // 녹색 구 - 사용자 앞 1m, 눈높이 1.5m
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        sphere.position = [0, 1.5, -1]
        sphere.name = "debugSphere"
        content.add(sphere)
        
        // 빨간 박스 - 녹색 구 옆
        let box = ModelEntity(
            mesh: .generateBox(size: 0.08),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        box.position = [0.5, 1.5, -1]
        box.name = "debugBox"
        content.add(box)
    }
    
    // MARK: - Actions
    
    private func startImageTracking() async {
        do {
            try await arManager.startImageTracking()
        } catch {
            print("❌ Failed to start image tracking: \(error.localizedDescription)")
        }
    }
    
    private func confirmAnchor() async {
        guard arManager.trackingStatus == .found else {
            print("⚠️ Cannot confirm - tracking status is not .found")
            return
        }
        
        isCreatingAnchor = true
        defer { isCreatingAnchor = false }
        
        do {
            // 샘플링 결과로부터 WorldAnchor 생성
            _ = try await arManager.createWorldAnchorFromSamples()
            
            arManager.stopImageTracking()
            
            await dismissImmersiveSpace()
            arManager.appState = .viewingModel
            await openImmersiveSpace(id: "model")
            
        } catch {
            print("❌ Failed to create anchor: \(error.localizedDescription)")
            // 에러 발생 시 재시도 가능하도록 상태 유지
        }
    }
    
    private func cancelTracking() {
        arManager.resetSampling()
        detectedAnchor = nil
    }
    
    private func retryTracking() async {
        arManager.resetSampling()
        await startImageTracking()
    }
    
    private func cleanup() {
        arManager.stopImageTracking()
        currentBoxEntity = nil
        attachmentAdded = false
    }
    
    // MARK: - Notification Handling
    
    private func handleAnchorNotification(_ notification: Notification) {
        guard let anchor = notification.object as? ImageAnchor else { return }
        
        if anchor.isTracked {
            detectedAnchor = anchor
        } else {
            detectedAnchor = nil
        }
    }
}

// MARK: - Status Overlay View

struct StatusOverlayView: View {
    let trackingStatus: TrackingStatus
    let positionHint: PositionHint
    let samplingProgress: (current: Int, total: Int)
    let isCreatingAnchor: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // 상태별 메인 콘텐츠
            statusContent
            
            // 위치 힌트 (있을 경우)
            if positionHint != .none && trackingStatus.isProcessing {
                Text(positionHint.message)
                    .font(.callout)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: trackingStatus)
    }
    
    @ViewBuilder
    private var statusContent: some View {
        switch trackingStatus {
        case .notStarted:
            StatusCard(
                icon: "hourglass",
                iconColor: .gray,
                title: "준비 중...",
                showProgress: true
            )
            
        case .searching:
            StatusCard(
                icon: "viewfinder",
                iconColor: .blue,
                title: "마커를 찾는 중...",
                subtitle: "마커를 카메라에 비춰주세요",
                showProgress: true
            )
            
        case .stabilizing:
            StatusCard(
                icon: "gyroscope",
                iconColor: .orange,
                title: "위치 안정화 중...",
                subtitle: "잠시만 기다려주세요",
                showProgress: true
            )
            
        case .sampling(let current, let total):
            SamplingCard(
                current: current,
                total: total,
                onCancel: onCancel
            )
            
        case .found:
            if isCreatingAnchor {
                StatusCard(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .green,
                    title: "WorldAnchor 생성 중...",
                    showProgress: true
                )
            } else {
                ConfirmCard(
                    onConfirm: onConfirm,
                    onCancel: onCancel
                )
            }
            
        case .anchored:
            StatusCard(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                title: "앵커 생성 완료!",
                subtitle: "3D 모델을 배치합니다..."
            )
            
        case .error(let message):
            ErrorCard(
                message: message,
                onRetry: onRetry
            )
        }
    }
}

// MARK: - Card Components

struct StatusCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var showProgress: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(iconColor)
                
                if showProgress {
                    ProgressView()
                        .scaleEffect(1.5)
                        .offset(x: 30, y: 20)
                }
            }
            
            Text(title)
                .font(.headline)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct SamplingCard: View {
    let current: Int
    let total: Int
    let onCancel: () -> Void
    
    private var progress: Double {
        Double(current) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 진행률 원형 표시
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
                
                Text("\(current)/\(total)")
                    .font(.title2.bold())
                    .foregroundColor(.blue)
            }
            
            Text("위치 확인 중")
                .font(.headline)
            
            Text("가만히 계세요")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("취소", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct ConfirmCard: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("위치가 확정되었습니다")
                .font(.headline)
            
            Text("이 위치에 3D 모델을 배치할까요?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("취소", action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("확인", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            
            Text("문제가 발생했습니다")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("다시 시도", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    let anchor: ImageAnchor?
    let samplesCount: Int
    let lastPosition: SIMD3<Float>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔧 Debug Info")
                .font(.headline)
            
            if let anchor = anchor {
                let pos = anchor.originFromAnchorTransform.columns.3
                Text("Position: (\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)), \(String(format: "%.2f", pos.z)))")
                    .font(.caption.monospaced())
                
                Text("Height: \(String(format: "%.2f", pos.y))m")
                    .font(.caption.monospaced())
                
                let distance = sqrt(pos.x * pos.x + pos.y * pos.y + pos.z * pos.z)
                Text("Distance: \(String(format: "%.2f", distance))m")
                    .font(.caption.monospaced())
                
                Text("Tracked: \(anchor.isTracked ? "Yes" : "No")")
                    .font(.caption.monospaced())
                    .foregroundColor(anchor.isTracked ? .green : .red)
            } else {
                Text("No anchor detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Text("Samples: \(samplesCount)/\(SamplingConfig.requiredSamples)")
                .font(.caption.monospaced())
            
            if let pos = lastPosition {
                Text("Last: (\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)), \(String(format: "%.2f", pos.z)))")
                    .font(.caption.monospaced())
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .foregroundColor(.white)
    }
}