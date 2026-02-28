//
//  ControlPanelView.swift
//  MarkerSync
//
//  Main control panel for tank customization
//

import SwiftUI

struct ControlPanelView: View {
    let isHost: Bool
    @Binding var currentColor: TankColor
    @Binding var currentOptions: TankOptions

    var body: some View {
        VStack(spacing: 20) {
            Text("K2 전차 제어")
                .font(.title2.bold())

            if isHost {
                ColorPickerGrid(
                    selection: $currentColor,
                    colors: TankColor.allCases,
                    isEnabled: isHost
                )

                Divider()

                OptionsControlView(
                    options: $currentOptions,
                    isEnabled: isHost
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("관람 모드")
                        .font(.headline)

                    Text("Host가 제어 중입니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(32)
        .frame(width: 400, height: 600)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        HStack(spacing: 40) {
            ControlPanelView(
                isHost: true,
                currentColor: .constant(.red),
                currentOptions: .constant(TankOptions())
            )

            ControlPanelView(
                isHost: false,
                currentColor: .constant(.blue),
                currentOptions: .constant(TankOptions())
            )
        }
    }
}
