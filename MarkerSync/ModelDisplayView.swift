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
    @State private var isHost: Bool = true
    @State private var lastDriftDistance: Float = 0
    @State private var totalDriftCorrections: Int = 0
    @State private var entityHeights: [UUID: Float] = [:]
    @State private var selectableEntitiesByAnchor: [UUID: [String: Entity]] = [:]
    @State private var selectableItemsByAnchor: [UUID: [SelectableMeshItem]] = [:]
    @State private var materialCacheByAnchor: [UUID: [String: [String: [any RealityKit.Material]]]] = [:]

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
                ForEach(TankPartRegistry.all) { part in
                    Attachment(id: "partBillboard_\(part.id)") {
                        if arManager.showPartBillboards {
                            TankPartBillboardView(part: part)
                        }
                    }
                }
            }

            // REMOVED: GestureControlPanelView() - Integrated into main RealityView

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
        .onChange(of: selectedAnchorId) { _, _ in
            refreshSelectableMeshItemsForSelectedAnchor()
            applyTankScale(arManager.tankScale, animated: false)
            applyTankRotation(arManager.tankRotation, animated: false)
        }
        .onChange(of: arManager.selectedTankColor) { _, newColor in
            if let anchorId = selectedAnchorId {
                applyTankColor(newColor, for: anchorId)
            }
        }
        .onChange(of: arManager.tankScale) { _, newScale in
            applyTankScale(newScale, animated: true)
        }
        .onChange(of: arManager.tankRotation) { _, newRotation in
            applyTankRotation(newRotation, animated: true)
        }
        .onChange(of: arManager.showPartBillboards) { _, show in
            updatePartBillboardVisibility(show)
        }
        .onChange(of: arManager.selectableMeshItems) { _, items in
            applySelectableMeshVisibilityForSelectedAnchor(items)
            cacheSelectableMeshItemsForSelectedAnchor(items)
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
            arManager.setSelectableMeshes([])
            return
        }

        let newTransform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)

        // 기존 모델이 있으면 Transform 업데이트 (Drift 보정)
        if let existingModel = modelEntities[anchorId] {
            existingModel.transform = newTransform
            applyXRayParameters(to: existingModel)
        } else {
            // 모델이 없으면 새로 로드
            loadModel(for: anchorId, anchorInfo: anchorInfo, content: content)
        }

        // Retrieve cached height for this anchor
        let cachedHeight = entityHeights[anchorId]

        if let explanationAttachment = attachments.entity(for: "explanationWindow"),
           let tankContainer = modelEntities[anchorId] {
            if !tankContainer.children.contains(where: { $0.name == "explanationWindow" }) {
                tankContainer.addChild(explanationAttachment)
                configureExplanationAttachment(explanationAttachment, height: cachedHeight)
            }
        }

        // Part billboards - attach to tankContainer (same as explanationWindow)
        if let tankContainer = modelEntities[anchorId] {
            attachPartBillboards(to: tankContainer, attachments: attachments)
        }
    }
    
    // MARK: - Material Cache & Color

    private func buildMaterialCache(from root: Entity) -> [String: [String: [any RealityKit.Material]]] {
        var cache: [String: [String: [any RealityKit.Material]]] = [:]

        // MaterialLibrary 탐색
        guard let materialLibrary = root.findEntity(named: "MaterialLibrary") else {
            print("⚠️ MaterialLibrary not found")
            return cache
        }

        // 전체 Holder 탐색 (자식 또는 손자 위치 가능하므로 재귀 탐색)
        func traverseForHolders(entity: Entity) {
            let name = entity.name
            if name.contains("_Holder_") {
                let components = name.components(separatedBy: "_Holder_")
                if components.count == 2 {
                    let entityName = components[0]
                    let colorName = components[1]

                    if let modelComp = entity.components[ModelComponent.self] as? ModelComponent {
                        if cache[entityName] == nil {
                            cache[entityName] = [:]
                        }
                        cache[entityName]?[colorName] = modelComp.materials
                        print("📦 Cached material: \(entityName) - \(colorName)")
                    }
                }
            }

            for child in entity.children {
                traverseForHolders(entity: child)
            }
        }

        traverseForHolders(entity: materialLibrary)
        
        // 런타임 비표시
        materialLibrary.isEnabled = false
        print("🙈 MaterialLibrary hidden")

        return cache
    }

    private func applyTankColor(_ color: TankColor, for anchorId: UUID) {
        guard let container = modelEntities[anchorId],
              let cache = materialCacheByAnchor[anchorId] else { return }

        let colorRawValue = color.rawValue

        func traverseAndApply(entity: Entity) {
            let name = entity.name
            if let entityCache = cache[name], let materials = entityCache[colorRawValue] {
                if var modelComp = entity.components[ModelComponent.self] as? ModelComponent {
                    modelComp.materials = materials
                    entity.components.set(modelComp)
                }
            }

            for child in entity.children {
                traverseAndApply(entity: child)
            }
        }

        traverseAndApply(entity: container)
        
        // 새 Material에 XRay 효과를 유지하기 위해 다시 파라미터 적용
        applyXRayParameters(to: container)
    }
    
    private func loadModel(for anchorId: UUID, anchorInfo: SharedAnchorInfo, content: RealityViewContent) {
        // 중복 로드 방지
        guard !isLoadingModel else { return }
        
        Task { @MainActor in
            isLoadingModel = true
            loadError = nil
            
            do {
                print("📦 Loading model for anchor: \(anchorId)")

                // Capture scale/rotation before await to avoid race with user changes
                let capturedScale = clampTankScale(arManager.tankScale)
                let capturedRotation = arManager.tankRotation

                // 컨테이너 Entity 생성
                let container = Entity()
                container.transform = Transform(matrix: anchorInfo.anchor.originFromAnchorTransform)
                container.name = "anchor_container_\(anchorId.uuidString)"

                // 3D 모델 로드
                let model = try await Entity(named: "Immersive", in: realityKitContentBundle)
                model.position = .zero
                model.name = "k2_tank_model"
                model.scale = SIMD3<Float>(repeating: capturedScale)
                model.transform.rotation = simd_quatf(angle: capturedRotation * .pi / 180, axis: [0, 1, 0])

                container.addChild(model)

                // Register before applying color so initial color update can find this container.
                modelEntities[anchorId] = container

                let cache = buildMaterialCache(from: model)
                materialCacheByAnchor[anchorId] = cache
                applyTankColor(arManager.selectedTankColor, for: anchorId)

                // Calculate entity height for dynamic positioning
                // Divide by captured scale to store the unscaled base height,
                // since visualBounds already reflects the current scale.
                if let modelEntity = container.findEntity(named: "k2_tank_model"),
                   let height = calculateEntityHeight(modelEntity) {
                    let unscaledHeight = height / capturedScale
                    entityHeights[anchorId] = unscaledHeight
                    print("✅ Cached unscaled height \(unscaledHeight)m (measured \(height)m at scale \(capturedScale)) for anchor: \(anchorId)")
                } else {
                    print("⚠️ Could not calculate height, will use fallback positioning")
                }

                // 디버그용 좌표축 추가
                if showDebugInfo {
                    let axes = createCoordinateAxes()
                    container.addChild(axes)
                }
                
                // Scene에 추가
                content.add(container)
                
                // 로컬 및 ARManager에 등록 (Drift 보정용)
                arManager.registerEntity(container, for: anchorId)

                // Selectable_ 메쉬 목록 생성 및 가시성 복원
                let selectableEntries = collectSelectableEntities(from: model)
                let selectableEntityMap = Dictionary(
                    uniqueKeysWithValues: selectableEntries.map { ($0.key, $0.entity) }
                )
                let selectableItems = selectableEntries.map { entry in
                    let isVisible = arManager.visibilityForSelectableMesh(key: entry.key)
                    entry.entity.isEnabled = isVisible
                    return SelectableMeshItem(
                        id: "\(anchorId.uuidString)::\(entry.key)",
                        entityKey: entry.key,
                        sourceName: entry.sourceName,
                        displayName: entry.displayName,
                        isVisible: isVisible
                    )
                }
                selectableEntitiesByAnchor[anchorId] = selectableEntityMap
                selectableItemsByAnchor[anchorId] = selectableItems

                if selectedAnchorId == anchorId {
                    arManager.setSelectableMeshes(selectableItems)
                }
                
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
            entityHeights.removeAll()
            selectableEntitiesByAnchor.removeAll()
            selectableItemsByAnchor.removeAll()
            materialCacheByAnchor.removeAll()
            arManager.setSelectableMeshes([])

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

        let activeAnchorIDs = Set(anchors.keys)
        selectableEntitiesByAnchor = selectableEntitiesByAnchor.filter { activeAnchorIDs.contains($0.key) }
        selectableItemsByAnchor = selectableItemsByAnchor.filter { activeAnchorIDs.contains($0.key) }
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
        entityHeights.removeAll()
        selectableEntitiesByAnchor.removeAll()
        selectableItemsByAnchor.removeAll()
        materialCacheByAnchor.removeAll()
        arManager.setSelectableMeshes([])
    }

    private func refreshSelectableMeshItemsForSelectedAnchor() {
        guard let anchorId = selectedAnchorId else {
            arManager.setSelectableMeshes([])
            return
        }

        let items = selectableItemsByAnchor[anchorId] ?? []
        arManager.setSelectableMeshes(items)
    }

    private func cacheSelectableMeshItemsForSelectedAnchor(_ items: [SelectableMeshItem]) {
        guard let anchorId = selectedAnchorId else { return }
        selectableItemsByAnchor[anchorId] = items
    }

    private func applySelectableMeshVisibilityForSelectedAnchor(_ items: [SelectableMeshItem]) {
        guard let anchorId = selectedAnchorId,
              let selectableEntities = selectableEntitiesByAnchor[anchorId] else {
            return
        }

        for item in items {
            selectableEntities[item.entityKey]?.isEnabled = item.isVisible
        }
    }

    private struct SelectableEntityEntry {
        let entity: Entity
        let key: String
        let sourceName: String
        let displayName: String
    }

    private func collectSelectableEntities(from root: Entity) -> [SelectableEntityEntry] {
        var collected: [SelectableEntityEntry] = []

        func traverse(entity: Entity, siblingIndexPath: [Int]) {
            let sourceName = entity.name
            if sourceName.hasPrefix("Selectable_") {
                let pathToken = siblingIndexPath.isEmpty
                    ? "root"
                    : siblingIndexPath.map(String.init).joined(separator: "/")
                let key = "\(sourceName)#\(pathToken)"
                let displayName = selectableDisplayName(from: sourceName)
                collected.append(
                    SelectableEntityEntry(
                        entity: entity,
                        key: key,
                        sourceName: sourceName,
                        displayName: displayName
                    )
                )
            }

            for (index, child) in entity.children.enumerated() {
                traverse(entity: child, siblingIndexPath: siblingIndexPath + [index])
            }
        }

        traverse(entity: root, siblingIndexPath: [])
        return collected
    }

    private func selectableDisplayName(from sourceName: String) -> String {
        let stripped = String(sourceName.dropFirst("Selectable_".count))
        let formatted = stripped.replacingOccurrences(of: "_", with: " ")
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceName : trimmed
    }

    private func clampTankScale(_ value: Float) -> Float {
        min(max(value, TankScaleConfig.minScale), TankScaleConfig.maxScale)
    }

    private func applyTankScale(_ scale: Float, animated: Bool) {
        guard let anchorId = selectedAnchorId,
              let tankContainer = modelEntities[anchorId],
              let modelEntity = tankContainer.findEntity(named: "k2_tank_model") else {
            return
        }

        let clampedScale = clampTankScale(scale)
        var updatedTransform = modelEntity.transform
        updatedTransform.scale = SIMD3<Float>(repeating: clampedScale)

        if animated {
            modelEntity.move(
                to: updatedTransform,
                relativeTo: modelEntity.parent,
                duration: TankScaleConfig.animationDuration,
                timingFunction: .easeInOut
            )
        } else {
            modelEntity.transform = updatedTransform
        }

        repositionExplanationAfterScale(animated: animated, scale: clampedScale)
        repositionPartBillboards(animated: animated)
    }

    private func applyTankRotation(_ degrees: Float, animated: Bool) {
        guard let anchorId = selectedAnchorId,
              let tankContainer = modelEntities[anchorId],
              let modelEntity = tankContainer.findEntity(named: "k2_tank_model") else {
            return
        }

        let radians = degrees * .pi / 180
        var updatedTransform = modelEntity.transform
        updatedTransform.rotation = simd_quatf(angle: radians, axis: [0, 1, 0])

        if animated {
            modelEntity.move(
                to: updatedTransform,
                relativeTo: modelEntity.parent,
                duration: TankRotationConfig.animationDuration,
                timingFunction: .easeInOut
            )
        } else {
            modelEntity.transform = updatedTransform
        }

        repositionPartBillboards(animated: animated)
    }

    private func repositionExplanationAfterScale(animated: Bool, scale: Float? = nil) {
        guard let anchorId = selectedAnchorId,
              let tankContainer = modelEntities[anchorId],
              let explanationEntity = tankContainer.children.first(where: { $0.name == "explanationWindow" }) else {
            return
        }

        let unscaledHeight = entityHeights[anchorId] ?? 7.0
        let currentScale = scale ?? clampTankScale(arManager.tankScale)
        let targetY = unscaledHeight * currentScale * 1.2

        var updatedTransform = explanationEntity.transform
        updatedTransform.translation = SIMD3<Float>(0, targetY, 0)

        if animated {
            explanationEntity.move(
                to: updatedTransform,
                relativeTo: explanationEntity.parent,
                duration: TankScaleConfig.animationDuration,
                timingFunction: .easeInOut
            )
        } else {
            explanationEntity.transform = updatedTransform
        }
    }
    
    private func configureExplanationAttachment(_ attachment: Entity, height: Float? = nil) {
        attachment.name = "explanationWindow"

        let unscaledHeight = height ?? 7.0  // fallback unscaled height
        let currentScale = clampTankScale(arManager.tankScale)
        attachment.position = [0, unscaledHeight * currentScale * 1.2, 0]

        attachment.components.set(BillboardComponent())

        print("📍 Explanation window positioned at y=\(unscaledHeight * currentScale * 1.2)m")
    }

    private func calculateEntityHeight(_ entity: Entity) -> Float? {
        let bounds = entity.visualBounds(relativeTo: nil)
        let height = bounds.max.y - bounds.min.y

        guard height > 0 else {
            print("⚠️ Invalid bounding box height: \(height)")
            return nil
        }

        print("📏 Calculated entity height: \(height)m")
        return height
    }

    // MARK: - Part Billboards

    /// Returns the tankContainer for the selected anchor.
    private func selectedTankContainer() -> Entity? {
        guard let anchorId = selectedAnchorId else { return nil }
        return modelEntities[anchorId]
    }

    /// Attaches billboard ViewAttachmentEntities and connector lines to tankContainer.
    /// Safe to call repeatedly - uses name-guard to prevent duplicates.
    /// Called from the RealityView update: closure — does NOT modify @State.
    private func attachPartBillboards(to tankContainer: Entity, attachments: RealityViewAttachments) {
        let currentScale = clampTankScale(arManager.tankScale)
        let rotationDegrees = arManager.tankRotation

        for part in TankPartRegistry.all {
            let billboardName = "partBillboard_\(part.id)"
            let lineName = "partLine_\(part.id)"

            // Billboard attachment — lifted slightly above the line endpoint
            // so the line visually connects near the card's bottom edge.
            let billboardLift: Float = 0.075
            if let billboardEntity = attachments.entity(for: billboardName),
               !tankContainer.children.contains(where: { $0.name == billboardName }) {
                billboardEntity.name = billboardName
                var billboardPos = modelToContainerPosition(part.billboardPosition, scale: currentScale, rotationDegrees: rotationDegrees)
                billboardPos.y += billboardLift
                billboardEntity.position = billboardPos
                billboardEntity.components.set(BillboardComponent())
                billboardEntity.isEnabled = arManager.showPartBillboards
                tankContainer.addChild(billboardEntity)
            }

            // Connector line
            if !tankContainer.children.contains(where: { $0.name == lineName }) {
                let startPos = modelToContainerPosition(part.localPosition, scale: currentScale, rotationDegrees: rotationDegrees)
                let endPos = modelToContainerPosition(part.billboardPosition, scale: currentScale, rotationDegrees: rotationDegrees)
                let lineEntity = makeConnectorLine(from: startPos, to: endPos)
                lineEntity.name = lineName
                lineEntity.isEnabled = arManager.showPartBillboards
                tankContainer.addChild(lineEntity)
            }
        }
    }

    /// Shows or hides all part billboard and line entities.
    private func updatePartBillboardVisibility(_ show: Bool) {
        guard let tankContainer = selectedTankContainer() else { return }
        for part in TankPartRegistry.all {
            tankContainer.findEntity(named: "partBillboard_\(part.id)")?.isEnabled = show
            tankContainer.findEntity(named: "partLine_\(part.id)")?.isEnabled = show
        }
        if show {
            repositionPartBillboards(animated: false)
        }
    }

    /// Repositions billboards and lines when scale or rotation changes.
    private func repositionPartBillboards(animated: Bool) {
        guard let tankContainer = selectedTankContainer() else { return }

        let currentScale = clampTankScale(arManager.tankScale)
        let rotationDegrees = arManager.tankRotation
        let duration = animated ? TankScaleConfig.animationDuration : 0

        let billboardLift: Float = 0.075
        for part in TankPartRegistry.all {
            let lineEndPos = modelToContainerPosition(part.billboardPosition, scale: currentScale, rotationDegrees: rotationDegrees)
            var billboardPos = lineEndPos
            billboardPos.y += billboardLift
            let startPos = modelToContainerPosition(part.localPosition, scale: currentScale, rotationDegrees: rotationDegrees)

            // Reposition billboard
            if let billboardEntity = tankContainer.findEntity(named: "partBillboard_\(part.id)") {
                if animated {
                    var transform = billboardEntity.transform
                    transform.translation = billboardPos
                    billboardEntity.move(to: transform, relativeTo: billboardEntity.parent, duration: duration, timingFunction: .easeInOut)
                } else {
                    billboardEntity.position = billboardPos
                }
            }

            // Recreate line with new geometry
            let lineName = "partLine_\(part.id)"
            if let oldLine = tankContainer.findEntity(named: lineName) {
                let wasEnabled = oldLine.isEnabled
                oldLine.removeFromParent()

                let newLine = makeConnectorLine(from: startPos, to: lineEndPos)
                newLine.name = lineName
                newLine.isEnabled = wasEnabled
                tankContainer.addChild(newLine)
            }
        }
    }

    /// Converts a position in k2_tank_model local space to tankContainer space.
    /// Applies scale and Y-axis rotation.
    private func modelToContainerPosition(_ localPos: SIMD3<Float>, scale: Float, rotationDegrees: Float) -> SIMD3<Float> {
        let scaled = localPos * scale
        let radians = rotationDegrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        return SIMD3<Float>(
            scaled.x * cosA + scaled.z * sinA,
            scaled.y,
            -scaled.x * sinA + scaled.z * cosA
        )
    }

    /// Creates a white line entity between two points in container space.
    private func makeConnectorLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> ModelEntity {
        let diff = end - start
        let length = simd_length(diff)
        guard length > 0.001 else { return ModelEntity() }

        let thickness: Float = 0.002
        let mesh = MeshResource.generateBox(
            width: thickness,
            height: length,
            depth: thickness
        )
        let line = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
        line.position = (start + end) / 2

        // Rotate box Y-axis to align with direction
        let up = SIMD3<Float>(0, 1, 0)
        let direction = simd_normalize(diff)
        let dot = simd_dot(up, direction)
        if dot < -0.9999 {
            // Anti-parallel: rotate 180° around X
            line.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else if dot < 0.9999 {
            line.orientation = simd_quatf(from: up, to: direction)
        }
        // else: nearly parallel to up, identity is correct

        return line
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

    // MARK: - XRay

    private func applyXRayParameters(to entity: Entity) {
        let wallNormal: SIMD3<Float>
        let wallD: Float
        let insideAlpha: Float

        if let selectedWall = arManager.selectedWall {
            wallNormal = selectedWall.normal
            wallD = selectedWall.distance
            insideAlpha = 0.3
        } else {
            // 벽 미선택 시 완전 불투명 유지
            wallNormal = SIMD3<Float>(0, 1, 0)
            wallD = 0
            insideAlpha = 1.0
        }

        let updatedCount = setShaderParametersRecursive(
            entity: entity,
            wallNormal: wallNormal,
            wallD: wallD,
            insideAlpha: insideAlpha
        )

        if updatedCount == 0 {
            print("⚠️ XRay params not applied: no ShaderGraphMaterial found")
        }
    }

    private func setShaderParametersRecursive(
        entity: Entity,
        wallNormal: SIMD3<Float>,
        wallD: Float,
        insideAlpha: Float
    ) -> Int {
        var appliedCount = 0

        if var modelComponent = entity.components[ModelComponent.self] {
            var updatedMaterials: [any RealityKit.Material] = []

            for material in modelComponent.materials {
                if var shaderMaterial = material as? ShaderGraphMaterial {
                    do {
                        try shaderMaterial.setParameter(name: "WallNormal", value: .simd3Float(wallNormal))
                        try shaderMaterial.setParameter(name: "WallD", value: .float(wallD))
                        try shaderMaterial.setParameter(name: "InsideAlpha", value: .float(insideAlpha))
                        updatedMaterials.append(shaderMaterial)
                        appliedCount += 1
                    } catch {
                        updatedMaterials.append(material)
                    }
                } else {
                    updatedMaterials.append(material)
                }
            }

            modelComponent.materials = updatedMaterials
            entity.components[ModelComponent.self] = modelComponent
        }

        for child in entity.children {
            appliedCount += setShaderParametersRecursive(
                entity: child,
                wallNormal: wallNormal,
                wallD: wallD,
                insideAlpha: insideAlpha
            )
        }

        return appliedCount
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
