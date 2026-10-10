//
//  MapaView.swift
//  RutaUTP
//
//  Pantalla principal del mapa.
//  - Mapa (MapKit) con la sede elegida, usuario y buses animados.
//  - Header con botón de menú y título "Mapa".
//  - Panel de búsqueda con TextField funcional y chips de destino.
//  - Al seleccionar destino: mapa hace zoom + traza la ruta con buses animados.
//  - Bottom panel con botón REPORTAR y cards de buses.
//

import SwiftUI
import MapKit

struct MapaView: View {
    @StateObject private var store: ScreenModelStore<MapaViewModel>

    init(locationService: LocationServiceProtocol = LocationService()) {
        _store = StateObject(wrappedValue: ScreenModelStore(
            MapaViewModel(locationService: locationService)
        ))
    }

    var body: some View {
        MapaScreenContent(vm: store.model)
    }
}

private struct MapaScreenContent: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @Bindable var vm: MapaViewModel
    @State private var pantallaVisible = false
    @State private var mostrarDrawer = false
    @State private var showReportarSheet = false
    @State private var showBoardingConfirmation = false
    @State private var mostrarAvisoViaje = false
    @State private var boardingReminderTask: Task<Void, Never>?
    @State private var boardingReminderDate: Date?
    @State private var boardingReminderRoute = 0
    /// Selector de destino en el mapa para el acceso con VoiceOver.
    @State private var showElegirEnMapa = false
    @State private var showDestinosGuardados = false
    /// Panel "Transportes cercanos" colapsado: solo queda el ícono de bus
    /// debajo del botón de mi ubicación.
    @State private var panelColapsado = false
    /// El punto central se confirma al dejar de mover el mapa durante un segundo.
    @State private var modoColocarMarcador = false
    @State private var confirmacionMarcador: Task<Void, Never>?
    /// Punto señalado por el usuario. Es un estado de la PANTALLA, no del
    /// ViewModel: no lo lee nadie más y no debe sobrevivir a la navegación
    /// hacia atrás, donde volvería a aparecer sin que se haya pedido.
    @State private var marcadorUsuario: CLLocationCoordinate2D?
    /// Punto bajo el círculo y cámara visible, sin publicar cada movimiento.
    @State private var centroMapa = CentroMapaVisible()
    @FocusState private var campoEnfocado: Bool

    @State private var cameraPosition: MapCameraPosition = .region(
        MapaViewModel.regionDeReferencia(TransporteApp.referenciaInicio)
    )

    private let tabBarHeight: CGFloat = 64

    /// Distancia a la que se empujan los paneles para retirarlos del mapa.
    ///
    /// Es un valor fijo y holgado, no la altura de la pantalla: sirve para
    /// expulsarlos del todo sea cual sea el dispositivo, y evita depender de
    /// `UIScreen.main` (deprecado, y que en iPad mide la pantalla en vez de la
    /// ventana). 900 pt supera con holgura la altura de cualquier iPhone,
    /// incluso en landscape.
    private let desplazamientoFueraDePantalla: CGFloat = 900

    /// Paneles flotantes retirados del mapa.
    ///
    /// Estas situaciones comparten el mismo gesto visual, y por eso una sola
    /// bandera las gobierna:
    ///  - **Colocar un marcador**: el mapa debe quedar libre para elegir
    ///    el punto central sin taparlo.
    ///  - **Buscar el recorrido**: mientras se resuelve el itinerario, el
    ///    buscador y las líneas se apartan y solo queda la ventana de carga.
    ///  - **Viajar en un micro**: quedan la ficha compacta y los controles del viaje.
    ///
    /// Reutilizar el mecanismo evita tener dos animaciones distintas para el
    /// mismo movimiento; lo único que cambia es la causa.
    private var panelesRetirados: Bool {
        modoColocarMarcador || vm.calculandoItinerario || viajeActivo
    }

    private var mostrandoRuta: Bool { vm.itinerario != nil }
    private var viajeActivo: Bool {
        trackingCoordinator.isEnabled && trackingCoordinator.selectedTripRoute != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── MAPA DE FONDO (iOS 17+ MapKit con MapPolyline) ──
            TransitMapCanvas(
                vm: vm,
                rutaViaje: viajeActivo ? trackingCoordinator.selectedTripRoute : nil,
                cameraPosition: $cameraPosition,
                marcadorUsuario: marcadorUsuario,
                marcadorEsDestinoActual: marcadorEsDestinoActual,
                modoColocarMarcador: modoColocarMarcador,
                campoEnfocado: $campoEnfocado,
                onCameraChange: actualizarCamaraVisible,
                onPlacementPointChange: actualizarPuntoVisible,
                onCameraEnd: {
                    if modoColocarMarcador { programarConfirmacionMarcador() }
                },
                onClearMarker: despejarMarcador
            )
            .accessibilityHidden(mostrarDrawer || (vm.calculandoItinerario && !viajeActivo))

            // ── UI FLOTANTE ──
            VStack(spacing: 0) {
                // Todo lo de ARRIBA (header, buscador y resumen del itinerario) viaja como un solo bloque:
                // así se retira hacia arriba de un tirón y no pieza a pieza.
                VStack(spacing: 0) {
                    if !mostrandoRuta {
                        MapHeaderView(vm: vm, mostrarDrawer: $mostrarDrawer)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Panel de búsqueda. Se aparta en cuanto hay un itinerario
                    // resuelto: a partir de ahí mandan la guía del viaje, el
                    // panel de transportes y los accesos al mapa. El buscador
                    // vuelve al limpiar la ruta (la X de la guía).
                    if vm.itinerario == nil {
                        MapSearchPanel(vm: vm, campoEnfocado: $campoEnfocado,
                                       showDestinosGuardados: $showDestinosGuardados)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if vm.busquedaResultado != nil {
                        RouteSummaryPanel(vm: vm, onConfirmBoarding: {
                            cancelarPreguntaDeViaje()
                            showBoardingConfirmation = true
                        })
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                .offset(y: panelesRetirados ? -desplazamientoFueraDePantalla : 0)
                .opacity(panelesRetirados ? 0 : 1)
                // Sin esto el bloque se sigue dibujando fuera de pantalla y
                // seguiría robando toques al mapa.
                .allowsHitTesting(!panelesRetirados)
                .accessibilityHidden(panelesRetirados)

                Spacer()

                // Todo lo de ABAJO se va por abajo, por el mismo motivo.
                VStack(spacing: 0) {
                    // Accesos originales del mapa: marcador arriba, ubicación debajo.
                    if !mostrandoRuta {
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                botonColocarMarcador
                                botonMiUbicacion
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 8)
                        }
                        .transition(.opacity)
                    }

                    if mostrandoRuta {
                        HStack(alignment: .center) {
                            botonReportar
                            Spacer(minLength: 12)
                            botonMiUbicacion
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 56)
                        .transition(.opacity)
                    } else {
                        NearbyTransportPanel(vm: vm, panelColapsado: $panelColapsado,
                                             reportButton: botonReportar)
                            .padding(.bottom, tabBarHeight + 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .offset(y: panelesRetirados ? desplazamientoFueraDePantalla : 0)
                .opacity(panelesRetirados ? 0 : 1)
                .allowsHitTesting(!panelesRetirados)
                .accessibilityHidden(panelesRetirados)
            }
            .animation(
                reduceMotion ? nil : panelesRetirados
                ? .easeIn(duration: 0.26)
                : .spring(response: 0.42, dampingFraction: 0.86),
                value: panelesRetirados
            )
            // Entrada/salida del buscador según haya o no itinerario resuelto.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: vm.itinerario != nil)
            .accessibilityHidden(mostrarDrawer)

            if viajeActivo {
                MapaViajeOverlay(coordinator: trackingCoordinator,
                                 locationService: vm.sharedLocationService,
                                 destino: vm.busquedaResultado?.titulo,
                                 mostrarAviso: $mostrarAvisoViaje,
                                 mostrarDrawer: $mostrarDrawer,
                                 statusColor: colorEstadoContribucion,
                                 onEndTrip: finalizarVistaDeViaje,
                                 reportButton: botonReportar,
                                 locationButton: botonMiUbicacion)
                    .transition(.opacity)
                    .accessibilityHidden(mostrarDrawer)
            }

            // ── POPUP DETALLE DE BUS ANIMADO ──
            if !viajeActivo {
                MapBusSelectionOverlay(vm: vm, tabBarHeight: tabBarHeight)
                    .zIndex(10)
                    .accessibilityHidden(mostrarDrawer)
            }

            // ── DRAWER OVERLAY ──
            if mostrarDrawer {
                SideDrawer(isOpen: $mostrarDrawer)
                    .environmentObject(router)
                    .transition(.move(edge: .leading))
            }

            // ── OVERLAY DE COLOCACIÓN DEL MARCADOR ──
            // Encima de la UI flotante: el botón de cancelar debe recibir el
            // toque aunque los paneles se estén retirando.
            MarkerPlacementOverlay(modoColocarMarcador: modoColocarMarcador,
                                   tabBarHeight: tabBarHeight, cancelarMarcador: cancelarMarcador)
                .zIndex(20)

            // ── VENTANA DE CARGA DEL ITINERARIO ──
            // Vive fuera del bloque flotante a propósito: ese bloque se retira
            // mientras se busca, y esta tarjeta es lo único que debe quedar.
            ventanaCargaItinerario
                .zIndex(15)

            // La X de la guía devuelve todos los paneles y la navegación.
            if !mostrandoRuta && !viajeActivo {
                BottomNavBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityHidden(mostrarDrawer || modoColocarMarcador || vm.calculandoItinerario)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: mostrandoRuta)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viajeActivo)
        .onAppear {
            pantallaVisible = true
            vm.actualizarActividadVisual(scenePhase == .active && !viajeActivo)
            vm.actualizarSedeTrabajo()
            vm.iniciarGPS()
            vm.refrescarDestinos() // chips: refleja lo guardado en Guardado
            consumirDestinoPendiente()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--colapsar") {
                panelColapsado = true
            }
            #endif
        }
        .onDisappear {
            pantallaVisible = false
            vm.actualizarActividadVisual(false)
            cancelarPreguntaDeViaje()
            confirmacionMarcador?.cancel()
            modoColocarMarcador = false
            vm.detener()
        }
        .onChange(of: scenePhase) { _, phase in
            vm.actualizarActividadVisual(pantallaVisible && phase == .active && !viajeActivo)
            if phase != .active {
                confirmacionMarcador?.cancel()
                modoColocarMarcador = false
                boardingReminderTask?.cancel()
            } else if boardingReminderDate != nil {
                // Si venció mientras la app no estaba activa, dar un momento al volver.
                iniciarEsperaDeViaje(minimumDelay: 3)
            }
        }
        .onChange(of: router.destinoPendiente) { _, _ in
            consumirDestinoPendiente()
        }
        .onChange(of: trackingCoordinator.tripStartedAt, initial: true) { _, _ in
            prepararVistaDeViaje()
        }
        .onChange(of: viajeActivo) { _, active in
            vm.actualizarActividadVisual(pantallaVisible && scenePhase == .active && !active)
            if !active { mostrarAvisoViaje = false }
        }
        .onChange(of: SedeTrabajoStore.shared.sede?.id) { _, _ in
            vm.actualizarSedeTrabajo()
        }
        .onChange(of: SedeTrabajoStore.shared.utpComoReferencia) { _, _ in
            vm.actualizarSedeTrabajo()
        }
        .onChange(of: vm.itinerarioFocusTick) { _, _ in
            guard !viajeActivo else { return }
            guard let polyline = vm.routePolyline else { return }
            programarPreguntaDeViaje(en: 30)
            // Acercar el inicio del viaje; el usuario conserva el zoom y arrastre manual.
            let rect = polyline.boundingMapRect
            withAnimation(.easeInOut(duration: 0.4)) {
                panelColapsado = true
                if let origin = vm.userRealCoordinate {
                    cameraPosition = .region(MapaViewModel.regionDePersona(origin, duranteViaje: true))
                } else {
                    cameraPosition = .rect(rect.insetBy(dx: -max(rect.width * 0.25, 1000),
                                                       dy: -max(rect.height * 0.65, 1800)))
                }
            }
        }
        .onChange(of: vm.destinoFocusTick) { _, _ in
            cancelarPreguntaDeViaje()
            guard !viajeActivo else { return }
            if !marcadorEsDestinoActual { marcadorUsuario = nil }
            withAnimation(.easeInOut(duration: 0.3)) { cameraPosition = .region(vm.region) }
        }
        .onChange(of: vm.busquedaResultado?.titulo) { _, _ in
            if !marcadorEsDestinoActual { marcadorUsuario = nil }
            if vm.busquedaResultado == nil { cancelarPreguntaDeViaje() }
        }
        .onChange(of: vm.calculandoItinerario) { _, calculating in
            if calculating { cancelarPreguntaDeViaje() }
        }
        .onChange(of: vm.region.center.latitude) { _, _ in
            guard !viajeActivo else { return }
            withAnimation {
                cameraPosition = .region(vm.region)
            }
        }
        .onChange(of: vm.region.center.longitude) { _, _ in
            guard !viajeActivo else { return }
            withAnimation {
                cameraPosition = .region(vm.region)
            }
        }
        .onChange(of: vm.recentrarToken) { _, _ in
            // Recentrado explícito (botón flecha): siempre mueve la cámara,
            // sin depender de que `region` cambie de valor.
            withAnimation(.spring(response: 0.5)) {
                cameraPosition = .region(vm.region)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: mostrarDrawer)
        .sheet(isPresented: $showBoardingConfirmation) {
            BoardingConfirmationSheet(coordinator: trackingCoordinator,
                                      locationService: vm.sharedLocationService,
                                      suggestedRouteID: vm.itinerario?.route.id,
                                      onRemindLater: { programarPreguntaDeViaje(en: 120) })
        }
        .sheet(isPresented: $showReportarSheet) {
            // La ruta del itinerario calculado entra ya seleccionada: si el
            // usuario acaba de buscar cómo llegar y luego reporta un cambio,
            // es casi siempre de ESA línea, y elegirla otra vez a mano es
            // un paso que soloServía para equivocarse.
            ReportarSheet(initialRouteID: trackingCoordinator.selectedTripRoute?.id ?? vm.itinerario?.route.id,
                          locationService: vm.sharedLocationService)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDestinosGuardados, onDismiss: { vm.refrescarDestinos() }) {
            DestinosGuardadosSheet(onSeleccionar: { lugar in
                guard let coordenada = lugar.coordinate, CLLocationCoordinate2DIsValid(coordenada) else { return }
                showDestinosGuardados = false
                campoEnfocado = false
                marcadorUsuario = nil
                vm.seleccionarLugar(titulo: lugar.nombre, coordenada: coordenada)
            }, onAdministrarParaderos: {
                showDestinosGuardados = false
                router.navigate(to: .seguridad)
            })
        }
        .fullScreenCover(isPresented: $showElegirEnMapa) {
            ElegirDestinoEnMapa(
                coordenadaInicial: vm.busquedaResultado?.coordenada,
                onElegir: { titulo, coordenada in
                    showElegirEnMapa = false
                    vm.seleccionarLugar(titulo: titulo, coordenada: coordenada)
                    vm.textoBusqueda = titulo
                },
                onCerrar: { showElegirEnMapa = false }
            )
        }
    }

    private func prepararVistaDeViaje() {
        guard viajeActivo, let inicio = trackingCoordinator.tripStartedAt else {
            mostrarAvisoViaje = false
            return
        }
        cancelarPreguntaDeViaje()
        confirmacionMarcador?.cancel()
        modoColocarMarcador = false
        campoEnfocado = false
        vm.busSeleccionado = nil
        // No repetir el aviso cuando se vuelve al mapa durante un viaje existente.
        mostrarAvisoViaje = Date().timeIntervalSince(inicio) < 6
        vm.actualizarActividadVisual(false)
    }

    private func finalizarVistaDeViaje() {
        cancelarPreguntaDeViaje()
        mostrarAvisoViaje = false
        marcadorUsuario = nil
        vm.limpiar()
    }

    private func cancelarPreguntaDeViaje() {
        boardingReminderTask?.cancel()
        boardingReminderTask = nil
        boardingReminderDate = nil
        showBoardingConfirmation = false
    }

    private func programarPreguntaDeViaje(en seconds: TimeInterval) {
        cancelarPreguntaDeViaje()
        guard vm.itinerario != nil, trackingCoordinator.selectedTripRoute == nil else { return }
        boardingReminderRoute = vm.itinerarioFocusTick
        boardingReminderDate = Date().addingTimeInterval(seconds)
        iniciarEsperaDeViaje()
    }

    private func iniciarEsperaDeViaje(minimumDelay: TimeInterval = 0) {
        boardingReminderTask?.cancel()
        guard let date = boardingReminderDate else { return }
        let revision = boardingReminderRoute
        let delay = max(minimumDelay, date.timeIntervalSinceNow)
        boardingReminderTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
                while !Task.isCancelled {
                    guard revision == vm.itinerarioFocusTick, vm.itinerario != nil,
                          !vm.calculandoItinerario, trackingCoordinator.selectedTripRoute == nil else {
                        boardingReminderDate = nil
                        return
                    }
                    // Mantener el recordatorio pendiente sin interrumpir otras pantallas.
                    guard scenePhase == .active else { return }
                    if !showReportarSheet && !showElegirEnMapa && !showDestinosGuardados && !mostrarDrawer && !modoColocarMarcador
                        && vm.busSeleccionado == nil && !campoEnfocado {
                        boardingReminderDate = nil
                        showBoardingConfirmation = true
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch { return }
        }
    }

    private var colorEstadoContribucion: Color {
        switch trackingCoordinator.observationPublisherState {
        case .inactive:
            return .secondary
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    // MARK: - Destino pendiente (desde Guardado u otras pantallas)
    private func consumirDestinoPendiente() {
        guard let destino = router.destinoPendiente else { return }
        router.destinoPendiente = nil
        #if DEBUG
        print("[Mapa] consumiendo destino pendiente: \(destino.titulo)")
        #endif
        vm.seleccionarLugar(titulo: destino.titulo, coordenada: destino.coordinate)
        vm.textoBusqueda = destino.titulo
    }

    // MARK: - Botón Mi Ubicación (centra el mapa en el GPS real)
    private var botonMiUbicacion: some View {
        BotonMiUbicacion(tieneUbicacion: vm.userRealCoordinate != nil) {
            if mostrandoRuta || viajeActivo, let origin = vm.userRealCoordinate {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MapaViewModel.regionDePersona(origin, duranteViaje: true))
                }
            } else {
                vm.recenterOnUser()
            }
        }
    }

    // MARK: - Marcador de referencia

    /// Botón que deja caer un marcador en el mapa, al estilo Uber/InDrive:
    /// se retira la interfaz y el punto se fija automáticamente al detenerse.
    private var botonColocarMarcador: some View {
        Button {
            campoEnfocado = false
            if voiceOverOn {
                showElegirEnMapa = true
                return
            }
            let regionActual = centroMapa.region ?? cameraPosition.region ?? vm.region
            let centro = centroMapa.coordenada ?? regionActual.center
            let cercana = MKCoordinateRegion(center: centro,
                                            latitudinalMeters: 350, longitudinalMeters: 350)
            // Acercar a las calles sin alejar un mapa que ya estuviera más cerca.
            let enfoque = MKCoordinateRegion(center: centro, span: MKCoordinateSpan(
                latitudeDelta: min(regionActual.span.latitudeDelta, cercana.span.latitudeDelta),
                longitudeDelta: min(regionActual.span.longitudeDelta, cercana.span.longitudeDelta)
            ))
            withAnimation(.easeInOut(duration: 0.3)) {
                modoColocarMarcador = true
                cameraPosition = .region(enfoque)
            }
            AppHaptics.impact(.light)
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.onSurface)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(Color.surfaceContainerLow)
                )
                .overlay(
                    Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Colocar un marcador en el mapa",
                                "Drop a marker on the map"))
        .accessibilityHint(voiceOverOn
            ? L.t("Abre el selector de puntos con acciones para mover y confirmar el destino", "Opens the point picker with actions to move and confirm the destination")
            : L.t("Mueve el mapa. El punto se selecciona tras un segundo sin moverlo", "Move the map. The point is selected after one second without movement"))
    }

    private var marcadorEsDestinoActual: Bool {
        guard let marcador = marcadorUsuario, let destino = vm.busquedaResultado else { return false }
        return marcador.latitude == destino.coordenada.latitude && marcador.longitude == destino.coordenada.longitude
    }

    private func actualizarCamaraVisible(_ context: MapCameraUpdateContext) {
        if centroMapa.camara != context.camera, modoColocarMarcador {
            confirmacionMarcador?.cancel()
            confirmacionMarcador = nil
        }
        centroMapa.camara = context.camera
        centroMapa.region = context.region
    }

    private func actualizarPuntoVisible(_ punto: CLLocationCoordinate2D?) {
        let cambio = centroMapa.coordenada?.latitude != punto?.latitude
            || centroMapa.coordenada?.longitude != punto?.longitude
        if cambio, modoColocarMarcador {
            confirmacionMarcador?.cancel()
            confirmacionMarcador = nil
        }
        centroMapa.coordenada = punto
    }

    private func programarConfirmacionMarcador() {
        confirmacionMarcador?.cancel()
        guard let punto = centroMapa.coordenada, CLLocationCoordinate2DIsValid(punto) else { return }
        confirmacionMarcador = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch { return }
            guard !Task.isCancelled, modoColocarMarcador, scenePhase == .active else { return }
            fijarMarcadorEnCentro()
        }
    }

    /// Fija el marcador en la coordenada que queda bajo el círculo visible.
    ///
    /// La conversión viene del mismo espacio donde se dibuja el círculo.
    private func fijarMarcadorEnCentro() {
        confirmacionMarcador?.cancel()
        confirmacionMarcador = nil
        guard modoColocarMarcador else { return }
        guard let centro = centroMapa.coordenada, CLLocationCoordinate2DIsValid(centro) else { return }
        AppHaptics.impact(.medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            marcadorUsuario = centro
            modoColocarMarcador = false
        }
        // Misma entrada que buscador y destinos guardados: cancela la ruta
        // anterior, calcula caminata + micro + caminata y actualiza las líneas.
        vm.seleccionarLugar(titulo: L.t("Punto marcado", "Marked point"), coordenada: centro)
    }

    /// Quita el marcador y devuelve los paneles a su sitio.
    private func despejarMarcador() {
        confirmacionMarcador?.cancel()
        AppHaptics.impact(.light)
        if marcadorEsDestinoActual { vm.limpiar() }
        withAnimation {
            marcadorUsuario = nil
            modoColocarMarcador = false
        }
    }

    /// La carga vive fuera de los paneles que se retiran al buscar una ruta.
    /// Conserva el aviso y su cancelación arriba, y los controles alineados abajo.
    @ViewBuilder
    private var ventanaCargaItinerario: some View {
        if vm.calculandoItinerario && !modoColocarMarcador && !viajeActivo {
            VStack {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.t("Buscando paradero y transporte…",
                             "Finding stops and transit…"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.onSurface)
                    Spacer(minLength: 4)
                    Button {
                        confirmacionMarcador?.cancel()
                        cancelarPreguntaDeViaje()
                        marcadorUsuario = nil
                        vm.limpiar()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.onSurfaceVariant)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Cancelar búsqueda de ruta", "Cancel route search"))
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)

                Spacer()

                HStack {
                    botonReportar
                    Spacer(minLength: 12)
                    botonMiUbicacion
                }
                .frame(height: 44)
                .padding(.horizontal, 20)
                .padding(.bottom, tabBarHeight + 32)
            }
            .transition(.opacity)
        }
    }

    private func cancelarMarcador() {
        confirmacionMarcador?.cancel()
        AppHaptics.impact(.light)
        withAnimation {
            modoColocarMarcador = false
        }
    }

    private var botonReportar: some View {
        Button {
            // Modo Señas: deja ver el videito antes de que el sheet tape el miniplayer.
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "mapa.reportar") { showReportarSheet = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(L.signable("mapa.reportar", "REPORTAR", "REPORT"))
                    .font(.labelCapsMd)
                    .appTracking(AppTracking.wideLabel)
            }
            .foregroundStyle(.onPrimaryFill)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.primaryFill)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .seniable("mapa.reportar", conGesto: false)
    }

}

/// Memoria del punto de selección y cámara, sin publicaciones por fotograma.
/// El aislamiento conserva lectura y escritura en el mismo actor que la UI.
@MainActor
private final class CentroMapaVisible {
    var coordenada: CLLocationCoordinate2D?
    var region: MKCoordinateRegion?
    var camara: MapCamera?
}

// MARK: - Reportar sheet
// ReportarSheet vive en Design/Components/ReportarSheet.swift (compartido
// con Seguridad). Ver ahí el diseño completo.

#Preview {
    MapaView()
        .environmentObject(AppRouter())
        .environmentObject(
            PassiveTrackingCoordinator(locationService: LocationService())
        )
}
