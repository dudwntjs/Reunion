import ActivityKit
import CoreLocation
import SwiftUI
import UserNotifications

@MainActor @Observable
final class ReunionStore {
    var meeting = Meeting()

    var estimate: RouteEstimate?
    var phase = JourneyPhase.free
    var pendingInvitation: String?
    var cloudNotificationWarning: String?
    var peers: [Peer] = []
    var friendPhase = JourneyPhase.free
    var friendCoordinate: Coordinate?
    var friendUpdated: Date?
    var sharingEnabled = false
    var sharingNeedsSync = false
    var friendSharing = false
    var friendJoined = false
    var friendLastSeen: Date?
    var mapFocusRequest = 0
    var myStatus: String {
        switch phase {
        case .free: "자유시간 중"
        case .moving: "출발했어요"
        case .arrived: "도착했어요"
        case .complete: "재합류 완료"
        }
    }
    var mySharingDescription: String {
        if credentials == nil {
            return "친구 연결 전"
        }
        if !sharingEnabled {
            return sharingNeedsSync ? "내 공유 중지 · 친구에게 전달 대기" : "위치 공유 꺼짐"
        }
        if connectionError != nil {
            return "연결 끊김 · 위치 전송 대기"
        }
        if let locationError {
            return locationError
        }
        if currentLocation == nil {
            return "위치 확인 중"
        }
        if Date().timeIntervalSince(locationUpdated ?? .distantPast) > 30 {
            return "위치 갱신 대기 · 마지막 위치 표시"
        }
        return lastSync == nil ? "위치 전송 중" : "실시간 위치 공유 중"
    }
    var friendSharingDescription: String {
        guard friendJoined else { return "친구가 연결되면 상태가 표시돼요" }

        if Date().timeIntervalSince(friendLastSeen ?? .distantPast) > 30 && !friendSharing {
            return "연결 확인 중 · 마지막 상태"
        }

        guard friendSharing else { return "위치 공유 꺼짐" }

        guard let date = friendUpdated else { return "위치 확인 중" }

        if friendIsStale {
            return "마지막 위치 · " + date.formatted(date: .omitted, time: .shortened)
        }
        return "실시간 위치 공유 중"
    }
    var situation: String { GroupStatus.summary(mine: phase, peers: peers) }
    var groupFriendStatus: String { GroupStatus.friendsSummary(peers) }
    var currentLocation: CLLocation?
    var isLocating = false
    var locationError: String?
    var hasDestination: Bool { !meeting.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var freshLocation: CLLocation? {
        guard let currentLocation, abs(currentLocation.timestamp.timeIntervalSinceNow) < 120 else {
            return nil
        }

        return currentLocation
    }
    var locationUpdated: Date?
    var prompt: PromptKind?
    var message: String?
    var error: String?
    var isLoading = false
    var isSyncing = false
    var notificationsEnabled = false
    var events: [StudyEvent] = []
    var reports: [StudyReport] = []
    var contactCount = 0
    var sessionID = UUID()
    var credentials: SessionCredentials?
    var lastSync: Date?
    var connectionError: String?
    var pendingEnd = false
    var name = "나"
    var demoProgress = 0.0
    var demoRunning = false
    var isForeground = true
    var didPromptMovement = false
    var acknowledgedPrompts = Set<String>()
    private var routeRevision = UUID()
    private var activity: Activity<ReunionAttributes>?
    private let locationService = LocationService()
    private var movementOrigin: CLLocation?
    private var friendID: String?
    private var pollCount = 0
    private var departedAt: Date?
    private var reminderRevision = UUID()
    var isDemo: Bool { false }
    var departure: Date? {
        estimate.map {
            DeparturePlanner.departure(
                target: meeting.target,
                duration: $0.seconds,
                bufferMinutes: 0
            )
        }
    }
    var eta: Date {
        max(departedAt ?? .now, estimate?.fetchedAt ?? .distantPast).addingTimeInterval(estimate?.seconds ?? 0)
    }
    var myCoordinate: Coordinate? {
        guard sharingEnabled, locationError == nil, phase != .complete, let location = currentLocation else {
            return nil
        }

        return .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    var friendStatus: String {
        switch friendPhase {
        case .free: "자유시간 중"
        case .moving: "만나러 오는 중"
        case .arrived: "도착했어요"
        case .complete: "재합류 완료"
        }
    }
    var friendIsStale: Bool {
        guard let updated = friendUpdated else { return !isDemo }

        return Date().timeIntervalSince(updated) > 30
    }

    init() {
        reports = Self.restore([StudyReport].self, key: "reports") ?? []
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            if let saved = Self.restore(Meeting.self, key: "meeting") {
                meeting = saved
            }
            credentials = Self.restore(SessionCredentials.self, key: "cloudCredentials")
            pendingEnd = credentials != nil && (Self.restore(Bool.self, key: "pendingEnd") ?? false)
            if credentials == nil && !UserDefaults.standard.bool(forKey: "reunion.currentLocationVersion") {
                meeting = Meeting()
                UserDefaults.standard.set(true, forKey: "reunion.currentLocationVersion")
                save(meeting, key: "meeting")
            }
            if credentials != nil {
                peers = Self.restore([Peer].self, key: "cloudPeers") ?? []
                friendJoined = !peers.isEmpty
                phase = Self.restore(JourneyPhase.self, key: "phase") ?? .free
                estimate = Self.restore(RouteEstimate.self, key: "estimate")
                departedAt = Self.restore(Date.self, key: "departedAt")
                sharingEnabled = phase != .complete && !pendingEnd
                name = Self.restore(String.self, key: "name") ?? "나"
            }
            events = Self.restore([StudyEvent].self, key: "events") ?? []
            contactCount = Self.restore(Int.self, key: "contacts") ?? 0
            sessionID = Self.restore(UUID.self, key: "sessionID") ?? UUID()
        }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                let fixture = ProcessInfo.processInfo.environment["REUNION_TEST_PEERS"],
                let data = fixture.data(using: .utf8),
                let participants = try? JSONDecoder().decode([Peer].self, from: data)
            {
                peers = participants
                friendJoined = !peers.isEmpty
            }
        #endif
        meeting.mode = .walk
        meeting.bufferMinutes = 0
        if estimate?.source != "카카오 도보 경로" { estimate = nil }
        locationService.onLocation = { [weak self] location in
            self?.receivedLocation(location)
        }
        locationService.onError = { [weak self] value in
            self?.locationError = value
            self?.isLocating = false
        }
        activity = Activity<ReunionAttributes>.activities.first
        if credentials != nil && sharingEnabled {
            locationService.enableBackgroundSharing()
        }
    }

    static func restore<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: "reunion.\(key)") else { return nil }

        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "reunion.\(key)")
        }
    }

    func log(_ type: String, _ detail: String = "") {
        events.append(.init(type: type, detail: detail))
        save(events, key: "events")
        save(sessionID, key: "sessionID")
    }

    func countContact() {
        contactCount += 1
        save(contactCount, key: "contacts")
        log("contact", "사용자가 재합류 관련 연락 1회를 기록")
        message = "연락 1회를 기록했어요"
    }

    func undoContact() {
        guard contactCount > 0 else { return }

        contactCount -= 1
        save(contactCount, key: "contacts")
        log("contact_correction", "연락 횟수 -1")
    }

    func updateMeeting(_ value: Meeting) {
        meeting = value
        meeting.mode = .walk
        meeting.bufferMinutes = 0
        routeRevision = UUID()
        estimate = nil
        save(meeting, key: "meeting")
        save(estimate, key: "estimate")
        acknowledgedPrompts = []
        didPromptMovement = false
        NotificationService.shared.cancel()
        notificationsEnabled = false
        log("meeting_configured", value.place)
    }

    func fetchRoute() async {
        guard !isLoading else { return }

        guard hasDestination, let location = freshLocation else {
            error = "현재 위치와 재합류 장소를 먼저 선택해 주세요."
            return
        }

        meeting.origin = .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let revision = routeRevision
        let requested = meeting
        isLoading = true
        estimate = nil
        save(estimate, key: "estimate")
        defer {
            isLoading = false
        }
        do {
            let result = try await RoutesClient().estimate(meeting: requested, key: MapConfiguration.restKey)

            guard revision == routeRevision else { return }

            estimate = result
            mapFocusRequest += 1
            save(estimate, key: "estimate")
            log("route_success", "\(result.seconds)s; \(result.distanceMeters)m; 카카오 도보 경로")
            message = "카카오 도보 경로로 출발 시간을 계산했어요"
            if notificationsEnabled {
                await enableNotifications()
            }
        } catch {
            guard revision == routeRevision else { return }

            self.error = error.localizedDescription
            log("route_failed", error.localizedDescription)
        }
    }

    func useDemoRoute() {
        routeRevision = UUID()
        estimate = .demo
        save(estimate, key: "estimate")
        log("demo_route_selected")
        if notificationsEnabled {
            Task {
                await enableNotifications()
            }
        }
    }

    func enableNotifications() async {
        guard let departure, phase == .free else { return }

        let revision = UUID()
        reminderRevision = revision
        do {
            let enabled = try await NotificationService.shared.schedule(departure: departure, place: meeting.place)

            guard reminderRevision == revision, phase == .free else {
                NotificationService.shared.cancel()
                return
            }

            notificationsEnabled = enabled
            if !enabled {
                error = "알림 권한이 꺼져 있어요. iPhone 설정에서 알림을 허용해 주세요."
            } else {
                message = departure <= .now ? "출발 예정 시간이 지났어요. 지금 출발을 확인해 주세요." : "출발 5분 전과 출발 시간에 알려드릴게요"
            }
        } catch {
            self.error = "알림 예약에 실패했어요: \(error.localizedDescription)"
        }
    }

    func startLocation() {
        locationError = nil
        isLocating = true
        locationService.start()
        Task {
            try? await Task.sleep(for: .seconds(15))
            if self.isLocating {
                self.isLocating = false
                self.locationError = "현재 위치를 찾지 못했어요. 위치 권한과 GPS 수신을 확인하고 다시 시도해 주세요."
            }
        }
    }

    func receivedLocation(_ location: CLLocation) {
        currentLocation = location
        locationUpdated = location.timestamp
        isLocating = false
        locationError = nil
        if sharingEnabled && Date().timeIntervalSince(lastSync ?? .distantPast) >= 3 {
            Task {
                await self.sync()
                await self.updateActivity()
            }
        }
        if movementOrigin == nil {
            movementOrigin = location
        }
        if phase == .free, hasDestination, let departure, abs(departure.timeIntervalSinceNow) <= 600,
            !didPromptMovement, let origin = movementOrigin, location.distance(from: origin) > 80
        {
            didPromptMovement = true
            prompt = .movement
            log("movement_candidate", "80m 이상 이동; 출발은 사용자 확인 필요")
        }
    }

    func setSharing(_ enabled: Bool) async {
        guard credentials != nil, phase != .complete else { return }

        sharingEnabled = enabled
        sharingNeedsSync = true
        save(sharingEnabled, key: "sharingEnabled")
        if enabled {
            locationError = nil
            isLocating = true
            locationService.enableBackgroundSharing()
        } else {
            locationService.stop()
        }
        await sync()
    }

    func applyCurrentOrigin() {
        guard let location = currentLocation, abs(location.timestamp.timeIntervalSinceNow) < 30 else {
            error = "먼저 현재 위치를 가져와 주세요. 실외에서 다시 시도해 보세요."
            return
        }

        meeting.origin = .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        routeRevision = UUID()
        estimate = nil
        save(meeting, key: "meeting")
        save(estimate, key: "estimate")
        NotificationService.shared.cancel()
        notificationsEnabled = false
        message = "현재 위치를 나의 출발지로 설정했어요"
    }

    func acknowledge(_ kind: PromptKind) {
        acknowledgedPrompts.insert(kind.rawValue)
        prompt = nil
        log("reminder_confirmed", kind.rawValue)
    }

    func depart() async { await setJourneyPhase(.moving) }

    func setJourneyPhase(_ newPhase: JourneyPhase) async {
        guard newPhase != .complete, phase != .complete, newPhase != phase else { return }
        phase = newPhase
        prompt = nil
        reminderRevision = UUID()
        NotificationService.shared.cancel()
        notificationsEnabled = false
        if newPhase == .moving {
            departedAt = .now
            if let estimate { startActivity(duration: estimate.seconds) }
        } else if newPhase == .free {
            departedAt = nil
            if let activity { await activity.end(nil, dismissalPolicy: .immediate) }
            activity = nil
        }
        save(phase, key: "phase")
        save(departedAt, key: "departedAt")
        log("status_confirmed", newPhase.rawValue)
        if credentials != nil {
            await sync()
            message = connectionError == nil ? "상태를 친구들에게 전달했어요" : "상태를 저장했어요. 연결되면 전달돼요."
        } else {
            message = "상태를 변경했어요. 친구와 연결하면 함께 볼 수 있어요."
        }
        await updateActivity()
    }

    func startActivity(duration: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("live_activity_unavailable")
            return
        }

        let state = ReunionAttributes.ContentState(
            status: "만나러 가는 중",
            friendStatus: groupFriendStatus,
            arrival: eta,
            progress: 0
        )
        let attributes = ReunionAttributes(
            place: meeting.place,
            friendName: "친구들",
            target: meeting.target,
            isDemo: isDemo
        )
        Task {
            for old in Activity<ReunionAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            do {
                let created = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(60)),
                    pushType: nil
                )
                activity = created

            } catch {
                log("live_activity_failed", error.localizedDescription)
            }
        }
    }

    func updateActivity() async {
        guard let activity else { return }

        await activity.update(
            ActivityContent(
                state: .init(
                    status: phase == .arrived ? "도착했어요" : "만나러 가는 중",
                    friendStatus: groupFriendStatus,
                    arrival: eta,
                    progress: isDemo ? demoProgress : phase == .arrived ? 1 : 0.5
                ),
                staleDate: .now.addingTimeInterval(60)
            )
        )
    }

    func arrive() async { await setJourneyPhase(.arrived) }

    func finish() async {
        // Stop this device immediately, even if the iCloud is unreachable.
        await finishLocally()

        guard credentials != nil else { return }

        pendingEnd = true
        save(pendingEnd, key: "pendingEnd")
        await flushPendingEnd()
    }

    func flushPendingEnd() async {
        guard pendingEnd, let credentials, !isSyncing else { return }

        isSyncing = true
        defer {
            isSyncing = false
        }
        do {
            _ = try await SessionClient.shared.end(credentials)
            pendingEnd = false
            save(pendingEnd, key: "pendingEnd")
            connectionError = nil
        } catch {
            connectionError = "이 기기의 위치 공유는 중지됐어요. iCloud 모임 종료는 연결되면 재시도합니다."
        }
    }

    func finishLocally() async {
        guard phase != .complete else { return }

        phase = .complete
        peers = peers.map { peer in
            var ended = peer
            ended.phase = "complete"
            ended.sharingEnabled = false
            ended.coordinate = nil
            ended.coordinateUpdatedAt = nil
            ended.eta = nil
            return ended
        }
        friendPhase = .complete
        friendCoordinate = nil
        currentLocation = nil
        sharingEnabled = false
        friendSharing = false
        sharingNeedsSync = false
        save(sharingEnabled, key: "sharingEnabled")
        demoRunning = false
        locationService.stop()
        NotificationService.shared.cancel()
        save(phase, key: "phase")
        log("reunion_completed")
        for activity in Activity<ReunionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    func demoFriendDepart() {
        guard isDemo, phase != .complete else { return }

        friendPhase = .moving
        friendCoordinate = meeting.coordinate
        friendUpdated = .now
        log("demo_friend_departure")
        message = "[체험] \(meeting.friendName)님이 출발했어요"
        Task {
            do {
                try await NotificationService.shared.demoFriendDeparture(name: meeting.friendName)
            } catch {
                self.error = "체험 알림을 보내지 못했어요."
            }
            await updateActivity()
        }
    }

    func tick() async {
        guard isForeground else { return }

        if phase == .free, let departure {
            let seconds = departure.timeIntervalSinceNow
            let kind: PromptKind? = seconds <= 0 ? .now : seconds <= 300 ? .soon : nil
            if let kind, prompt == nil, !acknowledgedPrompts.contains(kind.rawValue) {
                prompt = kind
            }
        }
        if isDemo && demoRunning && phase == .moving {
            demoProgress = min(1, demoProgress + 1.0 / 90.0)
            if friendPhase == .moving {
                friendCoordinate = interpolate(meeting.coordinate, meeting.coordinate, min(1, demoProgress * 0.9))
                friendUpdated = .now
            }
            if demoProgress >= 1 {
                demoRunning = false
                message = "약속 장소 근처예요. 도착했다면 확인해 주세요."
            }
        }
        pollCount += 1
        if pollCount % 10 == 0 {
            if pendingEnd {
                await flushPendingEnd()
            } else if credentials != nil && phase != .complete {
                await sync()
            }
        }
        if pollCount % 10 == 0 {
            await updateActivity()
        }
    }

    func connect(

        name: String,
        code: String?
    ) async -> Bool {
        guard code != nil || hasDestination else {
            error = "먼저 현재 위치 주변에서 재합류 장소를 선택해 주세요."
            return false
        }

        guard !isLoading else { return false }

        isLoading = true
        defer {
            isLoading = false
        }
        do {
            guard credentials == nil else {
                error = "현재 모임을 종료하고 새 모임을 시작한 뒤 참여해 주세요."
                return false
            }
            let deviceID = UserDefaults.standard.string(forKey: "reunion.cloudDeviceID") ?? UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: "reunion.cloudDeviceID")
            let reply = try await SessionClient.shared.connect(
                name: name,
                link: code,
                meeting: meeting,
                deviceID: deviceID
            )
            self.name = name
            save(name, key: "name")
            sharingEnabled = false
            friendSharing = false
            friendJoined = false
            peers = []
            save(sharingEnabled, key: "sharingEnabled")
            credentials = reply.credentials
            pendingInvitation = nil
            UserDefaults.standard.removeObject(forKey: "reunion.pendingInvitation")
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let localOrigin = meeting.origin
            meeting = reply.session.meeting
            meeting.origin = localOrigin
            meeting.mode = .walk
            meeting.bufferMinutes = 0
            phase = .free
            friendPhase = .free
            friendCoordinate = nil
            estimate = nil
            routeRevision = UUID()
            contactCount = 0
            events = []
            sessionID = UUID()
            departedAt = nil
            acknowledgedPrompts = []
            didPromptMovement = false
            NotificationService.shared.cancel()
            notificationsEnabled = false
            save(credentials, key: "cloudCredentials")
            save(meeting, key: "meeting")
            save(phase, key: "phase")
            save(estimate, key: "estimate")
            save(contactCount, key: "contacts")
            log("field_session_connected")
            apply(reply.session)
            await setSharing(true)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func sync() async {
        guard let credentials, !isSyncing, phase != .complete else { return }

        isSyncing = true
        defer {
            isSyncing = false
        }
        let sentSharing = sharingEnabled
        do {
            let remote = try await SessionClient.shared.update(
                credentials,
                phase: phase,
                sharingEnabled: sentSharing,
                coordinate: myCoordinate,
                coordinateUpdatedAt: locationUpdated,
                eta: phase == .moving && estimate != nil ? eta : nil,
                heading: (freshLocation?.course ?? -1) >= 0 ? freshLocation?.course : nil
            )
            apply(remote)
            lastSync = .now
            connectionError = nil
            if sharingEnabled == sentSharing {
                sharingNeedsSync = false
            }
        } catch {
            // An ended session rejects writes. Read its terminal state before reporting connectivity trouble.
            if let state = try? await SessionClient.shared.state(credentials), state.ended {
                await finishLocally()
                connectionError = nil
            } else {
                connectionError = error.localizedDescription
            }
        }
    }

    func refreshCloud() async -> Bool {
        guard let credentials, !isSyncing, phase != .complete else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let remote = try await SessionClient.shared.state(credentials)
            apply(remote)
            lastSync = .now
            connectionError = nil
            await updateActivity()
            return true
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    func apply(_ remote: RemoteSession) {
        cloudNotificationWarning = remote.notificationWarning
        if remote.ended {
            Task {
                await finishLocally()
            }
            return
        }

        let incoming = remote.participants.filter { $0.id != credentials?.participantID }
        let departed = incoming.filter { peer in
            peers.contains { $0.id == peer.id && $0.phase != "moving" } && peer.phase == "moving"
        }
        if !departed.isEmpty {
            message = departed.map(\.name).joined(separator: ", ") + "님이 출발했어요"
            log("friend_departure_received", departed.map(\.id).joined(separator: ","))
            for peer in departed {
                Task { try? await NotificationService.shared.friendDeparture(peer: peer) }
            }
        }
        peers = incoming
        save(peers, key: "cloudPeers")
        friendJoined = !peers.isEmpty
    }

    func saveReport(

        convenience: Int,
        usefulness: Int,
        comment: String
    ) {
        guard (1...5).contains(convenience), (1...5).contains(usefulness) else { return }

        log("survey_submitted")
        reports.removeAll {
            $0.sessionID == sessionID
        }
        reports.append(
            .init(
                sessionID: sessionID,
                condition: isDemo ? "단일 기기 시뮬레이션" : "두 iPhone 현장 테스트",
                contactCount: contactCount,
                convenience: convenience,
                usefulness: usefulness,
                comment: comment,
                routeSource: estimate?.source ?? "미계산",
                events: events
            )
        )
        save(reports, key: "reports")
        message = "테스트 기록을 저장했어요"
    }

    func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reunion-study.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(reports).write(to: url, options: .atomic)
            return url
        } catch {
            self.error = "기록을 내보내지 못했어요."
            return nil
        }
    }

    func resetDemo() async {
        guard !pendingEnd else {
            error = "위치 공유는 중지됐어요. 서버에 모임 종료가 전달된 후 새 체험을 시작할 수 있어요."
            return
        }

        guard credentials == nil || phase == .complete else {
            error = "먼저 현재 모임을 종료해 주세요."
            return
        }

        for activity in Activity<ReunionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        credentials = nil
        UserDefaults.standard.removeObject(forKey: "reunion.cloudPeers")
        save(credentials, key: "cloudCredentials")
        meeting = Meeting()
        estimate = nil
        phase = .free
        friendPhase = .free
        sharingEnabled = false
        friendSharing = false
        friendJoined = false
        peers = []
        sharingNeedsSync = false
        save(sharingEnabled, key: "sharingEnabled")
        friendCoordinate = nil
        friendUpdated = nil
        friendID = nil
        currentLocation = nil
        departedAt = nil
        movementOrigin = nil
        demoRunning = false
        demoProgress = 0
        contactCount = 0
        sessionID = UUID()
        events = []
        prompt = nil
        acknowledgedPrompts = []
        didPromptMovement = false
        locationService.stop()
        NotificationService.shared.cancel()
        notificationsEnabled = false
        connectionError = nil
        lastSync = nil
        save(meeting, key: "meeting")
        save(phase, key: "phase")
        save(contactCount, key: "contacts")
        log("demo_started")
    }

    private func interpolate(

        _ a: Coordinate,
        _ b: Coordinate,
        _ progress: Double
    ) -> Coordinate {
        .init(
            latitude: a.latitude + (b.latitude - a.latitude) * progress,
            longitude: a.longitude + (b.longitude - a.longitude) * progress
        )
    }
}
