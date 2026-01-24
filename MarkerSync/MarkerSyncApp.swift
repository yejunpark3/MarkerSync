//
//  MarkerSyncApp.swift
//  MarkerSync
//
//  Created by 박예준 on 1/18/26.
//

import SwiftUI

@main
struct MarkerSyncApp: App {
    @State private var arManager = ARManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(arManager)
        }
        .defaultSize(width: 500, height: 800)
        // .groupActivityAssociation(ARCollaborationActivity.self)  // Not available in this SDK version

        ImmersiveSpace(id: "tracking") {
            MarkerTrackingView()
                .environment(arManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: "model") {
            ModelDisplayView()
                .environment(arManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
