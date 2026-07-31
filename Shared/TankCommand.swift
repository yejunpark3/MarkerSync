import PeerToPeerMessaging

enum TankCommand: PeerToPeerMessage {
    case handshake
    case tankEvent(TankEvent)
    case stateSync(TankState)
    case meshListSync([MeshItemInfo])

    enum TankEvent: PeerToPeerMessage {
        case colorChange(TankColor)
        case scaleChange(Float)
        case rotationChange(Float)
        case optionsChange(TankOptions)
        case billboardVisibility(Bool)
        case meshVisibility(key: String, isVisible: Bool)
    }
}

struct TankState: Codable, Sendable, Hashable {
    var color: TankColor
    var scale: Float
    var rotation: Float
    var options: TankOptions
    var showBillboards: Bool
    var meshVisibility: [String: Bool]
}

struct MeshItemInfo: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var entityKey: String
    var displayName: String
    var isVisible: Bool
}
