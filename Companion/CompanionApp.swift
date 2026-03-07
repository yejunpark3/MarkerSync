import SwiftUI
import PeerToPeerMessaging

@main
struct CompanionApp: App {
    @State private var serverController: PeerMessagingController<Server<TankCommand>>
    @State private var viewModel: CompanionViewModel

    init() {
        let sc = PeerMessagingController<Server<TankCommand>>()
        let vm = CompanionViewModel(serverController: sc)
        self.serverController = sc
        self.viewModel = vm
    }

    var body: some Scene {
        WindowGroup {
            CompanionContentView()
                .environment(serverController)
                .environment(viewModel)
        }
    }
}
