//
//  ColorPickerView.swift
//  MarkerSync
//
//  Color picker components for tank customization
//

import SwiftUI

struct ColorPickerGrid: View {
    @Binding var selection: TankColor
    let colors: [TankColor]
    let isEnabled: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(colors, id: \.self) { color in
                ColorSwatch(
                    color: color,
                    isSelected: selection == color,
                    isEnabled: isEnabled
                )
                .onTapGesture {
                    if isEnabled {
                        selection = color
                    }
                }
            }
        }
    }
}

struct ColorSwatch: View {
    let color: TankColor
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.uiColor)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: isSelected ? 4 : 0)
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(), value: isSelected)

                if !isEnabled {
                    Color.black.opacity(0.3)
                        .clipShape(Circle())
                }
            }

            Text(color.displayName)
                .font(.caption)
                .foregroundStyle(isEnabled ? .primary : .secondary)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ColorPickerGrid(
            selection: .constant(.desertTan),
            colors: TankColor.allCases,
            isEnabled: true
        )
        .padding()
    }
}
