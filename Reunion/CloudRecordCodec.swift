import CloudKit
import Foundation

/// Record structure shared by creation, synchronization, and offline validation.
enum CloudRecordCodec {
    static func newGroup(meeting: Meeting, deviceID: String, name: String, zoneID: CKRecordZone.ID) throws -> [CKRecord]
    {
        let root = CKRecord(recordType: "ReunionMeeting", recordID: .init(recordName: "meeting", zoneID: zoneID))
        var publicMeeting = meeting
        publicMeeting.origin = meeting.coordinate
        root["meeting"] = try JSONEncoder().encode(publicMeeting) as NSData
        root["ended"] = 0 as NSNumber
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "다시 만나 · \(meeting.place)" as NSString
        share.publicPermission = .none
        let slots = (0..<10)
            .map { index in
                let slot = CKRecord(
                    recordType: "ReunionParticipant",
                    recordID: .init(recordName: "participant-\(index)", zoneID: zoneID)
                )
                slot.parent = CKRecord.Reference(recordID: root.recordID, action: .none)
                return slot
            }
        slots[0]["deviceID"] = deviceID as NSString
        slots[0]["peer"] =
            try JSONEncoder()
            .encode(
                Peer(
                    id: deviceID,
                    name: name,
                    phase: "free",
                    sharingEnabled: false,
                    updatedAt: Date().timeIntervalSince1970
                )
            ) as NSData
        return [root, share] + slots
    }

    static func snapshot(_ records: [CKRecord], notificationWarning: String?) throws -> RemoteSession {
        guard let root = records.first, let data = root["meeting"] as? Data else {
            throw SessionClient.Failure.invalidData
        }
        let ended = (root["ended"] as? NSNumber)?.boolValue == true
        let peers = try records.dropFirst()
            .compactMap { slot -> Peer? in
                guard let payload = slot["peer"] as? Data else { return nil }
                var peer = try JSONDecoder().decode(Peer.self, from: payload)
                if ended {
                    peer.phase = "complete"
                    peer.sharingEnabled = false
                    peer.coordinate = nil
                    peer.coordinateUpdatedAt = nil
                    peer.eta = nil
                    peer.heading = nil
                }
                return peer
            }
        return RemoteSession(
            meeting: try JSONDecoder().decode(Meeting.self, from: data),
            participants: peers,
            ended: ended,
            notificationWarning: notificationWarning
        )
    }
}
