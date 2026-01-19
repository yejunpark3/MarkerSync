import SwiftUI
import RealityKit

/// Centralized manager for debug elements in AR views
/// Handles creation, addition, and removal of coordinate axes and reference objects
class DebugElementManager {
    // MARK: - Types

    enum DebugElementType {
        case coordinateAxes
        case referenceSphere
        case referenceBox
    }

    // MARK: - Properties

    private var activeDebugElements: Set<String> = []

    // MARK: - Public Methods

    /// Adds coordinate axes to the specified entity
    /// - Parameters:
    ///   - to: The entity to add axes to
    ///   - length: Length of each axis (default: 0.3)
    ///   - thickness: Thickness of each axis (default: 0.005)
    func addCoordinateAxes(to entity: Entity, length: Float = 0.3, thickness: Float = 0.005) {
        let axesName = "debug_axes"

        // Remove existing axes if present
        if let existingAxes = entity.children.first(where: { $0.name == axesName }) {
            entity.removeChild(existingAxes)
        }

        let axes = createCoordinateAxes(length: length, thickness: thickness)
        entity.addChild(axes)
        activeDebugElements.insert(axesName)
    }

    /// Removes coordinate axes from the specified entity
    /// - Parameter from: The entity to remove axes from
    func removeCoordinateAxes(from entity: Entity) {
        let axesName = "debug_axes"

        if let existingAxes = entity.children.first(where: { $0.name == axesName }) {
            entity.removeChild(existingAxes)
            activeDebugElements.remove(axesName)
        }
    }

    /// Adds debug reference objects to the content
    /// - Parameters:
    ///   - to: The RealityViewContent to add reference objects to
    ///   - spherePosition: Position for the reference sphere (default: [0, 1.5, -1])
    ///   - boxPosition: Position for the reference box (default: [0.5, 1.5, -1])
    func addReferenceObjects(to content: RealityViewContent,
                           spherePosition: SIMD3<Float> = [0, 1.5, -1],
                           boxPosition: SIMD3<Float> = [0.5, 1.5, -1]) {

        // Add reference sphere
        let sphereName = "debug_reference_sphere"
        if !hasActiveElement(sphereName) {
            let sphere = createReferenceSphere(position: spherePosition)
            content.add(sphere)
            activeDebugElements.insert(sphereName)
        }

        // Add reference box
        let boxName = "debug_reference_box"
        if !hasActiveElement(boxName) {
            let box = createReferenceBox(position: boxPosition)
            content.add(box)
            activeDebugElements.insert(boxName)
        }
    }

    /// Removes debug reference objects from the content
    /// - Parameter from: The RealityViewContent to remove reference objects from
    func removeReferenceObjects(from content: RealityViewContent) {
        let sphereName = "debug_reference_sphere"
        let boxName = "debug_reference_box"

        // Remove reference sphere
        if let sphere = content.entities.first(where: { $0.name == sphereName }) {
            content.remove(sphere)
            activeDebugElements.remove(sphereName)
        }

        // Remove reference box
        if let box = content.entities.first(where: { $0.name == boxName }) {
            content.remove(box)
            activeDebugElements.remove(boxName)
        }
    }

    /// Updates debug elements based on the current debug state
    /// - Parameters:
    ///   - showDebug: Whether to show or hide debug elements
    ///   - content: The RealityViewContent to update
    ///   - entities: Array of entities that should have coordinate axes
    func updateDebugElements(showDebug: Bool,
                           content: RealityViewContent,
                           entities: [Entity]) {
        if showDebug {
            addReferenceObjects(to: content)
            entities.forEach { addCoordinateAxes(to: $0) }
        } else {
            removeReferenceObjects(from: content)
            entities.forEach { removeCoordinateAxes(from: $0) }
        }
    }

    /// Cleans up all active debug elements
    /// - Parameter content: The RealityViewContent to clean up
    func cleanup(from content: RealityViewContent) {
        removeReferenceObjects(from: content)

        // Remove axes from all entities in the content
        for entity in content.entities {
            removeCoordinateAxes(from: entity)
        }

        activeDebugElements.removeAll()
    }

    // MARK: - Private Methods

    private func hasActiveElement(_ name: String) -> Bool {
        return activeDebugElements.contains(name)
    }

    private func createCoordinateAxes(length: Float, thickness: Float) -> Entity {
        let container = Entity()
        container.name = "debug_axes"

        // X-axis (Red)
        let xAxis = ModelEntity(
            mesh: .generateBox(width: length, height: thickness, depth: thickness),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = [length / 2, 0, 0]
        container.addChild(xAxis)

        // Y-axis (Green)
        let yAxis = ModelEntity(
            mesh: .generateBox(width: thickness, height: length, depth: thickness),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = [0, length / 2, 0]
        container.addChild(yAxis)

        // Z-axis (Blue)
        let zAxis = ModelEntity(
            mesh: .generateBox(width: thickness, height: thickness, depth: length),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = [0, 0, length / 2]
        container.addChild(zAxis)

        return container
    }

    private func createReferenceSphere(position: SIMD3<Float>) -> Entity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        sphere.position = position
        sphere.name = "debug_reference_sphere"
        return sphere
    }

    private func createReferenceBox(position: SIMD3<Float>) -> Entity {
        let box = ModelEntity(
            mesh: .generateBox(size: 0.08),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        box.position = position
        box.name = "debug_reference_box"
        return box
    }
}