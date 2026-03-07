import SwiftUI
import PeerToPeerMessaging

@MainActor
@Observable
class CompanionViewModel {
    var color: TankColor = .red
    var scale: Float = 0.1
    var rotation: Float = 0
    var options: TankOptions = TankOptions()
    var showBillboards: Bool = false
    var meshItems: [MeshItemInfo] = []

    private let serverController: PeerMessagingController<Server<TankCommand>>

    init(serverController: PeerMessagingController<Server<TankCommand>>) {
        self.serverController = serverController
    }

    // MARK: - Outgoing (User Input -> Vision Pro)

    func syncColor(_ color: TankColor) {
        self.color = color
        serverController.send(.tankEvent(.colorChange(color)))
    }

    func syncScale(_ scale: Float) {
        self.scale = scale
        serverController.send(.tankEvent(.scaleChange(scale)))
    }

    func syncRotation(_ rotation: Float) {
        self.rotation = rotation
        serverController.send(.tankEvent(.rotationChange(rotation)))
    }

    func syncOptions(_ options: TankOptions) {
        self.options = options
        serverController.send(.tankEvent(.optionsChange(options)))
    }

    func syncShowBillboards(_ show: Bool) {
        self.showBillboards = show
        serverController.send(.tankEvent(.billboardVisibility(show)))
    }

    func syncMeshVisibility(key: String, isVisible: Bool) {
        if let index = meshItems.firstIndex(where: { $0.entityKey == key }) {
            meshItems[index].isVisible = isVisible
            serverController.send(.tankEvent(.meshVisibility(key: key, isVisible: isVisible)))
        }
    }

    // MARK: - Incoming (Vision Pro -> Local State)

    func handleTankEvent(_ event: TankCommand.TankEvent) {
        switch event {
        case .colorChange(let color):
            self.color = color
        case .scaleChange(let scale):
            self.scale = scale
        case .rotationChange(let rotation):
            self.rotation = rotation
        case .optionsChange(let options):
            self.options = options
        case .billboardVisibility(let isVisible):
            self.showBillboards = isVisible
        case .meshVisibility(let key, let isVisible):
            if let index = meshItems.firstIndex(where: { $0.entityKey == key }) {
                meshItems[index].isVisible = isVisible
            }
        }
    }

    func handleStateSync(_ state: TankState) {
        self.color = state.color
        self.scale = state.scale
        self.rotation = state.rotation
        self.options = state.options
        self.showBillboards = state.showBillboards
        
        // meshVisibility dictionary to meshItems array happens separately via meshListSync usually,
        // or we can apply it if meshItems is already populated.
        for (key, isVisible) in state.meshVisibility {
            if let index = meshItems.firstIndex(where: { $0.entityKey == key }) {
                meshItems[index].isVisible = isVisible
            }
        }
    }

    func handleMeshListSync(_ items: [MeshItemInfo]) {
        self.meshItems = items
    }
}
