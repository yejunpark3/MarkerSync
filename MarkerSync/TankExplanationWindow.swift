//
//  TankExplanationWindow.swift
//  MarkerSync
//
//  Created for tank explanation window
//

import SwiftUI

struct TankExplanationView: View {
    let title: String
    let description: String

    init(title: String = "K2 블랙 팬서", description: String = "대한민국 육군의 주력 전차. 3세대 전차로, 120mm 주포와 강력한 장갑을 갖추고 있습니다.") {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }

            Divider()

            // Description
            Text(description)
                .font(.subheadline)
                .lineSpacing(4)

            // Additional info
            HStack(spacing: 8) {
                InfoItem(label: "무게", value: "55톤")
                InfoItem(label: "승무원", value: "4명")
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

struct InfoItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        TankExplanationView()
    }
}
