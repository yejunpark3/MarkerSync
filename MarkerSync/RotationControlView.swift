//
//  RotationControlView.swift
//  MarkerSync
//
//  Tank Y-axis rotation control component
//

import SwiftUI
import Foundation

struct RotationControlView: View {
    @Binding var rotation: Float
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("방향 조절")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(displayText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                ForEach(TankRotationPreset.allCases, id: \.self) { preset in
                    Button {
                        guard isEnabled else { return }
                        rotation = preset.rawValue
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

            Slider(
                value: Binding(
                    get: { Double(rotation) },
                    set: { rotation = Float($0) }
                ),
                in: Double(TankRotationConfig.minDegrees)...Double(TankRotationConfig.maxDegrees),
                step: 1
            )
            .disabled(!isEnabled)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var displayText: String {
        String(format: "%.0f°", rotation.truncatingRemainder(dividingBy: 360))
    }

    private func isPresetSelected(_ preset: TankRotationPreset) -> Bool {
        abs(rotation - preset.rawValue) < 0.5
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        RotationControlView(rotation: .constant(90), isEnabled: true)
            .padding()
    }
}
