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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @Bindable var vm: MapaViewModel
    @State private var pantallaVisible = false
    @State private var mostrarDrawer = false
    @State private var showReportarSheet = false
    @State private var showBoardingConfirmation = false
    @State private var boardingReminderTask: Task<Void, Never>?
    @State private var boardingReminderDate: Date?
    @State private var boardingReminderRoute = 0
    /// Selector de destino tocando el mapa (botón del buscador).
    @State private var showElegirEnMapa = false
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
    /// Último centro que comunica MapKit. State conserva la referencia;
    /// su coordenada no es observable ni se usa para dibujar la interfaz.
    @State private var centroMapa = CentroMapaVisible()
    @FocusState private var campoEnfocado: Bool

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: TransporteApp.referenciaInicio,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
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
    /// Dos situaciones comparten el mismo gesto visual, y por eso una sola
    /// bandera las gobierna:
    ///  - **Colocar un marcador**: el mapa debe quedar libre para elegir
    ///    el punto central sin taparlo.
    ///  - **Buscar el recorrido**: mientras se resuelve el itinerario, el
    ///    buscador y las líneas se apartan y solo queda la ventana de carga.
    ///
    /// Reutilizar el mecanismo evita tener dos animaciones distintas para el
    /// mismo movimiento; lo único que cambia es la causa.
    private var panelesRetirados: Bool {
        modoColocarMarcador || vm.calculandoItinerario
    }

    private var mostrandoRuta: Bool { vm.itinerario != nil }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── MAPA DE FONDO (iOS 17+ MapKit con MapPolyline) ──
            TransitMapCanvas(
                vm: vm,
                cameraPosition: $cameraPosition,
                marcadorUsuario: marcadorUsuario,
                marcadorEsDestinoActual: marcadorEsDestinoActual,
                campoEnfocado: $campoEnfocado,
                onCameraChange: { center in
                    centroMapa.coordenada = center
                    if modoColocarMarcador { programarConfirmacionMarcador() }
                },
                onClearMarker: despejarMarcador
            )
            .accessibilityHidden(mostrarDrawer || vm.calculandoItinerario)

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
                                       showElegirEnMapa: $showElegirEnMapa)
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
                    // Antes de elegir ruta se ofrecen ambos accesos al mapa.
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

                    // El inicio del viaje se ofrece al resolver una ruta.
                    // Aquí solo se muestran los controles de un viaje confirmado.
                    if !mostrandoRuta, trackingCoordinator.isEnabled, trackingCoordinator.selectedTripRoute != nil {
                        TripContributionPanel(
                            coordinator: trackingCoordinator,
                            locationService: vm.sharedLocationService,
                            statusMessage: trackingCoordinator.statusMessage,
                            statusColor: colorEstadoContribucion
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    // Bottom panel: REPORTAR + cards siempre visibles; solo el
                    // encabezado "Transportes cercanos" se desliza al colapsar.
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
                panelesRetirados
                ? .easeIn(duration: 0.26)
                : .spring(response: 0.42, dampingFraction: 0.86),
                value: panelesRetirados
            )
            // Entrada/salida del buscador según haya o no itinerario resuelto.
            .animation(.easeInOut(duration: 0.28), value: vm.itinerario != nil)
            .accessibilityHidden(mostrarDrawer)

            // ── POPUP DETALLE DE BUS ANIMADO ──
            MapBusSelectionOverlay(vm: vm, tabBarHeight: tabBarHeight)
                .zIndex(10)
                .accessibilityHidden(mostrarDrawer)

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
            if !mostrandoRuta {
                BottomNavBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityHidden(mostrarDrawer || modoColocarMarcador || vm.calculandoItinerario)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.3), value: mostrandoRuta)
        .onAppear {
            pantallaVisible = true
            vm.actualizarActividadVisual(scenePhase == .active)
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
            vm.actualizarActividadVisual(pantallaVisible && phase == .active)
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
        .onChange(of: SedeTrabajoStore.shared.sede?.id) { _, _ in
            vm.actualizarSedeTrabajo()
        }
        .onChange(of: SedeTrabajoStore.shared.utpComoReferencia) { _, _ in
            vm.actualizarSedeTrabajo()
        }
        .onChange(of: vm.itinerarioFocusTick) { _, _ in
            guard let polyline = vm.routePolyline else { return }
            programarPreguntaDeViaje(en: 30)
            // Acercar el inicio del viaje; el usuario conserva el zoom y arrastre manual.
            let rect = polyline.boundingMapRect
            withAnimation(.easeInOut(duration: 0.4)) {
                panelColapsado = true
                if let origin = vm.userRealCoordinate {
                    cameraPosition = .region(MKCoordinateRegion(center: origin,
                        latitudinalMeters: 1000, longitudinalMeters: 1000))
                } else {
                    cameraPosition = .rect(rect.insetBy(dx: -max(rect.width * 0.25, 1000),
                                                       dy: -max(rect.height * 0.65, 1800)))
                }
            }
        }
        .onChange(of: vm.destinoFocusTick) { _, _ in
            cancelarPreguntaDeViaje()
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
            withAnimation {
                cameraPosition = .region(vm.region)
            }
        }
        .onChange(of: vm.region.center.longitude) { _, _ in
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
            ReportarSheet(initialRouteID: vm.itinerario?.route.id,
                          locationService: vm.sharedLocationService)
                .presentationDetents([.medium, .large])
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
                    if !showReportarSheet && !showElegirEnMapa && !mostrarDrawer && !modoColocarMarcador
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
            if mostrandoRuta, let origin = vm.userRealCoordinate {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(center: origin,
                        latitudinalMeters: 1000, longitudinalMeters: 1000))
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
            withAnimation {
                modoColocarMarcador = true
            }
            programarConfirmacionMarcador()
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

    private func programarConfirmacionMarcador() {
        confirmacionMarcador?.cancel()
        confirmacionMarcador = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch { return }
            guard !Task.isCancelled, modoColocarMarcador, scenePhase == .active else { return }
            fijarMarcadorEnCentro()
        }
    }

    /// Fija el marcador en el centro del mapa.
    ///
    /// Usa el último centro visible cuando termina la espera automática.
    private func fijarMarcadorEnCentro() {
        confirmacionMarcador?.cancel()
        confirmacionMarcador = nil
        guard modoColocarMarcador else { return }
        let centro = centroMapa.coordenada ?? vm.region.center
        guard CLLocationCoordinate2DIsValid(centro) else { return }
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
        if vm.calculandoItinerario && !modoColocarMarcador {
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

/// Memoria del centro visible para callbacks y confirmación, sin publicaciones.
/// El aislamiento conserva lectura y escritura en el mismo actor que la UI.
@MainActor
private final class CentroMapaVisible {
    var coordenada: CLLocationCoordinate2D?
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
