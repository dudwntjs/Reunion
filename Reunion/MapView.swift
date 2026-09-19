import SwiftUI

import KakaoMapsSDK

enum KakaoMapsSetup {
    static let enabled: Bool = {
        guard !MapConfiguration.nativeKey.isEmpty else { return false }
        SDKInitializer.InitSDK(appKey: MapConfiguration.nativeKey)
        return true
    }()
}

struct MapPin: Equatable {
    var id: String
    var title: String
    var coordinate: Coordinate
    var color: UIColor
    var heading: Double? = nil
    var stale = false
    var symbol = "person.fill"
}

struct ReunionMap: View {
    @Environment(ReunionStore.self) private var store
    var places: [PlaceResult] = []
    var selected: PlaceResult?
    var active = true
    var onSelect: (String) -> Void = { _ in }
    var onLongPress: (Coordinate) -> Void = { _ in }
    @State private var mapError: String?

    private var current: Coordinate? {
        store.currentLocation.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }
    private var pins: [MapPin] {
        var pins = places.map {
            MapPin(
                id: $0.id,
                title: $0.displayName.text,
                coordinate: $0.location,
                color: selected?.id == $0.id ? .systemOrange : .systemGray,
                symbol: "mappin"
            )
        }
        if let selected, !places.contains(where: { $0.id == selected.id }) {
            pins.append(
                MapPin(
                    id: selected.id,
                    title: selected.displayName.text,
                    coordinate: selected.location,
                    color: .systemOrange,
                    symbol: "mappin"
                )
            )
        }
        if store.hasDestination {
            pins.append(
                MapPin(
                    id: "destination",
                    title: store.meeting.place,
                    coordinate: store.meeting.coordinate,
                    color: .systemOrange,
                    symbol: "flag.fill"
                )
            )
        }
        if let current {
            let course = store.currentLocation?.course ?? -1
            pins.append(
                MapPin(
                    id: "me",
                    title: "나",
                    coordinate: current,
                    color: .systemBlue,
                    heading: course >= 0 ? course : nil,
                    stale: Date().timeIntervalSince(store.locationUpdated ?? .distantPast) > 30
                )
            )
        }
        for peer in store.peers {
            if let coordinate = peer.visibleCoordinate {
                pins.append(
                    MapPin(
                        id: "peer-" + peer.id,
                        title: peer.name,
                        coordinate: coordinate,
                        color: .systemGreen,
                        heading: peer.heading,
                        stale: peer.isStale
                    )
                )
            }
        }
        return pins
    }
    var body: some View {
        Group {
            if !KakaoMapsSetup.enabled {
                ContentUnavailableView(
                    "카카오 지도 연결 준비 중",
                    systemImage: "map",
                    description: Text("연결이 준비되면 내 위치와 친구들의 위치가 표시돼요.")
                )
            } else if let center = selected?.location ?? current
                ?? (store.hasDestination ? store.meeting.coordinate : places.first?.location)
            {
                KakaoMapCanvas(
                    pins: pins,
                    path: store.estimate?.coordinates ?? [],
                    center: center,
                    focus: "\(store.mapFocusRequest)-\(selected?.id ?? "")",
                    active: active,
                    onSelect: onSelect,
                    onLongPress: onLongPress,
                    onError: { mapError = $0 }
                )
                .overlay(alignment: .bottom) {
                    if let mapError {
                        Text(mapError).font(.caption).padding(10).background(.regularMaterial)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("내 위치를 확인해 주세요", systemImage: "location")
                } actions: {
                    Button {
                        store.startLocation()
                    } label: {
                        Text("내 위치 확인")
                    }
                }
            }
        }
        .frame(height: 380)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("togetherMap")
    }
}

struct KakaoMapCanvas: UIViewRepresentable {
    var pins: [MapPin]
    var path: [Coordinate]
    var center: Coordinate
    var focus: String
    var active: Bool
    var onSelect: (String) -> Void
    var onLongPress: (Coordinate) -> Void
    var onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SizedMapContainer {
        let view = SizedMapContainer(frame: .zero)
        let coordinator = context.coordinator
        coordinator.container = view
        coordinator.controller = KMController(viewContainer: view)
        coordinator.controller?.delegate = coordinator
        view.onLayout = { [weak coordinator] in coordinator?.updateEngine() }
        return view
    }
    func updateUIView(_ view: SizedMapContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateEngine()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SizedMapContainer, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 380)
    }
    static func dismantleUIView(_ view: SizedMapContainer, coordinator: Coordinator) {
        coordinator.dispose()
    }

    final class Coordinator: NSObject, MapControllerDelegate {
        var parent: KakaoMapCanvas
        weak var container: KMViewContainer?
        var controller: KMController?
        var map: KakaoMap?
        var labelLayer: LabelLayer?
        var routeLayer: RouteLayer?
        var handlers: [any DisposableEventHandler] = []
        var terrainHandler: (any DisposableEventHandler)?
        var styleIDs: [String] = []
        var renderedPins: [MapPin] = []
        var renderedPath: [Coordinate] = []
        var lastFocus: String?
        var ready = false
        var preparationStarted = false

        init(_ parent: KakaoMapCanvas) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pause),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(resume),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
        @objc private func pause() { controller?.pauseEngine() }
        @objc private func resume() { updateEngine() }
        func updateEngine() {
            guard let container, container.bounds.width > 0, container.bounds.height > 0,
                let controller
            else { return }
            if !preparationStarted {
                preparationStarted = true
                if !controller.prepareEngine() {
                    preparationStarted = false
                    DispatchQueue.main.async { self.parent.onError("지도 준비에 실패했어요. 앱을 다시 열어 주세요.") }
                    return
                }
            }
            if parent.active {
                if !controller.isEngineActive { controller.activateEngine() }
            } else if controller.isEngineActive {
                controller.pauseEngine()
            }
            map?.viewRect = container.bounds
            render()
        }
        func dispose() {
            NotificationCenter.default.removeObserver(self)
            handlers.forEach { $0.dispose() }
            terrainHandler?.dispose()
            controller?.pauseEngine()
            controller?.resetEngine()
            controller?.delegate = nil
            controller = nil
        }
        func addViews() {
            let info = MapviewInfo(
                viewName: "reunion",
                viewInfoName: "map",
                defaultPosition: point(parent.center),
                defaultLevel: 16
            )
            controller?.addView(info)
        }
        func addViewSucceeded(_ viewName: String, viewInfoName: String) {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            self.map = map
            map.viewRect = container?.bounds ?? .zero
            map.setGestureEnable(type: .rotate, enable: false)
            map.setGestureEnable(type: .tilt, enable: false)
            labelLayer = map.getLabelManager()
                .addLabelLayer(
                    option: LabelLayerOptions(
                        layerID: "participants",
                        competitionType: .none,
                        competitionUnit: .symbolFirst,
                        orderType: .rank,
                        zOrder: 10
                    )
                )
            let manager = map.getRouteManager()
            routeLayer = manager.addRouteLayer(layerID: "walk", zOrder: 0)
            let style = PerLevelRouteStyle(width: 7, color: .systemBlue, strokeWidth: 2, strokeColor: .white, level: 0)
            manager.addRouteStyleSet(RouteStyleSet(styleID: "walk", styles: [RouteStyle(styles: [style])]))
            terrainHandler = map.addTerrainLongPressedEventHandler(target: self) { target in
                { event in
                    target.parent.onLongPress(
                        Coordinate(
                            latitude: event.position.wgsCoord.latitude,
                            longitude: event.position.wgsCoord.longitude
                        )
                    )
                }
            }
            ready = true
            render()
        }
        func containerDidResized(_ size: CGSize) {
            map?.viewRect = CGRect(origin: .zero, size: size)
        }
        func authenticationSucceeded() { DispatchQueue.main.async { self.parent.onError(nil) } }
        func authenticationFailed(_ errorCode: Int, desc: String) {
            DispatchQueue.main.async { self.parent.onError("카카오 지도 인증 실패 (\(errorCode)). 키와 iOS 앱 등록을 확인해 주세요.") }
        }
        func addViewFailed(_ viewName: String, viewInfoName: String) {
            DispatchQueue.main.async { self.parent.onError("지도를 불러오지 못했어요. 네트워크를 확인해 주세요.") }
        }
        func render() {
            guard ready, let map else { return }
            let membershipChanged = renderedPins.map(\.id) != parent.pins.map(\.id)
            if renderedPins != parent.pins {
                handlers.forEach { $0.dispose() }
                handlers = []
                labelLayer?.clearAllItems()
                let manager = map.getLabelManager()
                styleIDs.forEach { manager.removePoiStyle($0) }
                styleIDs = []
                for pin in parent.pins {
                    let styleID = UUID().uuidString
                    styleIDs.append(styleID)
                    let icon = PoiIconStyle(symbol: Self.icon(pin), anchorPoint: CGPoint(x: 0.5, y: 1))
                    manager.addPoiStyle(PoiStyle(styleID: styleID, styles: [PerLevelPoiStyle(iconStyle: icon)]))
                    let options = PoiOptions(styleID: styleID, poiID: pin.id)
                    options.clickable = true
                    if let poi = labelLayer?.addPoi(option: options, at: point(pin.coordinate)) {
                        poi.show()
                        handlers.append(
                            poi.addPoiTappedEventHandler(target: self) { target in
                                { event in target.parent.onSelect(event.poiItem.itemID) }
                            }
                        )
                    }
                }
                renderedPins = parent.pins
            }
            if renderedPath != parent.path {
                routeLayer?.clearAllRoutes()
                if parent.path.count > 1 {
                    let options = RouteOptions(routeID: "mine", styleID: "walk", zOrder: 0)
                    options.segments = [RouteSegment(points: parent.path.map(point), styleIndex: 0)]
                    routeLayer?.addRoute(option: options)?.show()
                }
                renderedPath = parent.path
            }
            if lastFocus != parent.focus || membershipChanged {
                let points = parent.pins.map(\.coordinate) + parent.path
                if points.count > 1 {
                    let minLat = points.map(\.latitude).min()!, maxLat = points.map(\.latitude).max()!
                    let minLon = points.map(\.longitude).min()!, maxLon = points.map(\.longitude).max()!
                    let latPad = max(0.001, (maxLat - minLat) * 0.35)
                    let lonPad = max(0.001, (maxLon - minLon) * 0.2)
                    let area = AreaRect(
                        southWest: MapPoint(longitude: max(-180, minLon - lonPad), latitude: max(-85, minLat - latPad)),
                        northEast: MapPoint(longitude: min(180, maxLon + lonPad), latitude: min(85, maxLat + latPad))
                    )
                    map.moveCamera(CameraUpdate.make(area: area, levelLimit: 17))
                } else {
                    map.moveCamera(CameraUpdate.make(target: point(parent.center), zoomLevel: 16, mapView: map))
                }
                lastFocus = parent.focus
            }
        }
        private func point(_ coordinate: Coordinate) -> MapPoint {
            MapPoint(longitude: coordinate.longitude, latitude: coordinate.latitude)
        }
        private static func icon(_ pin: MapPin) -> UIImage {
            let text = String(pin.title.prefix(12)) + (pin.stale ? " · 마지막 위치" : "")
            let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let width = max(60, textWidth + 20)
            return UIGraphicsImageRenderer(size: CGSize(width: width, height: 80))
                .image { renderer in
                    let context = renderer.cgContext
                    context.setAlpha(pin.stale ? 0.6 : 1)
                    UIColor.secondarySystemBackground.setFill()
                    UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: width - 2, height: 24), cornerRadius: 12).fill()
                    (text as NSString)
                        .draw(at: CGPoint(x: 10, y: 5), withAttributes: [.font: font, .foregroundColor: UIColor.label])
                    UIColor.white.setFill()
                    UIBezierPath(ovalIn: CGRect(x: width / 2 - 23, y: 29, width: 46, height: 46)).fill()
                    pin.color.setFill()
                    UIBezierPath(ovalIn: CGRect(x: width / 2 - 20, y: 32, width: 40, height: 40)).fill()
                    let tail = UIBezierPath()
                    tail.move(to: CGPoint(x: width / 2 - 6, y: 68))
                    tail.addLine(to: CGPoint(x: width / 2, y: 80))
                    tail.addLine(to: CGPoint(x: width / 2 + 6, y: 68))
                    tail.close()
                    tail.fill()
                    context.saveGState()
                    context.translateBy(x: width / 2, y: 52)
                    if let heading = pin.heading { context.rotate(by: heading * .pi / 180) }
                    UIImage(systemName: pin.heading == nil ? pin.symbol : "location.north.fill")?
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                        .draw(in: CGRect(x: -10, y: -11, width: 20, height: 22))
                    context.restoreGState()
                }
        }
    }
}

final class SizedMapContainer: KMViewContainer {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
