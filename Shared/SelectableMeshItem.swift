import Foundation

public struct SelectableMeshItem: Identifiable, Equatable, Codable, Sendable, Hashable {
    public let id: String
    public let entityKey: String
    public let sourceName: String
    public let displayName: String
    public var isVisible: Bool
    
    public init(id: String, entityKey: String, sourceName: String, displayName: String, isVisible: Bool) {
        self.id = id
        self.entityKey = entityKey
        self.sourceName = sourceName
        self.displayName = displayName
        self.isVisible = isVisible
    }
}
