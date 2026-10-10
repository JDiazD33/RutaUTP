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
    let locationService: LocationServiceProtocol
    var statusMessage: String? = nil
    var statusColor: Color = .secondary
    var onEndTrip: () -> Void = {}
    @State private var showDetails = false
    @State private var choosingLine = false
    @State private var confirmEndTrip = false

    var body: some View {
        if let route = coordinator.selectedTripRoute {
            Button { showDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.onPrimaryFill)
                        .frame(width: 36, height: 36)
                        .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Tu transporte público", "Your public transport"))
                            .font(.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(L.t("Línea ", "Line ") + route.lineaConLetra)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Tu transporte público. Línea ", "Your public transport. Line ") + route.lineaConLetra)
            .accessibilityHint(L.t("Abre la ocupación y las opciones para cambiar de línea o finalizar el viaje.",
                                  "Opens occupancy and options to change line or end the trip."))
            .sheet(isPresented: $showDetails, onDismiss: { choosingLine = false }) {
                Group {
                    if choosingLine {
                        TripSelectionSheet(coordinator: coordinator,
                                           locationService: locationService,
                                           suggestedRouteID: coordinator.selectedTripRoute?.id)
                    } else {
                        tripDetails
                    }
                }
                .presentationDetents(choosingLine ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var tripDetails: some View {
        NavigationStack {
            Form {
                if let route = coordinator.selectedTripRoute {
                    Section(L.t("Tu transporte público", "Your public transport")) {
                        LabeledContent(L.t("Línea", "Line"), value: route.linea)
                        LabeledContent(L.t("Letra del transporte", "Transport letter"),
                                       value: route.letraTransporte.isEmpty
                                        ? L.t("No especificada", "Not specified")
                                        : route.letraTransporte)
                        if let place = coordinator.boardingPlace {
                            Label(L.t("Subiste en: ", "Boarded at: ") + place, systemImage: "mappin")
                        }
                        if coordinator.boardingPoint != nil {
                            Label(L.t("Punto de subida guardado", "Boarding point saved"), systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section(L.t("Ocupación del micro", "Bus occupancy")) {
                        TripOccupancyControls(service: coordinator.tripOccupancy) {
                            coordinator.updateTripOccupancy($0)
                        }
                    }
                    Section(L.t("Estado del viaje", "Trip status")) {
                        Text(coordinator.confirmedLine != nil
                             ? L.t("Estás ayudando en esta línea.", "You're helping on this line.")
                             : L.t("Esperando detectar movimiento compatible con tu línea.",
                                   "Waiting for movement matching your line."))
                        if let statusMessage {
                            Label {
                                Text(statusMessage)
                            } icon: {
                                Circle().fill(statusColor).frame(width: 8, height: 8)
                            }
                        }
                        if coordinator.isEnabled, !coordinator.isRunning,
                           let fallo = coordinator.errorCargaRutas {
                            Text(fallo.mensajeUsuario)
                            Button(L.t("Reintentar detección", "Retry detection")) {
                                coordinator.setContributionEnabled(true)
                            }
                        }
                    }
                    Section {
                        Button(L.t("Cambiar de línea", "Change line")) { choosingLine = true }
                        Button(L.t("Finalizar viaje", "End trip"), role: .destructive) {
                            confirmEndTrip = true
                        }
                    }
                }
            }
            .navigationTitle(L.t("Tu viaje", "Your trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { showDetails = false }
                }
            }
            .confirmationDialog(L.t("¿Finalizar este viaje?", "End this trip?"),
                                isPresented: $confirmEndTrip, titleVisibility: .visible) {
                Button(L.t("Finalizar viaje", "End trip"), role: .destructive) {
                    coordinator.endTrip()
                    showDetails = false
                    onEndTrip()
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
            } message: {
                Text(L.t("Se dejará de compartir la ubicación de este micro y volverás al mapa principal.",
                         "Sharing this bus's location will stop and you'll return to the main map."))
            }
        }
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
    let locationService: LocationServiceProtocol
    let suggestedRouteID: String?
    let onRemindLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLine = false

    var body: some View {
        Group {
            if confirmingLine {
                TripSelectionSheet(coordinator: coordinator, locationService: locationService,
                                   suggestedRouteID: suggestedRouteID)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
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
    let locationService: LocationServiceProtocol
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
                            Text(route.empresa).font(.subheadline)
                            LabeledContent(L.t("Letra del transporte", "Transport letter"),
                                           value: route.letraTransporte.isEmpty
                                            ? L.t("No especificada", "Not specified")
                                            : route.letraTransporte)
                                .accessibilityElement(children: .combine)
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
                                     currentLocation: coordinator.latestLocation,
                                     locationService: locationService) { nuevo in
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
                    feed = try await TransporteApp.repositorio.cargarRutas(reintentar: revisionCatalogo > 0)
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


/// Propone la ubicación actual; solo «Usar este punto» confirma dónde subió.
private struct BoardingPointMap: View {
    let route: RutaGTFS
    let locationService: LocationServiceProtocol
    let onConfirm: (BoardingPoint) -> Void
    private let regionInicial: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var point: BoardingPoint?
    @State private var camera: MapCameraPosition
    @State private var solicitudUbicacion = 0
    @State private var buscandoUbicacion = true
    @State private var mensajeUbicacion: String?
    @State private var usarUbicacionComoPunto = false
    @State private var mostrarAjustesUbicacion = false
    private static let antiguedadMaximaUbicacion: TimeInterval = 5

    init(route: RutaGTFS, initialPoint: BoardingPoint?, currentLocation: CLLocation?,
         locationService: LocationServiceProtocol,
         onConfirm: @escaping (BoardingPoint) -> Void) {
        self.route = route
        self.locationService = locationService
        self.onConfirm = onConfirm
        _point = State(initialValue: initialPoint)
        let lecturas = [currentLocation, (locationService as? LocationService)?.lastKnownLocation]
            .compactMap { $0 }
            .filter { locationService.authorizationStatus.isAuthorized
                && UbicacionPuntual.esValida($0, ahora: Date(),
                    antiguedadMaxima: Self.antiguedadMaximaUbicacion) }
        let freshLocation = lecturas.max { $0.timestamp < $1.timestamp }?.coordinate
        let center = freshLocation ?? initialPoint?.coordinate ?? route.shape.first
            ?? TransporteApp.referenciaInicio
        regionInicial = Self.regionCercana(center)
        _camera = State(initialValue: .userLocation(followsHeading: false,
                                                   fallback: .region(regionInicial)))
    }

    private static func regionCercana(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500)
    }

    private var fondoControl: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primaryFill)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }

    @MainActor
    private func actualizarPuntoConUbicacionActual() async {
        let solicitud = solicitudUbicacion
        let reemplazarPunto = usarUbicacionComoPunto
        buscandoUbicacion = true
        mensajeUbicacion = nil
        mostrarAjustesUbicacion = false
        let location = await UbicacionPuntual.obtener(desde: locationService,
            antiguedadMaxima: Self.antiguedadMaximaUbicacion)
        guard !Task.isCancelled, solicitud == solicitudUbicacion else { return }
        buscandoUbicacion = false
        usarUbicacionComoPunto = false
        guard let location else {
            switch locationService.authorizationStatus {
            case .denied:
                mostrarAjustesUbicacion = true
                mensajeUbicacion = L.t("La ubicación está desactivada para esta app. Actívala en Ajustes o marca el lugar manualmente.",
                                       "Location is turned off for this app. Enable it in Settings or mark the spot manually.")
            case .restricted:
                mensajeUbicacion = L.t("El dispositivo restringe el acceso a la ubicación. Puedes marcar el lugar manualmente.",
                                       "This device restricts location access. You can mark the spot manually.")
            default:
                mensajeUbicacion = L.t("No pudimos obtener una ubicación reciente y precisa. Vuelve a intentarlo o marca el lugar manualmente.",
                                       "Couldn't get a recent, accurate location. Try again or mark the spot manually.")
            }
            return
        }
        // MapKit deja de seguir al usuario al mover el mapa. La lectura puntual
        // solo propone el pin; nunca sustituye la cámara que sigue el punto azul.
        guard camera.followsUserLocation else { return }
        if point == nil || reemplazarPunto {
            point = BoardingPoint(coordinate: location.coordinate)
        }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                ZStack {
                    Map(position: $camera,
                        bounds: camera.followsUserLocation
                            ? MapCameraBounds(minimumDistance: 100, maximumDistance: 700) : nil) {
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
                            camera = .region(Self.regionCercana(coordinate))
                        }
                    }
                    .mapControlVisibility(.hidden)
                    VStack(spacing: 12) {
                        Button {
                            // La pulsación ordena volver al usuario inmediatamente,
                            // aunque el mapa se haya arrastrado antes o el GPS tarde.
                            let respaldo = camera.region ?? camera.fallbackPosition?.region ?? regionInicial
                            camera = .userLocation(followsHeading: false, fallback: .region(respaldo))
                            usarUbicacionComoPunto = true
                            buscandoUbicacion = true
                            solicitudUbicacion &+= 1
                        } label: {
                            Group {
                                if buscandoUbicacion {
                                    ProgressView().tint(Color.onPrimaryFill)
                                } else {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                            }
                            .foregroundStyle(Color.onPrimaryFill)
                            .frame(width: 52, height: 52)
                            .background(fondoControl)
                        }
                        .buttonStyle(.plain)
                        .disabled(buscandoUbicacion && usarUbicacionComoPunto && camera.followsUserLocation)
                        .accessibilityLabel(L.t("Marcar mi ubicación actual", "Mark my current location"))
                        .accessibilityHint(L.t("Acerca el mapa y coloca el punto donde estás. Confírmalo con Usar este punto.",
                                              "Centers the map and places the point where you are. Confirm with Use this point."))
                        .accessibilityValue(buscandoUbicacion
                            ? L.t("Buscando ubicación", "Finding location") : "")
                        Button {
                            withAnimation { camera = .automatic }
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.onPrimaryFill)
                                .frame(width: 52, height: 52)
                                .background(fondoControl)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Ver el recorrido", "Show route"))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point?.coordinate) {
                        point = BoardingPoint(coordinate: $0)
                        camera = .region(Self.regionCercana($0))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let mensajeUbicacion {
                        Text(mensajeUbicacion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if mostrarAjustesUbicacion {
                        Button(L.t("Abrir Ajustes de ubicación", "Open location settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .frame(minHeight: 44)
                    }
                    Text(L.t("Revisa el punto donde subiste antes de confirmarlo. La flecha marca tu ubicación actual; toca el mapa para elegir otro lugar.",
                             "Review where you boarded before confirming. The arrow marks your current location; tap the map to choose another spot."))
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
                    .disabled(point == nil || (buscandoUbicacion && usarUbicacionComoPunto && camera.followsUserLocation))
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(L.t("¿Dónde subiste?", "Where did you board?"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: solicitudUbicacion) { await actualizarPuntoConUbicacionActual() }
            .onReceive(locationService.authorizationPublisher) { estado in
                guard estado.isAuthorized, mostrarAjustesUbicacion, !buscandoUbicacion else { return }
                buscandoUbicacion = true
                solicitudUbicacion &+= 1
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
    }
}
