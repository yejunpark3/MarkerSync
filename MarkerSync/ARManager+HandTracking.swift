import ARKit
import Foundation

// MARK: - Hand Tracking Extension

extension ARManager {

    // MARK: - Hand Tracking Lifecycle

    /// Start hand tracking for heart gesture detection
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
                print("🖐️ Hand anchor update received: \(update.event)")
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
        print("👆 handleHandAnchorUpdate called - chirality: \(anchor.chirality), isTracked: \(anchor.isTracked)")

        // Collect both hands data
        if anchor.chirality == .left {
            handsData.left = anchor.isTracked ? anchor : nil
            print("   Left hand: \(handsData.left != nil ? "tracked" : "nil")")
        } else if anchor.chirality == .right {
            handsData.right = anchor.isTracked ? anchor : nil
            print("   Right hand: \(handsData.right != nil ? "tracked" : "nil")")
        }

        print("   Both hands tracked: \(handsData.bothHandsTracked)")

        // Attempt heart gesture detection
        if let transform = computeHeartGesture() {
            logHeartGestureDetection(transform: transform)
        } else {
            print("   ❌ No gesture detected this frame")
        }
    }

    // MARK: - Heart Gesture Detection (HappyBeam Algorithm)

    /// Compute heart gesture from both hands (based on HappyBeam implementation)
    /// - Returns: Transform at heart center if gesture is detected, nil otherwise
    private func computeHeartGesture() -> simd_float4x4? {
        guard let leftHand = handsData.left,
              let rightHand = handsData.right,
              leftHand.isTracked,
              rightHand.isTracked else {
            print("   [Gesture] ❌ Both hands not tracked")
            return nil
        }

        // Extract required joints
        guard let leftThumbKnuckle = leftHand.handSkeleton?.joint(.thumbKnuckle),
              let leftThumbTip = leftHand.handSkeleton?.joint(.thumbTip),
              let leftIndexTip = leftHand.handSkeleton?.joint(.indexFingerTip),
              let rightThumbKnuckle = rightHand.handSkeleton?.joint(.thumbKnuckle),
              let rightThumbTip = rightHand.handSkeleton?.joint(.thumbTip),
              let rightIndexTip = rightHand.handSkeleton?.joint(.indexFingerTip) else {
            print("   [Gesture] ❌ Missing joint data")
            return nil
        }

        // Convert to world coordinates (HappyBeam approach)
        let leftThumbTipWorld = matrix_multiply(
            leftHand.originFromAnchorTransform,
            leftThumbTip.anchorFromJointTransform
        ).columns.3.xyz

        let rightThumbTipWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightThumbTip.anchorFromJointTransform
        ).columns.3.xyz

        let leftIndexTipWorld = matrix_multiply(
            leftHand.originFromAnchorTransform,
            leftIndexTip.anchorFromJointTransform
        ).columns.3.xyz

        let rightIndexTipWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightIndexTip.anchorFromJointTransform
        ).columns.3.xyz

        // Distance calculations (HappyBeam logic)
        let indexDistance = distance(leftIndexTipWorld, rightIndexTipWorld)
        let thumbDistance = distance(leftThumbTipWorld, rightThumbTipWorld)

        print("   [Gesture] Index distance: \(String(format: "%.4f", indexDistance))m, Thumb distance: \(String(format: "%.4f", thumbDistance))m")

        // 4cm threshold check (same as HappyBeam)
        guard indexDistance < HeartGestureConfig.fingerDistanceThreshold &&
              thumbDistance < HeartGestureConfig.fingerDistanceThreshold else {
            print("   [Gesture] ❌ Distance threshold not met (max: \(String(format: "%.4f", HeartGestureConfig.fingerDistanceThreshold))m)")
            return nil
        }

        print("   [Gesture] ✅ Heart gesture threshold met!")

        // Calculate heart midpoint (HappyBeam approach)
        let halfway = (rightIndexTipWorld - leftThumbTipWorld) / 2
        let heartMidpoint = rightIndexTipWorld - halfway

        // Calculate axes (HappyBeam approach)
        let leftThumbKnuckleWorld = matrix_multiply(
            leftHand.originFromAnchorTransform,
            leftThumbKnuckle.anchorFromJointTransform
        ).columns.3.xyz

        let rightThumbKnuckleWorld = matrix_multiply(
            rightHand.originFromAnchorTransform,
            rightThumbKnuckle.anchorFromJointTransform
        ).columns.3.xyz

        let xAxis = normalize(rightThumbKnuckleWorld - leftThumbKnuckleWorld)
        let yAxis = normalize(rightIndexTipWorld - rightThumbTipWorld)
        let zAxis = normalize(cross(xAxis, yAxis))

        // Create transform (HappyBeam approach)
        let transform = simd_matrix(
            SIMD4(xAxis.x, xAxis.y, xAxis.z, 0),
            SIMD4(yAxis.x, yAxis.y, yAxis.z, 0),
            SIMD4(zAxis.x, zAxis.y, zAxis.z, 0),
            SIMD4(heartMidpoint.x, heartMidpoint.y, heartMidpoint.z, 1)
        )

        return transform
    }

    // MARK: - Logging

    /// Log heart gesture detection to console
    private func logHeartGestureDetection(transform: simd_float4x4) {
        let position = transform.columns.3.xyz
        let now = Date()

        // Throttle logging to prevent spam (0.5s interval)
        if let lastLog = lastGestureTime,
           now.timeIntervalSince(lastLog) < HeartGestureConfig.logThrottleInterval {
            return
        }

        lastGestureTime = now
        gestureDetectionState = .detected

        print("❤️ HEART GESTURE DETECTED!")
        print("   Position: (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))")
        print("   Timestamp: \(now)")

        // Optional: Post notification for future extensions
        NotificationCenter.default.post(name: .heartGestureDetected, object: transform)
    }
}

// MARK: - SIMD4 Extension

extension SIMD4 {
    /// Extract xyz components from SIMD4
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}
