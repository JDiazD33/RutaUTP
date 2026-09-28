import SwiftUI
import CoreLocation
import MapKit

/// La ficha pública muestra corroboraciones; los votos se envían desde el viaje.
struct BusOccupancyPanel: View {
    let vehicleID: String?
    @StateObject private var service = OccupancyService()

    private var reading: OccupancyReading? {
        service.buses.first { $0.vehicleId == vehicleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L.t("Ocupación", "Occupancy"), systemImage: "person.2.fill")
                Spacer()
                Text(reading?.state.title ?? (service.ready
                    ? L.t("Sin confirmar", "Unconfirmed")
                    : L.t("Sin datos recientes", "No recent data")))
                    .fontWeight(.semibold)
            }
            if let reading {
                Text(L.t("\(reading.confirmations) personas coinciden", "\(reading.confirmations) people agree"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(vehicleID == nil
                 ? L.t("Disponible para vehículos reales.", "Available for real vehicles.")
                 : L.t("Para indicar cómo va tu micro, usa «Estoy en un micro» en el mapa.",
                       "To report your bus occupancy, use ‘I'm on a bus’ on the map."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { if vehicleID != nil { service.start() } }
        .onDisappear { service.stop() }
    }
}

struct TripContributionPanel: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    @State private var showTrip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let route = coordinator.selectedTripRoute {
                HStack {
                    Label(L.t("Tu Transporte Público: línea ", "Your public transport: line ") + route.linea, systemImage: "bus.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(L.t("Ya bajé", "I've got off")) { coordinator.endTrip() }
                        .buttonStyle(.bordered)
                }
                Text(coordinator.confirmedLine != nil
                     ? L.t("Estás ayudando en esta línea. Mantén la app abierta.",
                           "You're helping on this line. Keep the app open.")
                     : L.t("Esperando detectar movimiento compatible con tu línea.",
                           "Waiting for movement matching your line."))
                    .font(.caption).foregroundStyle(.secondary)
                if let place = coordinator.boardingPlace {
                    Label(L.t("Subiste en: ", "Boarded at: ") + place, systemImage: "mappin")
                        .font(.caption).lineLimit(2)
                }
                if coordinator.boardingPoint != nil {
                    Label(L.t("Punto de subida guardado", "Boarding point saved"), systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TripOccupancyControls(service: coordinator.tripOccupancy) { coordinator.updateTripOccupancy($0) }
                Button(L.t("Cambiar de línea", "Change line")) { showTrip = true }
                    .font(.caption)
            } else {
                Button { showTrip = true } label: {
                    Label(L.t("Estoy en un micro", "I'm on a bus"), systemImage: "bus.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showTrip) { TripSelectionSheet(coordinator: coordinator) }
    }
}

private struct TripOccupancyControls: View {
    @ObservedObject var service: OccupancyService
    let onSelect: (BusOccupancyState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("¿Qué tan lleno va ahora?", "How full is it now?"))
                .font(.caption)
            HStack {
                ForEach(BusOccupancyState.allCases, id: \.self) { state in
                    Button(state.title) { onSelect(state) }
                        .buttonStyle(.bordered)
                        .disabled(service.sending)
                }
            }
            if let result = service.result {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TripSelectionSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [RutaGTFS] = []
    @State private var selected: RutaGTFS?
    @State private var search = ""
    @State private var occupancy = ""
    @State private var boardingPlace = ""
    @State private var boardingPoint: BoardingPoint?
    @State private var showBoardingMap = false
    @State private var loading = true

    private func occupancyOption(_ value: String, title: String, icon: String) -> some View {
        let selected = occupancy == value
        return Button {
            occupancy = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(selected ? Color.appPrimary : Color.secondary)
                Text(title)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.appPrimary : Color.secondary.opacity(0.4))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? L.t("Seleccionado", "Selected") : L.t("Sin seleccionar", "Not selected"))
    }

    private var filtered: [RutaGTFS] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return routes.filter {
            query.isEmpty || "\($0.linea) \($0.empresa) \($0.variante)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let route = selected {
                    Form {
                        Section(L.t("Tu Transporte Público", "Your Public Transport")) {
                            Text(L.t("Línea ", "Line ") + route.linea).font(.headline)
                            Text(route.empresa + " · " + route.variante).font(.subheadline)
                            Button(L.t("Elegir otra línea", "Choose another line")) { selected = nil }
                        }
                        Section {
                            Button { showBoardingMap = true } label: {
                                Label(boardingPoint == nil
                                      ? L.t("Marcar en el mapa", "Mark on the map")
                                      : L.t("Ver o cambiar el punto", "View or change point"),
                                      systemImage: "map")
                                    .frame(minHeight: 44)
                            }
                            if boardingPoint != nil {
                                HStack {
                                    Label(L.t("Punto seleccionado", "Point selected"), systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(Color.appPrimary)
                                    Spacer()
                                    Button(L.t("Quitar", "Remove"), role: .destructive) { boardingPoint = nil }
                                        .font(.caption)
                                }
                            }
                            TextField(L.t("Calle o referencia (opcional)", "Street or landmark (optional)"),
                                      text: $boardingPlace, axis: .vertical)
                                .lineLimit(1...3)
                                .onChange(of: boardingPlace) { _, value in
                                    boardingPlace = String(value.prefix(120))
                                }
                        } header: {
                            Text(L.t("¿Dónde subiste? (opcional)", "Where did you board? (optional)"))
                        } footer: {
                            Text(L.t("Marca el lugar, escribe una referencia o usa ambos. Es opcional y se guarda solo en tu teléfono para futuros paraderos de alumnos.",
                                     "Mark the spot, write a reference, or use both. This is optional and stays on your phone for future student stops."))
                        }
                        Section {
                            occupancyOption("", title: L.t("Prefiero no indicar", "Skip for now"),
                                            icon: "minus.circle")
                            ForEach(BusOccupancyState.allCases, id: \.rawValue) { state in
                                occupancyOption(state.rawValue, title: state.title,
                                    icon: state == .empty ? "person" : state == .space ? "person.2" : "person.3.fill")
                            }
                        } header: {
                            Text(L.t("¿Qué tan lleno va? (opcional)", "How full is it? (optional)"))
                        } footer: {
                            Text(L.t("Elige cómo va ahora. Puedes actualizarlo durante el viaje; el reporte vence en 3 minutos y necesita corroboración.",
                                     "Choose how full it is now. You can update it during the trip; the report expires in 3 minutes and needs corroboration."))
                        }
                        Button(L.t("Comenzar a ayudar", "Start helping")) {
                            coordinator.beginTrip(route: DetectionRouteGeometry(route: route),
                                                  occupancy: BusOccupancyState(rawValue: occupancy),
                                                  boardingPlace: boardingPlace,
                                                  boardingPoint: boardingPoint)
                            dismiss()
                        }
                        .disabled(!coordinator.isEnabled || !coordinator.isPublisherConfigured)
                    }
                } else {
                    List {
                        if loading {
                            ProgressView(L.t("Cargando líneas…", "Loading lines…"))
                        } else if filtered.isEmpty {
                            Text(L.t("No encontramos esa línea.", "No matching line found."))
                        }
                        Section(coordinator.latestLocation == nil
                                ? L.t("Elige la línea que tomaste", "Choose your line")
                                : L.t("Líneas cercanas primero", "Nearby lines first")) {
                            ForEach(filtered) { route in
                                Button { selected = route } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L.t("Línea ", "Line ") + route.linea).font(.headline)
                                        Text(route.empresa + " · " + route.variante)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: L.t("Línea o empresa", "Line or operator"))
                }
            }
            .fullScreenCover(isPresented: $showBoardingMap) {
                if let route = selected {
                    BoardingPointMap(route: route, initialPoint: boardingPoint,
                                     currentLocation: coordinator.latestLocation) { boardingPoint = $0 }
                }
            }
            .navigationTitle(L.t("Estoy en un micro", "I'm on a bus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
            .task {
                let feed = await GTFSRepository.shared.rutas()
                if let location = coordinator.latestLocation {
                    let distances = Dictionary(uniqueKeysWithValues: feed.map { route in
                        (route.id, RouteCandidateMatcher.closestMatch(for: location,
                            routes: [DetectionRouteGeometry(route: route)])?.distanceToRoute ?? .infinity)
                    })
                    routes = feed.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
                } else {
                    routes = feed.sorted { $0.linea.localizedStandardCompare($1.linea) == .orderedAscending }
                }
                loading = false
            }
        }
    }
}


/// Selección explícita: centrar en el usuario nunca confirma dónde subió.
private struct BoardingPointMap: View {
    let route: RutaGTFS
    let onConfirm: (BoardingPoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @Namespace private var mapScope
    @State private var point: BoardingPoint?
    @State private var camera: MapCameraPosition

    init(route: RutaGTFS, initialPoint: BoardingPoint?, currentLocation: CLLocation?,
         onConfirm: @escaping (BoardingPoint) -> Void) {
        self.route = route
        self.onConfirm = onConfirm
        _point = State(initialValue: initialPoint)
        let freshLocation = currentLocation.flatMap { location -> CLLocationCoordinate2D? in
            guard abs(location.timestamp.timeIntervalSinceNow) < 60,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return nil }
            return location.coordinate
        }
        let center = initialPoint?.coordinate ?? freshLocation ?? route.shape.first ?? GTFSRepository.coordenadaUTP
        _camera = State(initialValue: .region(MKCoordinateRegion(center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera, scope: mapScope) {
                    UserAnnotation()
                    MapPolyline(coordinates: route.shape).stroke(route.color, lineWidth: 4)
                    if let point {
                        Marker(L.t("Aquí subí", "I boarded here"), coordinate: point.coordinate)
                            .tint(Color.appPrimary)
                    }
                }
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        point = BoardingPoint(coordinate: coordinate)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 12) {
                        MapUserLocationButton(scope: mapScope)
                            .accessibilityLabel(L.t("Centrar en mi ubicación", "Center on my location"))
                        MapCompass(scope: mapScope)
                        Button {
                            withAnimation { camera = .automatic }
                        } label: {
                            Image(systemName: "map")
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel(L.t("Ver el recorrido", "Show route"))
                    }
                    .padding()
                }
            }
            .mapScope(mapScope)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text(L.t("Toca el lugar donde subiste. El botón de ubicación te acerca a donde estás ahora; puedes mover el mapa para marcar otro lugar.",
                             "Tap where you boarded. The location button centers on where you are now; move the map to mark another spot."))
                        .font(.subheadline).multilineTextAlignment(.center)
                    Button {
                        guard let point else { return }
                        onConfirm(point)
                        dismiss()
                    } label: {
                        Text(L.t("Usar este punto", "Use this point"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(point == nil)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(L.t("¿Dónde subiste?", "Where did you board?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
    }
}
