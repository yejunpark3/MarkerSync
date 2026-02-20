//
//  TankPartBillboardView.swift
//  MarkerSync
//
//  SwiftUI view for part description billboard cards in the 3D scene.
//

import SwiftUI

/// Billboard card displayed as a ViewAttachmentEntity above a tank part.
struct TankPartBillboardView: View {
    let part: TankPart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text(part.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }

            Divider()

            // Description
            Text(part.description)
                .font(.caption)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Specs
            if !part.specs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(part.specs.enumerated()), id: \.offset) { _, spec in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spec.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(spec.value)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(radius: 8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TankPartBillboardView(part: TankPartRegistry.all[0])
    }
}
