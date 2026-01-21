//
//  OptionsControlView.swift
//  MarkerSync
//
//  Equipment options control component
//

import SwiftUI

struct OptionsControlView: View {
    @Binding var options: TankOptions
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("장비 옵션")
                .font(.headline)

            Toggle("능동방어 시스템", isOn: $options.aps)
                .disabled(!isEnabled)

            Toggle("연막탄 발사기", isOn: $options.smokeDischarger)
                .disabled(!isEnabled)

            Toggle("지뢰제거 장비", isOn: $options.minePlow)
                .disabled(!isEnabled)

            Toggle("증가장갑", isOn: $options.additionalArmor)
                .disabled(!isEnabled)
        }
        .toggleStyle(.switch)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        OptionsControlView(
            options: .constant(TankOptions()),
            isEnabled: true
        )
        .padding()
    }
}
