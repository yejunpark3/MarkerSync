import ARKit
import RealityKit
import Foundation
import UIKit
import CryptoKit

extension ARManager {
    func startWallTracking() {
        wallTrackingTask?.cancel()

        guard let roomTracking = roomTracking else {
            print("⚠️ RoomTracking unavailable")
            return
        }

        print("🏠 Starting room wall tracking...")

        wallTrackingTask = Task { [weak self] in
            guard let self = self else { return }

            for await update in roomTracking.anchorUpdates {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.handleRoomAnchorUpdate(update)
                }
            }
        }
    }

    func selectWallForXRay(_ wall: DetectedWall) {
        selectedWall = wall
        isWallSelectionCompleted = true
        updateWallSelectionAppearance()
        print("✅ Selected wall: \(wall.id)")
        print("   Position: \(wall.position), Normal: \(wall.normal)")
    }

    func startMarkerRecognitionFlow() {
        guard selectedWall != nil else {
            trackingStatus = .error(ARError.wallSelectionRequired.localizedDescription)
            return
        }

        isMarkerTrackingActive = true
        trackingStatus = .notStarted
        print("🎯 Marker recognition enabled after wall selection")
    }

    func stopMarkerRecognitionFlow() {
        isMarkerTrackingActive = false
        stopImageTracking()
    }

    func resetWallSelectionFlow() {
        isMarkerTrackingActive = false
        isWallSelectionCompleted = false
        selectedWall = nil
        updateWallSelectionAppearance()
        trackingStatus = .wallSelecting
    }

    private func handleRoomAnchorUpdate(_ update: AnchorUpdate<RoomAnchor>) {
        let anchor = update.anchor

        switch update.event {
        case .added, .updated:
            rebuildWalls(for: anchor)
        case .removed:
            removeWalls(for: anchor.id)
        }
    }

    private func rebuildWalls(for anchor: RoomAnchor) {
        let wallGeometries = anchor.geometries(of: .wall)
        let previousWallIDs = Set(anchorToWallIDs[anchor.id] ?? [])
        var wallIDs: [UUID] = []

        for (index, geometry) in wallGeometries.enumerated() {
            let plane = calculateWallPlane(geometry: geometry, anchor: anchor)
            guard let plane else { continue }

            let wallID = stableWallID(anchorID: anchor.id, wallIndex: index)
            let wall = DetectedWall(
                id: wallID,
                normal: plane.normal,
                position: plane.position,
                distance: plane.distance,
                sourceAnchorID: anchor.id
            )

            wallsByID[wallID] = wall
            wallIDs.append(wallID)
            createOrUpdateWallVisualization(wall: wall, geometry: geometry, anchor: anchor)
        }

        let staleWallIDs = previousWallIDs.subtracting(Set(wallIDs))
        for staleWallID in staleWallIDs {
            removeWall(staleWallID, clearSelection: true)
        }

        anchorToWallIDs[anchor.id] = wallIDs
        if let selectedID = selectedWall?.id, let updatedSelected = wallsByID[selectedID] {
            selectedWall = updatedSelected
        }
        refreshDetectedWalls()
        updateWallSelectionAppearance()
    }

    private func removeWalls(for anchorID: UUID) {
        guard let wallIDs = anchorToWallIDs[anchorID] else { return }

        for wallID in wallIDs {
            removeWall(wallID, clearSelection: true)
        }

        anchorToWallIDs.removeValue(forKey: anchorID)
        refreshDetectedWalls()
    }

    private func refreshDetectedWalls() {
        detectedWalls = wallsByID.values.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func stableWallID(anchorID: UUID, wallIndex: Int) -> UUID {
        let seed = "\(anchorID.uuidString)-\(wallIndex)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func removeWall(_ wallID: UUID, clearSelection: Bool) {
        wallsByID.removeValue(forKey: wallID)

        if let wallEntity = wallEntities[wallID] {
            wallEntity.removeFromParent()
        }
        wallEntities.removeValue(forKey: wallID)

        if let arrowEntity = wallArrowEntities[wallID] {
            arrowEntity.removeFromParent()
        }
        wallArrowEntities.removeValue(forKey: wallID)

        if clearSelection, selectedWall?.id == wallID {
            selectedWall = nil
            isWallSelectionCompleted = false
        }
    }

    private func calculateWallPlane(
        geometry: MeshAnchor.Geometry,
        anchor: RoomAnchor
    ) -> (normal: SIMD3<Float>, position: SIMD3<Float>, distance: Float)? {
        let vertices = geometry.vertices.asSIMD3(ofType: Float.self)
        let faces = geometry.faces.asUInt32Array()

        guard faces.count >= 3,
              vertices.count >= 3,
              Int(faces[0]) < vertices.count,
              Int(faces[1]) < vertices.count,
              Int(faces[2]) < vertices.count else {
            return nil
        }

        let i0 = Int(faces[0])
        let i1 = Int(faces[1])
        let i2 = Int(faces[2])

        let v0 = vertices[i0]
        let v1 = vertices[i1]
        let v2 = vertices[i2]

        let edge1 = v1 - v0
        let edge2 = v2 - v0
        var localNormal = normalize(cross(edge1, edge2))

        guard localNormal.x.isFinite && localNormal.y.isFinite && localNormal.z.isFinite else {
            return nil
        }

        let transform = anchor.originFromAnchorTransform

        let rotationMatrix = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )

        var worldNormal = normalize(rotationMatrix * localNormal)

        // TankXRay와 동일: 첫 triangle의 centroid를 사용해 벽 위치를 계산
        // (평균점 계산으로 모든 벽 좌표가 같아지는 문제를 회피)
        let centroid = (v0 + v1 + v2) / 3.0
        let worldPoint4 = transform * SIMD4<Float>(centroid.x, centroid.y, centroid.z, 1.0)
        let worldPosition = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)

        // Normal 방향을 원점 기준으로 정렬
        let toOrigin = -worldPosition
        if dot(worldNormal, toOrigin) < 0 {
            worldNormal = -worldNormal
        }

        let planeDistance = -dot(worldPosition, worldNormal)
        return (worldNormal, worldPosition, planeDistance)
    }

    private func createOrUpdateWallVisualization(
        wall: DetectedWall,
        geometry: MeshAnchor.Geometry,
        anchor: RoomAnchor
    ) {
        guard let meshResource = createMeshResource(from: geometry) else {
            return
        }

        if let existingWallEntity = wallEntities[wall.id] {
            existingWallEntity.removeFromParent()
            wallEntities.removeValue(forKey: wall.id)
        }
        if let existingArrow = wallArrowEntities[wall.id] {
            existingArrow.removeFromParent()
            wallArrowEntities.removeValue(forKey: wall.id)
        }

        let baseMaterial = makeWallMaterial(isSelected: false)
        let wallEntity = ModelEntity(mesh: meshResource, materials: [baseMaterial])
        wallEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        wallEntity.name = "wallMesh_\(wall.id)"
        wallVisualizationRoot.addChild(wallEntity)
        wallEntities[wall.id] = wallEntity

        let arrowEntity = makeNormalArrowEntity(for: wall)
        wallVisualizationRoot.addChild(arrowEntity)
        wallArrowEntities[wall.id] = arrowEntity
    }

    private func createMeshResource(from geometry: MeshAnchor.Geometry) -> MeshResource? {
        let vertices = geometry.vertices.asSIMD3(ofType: Float.self)
        let indices = geometry.faces.asUInt32Array()

        guard !vertices.isEmpty, !indices.isEmpty else {
            return nil
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("❌ Failed to generate wall mesh: \(error)")
            return nil
        }
    }

    private func makeWallMaterial(isSelected: Bool) -> SimpleMaterial {
        let color: UIColor = isSelected
            ? .systemGreen.withAlphaComponent(0.55)
            : .systemBlue.withAlphaComponent(0.3)
        return SimpleMaterial(color: color, isMetallic: false)
    }

    private func makeNormalArrowEntity(for wall: DetectedWall) -> Entity {
        let arrowRoot = Entity()
        arrowRoot.name = "wallNormalArrow_\(wall.id)"

        let shaftLength: Float = 0.22
        let shaftThickness: Float = 0.01
        let headLength: Float = 0.06
        let headThickness: Float = 0.025

        let shaft = ModelEntity(
            mesh: .generateBox(width: shaftThickness, height: shaftThickness, depth: shaftLength),
            materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
        )
        shaft.position = [0, 0, shaftLength * 0.5]

        let head = ModelEntity(
            mesh: .generateBox(width: headThickness, height: headThickness, depth: headLength),
            materials: [SimpleMaterial(color: .systemYellow, isMetallic: false)]
        )
        head.position = [0, 0, shaftLength + (headLength * 0.5)]

        let center = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )

        arrowRoot.addChild(center)
        arrowRoot.addChild(shaft)
        arrowRoot.addChild(head)

        arrowRoot.position = wall.position
        arrowRoot.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: wall.normal)

        return arrowRoot
    }

    private func updateWallSelectionAppearance() {
        for (wallID, entity) in wallEntities {
            guard var model = entity.components[ModelComponent.self] else { continue }
            let isSelected = selectedWall?.id == wallID
            model.materials = [makeWallMaterial(isSelected: isSelected)]
            entity.components.set(model)
        }
    }
}
