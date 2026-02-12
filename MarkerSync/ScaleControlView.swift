//
//  ScaleControlView.swift
//  MarkerSync
//
//  Tank scale control component
//

import SwiftUI
import Foundation

struct ScaleControlView: View {
    @Binding var scale: Float
    let isEnabled: Bool

    @State private var edgePulse: CGFloat = 1.0
    @State private var lastBoundary: BoundaryState = .none

    private enum BoundaryState {
        case none
        case min
        case max
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("크기 조절")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(displayText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                ForEach(TankScalePreset.allCases, id: \.self) { preset in
                    Button {
                        guard isEnabled else { return }
                        updateScale(preset.scale)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: preset.iconName)
                                .font(.caption)
                            Text(preset.label)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPresetSelected(preset) ? .accentColor : .gray.opacity(0.35))
                    .disabled(!isEnabled)
                }
            }

            HStack(spacing: 8) {
                Text("최소")
                    .font(.caption2)
                    .foregroundStyle(atMinimum ? .orange : .secondary)
                    .scaleEffect(atMinimum ? edgePulse : 1.0)

                Slider(
                    value: Binding(
                        get: { Double(scale) },
                        set: { newValue in
                            updateScale(Float(newValue))
                        }
                    ),
                    in: Double(TankScaleConfig.minScale)...Double(TankScaleConfig.maxScale),
                    step: 0.01
                )
                .disabled(!isEnabled)

                Text("최대")
                    .font(.caption2)
                    .foregroundStyle(atMaximum ? .orange : .secondary)
                    .scaleEffect(atMaximum ? edgePulse : 1.0)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var displayText: String {
        let clamped = clamp(scale)
        return String(format: "%.2fx (%@)", clamped, TankScaleConfig.estimatedSize(clamped))
    }

    private var atMinimum: Bool {
        abs(clamp(scale) - TankScaleConfig.minScale) < 0.001
    }

    private var atMaximum: Bool {
        abs(clamp(scale) - TankScaleConfig.maxScale) < 0.001
    }

    private func isPresetSelected(_ preset: TankScalePreset) -> Bool {
        abs(clamp(scale) - preset.scale) < 0.001
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, TankScaleConfig.minScale), TankScaleConfig.maxScale)
    }

    private func updateScale(_ newValue: Float) {
        let clamped = clamp(newValue)
        scale = clamped

        let boundary: BoundaryState
        if abs(clamped - TankScaleConfig.minScale) < 0.001 {
            boundary = .min
        } else if abs(clamped - TankScaleConfig.maxScale) < 0.001 {
            boundary = .max
        } else {
            boundary = .none
        }

        if boundary != .none && boundary != lastBoundary {
            triggerBoundaryPulse()
        }
        lastBoundary = boundary
    }

    private func triggerBoundaryPulse() {
        edgePulse = 1.12
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            edgePulse = 1.0
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ScaleControlView(scale: .constant(0.5), isEnabled: true)
            .padding()
    }
}
