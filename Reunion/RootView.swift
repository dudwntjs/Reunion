import SwiftUI

struct RootView: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var editing = false
    @State private var showingRoute = false
    @State private var connecting = false
    @State private var confirmDeparture = false
    @State private var confirmEnd = false
    @State private var confirmSharing = false

    // MARK: - Body

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            reunionTab
            togetherTab
        }
        .sheet(isPresented: $editing) {
            MeetingEditor()
        }
        .sheet(isPresented: $showingRoute) {
            MeetingRouteView()
        }
        .sheet(isPresented: $connecting) {
            ConnectionView()
        }
        .sheet(item: $store.prompt) { kind in
            ReminderSheet(kind: kind) {
                confirmDeparture = true
            }
            .presentationDetents([.medium])
        }
        .alert("출발하셨나요?", isPresented: $confirmDeparture) {
            Button(role: .cancel) {
            } label: {
                Text("취소")
            }
            Button {
                Task {
                    await store.depart()
                }
            } label: {
                Text("출발 확인")
            }
        } message: {
            Text("친구에게 이동 중인 상태를 알려요. 위치 공유 설정은 그대로 유지됩니다.")
        }
        .alert("위치를 공유할까요?", isPresented: $confirmSharing) {
            Button(role: .cancel) {
            } label: {
                Text("취소")
            }
            Button {
                Task {
                    await store.setSharing(true)
                }
            } label: {
                Text("공유 시작")
            }
        } message: {
            Text("자유시간과 이동 중에 현재 위치를 친구에게 공유해요. 백그라운드에서도 위치를 사용하며 iPhone에 사용 표시가 나타나요.")
        }
        .alert("재합류를 완료할까요?", isPresented: $confirmEnd) {
            Button(role: .cancel) {
            } label: {
                Text("취소")
            }
            Button {
                Task {
                    await store.finish()
                }
            } label: {
                Text("완료")
            }
        } message: {
            Text("모든 참가자의 위치 공유를 종료합니다.")
        }
        .alert(
            "안내",
            isPresented: Binding(
                get: {
                    store.error != nil
                },
                set: {
                    if !$0 {
                        store.error = nil
                    }
                }
            )
        ) {
            Button {
                store.error = nil
            } label: {
                Text("확인")
            }
        } message: {
            Text(store.error ?? "")
        }
        .task {
            AppDelegate.store = store
            receiveInvitation()
            if store.credentials != nil {
                await store.sync()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    await store.tick()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            store.isForeground = phase == .active
            if phase == .active && store.credentials != nil {
                Task {
                    if store.pendingEnd {
                        await store.flushPendingEnd()
                    } else {
                        await store.sync()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ReunionCloudInvitation"))) { _ in
            receiveInvitation()
        }
        .onOpenURL { url in
            if CloudInvitation.url(url.absoluteString) != nil {
                UserDefaults.standard.set(url.absoluteString, forKey: "reunion.pendingInvitation")
                receiveInvitation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ReunionNotificationTapped"))) { notification in
            guard store.phase == .free, let id = notification.object as? String, let prompt = PromptKind(rawValue: id)
            else {
                tab = 1
                return
            }

            store.prompt = prompt
        }
    }

}

// MARK: - Subviews

extension RootView {

    private func receiveInvitation() {
        guard let link = UserDefaults.standard.string(forKey: "reunion.pendingInvitation") else { return }
        store.pendingInvitation = link
        connecting = true
    }

    private var meetingSection: some View {
        Section("다시 만날 약속") {
            if store.hasDestination {
                Label(store.meeting.place, systemImage: "mappin.and.ellipse")
                if !store.meeting.note.isEmpty {
                    Text(store.meeting.note)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("만날 시간") {
                    Text(store.meeting.target, format: .dateTime.month().day().hour().minute())
                }
                routeButton
                if store.credentials == nil && store.phase == .free {
                    Button {
                        editing = true
                    } label: {
                        Text("약속 변경")
                    }
                    .accessibilityIdentifier("editMeeting")
                }
            } else {
                Text("다시 만날 시간과 장소를 정해 주세요.")
                    .foregroundStyle(.secondary)
                Button {
                    editing = true
                } label: {
                    Label("다시 만날 약속 정하기", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("findPlace")
            }
        }
    }

    private var routeButton: some View {
        Button {
            showingRoute = true
        } label: {
            Label("약속 장소까지 길 찾기", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
        }
        .accessibilityIdentifier("showMeetingRoute")
    }

    private var departureSection: some View {
        Section("나의 출발 안내") {
            LabeledContent("지금 상태", value: store.myStatus)
            if let estimate = store.estimate {
                LabeledContent("이동시간", value: "\(store.meeting.mode.title) \(estimate.minutes)분")
                LabeledContent("여유시간", value: "\(store.meeting.bufferMinutes)분")
                if let departure = store.departure, store.phase == .free {
                    LabeledContent("출발할 시간") {
                        Text(departure, style: .time)
                    }
                }
                if store.phase == .moving {
                    LabeledContent("도착 예상") {
                        Text(store.eta, style: .time)
                    }
                    Text("출발할 때 계산한 예상 시각이에요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.phase == .free {
                Picker(
                    "이동수단",
                    selection: Binding(
                        get: {
                            store.meeting.mode
                        },
                        set: { mode in
                            var meeting = store.meeting
                            meeting.mode = mode
                            store.updateMeeting(meeting)
                        }
                    )
                ) {
                    ForEach(TravelMode.allCases) {
                        Text($0.title)
                            .tag($0)
                    }
                }
                Stepper(
                    "여유시간 \(store.meeting.bufferMinutes)분",
                    value: Binding(
                        get: {
                            store.meeting.bufferMinutes
                        },
                        set: { value in
                            var meeting = store.meeting
                            meeting.bufferMinutes = value
                            store.updateMeeting(meeting)
                        }
                    ),
                    in: 0...30
                )
                Button {
                    Task {
                        await store.fetchRoute()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text(store.estimate == nil ? "현재 위치에서 이동시간 확인" : "이동시간 다시 확인")
                        if store.isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isLoading)
                if store.estimate != nil {
                    Button {
                        Task {
                            await store.enableNotifications()
                        }
                    } label: {
                        Label(store.notificationsEnabled ? "출발 알림 예약됨" : "출발 알림 켜기", systemImage: "bell")
                    }
                    Button {
                        confirmDeparture = true
                    } label: {
                        Label("출발했어요", systemImage: "figure.walk")
                    }
                    .accessibilityIdentifier("depart")
                }
            }
            if store.phase == .moving {
                Button {
                    Task {
                        await store.arrive()
                    }
                } label: {
                    Label("도착했어요", systemImage: "checkmark.circle")
                }
            }
            if store.phase == .arrived {
                Button {
                    confirmEnd = true
                } label: {
                    Label("친구와 다시 만났어요", systemImage: "person.2.fill")
                }
            }
            if store.phase == .complete {
                Button {
                    Task {
                        await store.resetDemo()
                        editing = true
                    }
                } label: {
                    Text("새 약속 정하기")
                }
            }
        }
    }

    private var friendSection: some View {
        Section("친구") {
            if store.credentials != nil {
                LabeledContent(
                    "참여 인원",
                    value: "\(store.peers.count + 1)명 / 최대 10명"
                )
            }
            Button {
                connecting = true
            } label: {
                Label(store.credentials == nil ? "친구와 연결하기" : "모임과 초대 보기", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("connect")
        }
    }

    private var participantSection: some View {
        Section("지금 우리") {
            Label(store.situation, systemImage: "person.2")
            ParticipantStatus(
                name: "나",
                status: store.myStatus,
                detail: store.mySharingDescription,
                isStale: false
            )
            ForEach(store.peers) { peer in
                ParticipantStatus(
                    name: peer.name,
                    status: peer.status,
                    detail: peer.sharingDescription,
                    isStale: peer.sharesLocation && peer.isStale
                )
            }

        }
    }

    private var reunionTab: some View {
        NavigationStack {
            List {
                meetingSection
                if store.hasDestination {
                    departureSection
                }
                if let issue = store.locationError {
                    Section {
                        Text(issue)
                            .foregroundStyle(.secondary)
                        Button {
                            store.startLocation()
                        } label: {
                            Text("현재 위치 다시 확인")
                        }
                    }
                }
            }
            .navigationTitle("재합류")
        }
        .tabItem {
            Label("재합류", systemImage: "calendar")
        }
        .tag(0)
    }

    private var togetherTab: some View {
        NavigationStack {
            List {
                friendSection
                Section {
                    ReunionMap(expanded: true)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                participantSection
                Section {
                    Toggle(
                        "내 실시간 위치 공유",
                        isOn: Binding(
                            get: {
                                store.sharingEnabled
                            },
                            set: { enabled in
                                if enabled {
                                    confirmSharing = true
                                } else {
                                    Task {
                                        await store.setSharing(false)
                                    }
                                }
                            }
                        )
                    )
                    .disabled(store.credentials == nil || store.phase == .complete)
                    .accessibilityIdentifier("sharingToggle")
                    if let locationIssue = store.locationError {
                        Text(locationIssue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if store.sharingNeedsSync {
                        Label("공유 설정을 전달하는 중", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let warning = store.cloudNotificationWarning {
                        Text(warning).font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue = store.connectionError {
                        Label(issue, systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("켜 두면 자유시간에도 위치를 공유해요. 언제든 끌 수 있고, 재합류를 완료하면 자동으로 종료돼요.")
                }
            }
            .navigationTitle("함께 보기")

            .refreshable {
                await store.sync()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.mapFocusRequest += 1
                        store.startLocation()
                    } label: {
                        Label("내 위치", systemImage: "location")
                    }
                }
            }
        }
        .tabItem {
            Label("함께 보기", systemImage: "map")
        }
        .tag(1)
    }

    private var directionsURL: URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        let destination = "\(store.meeting.coordinate.latitude),\(store.meeting.coordinate.longitude)"
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "travelmode", value: store.meeting.mode.mapsValue),
        ]
        return components?.url
    }
}
