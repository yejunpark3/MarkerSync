import GroupActivities

struct ARCollaborationActivity: GroupActivity {
    static let activityIdentifier = "com.markersync.arcollaboration"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "AR 마커 협업"
        metadata.type = .generic
        metadata.supportsContinuationOnTV = false
        return metadata
    }
}
