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
                Text(L.f("{0} personas coinciden", "{0} people agree", ["\(reading.confirmations)"]))
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
    var itinerary: TransitItinerary? = nil
    var statusMessage: String? = nil
    var statusColor: Color = .secondary
    var onEndTrip: () -> Void = {}
    @State private var showDetails = false
    @State private var choosingLine = false
    @State private var confirmEndTrip = false
    @State private var confirmarReinicioSubidas = false
    @State private var errorRecuperacionSubidas = false
    @State private var respaldoSubidas: URL?

    private var siguienteTramo: RutaGTFS? {
        guard let itinerary, coordinator.selectedTripRoute?.id == itinerary.route.id else { return nil }
        return itinerary.transfer?.route
    }

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
                                           suggestedRouteID: siguienteTramo?.id,
                                           itinerary: itinerary)
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
                            Label(coordinator.falloAlGuardarSubida
                                  ? L.t("Punto de subida seleccionado", "Boarding point selected")
                                  : L.t("Punto de subida guardado", "Boarding point saved"), systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                        }
                        if coordinator.falloAlGuardarSubida {
                            Label(L.t("No pudimos guardar esta referencia de subida. Tus datos anteriores se conservan; puedes seguir ayudando durante este viaje.",
                                      "We couldn't save this boarding reference. Your previous data has been preserved; you can keep contributing during this trip."),
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.appError)
                            Button(L.t("Reintentar guardado", "Retry saving")) {
                                coordinator.reintentarGuardarSubida()
                            }
                            if BoardingPlaceStore.datosInvalidos() {
                                Button(L.t("Respaldar y reiniciar notas de subida", "Back up and reset boarding notes")) {
                                    confirmarReinicioSubidas = true
                                }
                            }
                        }
                        if let respaldoSubidas {
                            ShareLink(item: respaldoSubidas) {
                                Label(L.t("Compartir respaldo de subidas", "Share boarding backup"),
                                      systemImage: "square.and.arrow.up")
                            }
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
                                Text(L.aviso(statusMessage))
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
                        if let siguienteTramo {
                            Button {
                                choosingLine = true
                            } label: {
                                Label(L.t("Tomar transbordo", "Take the transfer") + " · " + siguienteTramo.lineaConLetra,
                                      systemImage: "arrow.triangle.branch")
                                    .frame(minHeight: 44)
                            }
                        } else if itinerary == nil {
                            Button(L.t("Cambiar de línea", "Change line")) { choosingLine = true }
                                .frame(minHeight: 44)
                        }
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
            .alert(L.t("¿Empezar un nuevo historial de subidas?", "Start a new boarding history?"),
                   isPresented: $confirmarReinicioSubidas) {
                Button(L.t("Respaldar y reiniciar", "Back up and reset"), role: .destructive) {
                    do {
                        if let archivo = try BoardingPlaceStore.respaldarYReiniciar() { respaldoSubidas = archivo }
                        coordinator.reintentarGuardarSubida()
                    } catch { errorRecuperacionSubidas = true }
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: {
                Text(L.t("Se guardará una copia del historial original en tus documentos y se reintentará guardar la subida de este viaje.",
                         "A copy of the original history will be saved in your documents and saving this trip's boarding reference will be retried."))
            }
            .alert(L.t("No se pudo reiniciar", "Couldn't reset"), isPresented: $errorRecuperacionSubidas) {
                Button(L.t("Aceptar", "OK"), role: .cancel) {}
            } message: {
                Text(L.t("No se reiniciaron los datos. Reintenta la lectura y comprueba el espacio disponible.",
                         "The data was not reset. Retry reading and check available storage."))
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
    @Environment(\.dynamicTypeSize) private var textSize
    @ObservedObject var service: OccupancyService
    let onSelect: (BusOccupancyState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("¿Qué tan lleno va ahora?", "How full is it now?"))
                .font(.caption)
            // No comprimir las tres respuestas en una fila con letra grande.
            (textSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))) {
                ForEach(BusOccupancyState.allCases, id: \.self) { state in
                    Button { onSelect(state) } label: {
                        Text(state.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
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

/// Conserva las líneas y paraderos del itinerario elegido para confirmar la subida.
struct BoardingConfirmationSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    let itinerary: TransitItinerary?
    let onRemindLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var confirmingLine = false

    var body: some View {
        Group {
            if confirmingLine {
                TripSelectionSheet(coordinator: coordinator, locationService: locationService,
                                   itinerary: itinerary)
            } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        Text(L.t("¿Ya te encuentras en el transporte público?",
                                 "Are you already on public transport?"))
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        Image(systemName: "bus")
                            .font(.title2)
                            .foregroundStyle(Color.appPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                    Text(L.t("Si ya subiste, confirma la línea que tomaste. Si aún no, puedes seguir viendo tu ruta.",
                             "If you've boarded, confirm your line. Otherwise, keep viewing your route."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { confirmingLine = true } label: {
                        Text(L.t("Sí, ya subí", "Yes, I'm on board"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(Color.onPrimaryFill)
                    .padding(.vertical, 6)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        onRemindLater()
                        dismiss()
                    } label: {
                        Label(L.t("Recordarme en 2 minutos", "Remind me in 2 minutes"), systemImage: "clock")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button(L.t("Todavía no", "Not yet")) { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                }
                .background(Color.appBackground)
            }
        }
        .presentationDetents(confirmingLine || textSize.isAccessibilitySize ? [.large] : [.height(490), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}

private struct TripSelectionSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    let suggestedRouteID: String?
    let itinerary: TransitItinerary?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var referenciaEnfocada: Bool
    @State private var showConsent = false
    @State private var comenzarAlEstarListo = false
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
    @State private var tareaDireccion: Task<Void, Never>?

    init(coordinator: PassiveTrackingCoordinator, locationService: LocationServiceProtocol,
         suggestedRouteID: String? = nil, itinerary: TransitItinerary? = nil) {
        self.coordinator = coordinator
        self.locationService = locationService
        self.suggestedRouteID = suggestedRouteID
        self.itinerary = itinerary
        let previstas = itinerary.map { [$0.route] + ($0.transfer.map { [$0.route] } ?? []) } ?? []
        _selected = State(initialValue: previstas.first { $0.id == suggestedRouteID } ?? previstas.first)
        _loading = State(initialValue: itinerary == nil)
    }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    private var filtered: [RutaGTFS] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return routes.filter {
            query.isEmpty || "\($0.lineaConLetra) \($0.empresa) \($0.variante)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func seleccionar(_ route: RutaGTFS) {
        guard selected?.id != route.id else { return }
        // Cada micro tiene su propia referencia de subida; no reutilizar la del tramo anterior.
        tareaDireccion?.cancel()
        boardingPoint = nil
        boardingPlace = ""
        occupancy = ""
        selected = route
        AppHaptics.selection()
    }

    private func escribirDireccion(para punto: BoardingPoint) {
        tareaDireccion?.cancel()
        let referenciaAnterior = boardingPlace
        tareaDireccion = Task { @MainActor in
            let nombre = await Geocodificacion.nombreDelLugar(punto.coordinate)
            guard !Task.isCancelled, boardingPoint == punto,
                  boardingPlace == referenciaAnterior else { return }
            // La respuesta tardía nunca sustituye una corrección escrita por la persona.
            boardingPlace = String(nombre.prefix(120))
        }
    }

    private func comenzarViaje() {
        guard let route = selected, coordinator.isPublisherConfigured else { return }
        guard coordinator.isEnabled else { showConsent = true; return }
        // Activar pide permisos y carga GTFS de forma asíncrona. No declarar
        // el viaje antes de que termine: una denegación dejaría una selección huérfana.
        guard coordinator.isRunning else {
            comenzarAlEstarListo = true
            coordinator.setContributionEnabled(true)
            return
        }
        comenzarAlEstarListo = false
        referenciaEnfocada = false
        coordinator.beginTrip(route: DetectionRouteGeometry(route: route),
                              occupancy: BusOccupancyState(rawValue: occupancy),
                              boardingPlace: boardingPlace, boardingPoint: boardingPoint)
        // El coordinador puede rechazar el inicio si cambian las preferencias.
        guard coordinator.selectedTripRoute?.id == route.id else { return }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let route = selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            encabezado
                            recorrido(route)
                            puntoDeSubida
                            ocupacion
                            estadoContribucion
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) { accionPrincipal }
                } else {
                    catalogo
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                        .frame(minHeight: 44)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("Listo", "Done")) { referenciaEnfocada = false }
                }
            }
            .fullScreenCover(isPresented: $showBoardingMap) {
                if let route = selected {
                    BoardingPointMap(route: route, initialPoint: boardingPoint,
                                     currentLocation: coordinator.latestLocation,
                                     locationService: locationService) { nuevo in
                        boardingPoint = nuevo
                        escribirDireccion(para: nuevo)
                    }
                    .seguirTemaForzado()
                }
            }
            .confirmationDialog(L.t("Ayudar con ubicaciones en tiempo real", "Help with real-time locations"),
                                isPresented: $showConsent, titleVisibility: .visible) {
                Button(L.t("Aceptar y activar", "Accept and turn on")) {
                    comenzarAlEstarListo = true
                    coordinator.setContributionEnabled(true)
                    if coordinator.isRunning { comenzarViaje() }
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: {
                Text(TextoConsentimientoContribucion.confirmacion)
            }
            .task(id: revisionCatalogo) { await cargarCatalogo() }
            .onChange(of: coordinator.isRunning) { _, listo in
                if listo, comenzarAlEstarListo { comenzarViaje() }
            }
            .onChange(of: coordinator.isEnabled) { _, activo in
                if !activo { comenzarAlEstarListo = false }
            }
            .onDisappear {
                tareaDireccion?.cancel()
                comenzarAlEstarListo = false
            }
        }
        .tint(acento)
        .presentationDetents([.large])
    }

    private var encabezado: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(L.t("Estoy en un micro", "I'm on a bus"))
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Image(systemName: "bus")
                .font(.title2)
                .foregroundStyle(acento)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    private func recorrido(_ route: RutaGTFS) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            tituloSeccion(L.t("Tu recorrido", "Your journey"))
            VStack(spacing: 0) {
                if let itinerary, let transfer = itinerary.transfer {
                    filaTramo(itinerary.route, titulo: L.t("Primer micro", "First bus"),
                              desde: itinerary.board, hasta: itinerary.firstAlight)
                    Divider().padding(.leading, 16)
                    filaTramo(transfer.route, titulo: L.t("Segundo micro", "Second bus"),
                              desde: transfer.board, hasta: transfer.alight)
                } else {
                    identidad(route)
                        .padding(16)
                }
            }
            .background(superficie, in: RoundedRectangle(cornerRadius: 18))
            if itinerary?.transfer != nil {
                Text(L.t("El transbordo ya está preparado. Selecciona el micro en el que estás ahora.",
                         "Your transfer is ready. Select the bus you're on now."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if itinerary == nil {
                Button(L.t("Cambiar de línea", "Change line")) { selected = nil }
                    .frame(minHeight: 44)
            }
        }
    }

    private func identidad(_ route: RutaGTFS) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(route.color).frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(L.t("Línea ", "Line ") + route.lineaConLetra)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(route.empresa)
                .font(.body).fixedSize(horizontal: false, vertical: true)
            Text(route.recorridoLocalizado)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func filaTramo(_ route: RutaGTFS, titulo: String,
                           desde: ParaderoGTFS, hasta: ParaderoGTFS) -> some View {
        let elegido = selected?.id == route.id
        return Button { seleccionar(route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(titulo).font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: elegido ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(elegido ? acento : Color(uiColor: .secondaryLabel))
                        .accessibilityHidden(true)
                }
                identidad(route)
                Text(desde.nombreVisible + " → " + hasta.nombreVisible)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(elegido ? L.t("Seleccionado", "Selected") : L.t("Sin seleccionar", "Not selected"))
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
    }

    private var puntoDeSubida: some View {
        VStack(alignment: .leading, spacing: 12) {
            tituloSeccion(L.t("¿Dónde subiste? (opcional)", "Where did you board? (optional)"))
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    referenciaEnfocada = false
                    showBoardingMap = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map").foregroundStyle(acento).frame(width: 24)
                        Text(boardingPoint == nil
                             ? L.t("Marcar en el mapa", "Mark on the map")
                             : L.t("Ver o cambiar el punto", "View or change point"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).padding(16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("Calle o referencia", "Street or landmark"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextField(L.t("Calle o referencia", "Street or landmark"),
                              text: $boardingPlace, axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                        .focused($referenciaEnfocada)
                        .submitLabel(.done)
                        .onSubmit { referenciaEnfocada = false }
                        .onChange(of: boardingPlace) { _, value in
                            boardingPlace = String(value.prefix(120))
                        }
                }
                .padding(16)
                if boardingPoint != nil {
                    Divider().padding(.leading, 16)
                    Button(role: .destructive) {
                        tareaDireccion?.cancel()
                        boardingPoint = nil
                        boardingPlace = ""
                    } label: {
                        Label(L.t("Quitar punto", "Remove point"), systemImage: "mappin.slash")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(superficie, in: RoundedRectangle(cornerRadius: 18))
            Text(L.t("La referencia de subida es opcional y se guarda solo en tu teléfono.",
                     "Your boarding reference is optional and saved only on your phone."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var ocupacion: some View {
        VStack(alignment: .leading, spacing: 12) {
            tituloSeccion(L.t("¿Qué tan lleno va? (opcional)", "How full is it? (optional)"))
            VStack(spacing: 0) {
                occupancyOption("", title: L.t("Prefiero no indicar", "Skip for now"), icon: "minus.circle")
                ForEach(BusOccupancyState.allCases, id: \.rawValue) { state in
                    Divider().padding(.leading, 56)
                    occupancyOption(state.rawValue, title: state.title,
                                    icon: state == .empty ? "person" : state == .space ? "person.2" : "person.3")
                }
            }
            .background(superficie, in: RoundedRectangle(cornerRadius: 18))
            Text(L.t("Puedes actualizarlo durante el viaje. El reporte vence en 3 minutos y necesita corroboración.",
                     "You can update it during your trip. The report expires in 3 minutes and needs corroboration."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func occupancyOption(_ value: String, title: String, icon: String) -> some View {
        let elegido = occupancy == value
        return Button { occupancy = value; AppHaptics.selection() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                    .foregroundStyle(elegido ? acento : Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: elegido ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(elegido ? acento : Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityLabel(title)
        .accessibilityValue(elegido ? L.t("Seleccionado", "Selected") : L.t("Sin seleccionar", "Not selected"))
        .accessibilityAddTraits(elegido ? [.isSelected] : [])
    }

    @ViewBuilder
    private var estadoContribucion: some View {
        if !coordinator.isPublisherConfigured {
            Text(L.t("Esta instalación aún no tiene habilitada la contribución de viajes. Puedes seguir consultando la ruta en el mapa.",
                     "Trip contributions aren't configured on this installation yet. You can still view your route on the map."))
                .font(.subheadline).foregroundStyle(.secondary)
        } else if !coordinator.isEnabled {
            Text(L.t("Para contribuir con tu viaje, activa esta opción y concede los permisos de ubicación y movimiento.",
                     "To contribute your trip, enable this option and grant location and motion permissions."))
                .font(.subheadline).foregroundStyle(.secondary)
            if locationService.authorizationStatus == .denied {
                Button(L.t("Abrir Ajustes de ubicación", "Open location settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .frame(minHeight: 44)
            }
        }
        if comenzarAlEstarListo, coordinator.isEnabled, !coordinator.isRunning {
            Text(L.aviso(coordinator.statusMessage))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if coordinator.isEnabled, !coordinator.isRunning, let fallo = coordinator.errorCargaRutas {
            VStack(alignment: .leading, spacing: 12) {
                Text(fallo.mensajeUsuario).font(.subheadline).foregroundStyle(.secondary)
                Button(L.t("Reintentar detección", "Retry detection")) {
                    coordinator.setContributionEnabled(true)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var accionPrincipal: some View {
        Button(action: comenzarViaje) {
            Text(coordinator.isEnabled
                 ? L.t("Comenzar a ayudar", "Start helping")
                 : L.t("Activar y continuar", "Enable and continue"))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(coordinator.isPublisherConfigured ? Color.onPrimaryFill : Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(coordinator.isPublisherConfigured ? Color.primaryFill : Color.surfaceContainerHigh,
                            in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.isPublisherConfigured)
        .accessibilityHint(coordinator.isEnabled ? "" : TextoConsentimientoContribucion.pistaAccesibilidad)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(alignment: .top) { Divider() }
    }

    private func tituloSeccion(_ titulo: String) -> some View {
        Text(titulo).font(.headline).accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var catalogo: some View {
        List {
            Section { encabezado.listRowBackground(Color.clear) }
            if loading {
                ProgressView(L.t("Cargando líneas…", "Loading lines…"))
            } else if let errorCargaRutas {
                Text(L.aviso(errorCargaRutas)).foregroundStyle(.secondary)
                Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
                    .frame(minHeight: 44)
            } else if filtered.isEmpty {
                Text(routes.isEmpty
                     ? L.t("El catálogo no contiene líneas.", "The catalog contains no lines.")
                     : L.t("No encontramos esa línea.", "No matching line found."))
            }
            Section(coordinator.latestLocation == nil
                    ? L.t("Elige la línea que tomaste", "Choose your line")
                    : L.t("Líneas cercanas primero", "Nearby lines first")) {
                ForEach(filtered) { route in
                    Button { seleccionar(route) } label: { identidad(route).frame(minHeight: 44) }
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: L.t("Línea o empresa", "Line or operator"))
    }

    @MainActor
    private func cargarCatalogo() async {
        // El itinerario ya contiene las rutas reales: no recargar todo el catálogo para confirmarlas.
        guard itinerary == nil else { return }
        loading = true
        errorCargaRutas = nil
        do {
            let feed = try await TransporteApp.repositorio.cargarRutas(reintentar: revisionCatalogo > 0)
            guard !Task.isCancelled else { return }
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
        } catch {
            guard !Task.isCancelled else { return }
            errorCargaRutas = (error as? FalloCargaGTFS)?.mensajeUsuario
                ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
        }
        loading = false
    }
}


/// La cámara se acerca al usuario al abrir; solo una selección explícita cambia el pin.
private struct BoardingPointMap: View {
    let route: RutaGTFS
    let locationService: LocationServiceProtocol
    let onConfirm: (BoardingPoint) -> Void
    private let regionInicial: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var point: BoardingPoint?
    @State private var camera: MapCameraPosition
    @State private var ubicacionActual: CLLocation?
    @State private var solicitudUbicacion = 0
    @State private var revisionCamara = 0
    @State private var revisionPunto = 0
    @State private var revisionCamaraSolicitada = 0
    @State private var revisionPuntoSolicitado = 0
    @State private var buscandoUbicacion = true
    @State private var mensajeUbicacion: String?
    @State private var marcarUbicacionSolicitada = false
    @State private var mostrarAjustesUbicacion = false
    @State private var reanudarUbicacion = false
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
        let lectura = lecturas.max { $0.timestamp < $1.timestamp }
        let center = lectura?.coordinate ?? initialPoint?.coordinate ?? route.shape.first
            ?? TransporteApp.referenciaInicio
        regionInicial = Self.regionCercana(center)
        _ubicacionActual = State(initialValue: lectura)
        // Una lectura reciente centra desde el primer fotograma. Mientras llega
        // el GPS compartido, MapKit también puede mostrar el punto azul.
        _camera = State(initialValue: lectura == nil
            ? .userLocation(followsHeading: false, fallback: .region(regionInicial))
            : .region(regionInicial))
    }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    private var puedeConfirmar: Bool {
        point != nil && !(buscandoUbicacion && marcarUbicacionSolicitada
                         && revisionPunto == revisionPuntoSolicitado)
    }

    private static func regionCercana(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500)
    }

    @MainActor
    private func moverCamara(_ position: MapCameraPosition) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            camera = position
        }
    }

    @MainActor
    private func seleccionar(_ coordinate: CLLocationCoordinate2D) {
        guard let nuevoPunto = BoardingPoint(coordinate: coordinate) else { return }
        revisionPunto &+= 1
        point = nuevoPunto
    }

    @MainActor
    private func solicitarUbicacion(marcarPunto: Bool) {
        revisionCamaraSolicitada = revisionCamara
        revisionPuntoSolicitado = revisionPunto
        marcarUbicacionSolicitada = marcarPunto
        mensajeUbicacion = nil
        mostrarAjustesUbicacion = false
        if let lectura = ubicacionActual, locationService.authorizationStatus.isAuthorized,
           UbicacionPuntual.esValida(lectura, ahora: Date(),
               antiguedadMaxima: Self.antiguedadMaximaUbicacion) {
            // La nueva orden invalida cualquier respuesta puntual anterior.
            solicitudUbicacion &+= 1
            buscandoUbicacion = false
            marcarUbicacionSolicitada = false
            revisionCamara &+= 1
            moverCamara(.region(Self.regionCercana(lectura.coordinate)))
            if marcarPunto { seleccionar(lectura.coordinate) }
            return
        }
        buscandoUbicacion = true
        solicitudUbicacion &+= 1
    }

    @MainActor
    private func actualizarUbicacionActual() async {
        guard buscandoUbicacion, scenePhase != .background else { return }
        let solicitud = solicitudUbicacion
        // Conservar las revisiones originales también si se reanuda la misma
        // búsqueda tras volver de Ajustes o del segundo plano.
        let camaraAlSolicitar = revisionCamaraSolicitada
        let puntoAlSolicitar = revisionPuntoSolicitado
        let marcarPunto = marcarUbicacionSolicitada
        let location = await UbicacionPuntual.obtener(desde: locationService,
            antiguedadMaxima: Self.antiguedadMaximaUbicacion)
        guard !Task.isCancelled, solicitud == solicitudUbicacion else { return }
        buscandoUbicacion = false
        marcarUbicacionSolicitada = false
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
        ubicacionActual = location
        // Un resultado tardío no deshace un arrastre, «Ver recorrido» ni un tap.
        if revisionCamara == camaraAlSolicitar {
            moverCamara(.region(Self.regionCercana(location.coordinate)))
        }
        if marcarPunto, revisionPunto == puntoAlSolicitar {
            seleccionar(location.coordinate)
        }
    }

    @MainActor
    private func verRecorrido() {
        revisionCamara &+= 1
        let coordinates = (route.shape.isEmpty ? route.paraderos.map(\.coordinate) : route.shape)
            .filter { CLLocationCoordinate2DIsValid($0) }
        guard let first = coordinates.first else {
            moverCamara(.region(regionInicial))
            return
        }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let mapPoint = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
        }
        if rect.size.width < 1, rect.size.height < 1 {
            moverCamara(.region(Self.regionCercana(first)))
        } else {
            moverCamara(.rect(rect.insetBy(dx: -max(rect.size.width * 0.12, 100),
                                          dy: -max(rect.size.height * 0.12, 100))))
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                MapReader { proxy in
                    Map(position: $camera) {
                        UserAnnotation()
                        MapPolyline(coordinates: route.shape).stroke(route.color, lineWidth: 4)
                        if let point {
                            Marker(L.t("Aquí subí", "I boarded here"), coordinate: point.coordinate)
                                .tint(acento)
                        }
                    }
                    // Sin límites de distancia: se conserva todo el zoom y los
                    // gestos nativos. Tocar el mapa solo cambia la selección.
                    .onTapGesture { location in
                        if let coordinate = proxy.convert(location, from: .local) {
                            revisionCamara &+= 1
                            seleccionar(coordinate)
                        }
                    }
                    .onMapCameraChange(frequency: .continuous) {
                        if camera.positionedByUser { revisionCamara &+= 1 }
                    }
                    .mapControlVisibility(.hidden)
                    .overlay(alignment: .topTrailing) {
                        controlesMapa.padding(16)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        pieMapa(alturaDisponible: geometry.size.height)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("¿Dónde subiste?", "Where did you board?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task(id: solicitudUbicacion) { await actualizarUbicacionActual() }
            .onReceive(locationService.authorizationPublisher) { estado in
                guard scenePhase != .background, estado.isAuthorized,
                      mostrarAjustesUbicacion, !buscandoUbicacion else { return }
                solicitarUbicacion(marcarPunto: false)
            }
            .onChange(of: scenePhase) { _, fase in
                if fase == .background, buscandoUbicacion {
                    reanudarUbicacion = true
                    buscandoUbicacion = false
                    solicitudUbicacion &+= 1
                } else if fase == .active, reanudarUbicacion {
                    reanudarUbicacion = false
                    buscandoUbicacion = true
                    solicitudUbicacion &+= 1
                } else if fase == .active, mostrarAjustesUbicacion,
                          locationService.authorizationStatus.isAuthorized, !buscandoUbicacion {
                    solicitarUbicacion(marcarPunto: false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .tint(acento)
    }

    private var controlesMapa: some View {
        let layout = verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))
        return layout {
            Button { solicitarUbicacion(marcarPunto: false) } label: {
                Group {
                    if buscandoUbicacion {
                        ProgressView().tint(acento)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.body.weight(.semibold))
                    }
                }
                .foregroundStyle(acento)
                .frame(minWidth: 48, minHeight: 48)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Mi ubicación", "My location"))
            .accessibilityHint(L.t("Centra el mapa sin cambiar el lugar marcado", "Centers the map without changing the marked place"))
            .accessibilityValue(buscandoUbicacion ? L.t("Buscando ubicación", "Finding location") : "")

            Button { verRecorrido() } label: {
                Image(systemName: "map")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(acento)
                    .frame(minWidth: 48, minHeight: 48)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Ver el recorrido", "Show route"))
        }
    }

    private func pieMapa(alturaDisponible: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Punto de subida", "Boarding point"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Text(point == nil
                         ? L.t("Toca el mapa donde subiste o marca tu ubicación actual.",
                               "Tap where you boarded on the map or mark your current location.")
                         : L.t("Punto seleccionado. Toca otro lugar del mapa para cambiarlo.",
                               "Point selected. Tap another place on the map to change it."))
                        .font(.subheadline)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    if buscandoUbicacion {
                        Label(L.t("Buscando tu ubicación…", "Finding your location…"), systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let mensajeUbicacion {
                        Text(L.aviso(mensajeUbicacion))
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        if mostrarAjustesUbicacion {
                            Button(L.t("Abrir Ajustes de ubicación", "Open location settings")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .frame(minHeight: 44)
                        } else {
                            Button(L.t("Reintentar ubicación", "Retry location")) {
                                solicitarUbicacion(marcarPunto: false)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    Button { solicitarUbicacion(marcarPunto: true) } label: {
                        Label(L.t("Marcar mi ubicación", "Mark my location"), systemImage: "mappin.and.ellipse")
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(acento)
                    .accessibilityHint(L.t("Coloca el punto donde estás. Después puedes confirmarlo.",
                                          "Places the point where you are. You can then confirm it."))
                    SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point?.coordinate) {
                        revisionCamara &+= 1
                        seleccionar($0)
                        moverCamara(.region(Self.regionCercana($0)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            // El pie puede desplazarse con texto grande o en horizontal; la
            // confirmación sigue visible y el mapa conserva espacio útil.
            .frame(maxHeight: max(100, alturaDisponible * (dynamicTypeSize.isAccessibilitySize ? 0.45 : 0.32)))

            Button {
                guard puedeConfirmar, let point else { return }
                onConfirm(point)
                dismiss()
            } label: {
                Text(L.t("Usar este punto", "Use this point"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.onPrimaryFill)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!puedeConfirmar)
            .opacity(puedeConfirmar ? 1 : 0.5)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color.appSurface)
        .overlay(alignment: .top) { Divider() }
    }
}
