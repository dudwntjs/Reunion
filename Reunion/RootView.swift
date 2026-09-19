import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(ReunionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var editing = false
    @State private var connecting = false
    @State private var confirmEnd = false
    @State private var query = ""
    @State private var places: [PlaceResult] = []
    @State private var selected: PlaceResult?
    @State private var selectedPeer: String?
    @State private var searching = false
    @State private var searched = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        meetingSection
                        departureSection
                        statusSection
                    }
                    .padding(20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("재합류")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("재합류", systemImage: "calendar") }
            .tag(0)
            NavigationStack {
                ScrollViewReader { proxy in
                    List {
                        if store.credentials == nil && store.phase != .complete { searchSection }
                        Section {
                            ReunionMap(
                                places: places,
                                selected: selected,
                                active: tab == 1 && scenePhase == .active,
                                onSelect: selectPin,
                                onLongPress: selectCoordinate
                            )
                            .listRowInsets(EdgeInsets())
                            .id("sharedMap")
                        } footer: {
                            Text("파랑: 나와 내 도보 경로 · 초록: 친구 · 주황: 만날 곳\n화살표는 이동 방향이에요. 오래된 위치는 흐리게 보여요.")
                        }
                        selectionSection
                        if store.hasDestination { walkingSection }
                        participantsSection
                        sharingSection
                        Section("친구와 함께") {
                            if store.credentials != nil {
                                LabeledContent("참여 인원", value: "\(store.peers.count + 1)명 / 최대 10대")
                            }
                            Button {
                                connecting = true
                            } label: {
                                Label(
                                    store.credentials == nil ? "친구와 연결하기" : "모임과 초대 보기",
                                    systemImage: "person.badge.plus"
                                )
                            }
                            .accessibilityIdentifier("connect")
                        }
                    }
                    .navigationTitle("함께 보기")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                searchFocused = false
                                store.startLocation()
                                store.mapFocusRequest += 1
                            } label: {
                                Image(systemName: "location")
                            }
                            .accessibilityLabel("내 위치와 친구들 보기")
                        }
                    }
                    .onChange(of: selected?.id) { _, value in
                        if value != nil { withAnimation { proxy.scrollTo("sharedMap", anchor: .top) } }
                    }
                }
            }
            .tabItem { Label("함께 보기", systemImage: "map") }
            .tag(1)
        }
        .sheet(isPresented: $editing) { MeetingEditor(proposedPlace: selected) }
        .sheet(isPresented: $connecting) { ConnectionView() }
        .sheet(item: $store.prompt) { kind in
            ReminderSheet(kind: kind) { Task { await store.depart() } }
                .presentationDetents([.medium])
        }
        .alert("재합류를 완료할까요?", isPresented: $confirmEnd) {
            Button(role: .cancel) {
            } label: {
                Text("취소")
            }
            Button {
                Task { await store.finish() }
            } label: {
                Text("완료")
            }
        } message: {
            Text("모든 참가자의 위치 공유를 종료합니다.")
        }
        .alert("안내", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
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
            if store.credentials != nil { await store.sync() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { await store.tick() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            store.isForeground = phase == .active
            if phase == .active && store.credentials != nil {
                Task {
                    if store.pendingEnd { await store.flushPendingEnd() } else { await store.sync() }
                }
            }
        }
        .onChange(of: tab) { _, tab in
            if tab == 1 && store.currentLocation == nil { store.startLocation() }
        }
        .onChange(of: store.meeting.coordinate) { _, _ in clearSearch() }
        .onChange(of: store.credentials?.rootName) { _, _ in clearSearch() }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            requestID = UUID()
            searching = false
            searched = false
            searchError = nil
            places = []
            selected = nil
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
            if store.phase == .free, let id = notification.object as? String, let kind = PromptKind(rawValue: id) {
                store.prompt = kind
            } else {
                tab = 1
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Reunion

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18, content: content)
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var meetingSection: some View {
        card {
            Label("다시 만날 약속", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if store.hasDestination {
                Text(store.meeting.place).font(.title2.bold()).multilineTextAlignment(.center)
                Text(store.meeting.target, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(store.meeting.target, format: .dateTime.month().day().weekday())
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.credentials == nil && store.phase != .complete {
                    Button("약속 변경") {
                        selected = nil
                        editing = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("어디서 다시 만날까요?").font(.title2.bold())
                Button {
                    tab = 1
                    searchFocused = true
                } label: {
                    Label("다시 만날 약속 정하기", systemImage: "plus")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("findPlace")
            }
            if store.phase == .complete {
                Button("새 약속 시작") {
                    Task {
                        await store.resetDemo()
                        selected = nil
                        places = []
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusSection: some View {
        card {
            Text("나의 현재 상태").font(.headline)
            Text(
                store.phase == .free
                    ? "나는 아직 출발 전이에요"
                    : store.phase == .moving ? "나는 이동 중이에요" : store.phase == .arrived ? "나는 도착했어요" : "재합류를 마쳤어요"
            )
            .font(.title.bold()).multilineTextAlignment(.center)
            Text("출발하거나 도착하면 아래 버튼으로 알려주세요")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { statusButtons }
                VStack(spacing: 8) { statusButtons }
            }
            .disabled(store.phase == .complete || store.isSyncing)
            if store.phase == .arrived {
                Button("모두 만났어요 · 약속 종료") { confirmEnd = true }.buttonStyle(.bordered)
            }
        }
    }
    @ViewBuilder private var statusButtons: some View {
        phaseButton(.moving, title: "출발했어요", icon: "figure.walk")
        phaseButton(.arrived, title: "도착했어요", icon: "checkmark.circle.fill")
    }
    private func phaseButton(_ phase: JourneyPhase, title: String, icon: String) -> some View {
        Button {
            Task { await store.setJourneyPhase(phase) }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.bold()).fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .buttonStyle(.bordered)
        .tint(store.phase == phase ? .blue : .gray)
        .accessibilityIdentifier("phase-\(phase.rawValue)")
        .accessibilityValue(store.phase == phase ? "선택됨" : "선택 안 됨")
    }
    private var departureSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let due = store.phase == .free && (store.departure.map { $0 <= context.date } ?? false)
            VStack(spacing: 14) {
                Label("도보 출발 안내", systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                if store.phase == .complete {
                    Text("다시 만났어요!").font(.title.bold())
                } else if store.phase == .arrived {
                    Text("약속 장소에 도착했어요").font(.title2.bold())
                    Text("친구가 도착하면 함께 만나세요")
                } else if store.phase == .moving {
                    Text("친구를 만나러 가는 중").font(.title2.bold())
                    if store.estimate != nil {
                        Text("도착 예상 \(store.eta.formatted(date: .omitted, time: .shortened))").font(.title3.bold())
                    }
                    Button("걸어가는 길 보기") { tab = 1 }.buttonStyle(.bordered)
                } else if let departure = store.departure {
                    Text(due ? "지금 바로 출발하세요!" : "아직 자유시간이에요")
                        .font(.title.bold())
                    if due {
                        Text("친구와 만날 시간에 맞춰 출발해 주세요")
                    } else {
                        Text("출발까지 \(countdown(departure.timeIntervalSince(context.date)))")
                            .font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Text(
                        "\(departure.formatted(date: .omitted, time: .shortened)) 출발 · 도보 약 \(store.estimate?.minutes ?? 0)분"
                    )
                    Button(store.notificationsEnabled ? "출발 알림 예약됨" : "출발 알림 켜기") {
                        Task { await store.enableNotifications() }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(store.hasDestination ? "언제 출발하면 될까요?" : "약속을 먼저 정해 주세요")
                        .font(.title2.bold())
                    if store.hasDestination {
                        Button("도보 출발 시간 확인") { Task { await store.fetchRoute() } }
                            .buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(store.isLoading)
                        if store.isLoading { ProgressView() }
                    } else {
                        Text("걸리는 시간에 맞춰 출발을 알려드려요")
                    }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(24)
            .foregroundStyle(due ? Color.white : Color.primary)
            .tint(due ? .white : .blue)
            .background(due ? Color.red : Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
        }
    }
    private func countdown(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        if value >= 3600 { return "\(value / 3600)시간 \((value % 3600) / 60)분" }
        if value >= 60 { return "\(value / 60)분 \(value % 60)초" }
        return "\(value)초"
    }

    // MARK: - Shared map

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("장소 이름이나 주소 검색", text: $query)
                    .focused($searchFocused).submitLabel(.search).onSubmit(search)
                    .accessibilityIdentifier("placeQuery")
                Button(action: search) { Text("검색") }
                    .accessibilityIdentifier("searchPlaces")
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
            }
            if searching { ProgressView("장소 확인 중") }
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
            if searched && places.isEmpty && !searching && searchError == nil { Text("검색 결과가 없어요. 다른 검색어로 찾아보세요.") }
            ForEach(places) { place in
                Button {
                    selected = place
                    selectedPeer = nil
                    searchFocused = false
                    store.mapFocusRequest += 1
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.displayName.text)
                            if let address = place.formattedAddress {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selected?.id == place.id { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityIdentifier("placeResult-\(place.id)")
            }
        }
    }
    @ViewBuilder private var selectionSection: some View {
        if let selected, store.credentials == nil {
            Section("선택한 장소") {
                Label(selected.displayName.text, systemImage: "mappin.circle.fill")
                if let address = selected.formattedAddress { Text(address).font(.caption).foregroundStyle(.secondary) }
                Button {
                    editing = true
                } label: {
                    Text("이곳에서 만날 약속 정하기")
                }
                .accessibilityIdentifier("choosePlace")
            }
        }
        if let peer = store.peers.first(where: { $0.id == selectedPeer }) {
            Section("선택한 친구") {
                ParticipantStatus(
                    name: peer.name,
                    status: peer.status,
                    detail: peer.sharingDescription,
                    isStale: peer.isStale
                )
            }
        }
    }
    private var walkingSection: some View {
        Section("내 도보 경로") {
            Label(store.meeting.place, systemImage: "flag.fill")
            Button {
                Task { await store.fetchRoute() }
            } label: {
                HStack {
                    Text(store.estimate == nil ? "현재 위치에서 도보 길찾기" : "현재 위치에서 경로 다시 확인")
                    if store.isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(store.isLoading)
            if let estimate = store.estimate {
                Label("도보 약 \(estimate.minutes)분", systemImage: "figure.walk").font(.title2.bold())
                Text("\(estimate.fetchedAt.formatted(date: .omitted, time: .shortened)) 확인 · 파란 선을 따라 이동해요")
                    .font(.caption).foregroundStyle(.secondary)
                if let steps = estimate.instructions, !steps.isEmpty {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: directionIcon(text))
                                .font(.system(size: 28, weight: .bold))
                                .frame(width: 54, height: 58)
                                .foregroundStyle(.blue)
                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            Text(text).font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
    private func directionIcon(_ instruction: String) -> String {
        if instruction.contains("왼쪽") || instruction.contains("좌회전") { return "arrow.turn.up.left" }
        if instruction.contains("오른쪽") || instruction.contains("우회전") { return "arrow.turn.up.right" }
        if instruction.contains("횡단보도") { return "figure.walk" }
        if instruction.contains("계단") { return "figure.stairs" }
        if instruction.contains("도착") { return "flag.checkered" }
        if instruction.contains("직진") { return "arrow.up" }
        return "mappin.and.ellipse"
    }
    private var participantsSection: some View {
        Section("지금 우리") {
            Label(store.situation, systemImage: "person.2")
            ParticipantStatus(name: "나", status: store.myStatus, detail: store.mySharingDescription, isStale: false)
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
    private var sharingSection: some View {
        Section {
            Label(
                store.credentials == nil ? "친구와 연결하면 위치가 자동으로 공유돼요" : store.mySharingDescription,
                systemImage: "location.fill"
            )
            .font(.footnote).foregroundStyle(.secondary)
            if let error = store.locationError { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let error = store.connectionError { Text(error).font(.caption).foregroundStyle(.orange) }
            if let warning = store.cloudNotificationWarning { Text(warning).font(.caption).foregroundStyle(.secondary) }
            if store.sharingNeedsSync { Text("공유 설정을 전달하는 중").font(.caption) }
        } footer: {
            Text("위치가 30초 이상 갱신되지 않으면 마지막 위치로 표시돼요.")
        }
    }

    // MARK: - Search and invitations

    private func clearSearch() {
        searchTask?.cancel()
        requestID = UUID()
        places = []
        selected = nil
        selectedPeer = nil
        searching = false
        searched = false
        searchError = nil
        query = ""
    }

    private func search() {
        guard store.credentials == nil else { return }
        searchTask?.cancel()
        let id = UUID()
        requestID = id
        searching = true
        searched = true
        searchError = nil
        selected = nil
        searchFocused = false
        let requested = query
        let near = store.currentLocation.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        searchTask = Task {
            defer { if requestID == id { searching = false } }
            do {
                let results: [PlaceResult]
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                        let fixture = ProcessInfo.processInfo.environment["REUNION_TEST_PLACES"],
                        let data = fixture.data(using: .utf8)
                    {
                        results = try JSONDecoder().decode([PlaceResult].self, from: data)
                    } else {
                        results = try await KakaoAPI.search(query: requested, near: near, key: MapConfiguration.restKey)
                    }
                #else
                    results = try await KakaoAPI.search(query: requested, near: near, key: MapConfiguration.restKey)
                #endif
                guard !Task.isCancelled, requestID == id else { return }
                places = results
                store.mapFocusRequest += 1
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                places = []
                searchError = error.localizedDescription
            }
        }
    }
    private func selectPin(_ id: String) {
        if id.hasPrefix("peer-") {
            selectedPeer = String(id.dropFirst(5))
            return
        }
        if let place = places.first(where: { $0.id == id }) {
            selected = place
            store.mapFocusRequest += 1
        }
    }
    private func selectCoordinate(_ coordinate: Coordinate) {
        guard store.credentials == nil, store.phase != .complete else { return }
        searchTask?.cancel()
        let id = UUID()
        requestID = id
        searching = true
        searchError = nil
        searchFocused = false
        searchTask = Task {
            defer { if requestID == id { searching = false } }
            do {
                let request = try KakaoAPI.reverseRequest(coordinate: coordinate, key: MapConfiguration.restKey)
                let address = try KakaoAPI.decodeAddress(await KakaoAPI.data(for: request))
                guard !Task.isCancelled, requestID == id else { return }
                selected = PlaceResult(
                    id: "map-\(UUID().uuidString)",
                    displayName: .init(text: address ?? "지도에서 선택한 위치"),
                    formattedAddress: address,
                    location: coordinate
                )
                places = []
                store.mapFocusRequest += 1
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                searchError = error.localizedDescription
            }
        }
    }
    private func receiveInvitation() {
        guard let link = UserDefaults.standard.string(forKey: "reunion.pendingInvitation") else { return }
        store.pendingInvitation = link
        connecting = true
    }
}
