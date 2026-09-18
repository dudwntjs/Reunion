import SwiftUI

import GoogleMaps

struct ReunionMap: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) var store
    var expanded = false

    private var destination: Coordinate? { store.hasDestination ? store.meeting.coordinate : nil }

    private var current: Coordinate? {
        store.currentLocation.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if GoogleMapsSetup.enabled, let center = current ?? destination {
                GoogleMapCanvas(
                    destination: destination,
                    mine: current,
                    friend: store.friendCoordinate,
                    friendName: store.meeting.friendName,
                    polyline: store.estimate?.encodedPolyline,
                    center: center,
                    mineStatus: store.myStatus,
                    friendStatus: store.friendStatus,
                    friendIsStale: store.friendIsStale,
                    focusRequest: store.mapFocusRequest
                )
            } else {
                ContentUnavailableView {
                    Label(GoogleMapsSetup.enabled ? "내 주변 지도" : "지도를 준비 중이에요", systemImage: "map")
                } description: {
                    Text(GoogleMapsSetup.enabled ? "현재 위치를 확인하면 지도가 표시돼요." : "연결이 준비되면 나와 친구의 위치가 표시돼요.")
                } actions: {
                    if GoogleMapsSetup.enabled {
                        Button {
                            store.startLocation()
                        } label: {
                            Text("내 위치 확인")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(height: expanded ? 360 : 240)
    }
}
enum GoogleMapsSetup {
    static let enabled: Bool = {
        let key = GoogleConfiguration.configured("GOOGLE_MAPS_API_KEY")

        guard !key.isEmpty else { return false }

        return GMSServices.provideAPIKey(key)
    }()
}
struct GoogleMapCanvas: UIViewRepresentable {

    // MARK: - Properties

    var destination: Coordinate?
    var mine: Coordinate?
    var friend: Coordinate?
    var friendName: String
    var polyline: String?
    var center: Coordinate
    var mineStatus = ""
    var friendStatus = ""
    var friendIsStale = false
    var focusRequest = 0
    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: center.latitude, longitude: center.longitude, zoom: 15)
        let map = GMSMapView(options: options)
        map.settings.compassButton = true
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        map.clear()
        func marker(

            _ coordinate: Coordinate,
            _ title: String,
            _ status: String,
            _ color: UIColor,
            _ stale: Bool = false
        ) {
            let marker = GMSMarker(
                position: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            marker.title = title
            marker.snippet = status
            marker.icon = Self.personPin(title: title, color: color, isDestination: status.isEmpty)
            marker.groundAnchor = CGPoint(x: 0.5, y: 1)
            marker.tracksViewChanges = false
            marker.opacity = stale ? 0.55 : 1
            marker.map = map
        }
        if let destination {
            marker(destination, "약속 장소", "", .systemOrange)
        }
        if let mine {
            marker(mine, "나", mineStatus, .systemBlue)
        }
        if let friend {
            marker(friend, friendName, friendIsStale ? "마지막 위치" : friendStatus, .systemGreen, friendIsStale)
        }
        if let polyline, let path = GMSPath(fromEncodedPath: polyline) {
            let line = GMSPolyline(path: path)
            line.strokeColor = .systemBlue
            line.strokeWidth = 4
            line.map = map
        }
        let changed =
            context.coordinator.destination != destination || context.coordinator.hasFriend != (friend != nil)
            || context.coordinator.focusRequest != focusRequest
        if changed || !context.coordinator.centered {
            let positions = [destination, mine, friend]
                .compactMap {
                    $0
                }
            if positions.count > 1 {
                var bounds = GMSCoordinateBounds()
                for point in positions {
                    bounds = bounds.includingCoordinate(
                        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    )
                }
                if let polyline, let path = GMSPath(fromEncodedPath: polyline) {
                    for index in 0..<path.count() {
                        bounds = bounds.includingCoordinate(path.coordinate(at: index))
                    }
                }
                map.animate(with: GMSCameraUpdate.fit(bounds, with: UIEdgeInsets(top: 105, left: 45, bottom: 45, right: 45)))
            } else {
                map.animate(toLocation: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
            }
            context.coordinator.destination = destination
            context.coordinator.hasFriend = friend != nil
            context.coordinator.focusRequest = focusRequest
            context.coordinator.centered = true
        }
    }
    private static func personPin(title: String, color: UIColor, isDestination: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let text = String(title.prefix(10))
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let width = max(60, textWidth + 24)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 88))
            .image { renderer in
                let context = renderer.cgContext
                context.setShadow(
                    offset: CGSize(width: 0, height: 2),
                    blur: 5,
                    color: UIColor.black.withAlphaComponent(0.18).cgColor
                )
                UIColor.secondarySystemBackground.setFill()
                UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: width - 4, height: 25), cornerRadius: 12).fill()
                context.setShadow(offset: .zero, blur: 0)
                (text as NSString)
                    .draw(
                        at: CGPoint(x: (width - textWidth) / 2, y: 7),
                        withAttributes: [.font: font, .foregroundColor: UIColor.label]
                    )
                let circle = CGRect(x: width / 2 - 23, y: 32, width: 46, height: 46)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: circle.insetBy(dx: -3, dy: -3)).fill()
                color.setFill()
                UIBezierPath(ovalIn: circle).fill()
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: width / 2 - 7, y: 74))
                tail.addLine(to: CGPoint(x: width / 2, y: 87))
                tail.addLine(to: CGPoint(x: width / 2 + 7, y: 74))
                tail.close()
                tail.fill()
                UIImage(systemName: isDestination ? "flag.fill" : "person.fill")?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: width / 2 - 11, y: 43, width: 22, height: 24))
            }
    }

    final class Coordinator {
        var destination: Coordinate?
        var hasFriend = false
        var centered = false
        var focusRequest = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

struct MeetingRouteView: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loadingLocation = false
    @State private var routeError: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ReunionMap(expanded: true)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    Label(store.meeting.place, systemImage: "flag.fill")
                    Picker(
                        "이동수단",
                        selection: Binding(
                            get: { store.meeting.mode },
                            set: { mode in
                                var meeting = store.meeting
                                meeting.mode = mode
                                store.updateMeeting(meeting)
                            }
                        )
                    ) {
                        ForEach(TravelMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.phase != .free || store.isLoading || loadingLocation)
                    if let estimate = store.estimate {
                        LabeledContent("예상 이동시간", value: "\(estimate.minutes)분")
                        LabeledContent(
                            "이동 거리",
                            value: String(format: "%.1f km", Double(estimate.distanceMeters) / 1000)
                        )
                        Text("약속 시간에 맞춘 경로 · 마지막 계산 \(estimate.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await calculate() }
                    } label: {
                        if store.isLoading || loadingLocation {
                            ProgressView(loadingLocation ? "현재 위치 확인 중" : "경로 찾는 중")
                        } else {
                            Label("현재 위치에서 경로 찾기", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                    }
                    .disabled(store.isLoading || loadingLocation)
                }
                if let routeError {
                    Section {
                        Text(routeError)
                            .foregroundStyle(.secondary)
                    }
                }
                if let instructions = store.estimate?.instructions, !instructions.isEmpty {
                    Section("이동 안내") {
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                    .frame(width: 24, height: 24)
                                    .background(.blue.opacity(0.1), in: Circle())
                                Text(instruction)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("길 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("완료")
                    }
                }
            }
            .task {
                if store.estimate?.instructions == nil { await calculate() }
            }
            .onChange(of: store.meeting.mode) { _, _ in
                Task { await calculate() }
            }
        }
    }

    // MARK: - Methods

    private func calculate() async {
        guard !loadingLocation && !store.isLoading else { return }

        routeError = nil
        if store.freshLocation == nil {
            loadingLocation = true
            store.startLocation()
            for _ in 0..<60 {
                if store.freshLocation != nil || Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            loadingLocation = false
        }
        guard !Task.isCancelled else { return }
        guard store.freshLocation != nil else {
            routeError = "현재 위치를 확인할 수 없어요. iPhone 설정에서 위치 권한을 확인한 뒤 다시 시도해 주세요."
            return
        }

        store.error = nil
        await store.fetchRoute()
        routeError = store.error
        store.error = nil
        store.mapFocusRequest += 1
    }
}
