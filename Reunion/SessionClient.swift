import CloudKit
import Foundation

struct RemoteSession {
    var meeting: Meeting
    var participants: [Peer]
    var ended: Bool
    var notificationWarning: String?
}

struct SessionCredentials: Codable {
    var zoneName: String
    var ownerName: String
    var rootName: String
    var participantID: String
    var slotName: String
    var accountID: String
    var isOwner: Bool
    var shareURL: URL
}

struct SessionReply {
    var session: RemoteSession
    var credentials: SessionCredentials
}

/// Only explicitly invited iCloud accounts can access the shared hierarchy.
/// Invitees are trusted collaborators; CloudKit read/write permission covers the entire hierarchy.
actor SessionClient {
    static let shared = SessionClient()
    static let containerID = "iCloud.com.reunion.poc"
    private let container = CKContainer(identifier: containerID)
    private var subscribed: Set<String> = []
    private var retryAfter = Date.distantPast
    private var notificationWarning: String?

    enum Failure: LocalizedError {
        case account, wrongAccount, invalidLink, invalidData, full, ended, conflict, retry(Date)
        var errorDescription: String? {
            switch self {
            case .account: "iPhone 설정에서 iCloud에 로그인하고 iCloud Drive를 켜 주세요."
            case .wrongAccount: "모임에 참여했던 iCloud 계정으로 로그인해 주세요."
            case .invalidLink: "초대받은 iCloud 계정으로 이 앱의 초대 링크를 열어 주세요."
            case .invalidData: "모임 정보를 읽을 수 없어요. 초대 링크와 iCloud 설정을 확인해 주세요."
            case .full: "한 모임에는 최대 10대까지 참여할 수 있어요."
            case .ended: "이미 종료된 모임이에요. 새 초대로 참여해 주세요."
            case .conflict: "다른 참가자가 정보를 변경했어요. 잠시 후 다시 시도해 주세요."
            case .retry(let date): "iCloud 연결이 지연돼요. \(date.formatted(date: .omitted, time: .standard)) 이후 다시 시도해 주세요."
            }
        }
    }

    // MARK: - Connection

    func connect(name: String, link: String?, meeting: Meeting, deviceID: String) async throws -> SessionReply {
        let account = try await accountID()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { throw Failure.invalidData }
        if let link {
            guard let url = CloudInvitation.url(link) else { throw Failure.invalidLink }
            let metadata = try await container.shareMetadata(for: url)
            guard metadata.containerIdentifier == Self.containerID,
                let rootID = metadata.hierarchicalRootRecordID
            else { throw Failure.invalidLink }
            let isOwner = metadata.ownerIdentity.userRecordID?.recordName == account
            if !isOwner { _ = try await container.accept(metadata) }
            let zone = CKRecordZone.ID(
                zoneName: rootID.zoneID.zoneName,
                ownerName: isOwner ? CKCurrentUserDefaultName : rootID.zoneID.ownerName
            )
            let db = isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
            let root = CKRecord.ID(recordName: rootID.recordName, zoneID: zone)
            var credentials = SessionCredentials(
                zoneName: zone.zoneName,
                ownerName: zone.ownerName,
                rootName: root.recordName,
                participantID: deviceID,
                slotName: "",
                accountID: account,
                isOwner: isOwner,
                shareURL: url
            )
            for _ in 0..<4 {
                let records = try await fetch(root: root, db: db)
                guard !isEnded(records[0]) else { throw Failure.ended }
                let slots = Array(records.dropFirst())
                let existing = slots.first { ($0["deviceID"] as? String) == deviceID }
                guard let slot = existing ?? slots.first(where: { $0["deviceID"] == nil }) else { throw Failure.full }
                credentials.slotName = slot.recordID.recordName
                if existing == nil {
                    slot["deviceID"] = deviceID as NSString
                    slot["peer"] =
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
                    do { try await save([slot], db: db) } catch  where isConflict(error) { continue }
                }
                await subscribe(db: db, account: account)
                return SessionReply(session: try await state(credentials), credentials: credentials)
            }
            throw Failure.conflict
        }
        guard meeting.coordinate.isValid, !meeting.place.isEmpty, meeting.target > .now else {
            throw Failure.invalidData
        }
        let zone = CKRecordZone(zoneName: "Reunion-" + UUID().uuidString)
        _ = try await container.privateCloudDatabase.save(zone)
        let records = try CloudRecordCodec.newGroup(
            meeting: meeting,
            deviceID: deviceID,
            name: name,
            zoneID: zone.zoneID
        )
        let root = records[0]
        let share = records[1]
        let slots = Array(records.dropFirst(2))
        try await save([root, share] + slots, db: container.privateCloudDatabase)
        guard let savedShare = try await container.privateCloudDatabase.record(for: share.recordID) as? CKShare,
            let url = savedShare.url
        else { throw Failure.invalidData }
        let credentials = SessionCredentials(
            zoneName: zone.zoneID.zoneName,
            ownerName: zone.zoneID.ownerName,
            rootName: root.recordID.recordName,
            participantID: deviceID,
            slotName: slots[0].recordID.recordName,
            accountID: account,
            isOwner: true,
            shareURL: url
        )
        await subscribe(db: container.privateCloudDatabase, account: account)
        return SessionReply(session: try await state(credentials), credentials: credentials)
    }

    func share(_ credentials: SessionCredentials) async throws -> CKShare {
        try await validate(credentials)
        guard credentials.isOwner else { throw Failure.invalidLink }
        let root = try await container.privateCloudDatabase.record(for: rootID(credentials))
        guard let reference = root.share,
            let share = try await container.privateCloudDatabase.record(for: reference.recordID) as? CKShare
        else {
            throw Failure.invalidData
        }
        return share
    }

    // MARK: - Synchronization

    func state(_ credentials: SessionCredentials) async throws -> RemoteSession {
        try await validate(credentials)
        let db = database(credentials)
        await subscribe(db: db, account: credentials.accountID)
        return try snapshot(await fetch(root: rootID(credentials), db: db))
    }

    func update(
        _ credentials: SessionCredentials,
        phase: JourneyPhase,
        sharingEnabled: Bool,
        coordinate: Coordinate?,
        coordinateUpdatedAt: Date?,
        eta: Date?
    ) async throws -> RemoteSession {
        try await validate(credentials)
        let db = database(credentials)
        await subscribe(db: db, account: credentials.accountID)
        for _ in 0..<3 {
            let records = try await fetch(root: rootID(credentials), db: db)
            if isEnded(records[0]) { return try snapshot(records) }
            guard let slot = records.first(where: { $0.recordID.recordName == credentials.slotName }),
                (slot["deviceID"] as? String) == credentials.participantID,
                let payload = slot["peer"] as? Data
            else { throw Failure.invalidData }
            let previous = try JSONDecoder().decode(Peer.self, from: payload)
            var peer = previous
            peer.phase = phase.rawValue
            peer.sharingEnabled = sharingEnabled
            peer.coordinate = sharingEnabled ? coordinate : nil
            peer.coordinateUpdatedAt = peer.coordinate == nil ? nil : coordinateUpdatedAt?.timeIntervalSince1970
            peer.eta = eta?.timeIntervalSince1970
            if peer == previous && Date().timeIntervalSince1970 - previous.updatedAt < 30 {
                return try snapshot(records)
            }
            peer.updatedAt = Date().timeIntervalSince1970
            slot["peer"] = try JSONEncoder().encode(peer) as NSData
            do {
                try await save([slot], db: db)
                return try snapshot(records)
            } catch  where isConflict(error) { continue }
        }
        throw Failure.conflict
    }

    func end(_ credentials: SessionCredentials) async throws -> RemoteSession {
        try await validate(credentials)
        let db = database(credentials)
        for _ in 0..<3 {
            let records = try await fetch(root: rootID(credentials), db: db)
            if isEnded(records[0]) { return try snapshot(records) }
            records[0]["ended"] = 1 as NSNumber
            for slot in records.dropFirst() {
                guard let payload = slot["peer"] as? Data else { continue }
                var peer = try JSONDecoder().decode(Peer.self, from: payload)
                peer.phase = "complete"
                peer.sharingEnabled = false
                peer.coordinate = nil
                peer.coordinateUpdatedAt = nil
                peer.eta = nil
                slot["peer"] = try JSONEncoder().encode(peer) as NSData
            }
            do {
                try await save(records, db: db)
                return try snapshot(records)
            } catch  where isConflict(error) { continue }
        }
        throw Failure.conflict
    }

    // MARK: - CloudKit

    private func accountID() async throws -> String {
        if Date() < retryAfter { throw Failure.retry(retryAfter) }
        guard try await container.accountStatus() == .available else { throw Failure.account }
        return try await container.userRecordID().recordName
    }
    private func validate(_ credentials: SessionCredentials) async throws {
        guard try await accountID() == credentials.accountID else { throw Failure.wrongAccount }
    }
    private func database(_ credentials: SessionCredentials) -> CKDatabase {
        credentials.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }
    private func rootID(_ credentials: SessionCredentials) -> CKRecord.ID {
        .init(
            recordName: credentials.rootName,
            zoneID: .init(zoneName: credentials.zoneName, ownerName: credentials.ownerName)
        )
    }
    private func fetch(root: CKRecord.ID, db: CKDatabase) async throws -> [CKRecord] {
        let ids = [root] + (0..<10).map { CKRecord.ID(recordName: "participant-\($0)", zoneID: root.zoneID) }
        do {
            let result = try await db.records(for: ids)
            return try ids.map { id in
                guard let record = result[id] else { throw Failure.invalidData }
                return try record.get()
            }
        } catch {
            recordBackoff(error)
            throw error
        }
    }
    private func save(_ records: [CKRecord], db: CKDatabase) async throws {
        do {
            let result = try await db.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            let errors = result.saveResults.values.compactMap { value -> Error? in
                if case .failure(let error) = value { return error }
                return nil
            }
            if let conflict = errors.first(where: isConflict) { throw conflict }
            if let first = errors.first { throw first }
        } catch {
            recordBackoff(error)
            throw error
        }
    }
    private func snapshot(_ records: [CKRecord]) throws -> RemoteSession {
        try CloudRecordCodec.snapshot(records, notificationWarning: notificationWarning)
    }

    private func isEnded(_ root: CKRecord) -> Bool { (root["ended"] as? NSNumber)?.boolValue == true }
    private func isConflict(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .serverRecordChanged { return true }
        return error.partialErrorsByItemID?.values.contains(where: isConflict) ?? false
    }
    private func recordBackoff(_ error: Error) {
        if let delay = (error as? CKError)?.retryAfterSeconds { retryAfter = Date().addingTimeInterval(max(delay, 1)) }
    }
    private func subscribe(db: CKDatabase, account: String) async {
        let key = "\(account)-\(db.databaseScope.rawValue)"
        guard !subscribed.contains(key) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "reunion-changes-v1")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await db.save(subscription)
            subscribed.insert(key)
            notificationWarning = nil
        } catch {
            recordBackoff(error)
            notificationWarning = "iCloud 변경 알림을 등록하지 못했어요. 앱을 열어 두면 상태를 확인할 수 있어요."
        }
    }
}
