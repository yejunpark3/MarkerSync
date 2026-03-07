import PeerToPeerMessaging

public enum TankCommand: PeerToPeerMessage {
    case handshake
    case tankEvent(TankEvent)
    case stateSync(TankState)
    case meshListSync([MeshItemInfo])

    public enum TankEvent: PeerToPeerMessage {
        case colorChange(TankColor)
        case scaleChange(Float)
        case rotationChange(Float)
        case optionsChange(TankOptions)
        case billboardVisibility(Bool)
        case meshVisibility(key: String, isVisible: Bool)
    }
}

public struct TankState: Codable, Sendable, Hashable {
    public var color: TankColor
    public var scale: Float
    public var rotation: Float
    public var options: TankOptions
    public var showBillboards: Bool
    public var meshVisibility: [String: Bool]
}

public struct MeshItemInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var entityKey: String
    public var displayName: String
    public var isVisible: Bool
}
