import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ModelDisplayView: View {
    @Environment(ARManager.self) var arManager
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    // MARK: - State
    @State private var modelEntities: [UUID: Entity] = [:]
    @State private var selectedAnchorId: UUID?
    @State private var connectionLost = false
    @State private var isLoadingModel = false
    @State private var loadError: String?
    @State private var showDebugInfo = true
    @State private var showExplanation = true
    @State private var showControlPanel = true
    @State private var currentColor: TankColor = .desertTan
    @State private var currentOptions: TankOptions = TankOptions()
    @State private var isHost: Bool = true
    @State private var lastDriftDistance: Float = 0
    @State private var totalDriftCorrections: Int = 0

    // MARK: - Debug Manager
    @State private var debugManager = DebugElementManager()
    
    var body: some View {
        ZStack {
            RealityView { content, attachments in
                // 초기 설정 - 디버그 참조 오브젝트
                if showDebugInfo {
                    addDebugReferenceObjects(to: content)
                }
            } update: { content, attachments in
                updateModels(in: content, attachments: attachments)
            } attachments: {
                Attachment(id: "explanationWindow") {
                    if showExplanation {
                        TankExplanationView()
                    }
                }

                Attachment(id: "controlPanel") {
                    if showControlPanel {
                        ControlPanelView(
                            isHost: isHost,
                            currentColor: $currentColor,
                            currentOptions: $currentOptions
                        )
                    }
                }
            }

            // 상태 오버레이
            statusOverlay
        }
        .task {
            await initializeView()
        }
        .onChange(of: arManager.isConnected) { _, isConnected in
            connectionLost = !isConnected
        }
        .onChange(of: arManager.sharedAnchors) { _, anchors in
            handleAnchorsChanged(anchors)
        }
        .onReceive(NotificationCenter.default.publisher(for: .worldAnchorUpdated)) { notification in
            handleDriftNotification(notification)
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
    
    // MARK: - Status Overlay
    
    @ViewBuilder
    private var statusOverlay: some View {
        VStack {
            Spacer()
            
            // 연결 상태
            if connectionLost {
                StatusBanner(
                    icon: "wifi.slash",
                    message: "연결이 끊어졌습니다. 재연결 시도 중...",
                    color: .orange
                )
            }
            
            // 로딩 상태
            if isLoadingModel {
                StatusBanner(
                    icon: "cube.transparent",
                    message: "3D 모델 로드 중...",
                    color: .blue,
                    showProgress: true
                )
            }
            
            // 에러 상태
            if let error = loadError {
                StatusBanner(
                    icon: "exclamationmark.triangle",
                    message: error,
                    color: .red
                )
            }
            
            // 디버그 정보
            if showDebugInfo {
                DebugPanel(
                    selectedAnchorId: selectedAnchorId,
                    anchorsCount: arManager.sharedAnchors.count,
                    entitiesCount: modelEntities.count,
                    lastDrift: lastDriftDistance,
                    totalCorrections: totalDriftCorrections
                )
            }

            Button(action: {
                showExplanation.toggle()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: showExplanation ? "info.circle.fill" : "info.circle")
                    Text(showExplanation ? "정보 숨기기" : "정보 보기")
                }
            }

            Button(action: {
                showControlPanel.toggle()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: showControlPanel ? "slider.horizontal.3" : "slider.horizontal.3")
                    Text(showControlPanel ? "제어 숨기기" : "제어 보기")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .padding(.bottom, 50)
        
        // 앵커 선택기 (다중 앵커 시)
        if arManager.sharedAnchors.count > 1 {
            anchorSelector
        }
    }
    
    @ViewBuilder
    private var anchorSelector: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("앵커 선택")
                        .font(.headline)
                    
                    ForEach(Array(arManager.sharedAnchors.values)) { anchorInfo in
                        Button(action: {
                            selectedAnchorId = anchorInfo.id
                        }) {
                            HStack {
                                Circle()
                                    .fill(anchorInfo.isActive ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                
                                Text(anchorInfo.id.uuidString.prefix(8) + "...")
                                    .font(.caption.monospaced())
                                
                                if anchorInfo.id == selectedAnchorId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding()
            }
            Spacer()
        }
    }
    
    // MARK: - Model Management
    
    private func updateModels(in content: RealityViewContent, attachments: RealityViewAttachments) {
        // 선택된 앵커 확인
        guard let anchorId = selectedAnchorId,
              let anchorInfo = arManager.sharedAnchors[anchorId],
              anchorInfo.isActive else {
            removeAllModels(from: content)
            return
        }

        let newTransform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)

        // 기존 모델이 있으면 Transform 업데이트 (Drift 보정)
        if let existingModel = modelEntities[anchorId] {
            existingModel.transform = newTransform
        } else {
            // 모델이 없으면 새로 로드
            loadModel(for: anchorId, anchorInfo: anchorInfo, content: content)
        }

        if let explanationAttachment = attachments.entity(for: "explanationWindow"),
           let tankContainer = modelEntities[anchorId] {
            if !tankContainer.children.contains(where: { $0.name == "explanationWindow" }) {
                tankContainer.addChild(explanationAttachment)
                configureExplanationAttachment(explanationAttachment)
            }
        }

        if let controlPanel = attachments.entity(for: "controlPanel"),
           let tankContainer = modelEntities[anchorId] {
            if !tankContainer.children.contains(where: { $0.name == "controlPanel" }) {
                tankContainer.addChild(controlPanel)
                configureControlPanel(controlPanel)
            }
        }
    }
    
    private func loadModel(for anchorId: UUID, anchorInfo: SharedAnchorInfo, content: RealityViewContent) {
        // 중복 로드 방지
        guard !isLoadingModel else { return }
        
        Task { @MainActor in
            isLoadingModel = true
            loadError = nil
            
            do {
                print("📦 Loading model for anchor: \(anchorId)")
                
                // 컨테이너 Entity 생성
                let container = Entity()
                container.transform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)
                container.name = "anchor_container_\(anchorId.uuidString)"
                
                // 3D 모델 로드
                let model = try await Entity(named: "Immersive", in: realityKitContentBundle)
                model.position = .zero
                model.name = "k2_tank_model"
                
                container.addChild(model)
                
                // 디버그용 좌표축 추가
                if showDebugInfo {
                    let axes = createCoordinateAxes()
                    container.addChild(axes)
                }
                
                // Scene에 추가
                content.add(container)
                
                // 로컬 및 ARManager에 등록 (Drift 보정용)
                modelEntities[anchorId] = container
                arManager.registerEntity(container, for: anchorId)
                
                print("✅ Model loaded and registered for anchor: \(anchorId)")
                printModelInfo(container, anchorInfo: anchorInfo)
                
                isLoadingModel = false
                
            } catch {
                print("❌ Failed to load model: \(error)")
                loadError = "모델 로드 실패: \(error.localizedDescription)"
                isLoadingModel = false
            }
        }
    }
    
    private func removeAllModels(from content: RealityViewContent) {
        Task { @MainActor in
            for (anchorId, entity) in modelEntities {
                content.remove(entity)
                arManager.unregisterEntity(for: anchorId)
            }
            modelEntities.removeAll()
            
            if !arManager.sharedAnchors.isEmpty {
                print("⚠️ All models removed - no active anchor selected")
            }
        }
    }
    
    // MARK: - Lifecycle
    
    private func initializeView() async {
        print("📍 ModelDisplayView initialized")
        print("   SharedAnchors count: \(arManager.sharedAnchors.count)")
        
        // 첫 번째 앵커 자동 선택
        if let firstAnchor = arManager.sharedAnchors.values.first {
            selectedAnchorId = firstAnchor.id
            print("   Selected anchor: \(firstAnchor.id)")
        } else {
            print("   ⚠️ No anchors available")
        }
    }
    
    private func handleAnchorsChanged(_ anchors: [UUID: SharedAnchorInfo]) {
        print("📍 SharedAnchors changed, count: \(anchors.count)")
        
        // 선택된 앵커가 없거나 제거되었으면 첫 번째 앵커 선택
        if selectedAnchorId == nil || anchors[selectedAnchorId!] == nil {
            if let first = anchors.values.first {
                selectedAnchorId = first.id
                print("   Auto-selected anchor: \(first.id)")
            }
        }
    }
    
    private func handleDriftNotification(_ notification: Notification) {
        guard let anchor = notification.object as? WorldAnchor,
              let userInfo = notification.userInfo,
              let driftDistance = userInfo["driftDistance"] as? Float else {
            return
        }
        
        // 유의미한 드리프트만 카운트 (1mm 이상)
        if driftDistance > 0.001 {
            lastDriftDistance = driftDistance
            totalDriftCorrections += 1
            
            // Entity Transform 직접 업데이트 (이미 ARManager에서 처리되지만 확인용)
            if let entity = modelEntities[anchor.id] {
                entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            }
        }
    }
    
    private func cleanup() {
        print("🧹 ModelDisplayView cleanup")
        
        // ARManager에서 Entity 등록 해제
        for anchorId in modelEntities.keys {
            arManager.unregisterEntity(for: anchorId)
        }
        
        modelEntities.removeAll()
    }
    
    private func configureExplanationAttachment(_ attachment: Entity) {
        attachment.name = "explanationWindow"
        attachment.position = [0, 0.7, 0]

        attachment.components.set(BillboardComponent())
    }

    private func configureControlPanel(_ attachment: Entity) {
        attachment.name = "controlPanel"
        attachment.position = [-1.0, 1.0, 0]

        attachment.components.set(BillboardComponent())
    }

    // MARK: - Debug Helpers
    
    private func addDebugReferenceObjects(to content: RealityViewContent) {
        // 녹색 구 - 사용자 앞 1m, 눈높이
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        sphere.position = [0, 1.5, -1]
        sphere.name = "debug_reference_sphere"
        content.add(sphere)
    }
    
    private func createCoordinateAxes() -> Entity {
        let container = Entity()
        container.name = "debug_axes"
        
        let length: Float = 0.5
        let thickness: Float = 0.01
        
        // X축 (빨강)
        let xAxis = ModelEntity(
            mesh: .generateBox(width: length, height: thickness, depth: thickness),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = [length / 2, 0, 0]
        container.addChild(xAxis)
        
        // Y축 (초록)
        let yAxis = ModelEntity(
            mesh: .generateBox(width: thickness, height: length, depth: thickness),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = [0, length / 2, 0]
        container.addChild(yAxis)
        
        // Z축 (파랑)
        let zAxis = ModelEntity(
            mesh: .generateBox(width: thickness, height: thickness, depth: length),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = [0, 0, length / 2]
        container.addChild(zAxis)
        
        return container
    }
    
    private func printModelInfo(_ container: Entity, anchorInfo: SharedAnchorInfo) {
        let transform = anchorInfo.anchor.originFromAnchorTransform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        print("📐 Model placement info:")
        print("   Anchor ID: \(anchorInfo.id)")
        print("   Position: \(position)")
        print("   Container world position: \(container.position(relativeTo: nil))")
        print("   Is Host created: \(anchorInfo.creatorId != nil)")
    }
}

// MARK: - Supporting Views

struct StatusBanner: View {
    let icon: String
    let message: String
    let color: Color
    var showProgress: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
            
            Text(message)
                .font(.subheadline)
            
            if showProgress {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct DebugPanel: View {
    let selectedAnchorId: UUID?
    let anchorsCount: Int
    let entitiesCount: Int
    let lastDrift: Float
    let totalCorrections: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🔧 Debug Info")
                .font(.headline)
            
            Divider()
            
            Group {
                Text("Anchors: \(anchorsCount)")
                Text("Entities: \(entitiesCount)")
                
                if let anchorId = selectedAnchorId {
                    Text("Selected: \(anchorId.uuidString.prefix(8))...")
                }
                
                Divider()
                
                Text("Drift Corrections: \(totalCorrections)")
                Text("Last Drift: \(String(format: "%.4f", lastDrift))m")
            }
            .font(.caption.monospaced())
        }
        .padding(16)
        .background(Color.black.opacity(0.75))
        .cornerRadius(12)
        .foregroundColor(.white)
        .frame(maxWidth: 250)
    }
}