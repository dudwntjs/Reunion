import CloudKit
import Foundation

@main
struct CloudRecordCheck {
    static func main() throws {
        var meeting = Meeting()
        meeting.place = "약속 장소"
        meeting.coordinate = Coordinate(latitude: 37.5, longitude: 127)
        meeting.origin = Coordinate(latitude: 38, longitude: 128)
        let zoneID = CKRecordZone.ID(zoneName: "offline-test", ownerName: CKCurrentUserDefaultName)
        let records = try CloudRecordCodec.newGroup(meeting: meeting, deviceID: "device-A", name: "나", zoneID: zoneID)
        precondition(records.count == 12)
        let share = records[1] as! CKShare
        precondition(share.publicPermission == .none, "No public access to participant locations")
        let slots = Array(records.dropFirst(2))
        precondition(slots.count == 10 && Set(slots.map { $0.recordID.recordName }).count == 10)
        precondition(slots.allSatisfy { $0.parent?.recordID == records[0].recordID })
        let snapshotRecords = [records[0]] + slots
        let initial = try CloudRecordCodec.snapshot(snapshotRecords, notificationWarning: nil)
        precondition(initial.meeting.origin == meeting.coordinate, "Do not upload private origin before consent")
        precondition(initial.participants.count == 1)
        precondition(initial.participants[0].coordinate == nil && initial.participants[0].sharingEnabled == false)
        let peer = Peer(
            id: "device-B",
            name: "친구",
            phase: "moving",
            sharingEnabled: true,
            coordinate: Coordinate(latitude: 37.51, longitude: 127.01),
            updatedAt: 1,
            coordinateUpdatedAt: 1,
            eta: 100
        )
        slots[1]["peer"] = try JSONEncoder().encode(peer) as NSData
        let active = try CloudRecordCodec.snapshot(snapshotRecords, notificationWarning: "test-warning")
        precondition(active.participants.count == 2 && active.participants[1].coordinate != nil)
        precondition(active.notificationWarning == "test-warning")
        records[0]["ended"] = 1 as NSNumber
        let ended = try CloudRecordCodec.snapshot(snapshotRecords, notificationWarning: nil)
        precondition(
            ended.ended
                && ended.participants.allSatisfy { $0.coordinate == nil && $0.phase == "complete" && $0.eta == nil }
        )
        do {
            _ = try CloudRecordCodec.snapshot([], notificationWarning: nil)
            preconditionFailure("Reject missing root")
        } catch {}
        print(
            "CloudKit record checks passed: private invitation, ten slots, origin privacy, consent, independent peers, termination, malformed data"
        )
    }
}
