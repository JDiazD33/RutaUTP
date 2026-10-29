//
//  TripSelectionSheet.swift
//  RutaUTP
//
//  Selector de ruta y paradero para empezar a compartir el viaje.
//
//  Lo usan TripContributionPanel y BoardingConfirmationSheet.
//

import SwiftUI
import CoreLocation
import MapKit

struct TripSelectionSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    let suggestedRouteID: String?
    let itinerary: TransitItinerary?
    private let embeddedInNavigation: Bool
    private let onClose: (() -> Void)?
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
         suggestedRouteID: String? = nil, itinerary: TransitItinerary? = nil,
         embeddedInNavigation: Bool = false, onClose: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.locationService = locationService
        self.suggestedRouteID = suggestedRouteID
        self.itinerary = itinerary
        self.embeddedInNavigation = embeddedInNavigation
        self.onClose = onClose
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
        // Guardar una referencia útil de inmediato, incluso sin red. No dejar
        // la calle del punto anterior mientras se resuelve la nueva dirección.
        boardingPlace = L.t("Punto en el mapa", "Picked spot")
            + String(format: " (%.5f, %.5f)", punto.coordinate.latitude, punto.coordinate.longitude)
        let referenciaAnterior = boardingPlace
        tareaDireccion = Task { @MainActor in
            let nombre = await Geocodificacion.nombreDelLugar(punto.coordinate)
            guard !Task.isCancelled, boardingPoint == punto,
                  boardingPlace == referenciaAnterior,
                  nombre != L.t("Punto en el mapa", "Picked spot") else { return }
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
        cerrar()
    }

    private func cerrar() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                contenido
            } else {
                NavigationStack { contenido }
            }
        }
        .tint(acento)
        .presentationDetents([.large])
    }

    private var contenido: some View {
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
                Button(L.t("Cancelar", "Cancel")) { cerrar() }
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
            // El mapa actualiza el formulario aunque lo cubra por completo.
            if !showBoardingMap { tareaDireccion?.cancel() }
            comenzarAlEstarListo = false
        }
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
