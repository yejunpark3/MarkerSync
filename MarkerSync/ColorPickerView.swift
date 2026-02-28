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
        VStack(alignment: .leading, spacing: 8) {
            Text("색상 선택")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
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
                    .frame(width: 50, height: 50)
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

struct SelectableMeshToggleList: View {
    let items: [SelectableMeshItem]
    let isEnabled: Bool
    let onToggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("부위 표시")
                .font(.caption)
                .foregroundColor(.secondary)

            if items.isEmpty {
                Text("표시 가능한 부위 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        Toggle(
                            item.displayName,
                            isOn: Binding(
                                get: { item.isVisible },
                                set: { newValue in
                                    onToggle(item.entityKey, newValue)
                                }
                            )
                        )
                        .font(.caption)
                        .disabled(!isEnabled)
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ColorPickerGrid(
            selection: .constant(.red),
            colors: TankColor.allCases,
            isEnabled: true
        )
        .padding()
    }
}
