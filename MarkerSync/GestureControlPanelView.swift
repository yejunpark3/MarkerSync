//
//  GestureControlPanelView.swift
//  MarkerSync
//
//  Created by Claude Code
//

import SwiftUI
import RealityKit

// DEPRECATED: Gesture panel functionality moved to main window (ContentView)
// This file is kept for reference but is no longer used in the application

/// View that displays a control panel above the user's hand when palm-up gesture is detected
struct GestureControlPanelView: View {
    @Environment(ARManager.self) var arManager
    @State private var currentHandTransform: simd_float4x4?
    @State private var isGestureActive = false
    @State private var selectedColor: TankColor = .red
    @State private var selectedOptions = TankOptions()

    var body: some View {
        RealityView { content, attachments in
            // Initial setup - called once
            print("🎬 GestureControlPanelView: initial setup")
        } update: { content, attachments in
            updateGesturePanel(in: content, attachments: attachments)
        } attachments: {
            Attachment(id: "gestureControlPanel") {
                if isGestureActive {
                    ControlPanelView(
                        isHost: arManager.userRole == .host,
                        currentColor: $selectedColor,
                        currentOptions: $selectedOptions
                    )
                    .frame(width: 400, height: 600)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .palmUpGestureDetected)) { notification in
            guard let transform = notification.object as? simd_float4x4 else { return }
            currentHandTransform = transform
            isGestureActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .palmUpGestureEnded)) { _ in
            isGestureActive = false
            currentHandTransform = nil
        }
    }

    /// Update the gesture panel position and visibility
    private func updateGesturePanel(in content: RealityViewContent, attachments: RealityViewAttachments) {
        // If gesture is inactive, remove existing entity
        guard isGestureActive, let handTransform = currentHandTransform else {
            if let handRoot = content.entities.first(where: { $0.name == "handGestureRoot" }) {
                content.remove(handRoot)
                print("🗑️ Removed hand gesture panel")
            }
            return
        }

        // If entity already exists, just update transform (prevents flickering)
        if let existingHandRoot = content.entities.first(where: { $0.name == "handGestureRoot" }) {
            existingHandRoot.transform = Transform(matrix: handTransform)
            return
        }

        // Create new entity (first detection only)
        let handRoot = Entity()
        handRoot.name = "handGestureRoot"
        handRoot.transform = Transform(matrix: handTransform)

        if let panelAttachment = attachments.entity(for: "gestureControlPanel") {
            // Position 15cm above hand
            panelAttachment.position = [0, 0.15, 0]

            // Make panel always face the camera
            panelAttachment.components.set(BillboardComponent())

            handRoot.addChild(panelAttachment)
            print("✨ Created hand gesture panel at position: \(handRoot.position)")
        }

        content.add(handRoot)
    }
}
