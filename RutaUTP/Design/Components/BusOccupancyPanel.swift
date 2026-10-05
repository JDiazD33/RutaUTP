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
                 : L.t("Busca tu ruta y confirma «Sí, ya subí» para indicar cómo va tu micro.",
                       "Find your route and confirm ‘Yes, I'm on board’ to report bus occupancy."))
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
    var statusMessage: String? = nil
    var statusColor: Color = .secondary
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
            if coordinator.isEnabled, !coordinator.isRunning,
               let fallo = coordinator.errorCargaRutas {
                Text(fallo.mensajeUsuario).font(.caption).foregroundStyle(.secondary)
                Button(L.t("Reintentar detección", "Retry detection")) {
                    coordinator.setContributionEnabled(true)
                }
                .buttonStyle(.bordered)
            }
            if let statusMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
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

/// Pregunta tras encontrar una ruta; responder no conserva el itinerario.
struct BoardingConfirmationSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let suggestedRouteID: String?
    let onRemindLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLine = false

    var body: some View {
        Group {
            if confirmingLine {
                TripSelectionSheet(coordinator: coordinator, suggestedRouteID: suggestedRouteID)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .frame(width: 64, height: 64)
                        .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 22))
                    Text(L.t("¿Ya te encuentras en el transporte público?",
                             "Are you already on public transport?"))
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(L.t("Si ya subiste, confirma la línea que tomaste. Si aún no, puedes seguir viendo tu ruta.",
                             "If you've boarded, confirm your line. Otherwise, keep viewing your route."))
                        .font(.subheadline)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button { confirmingLine = true } label: {
                        Text(L.t("Sí, ya subí", "Yes, I'm on board"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appPrimary)
                    Button {
                        onRemindLater()
                        dismiss()
                    } label: {
                        Label(L.t("Recordarme en 2 minutos", "Remind me in 2 minutes"), systemImage: "clock")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button(L.t("Todavía no", "Not yet")) { dismiss() }
                        .frame(minHeight: 44)
                }
                .padding(24)
            }
        }
        .presentationDetents(confirmingLine ? [.large] : [.height(490), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

private struct TripSelectionSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    var suggestedRouteID: String? = nil
    @State private var showConsent = false
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [RutaGTFS] = []
    @State private var selected: RutaGTFS?
    @State private var search = ""
    @State private var occupancy = ""
    @State private var boardingPlace = ""
    @State private var boardingPoint: BoardingPoint?
    @State private var showBoardingMap = false
    @State private var loading = true
    @State private var errorCargaRutas: String?
    @State private var revisionCatalogo = 0
    /// Geocodificación inversa en curso. Se cancela al mover el punto otra vez:
    /// si no, la respuesta de un punto viejo landingaría después y pondría una
    /// calle que ya no corresponde al pin.
    @State private var tareaDireccion: Task<Void, Never>?

    /// Escribe la calle del punto marcado, sustituyendo lo que hubiera.
    ///
    /// Es un RELLENO, no un cierre: el campo sigue editable porque la calle
    /// que devuelve el sistema no siempre es la que el usuario reconoce
    /// ("Av. España" puede salir como "Calle España").
    private func escribirDireccion(para punto: BoardingPoint) {
        tareaDireccion?.cancel()
        tareaDireccion = Task { @MainActor in
            let nombre = await Geocodificacion.nombreDelLugar(
                CLLocationCoordinate2D(latitude: punto.latitude,
                                       longitude: punto.longitude)
            )
            guard !Task.isCancelled else { return }
            boardingPlace = String(nombre.prefix(120))
        }
    }

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
                        if coordinator.isEnabled, !coordinator.isRunning,
                           let fallo = coordinator.errorCargaRutas {
                            Section {
                                Text(fallo.mensajeUsuario).font(.caption).foregroundStyle(.secondary)
                                Button(L.t("Reintentar detección", "Retry detection")) {
                                    coordinator.setContributionEnabled(true)
                                }
                            }
                        }
                        if !coordinator.isEnabled {
                            Section {
                                if coordinator.isPublisherConfigured {
                                    Button(L.t("Activar Ayudar con ubicaciones", "Turn on Help with locations")) {
                                        showConsent = true
                                    }
                                    .accessibilityHint(TextoConsentimientoContribucion.pistaAccesibilidad)
                                    Text(L.t("Para contribuir con tu viaje, activa esta opción y concede los permisos de ubicación y movimiento.",
                                             "To contribute your trip, enable this option and grant location and motion permissions."))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(L.t("Esta instalación aún no tiene habilitada la contribución de viajes. Puedes seguir consultando la ruta en el mapa.",
                                             "Trip contributions aren't configured on this installation yet. You can still view your route on the map."))
                                }
                            }
                        }
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
                                    Button(L.t("Quitar", "Remove"), role: .destructive) {
                                        boardingPoint = nil
                                        boardingPlace = ""
                                    }
                                        .font(.caption)
                                }
                            }
                            TextField(L.t("Calle o referencia", "Street or landmark"),
                                      text: $boardingPlace, axis: .vertical)
                                .lineLimit(1...3)
                                .onChange(of: boardingPlace) { _, value in
                                    boardingPlace = String(value.prefix(120))
                                }
                        } header: {
                            Text(L.t("¿Dónde subiste? (opcional)", "Where did you board? (optional)"))
                        } footer: {
                            Text(L.t("Marca el lugar y la dirección se escribe sola; puedes corregirla. Es opcional y se guarda solo en tu teléfono para futuros paraderos de alumnos.",
                                     "Mark the spot and the address is written for you; you can edit it. This is optional and stays on your phone for future student stops."))
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
                        } else if let errorCargaRutas {
                            Text(errorCargaRutas).foregroundStyle(.secondary)
                            Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
                        } else if filtered.isEmpty {
                            Text(routes.isEmpty
                                 ? L.t("El catálogo no contiene líneas.", "The catalog contains no lines.")
                                 : L.t("No encontramos esa línea.", "No matching line found."))
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
                                     currentLocation: coordinator.latestLocation) { nuevo in
                        boardingPoint = nuevo
                        // La calle se escribe sola a partir del punto marcado:
                        // es lo que el usuario acaba de señalar, y preguntárselo
                        // otra vez es el mismo dato dos veces.
                        escribirDireccion(para: nuevo)
                    }
                }
            }
            .navigationTitle(L.t("Estoy en un micro", "I'm on a bus"))
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { tareaDireccion?.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
            .confirmationDialog(L.t("Ayudar con ubicaciones en tiempo real", "Help with real-time locations"),
                                isPresented: $showConsent, titleVisibility: .visible) {
                Button(L.t("Aceptar y activar", "Accept and turn on")) {
                    coordinator.setContributionEnabled(true)
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: {
                Text(TextoConsentimientoContribucion.confirmacion)
            }
            .task(id: revisionCatalogo) {
                loading = true
                errorCargaRutas = nil
                let feed: [RutaGTFS]
                do {
                    feed = try await GTFSRepository.shared.cargarRutas(reintentar: revisionCatalogo > 0)
                    guard !Task.isCancelled else { return }
                } catch {
                    guard !Task.isCancelled else { return }
                    errorCargaRutas = (error as? FalloCargaGTFS)?.mensajeUsuario
                        ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
                    loading = false
                    return
                }
                if let location = coordinator.latestLocation {
                    let distances = Dictionary(uniqueKeysWithValues: feed.map { route in
                        (route.id, RouteCandidateMatcher.closestMatch(for: location,
                            routes: [DetectionRouteGeometry(route: route)])?.distanceToRoute ?? .infinity)
                    })
                    routes = feed.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
                } else {
                    routes = feed.sorted { $0.linea.localizedStandardCompare($1.linea) == .orderedAscending }
                }
                if let suggestedRouteID { selected = routes.first { $0.id == suggestedRouteID } }
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
