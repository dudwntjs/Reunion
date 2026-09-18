import CoreLocation
import SwiftUI

import GoogleMaps

struct MeetingEditor: View {

    // MARK: - Properties

    @Environment(ReunionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Meeting()
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var searching = false
    @State private var searchPresented = false
    @State private var searched = false
    @State private var searchError: String?
    @State private var task: Task<Void, Never>?
    @State private var selectedID: String?
    @State private var requestID = UUID()
    @State private var submittedQuery = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            meetingForm
                .searchable(
                    text: $query,
                    isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "장소 이름이나 주소 검색"
                )
                .onSubmit(of: .search) {
                    search()
                }
                .navigationTitle("약속 정하기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("취소")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save()
                        } label: {
                            Text("저장")
                        }
                        .disabled(!valid)
                        .accessibilityIdentifier("saveMeeting")
                    }
                }
        }
        .onAppear {
            draft = store.meeting
            if store.freshLocation == nil {
                store.startLocation()
            }
        }
        .onDisappear {
            task?.cancel()
        }
        .onChange(of: query) { _, value in
            if value.isEmpty && selectedID != nil && !searchPresented {
                return
            }

            guard value.trimmingCharacters(in: .whitespacesAndNewlines) != submittedQuery else {
                return
            }

            task?.cancel()
            requestID = UUID()
            searching = false
            results = []
            searched = false
            searchError = nil
        }
    }
}

// MARK: - Subviews

extension MeetingEditor {

    @ViewBuilder
    private var placeSection: some View {
        if !draft.place.isEmpty {
            Section("선택한 장소") {
                Label(draft.place, systemImage: "checkmark.circle.fill")
            }
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        if GoogleMapsSetup.enabled, let center = mapCenter {
            Section("지도에서 장소 선택") {
                PlaceSelectionMap(
                    places: results,
                    selectedID: selectedID,
                    current: center,
                    onSelect: select
                )
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
                if let place = results.first(where: { $0.id == selectedID }) {
                    Label(place.displayName.text, systemImage: "checkmark.circle.fill")
                    if let address = place.formattedAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        Section("다시 만날 시간") {
            DatePicker("약속 시간", selection: $draft.target, in: Date()...Date().addingTimeInterval(86400))
            TextField("상세 만남 위치 (선택)", text: $draft.note)
        }
    }

    private var travelSection: some View {
        Section("나의 이동") {
            Picker("이동수단", selection: $draft.mode) {
                ForEach(TravelMode.allCases) {
                    Label($0.title, systemImage: $0.icon)
                        .tag($0)
                }
            }
            Stepper("여유시간 \(draft.bufferMinutes)분", value: $draft.bufferMinutes, in: 0...30)
        }
    }

    private var meetingForm: some View {
        Form {
            placeSection
            mapSection
            if searching {
                Section {
                    ProgressView("장소 검색 중")
                }
            }
            if let searchError {
                Section {
                    Text(searchError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if searched && !searching && results.isEmpty && searchError == nil {
                Section {
                    Text("검색 결과가 없어요. 다른 이름으로 찾아보세요.")
                        .foregroundStyle(.secondary)
                }
            }
            if !results.isEmpty {
                Section {
                    ForEach(results) { place in
                        Button {
                            select(place)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.displayName.text)
                                        .foregroundStyle(.primary)
                                    if let address = place.formattedAddress {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let location = store.freshLocation {
                                        Text(distance(to: place, from: location))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedID == place.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityIdentifier("placeResult-\(place.id)")
                        if let sources = place.attributions {
                            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                                if let provider = source.provider {
                                    Text(provider)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("검색 결과")
                } footer: {
                    Text("Google Maps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            timeSection
            travelSection
        }
    }
}

// MARK: - Methods

extension MeetingEditor {

    private var mapCenter: Coordinate? {
        if let first = results.first { return first.location }
        if !draft.place.isEmpty { return draft.coordinate }
        return store.currentLocation.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
    }

    private var valid: Bool {
        !draft.place.isEmpty && draft.coordinate.isValid && draft.target > .now

    }

    private func select(_ place: PlaceResult) {
        searchPresented = false
        selectedID = place.id
        draft.place = place.displayName.text
        draft.coordinate = place.location
    }

    private func search() {
        let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !requested.isEmpty else { return }

        task?.cancel()
        submittedQuery = requested
        let id = UUID()
        requestID = id
        searching = true
        searched = true
        searchError = nil
        task = Task { @MainActor in
            defer {
                if requestID == id {
                    searching = false
                }
            }
            do {
                let places = try await PlacesClient().search(
                    query: requested,
                    near: store.freshLocation.map {
                        .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    },
                    key: GoogleConfiguration.placesKey
                )

                guard !Task.isCancelled, requestID == id else { return }

                results = places
            } catch {
                guard !Task.isCancelled, requestID == id else { return }

                searchError = error.localizedDescription
                results = []
            }
        }
    }

    private func save() {
        guard valid else { return }

        if let location = store.freshLocation {
            draft.origin = .init(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
        store.updateMeeting(draft)
        dismiss()
        if !GoogleConfiguration.routesKey.isEmpty && store.freshLocation != nil {
            Task {
                await store.fetchRoute()
            }
        }
    }

    private func distance(to place: PlaceResult, from location: CLLocation) -> String {
        let meters = location.distance(
            from: CLLocation(latitude: place.location.latitude, longitude: place.location.longitude)
        )
        return meters < 1000 ? "직선거리 \(Int(meters))m" : String(format: "직선거리 %.1fkm", meters / 1000)
    }
}

/// 검색 결과 핀과 목록의 장소 선택을 동기화합니다.
private struct PlaceSelectionMap: UIViewRepresentable {

    // MARK: - Properties

    var places: [PlaceResult]
    var selectedID: String?
    var current: Coordinate
    var onSelect: (PlaceResult) -> Void

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: current.latitude,
            longitude: current.longitude,
            zoom: 15
        )
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.isMyLocationEnabled = true
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let resultsChanged = coordinator.places != places
        let selectionChanged = coordinator.selectedID != selectedID
        guard resultsChanged || selectionChanged else { return }

        map.clear()
        var bounds = GMSCoordinateBounds()
        for place in places {
            let position = CLLocationCoordinate2D(
                latitude: place.location.latitude,
                longitude: place.location.longitude
            )
            let marker = GMSMarker(position: position)
            marker.title = place.displayName.text
            marker.snippet = place.formattedAddress
            marker.userData = place.id
            marker.icon = GMSMarker.markerImage(with: place.id == selectedID ? .systemBlue : .systemRed)
            marker.map = map
            bounds = bounds.includingCoordinate(position)
            if place.id == selectedID {
                map.selectedMarker = marker
                if selectionChanged {
                    map.animate(toLocation: position)
                }
            }
        }
        if resultsChanged, let first = places.first {
            if places.count == 1 {
                map.animate(
                    to: GMSCameraPosition(
                        latitude: first.location.latitude,
                        longitude: first.location.longitude,
                        zoom: 16
                    )
                )
            } else {
                map.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 48))
            }
        }
        coordinator.places = places
        coordinator.selectedID = selectedID
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: PlaceSelectionMap
        var places: [PlaceResult] = []
        var selectedID: String?

        init(parent: PlaceSelectionMap) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String,
                let place = parent.places.first(where: { $0.id == id })
            else { return false }

            parent.onSelect(place)
            return false
        }
    }
}
