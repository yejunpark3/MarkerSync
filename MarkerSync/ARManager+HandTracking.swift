import ARKit
import Foundation

// MARK: - Hand Tracking Extension

extension ARManager {

    // MARK: - Hand Tracking Lifecycle

    /// Start hand tracking for palm-up gesture detection
    func startHandTracking() async throws {
        guard let handTracking = handTracking else {
            throw ARError.handTrackingUnavailable
        }

        print("👋 Starting hand tracking...")
        gestureDetectionState = .searching

        // Monitor anchor updates
        // Note: Provider is already running from setupProviders()
        handTrackingTask = Task { [weak self] in
            guard let self = self, let handTracking = self.handTracking else { return }

            for await update in handTracking.anchorUpdates {
                // print("🖐️ Hand anchor update received: \(update.event)")
                if Task.isCancelled { break }
                await MainActor.run {
                    self.handleHandAnchorUpdate(update)
                }
            }
            print("⚠️ Hand tracking loop ended")
        }

        print("✅ Hand tracking started")
    }

    /// Stop hand tracking
    func stopHandTracking() {
        handTrackingTask?.cancel()
        handTrackingTask = nil
        gestureDetectionState = .notTracking
        handsData = HandsData()
        print("🛑 Hand tracking stopped")
    }

    // MARK: - Anchor Update Handling

    /// Handle hand anchor updates from ARKit
    private func handleHandAnchorUpdate(_ update: AnchorUpdate<HandAnchor>) {
        let anchor = update.anchor
        // print("👆 handleHandAnchorUpdate called - chirality: \(anchor.chirality), isTracked: \(anchor.isTracked)")

        // Track previous gesture state
        let wasDetected = (gestureDetectionState == .detected)

        // Collect both hands data
        if anchor.chirality == .left {
            handsData.left = anchor.isTracked ? anchor : nil
            // print("   Left hand: \(handsData.left != nil ? "tracked" : "nil")")
        } else if anchor.chirality == .right {
            handsData.right = anchor.isTracked ? anchor : nil
            // print("   Right hand: \(handsData.right != nil ? "tracked" : "nil")")
        }

        // print("   Both hands tracked: \(handsData.bothHandsTracked)")

        // Attempt palm-up gesture detection
        if let transform = computePalmUpGesture() {
            logPalmUpGestureDetection(transform: transform)
        } else {
            // print("   ❌ No gesture detected this frame")

            // Post gesture ended notification if gesture was previously detected
            if wasDetected {
                gestureDetectionState = .searching
                NotificationCenter.default.post(name: .palmUpGestureEnded, object: nil)
                print("👋 Palm-up gesture ENDED")
            }
        }
    }

    // MARK: - Palm-Up Gesture Detection

    /// Compute palm-up gesture from right hand only
    /// Detects when right palm is facing upward
    /// - Returns: Transform at right wrist if detected, nil otherwise
    private func computePalmUpGesture() -> simd_float4x4? {
        // Step 1: Verify RIGHT hand is tracked (left hand not needed)
        guard let rightHand = handsData.right,
              rightHand.isTracked else {
            // print("   [Gesture] ❌ Right hand not tracked")
            return nil
        }

        // Step 2: Extract required joints for palm normal calculation
        guard let rightWrist = rightHand.handSkeleton?.joint(.wrist),
              let rightIndexMeta = rightHand.handSkeleton?.joint(.indexFingerMetacarpal),
              let rightRingMeta = rightHand.handSkeleton?.joint(.ringFingerMetacarpal) else {
            // print("   [Gesture] ❌ Missing joint data")
            return nil
        }

        // Step 3: Convert joints to world coordinates
        let rightWristWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightWrist.anchorFromJointTransform
        ).columns.3.xyz

        let rightIndexMetaWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightIndexMeta.anchorFromJointTransform
        ).columns.3.xyz

        let rightRingMetaWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightRingMeta.anchorFromJointTransform
        ).columns.3.xyz

        // Step 4: Calculate palm normal using cross product
        let v1 = rightIndexMetaWorld - rightWristWorld
        let v2 = rightRingMetaWorld - rightWristWorld
        let palmNormal = normalize(cross(v1, v2))

        // Step 5: Check orientation against up vector
        let upVector = SIMD3<Float>(0, 1, 0)
        let dotProduct = dot(palmNormal, upVector)

        // print("   [Gesture] Right palm dot: \(String(format: "%.3f", dotProduct))")

        // Step 6: Check threshold
        guard dotProduct > PalmUpGestureConfig.palmUpThreshold else {
            // print("   [Gesture] ❌ Palm orientation threshold not met (threshold: \(String(format: "%.3f", PalmUpGestureConfig.palmUpThreshold)))")
            return nil
        }

        // print("   [Gesture] ✅ Right palm-up gesture detected!")

        // Step 7: Create transform at right wrist position
        // Y-axis: palm normal (pointing up)
        let yAxis = palmNormal
        // X-axis: direction from wrist to index metacarpal
        let xAxis = normalize(rightIndexMetaWorld - rightWristWorld)
        // Z-axis: perpendicular to both
        let zAxis = normalize(cross(xAxis, yAxis))

        let transform = simd_matrix(
            SIMD4(xAxis.x, xAxis.y, xAxis.z, 0),
            SIMD4(yAxis.x, yAxis.y, yAxis.z, 0),
            SIMD4(zAxis.x, zAxis.y, zAxis.z, 0),
            SIMD4(rightWristWorld.x, rightWristWorld.y, rightWristWorld.z, 1)
        )

        return transform
    }

    // MARK: - Logging

    /// Log palm-up gesture detection to console
    private func logPalmUpGestureDetection(transform: simd_float4x4) {
        let position = transform.columns.3.xyz
        let now = Date()

        // Throttle logging to prevent spam (0.5s interval)
        if let lastLog = lastGestureTime,
           now.timeIntervalSince(lastLog) < PalmUpGestureConfig.logThrottleInterval {
            return
        }

        lastGestureTime = now
        gestureDetectionState = .detected

        print("🙌 RIGHT PALM-UP GESTURE DETECTED!")
        print("   Position: (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))")
        print("   Timestamp: \(now)")

        // Post notification for future extensions
        NotificationCenter.default.post(name: .palmUpGestureDetected, object: transform)
    }
}

// MARK: - SIMD4 Extension

extension SIMD4 {
    /// Extract xyz components from SIMD4
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}
