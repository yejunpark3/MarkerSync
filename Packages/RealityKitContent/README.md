  # K2 Tank Color Customization Implementation Plan

  ## Overview

  Implement a floating control panel UI for K2 tank color customization in visionOS. **This implementation focuses on UI only** - actual color application and network
  synchronization will be implemented later.

  **Scope**: UI-only implementation (color selection interface)
  **UI Pattern**: Floating Control Panel (SwiftUI Attachment above tank)
  **Future Work**: Material application, SharePlay synchronization

  ---

  ## Current Status

  ### ✅ Already Implemented
  - TankCustomizationModels.swift exists with TankColor enum (4 colors)
  - TankCustomizationManager.swift exists with basic state management
  - ControlPanelView.swift exists with panel UI structure
  - ColorPickerView.swift exists with color grid UI
  - ARManager.swift has `customizationManager` property declared (line 44)
  - MarkerSyncApp.swift has Environment injection for customizationManager (lines 24, 31)

  ### ❌ Missing Implementation
  - TankCustomizationManager not initialized in ARManager
  - ModelDisplayView missing RealityView `attachments:` block
  - No floating toggle button to show/hide panel
  - Panel not positioned/attached to tank entity

  ---

  ## Implementation Strategy

  ### Phase 1: Initialize TankCustomizationManager
  Ensure manager is properly created and accessible.

  **Modified Files:**
  - `MarkerSync/ARManager.swift`
  - Add initialization in `init()`: `customizationManager = TankCustomizationManager()`

  **Testing**: Verify manager accessible via environment in views

  ---

  ### Phase 2: Integrate Floating Panel in ModelDisplayView
  Add RealityView attachments block and position panel above tank (MAIN WORK).

  **Modified Files:**
  - `MarkerSync/ModelDisplayView.swift`
  - Add `attachments:` parameter to RealityView
  - Create `Attachment(id: "controlPanel")` with ControlPanelView
  - In `update:` closure:
  - Find tank entity from `modelEntities[anchorId]`
  - Position attachment at `[0, 0.4, 0]` relative to tank
  - Add `BillboardComponent()` for camera-facing behavior
  - Toggle visibility based on `customizationManager.isPanelVisible`
  - Add floating toggle button in overlay to show/hide panel

  **Testing**: Panel appears above tank, toggles visibility, always faces camera

  ---

  ### Phase 3: Polish and Verification
  Test UI interactions and ensure smooth UX.

  **Testing Checklist:**
  - [ ] Panel positioned correctly above tank
  - [ ] Billboard component makes panel face camera
  - [ ] Toggle button shows/hides panel smoothly
  - [ ] Color selection updates state
  - [ ] UI maintains 60 FPS
  - [ ] Works with multiple anchors (panel attached to selected tank)

  ---

  ## Critical Files

  ### Files to Modify (2 existing files)
  1. `/MarkerSync/ARManager.swift` - Initialize customizationManager
  2. `/MarkerSync/ModelDisplayView.swift` - Add attachments block, toggle button, positioning logic

  ### Files NOT Creating (Future Implementation)
  - ❌ `CustomizationMessage.swift` - Network protocol (not needed yet)
  - ❌ `ARManager+Customization.swift` - Network sync (not needed yet)
  - ❌ `MaterialApplicator.swift` - Material application (not needed yet)

  ---

  ## Key Technical Details

  ### 1. Attachment Positioning Approach
  ```swift
  // In ModelDisplayView update: closure
  if let anchorId = selectedAnchorId,
  let container = modelEntities[anchorId],
  let panelEntity = attachments.entity(for: "controlPanel") {

  // Position panel 0.4m above tank
  panelEntity.position = [0, 0.4, 0]

  // Add billboard component (camera-facing)
  panelEntity.components.set(BillboardComponent())

  // Add as child of tank container
  container.addChild(panelEntity)

  // Toggle visibility
  panelEntity.isEnabled = customizationManager.isPanelVisible
  }
  ```

  ### 2. Toggle Button in Overlay
  ```swift
  // Add button to statusOverlay
  if let selectedAnchorId, arManager.sharedAnchors[selectedAnchorId] != nil {
  VStack {
  HStack {
  Spacer()
  Button {
  customizationManager.togglePanel()
  } label: {
  Image(systemName: "paintpalette.fill")
  .font(.title2)
  }
  .buttonStyle(.bordered)
  .padding()
  }
  Spacer()
  }
  }
  ```

  ---

  ## Verification Checklist

  ### Manual Testing
  - [ ] ARManager initializes customizationManager successfully
  - [ ] Panel appears above tank when toggle button pressed
  - [ ] Panel always faces camera (billboard behavior)
  - [ ] Color selection updates state visually
  - [ ] Panel hides when toggle button pressed again
  - [ ] UI maintains 60 FPS
  - [ ] Works with multiple anchors

  ---

  ## Success Criteria

  ✅ Floating control panel appears above tank
  ✅ Panel toggles show/hide smoothly
  ✅ Color picker UI fully functional
  ✅ UI follows visionOS design patterns
  ✅ No performance degradation

  **Deferred to future phases:**
  - Color material application to 3D model
  - Network synchronization
  - Role-based access control