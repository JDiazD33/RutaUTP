//
//  MapaView.swift
//  RutaUTP
//
//  Pantalla principal del mapa.
//  - Mapa (MapKit) de fondo con marcadores UTP, usuario y buses animados.
//  - Header con botón de menú y título "Mapa".
//  - Panel de búsqueda con TextField funcional y chips de destino.
//  - Al seleccionar destino: mapa hace zoom + traza la ruta con buses animados.
//  - Bottom panel con botón REPORTAR y cards de buses.
//

import SwiftUI
import MapKit

struct MapaView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @StateObject private var vm: MapaViewModel
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
    /// Centro de lo que se está viendo. Lo mantiene MapKit, no se deduce: es
    /// el punto exacto que caerá el marcador.
    @State private var centroMapa: CLLocationCoordinate2D?
    @FocusState private var campoEnfocado: Bool

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
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

    /// El servicio de ubicación se inyecta para compartirlo con el rastreo
    /// pasivo: una sola instancia para toda la app (ver `RutaUTPApp`).
    init(locationService: LocationServiceProtocol = LocationService()) {
        _vm = StateObject(
            wrappedValue: MapaViewModel(locationService: locationService)
        )
    }

    private var resumenItinerario: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if vm.calculandoItinerario {
                    ProgressView().controlSize(.small)
                    Text(L.t("Buscando paradero y transporte…", "Finding stops and transit…"))
                } else {
                    Text(vm.busquedaResultado.map { L.t("Hacia ", "To ") + $0.titulo } ?? "")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { vm.limpiar() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(L.t("Quitar ruta", "Clear route"))
            }
            .font(.system(size: 13, weight: .semibold))
            if let plan = vm.itinerario {
                Label(L.t("Camina ", "Walk ") + "\(Int(ceil(plan.walkToBoardMeters))) m · " + plan.board.nombre,
                      systemImage: "figure.walk")
                Label(L.t("Toma la línea ", "Take line ") + plan.route.linea + " · " + plan.route.precioTexto,
                      systemImage: "bus.fill")
                if let transfer = plan.transfer {
                    Text(L.t("1 transbordo", "1 transfer")).fontWeight(.bold)
                    Label(L.t("Baja en ", "Get off at ") + plan.firstAlight.nombre, systemImage: "mappin.and.ellipse")
                    Label(L.t("Camina ", "Walk ") + "\(Int(ceil(transfer.walkMeters))) m · " + transfer.board.nombre,
                          systemImage: "figure.walk")
                    Label(L.t("Luego toma ", "Then take ") + transfer.route.linea + " · " + transfer.route.precioTexto,
                          systemImage: "arrow.triangle.swap")
                    Text(L.t("El tiempo incluye una espera estimada para el segundo micro.",
                             "Time includes an estimated wait for the second bus."))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Label(L.t("Baja en ", "Get off at ") + plan.alight.nombre,
                      systemImage: "mappin.and.ellipse")
                Text(L.t("Luego camina \(Int(ceil(plan.walkToDestinationMeters))) m hasta tu destino.",
                         "Then walk \(Int(ceil(plan.walkToDestinationMeters))) m to your destination."))
                    .foregroundStyle(Color.onSurfaceVariant)
                Text(L.t("··· A pie   ━ En bus", "··· Walk   ━ Bus") + " · ~\(vm.etaMinutos ?? 0) min")
                    .foregroundStyle(Color.onSurfaceVariant)
                if plan.walkingApproximate {
                    AvisoRutaAproximada()
                }
                if trackingCoordinator.selectedTripRoute == nil {
                    invitacionConfirmarViaje
                }
            } else if let mensaje = vm.mensajeRuta {
                Text(mensaje).foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Acceso voluntario que permanece disponible aunque se cierre el aviso.
    private var invitacionConfirmarViaje: some View {
        Button {
            cancelarPreguntaDeViaje()
            showBoardingConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("¿Ya subiste?", "Already on board?"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Confirma tu línea", "Confirm your line"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(L.t("¿Ya subiste? Confirma tu línea", "Already on board? Confirm your line"))
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── MAPA DE FONDO (iOS 17+ MapKit con MapPolyline) ──
            Map(position: $cameraPosition) {

                // 1. Marcador UTP Trujillo (Av. Nicolás de Piérola 1221)
                Annotation("UTP Trujillo", coordinate: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645)) {
                    MarcadorUTP()
                }

                // 2. Marcador del Usuario (GPS Real o Peatón)
                if let userCoord = vm.userRealCoordinate {
                    Annotation(L.t("Mi Ubicación", "My Location"), coordinate: userCoord) {
                        PulsingUserMarker()
                    }
                }

                // Caminatas punteadas y recorrido del transporte en línea continua.
                if let plan = vm.itinerario {
                    MapPolyline(coordinates: plan.walkToBoard)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                    MapPolyline(coordinates: plan.busDibujo)
                        .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: plan.busDibujo)
                        .stroke(plan.route.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    if let transfer = plan.transfer {
                        MapPolyline(coordinates: transfer.walk)
                            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                        MapPolyline(coordinates: transfer.busDibujo)
                            .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: transfer.busDibujo)
                            .stroke(transfer.route.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        Annotation(plan.firstAlight.nombre, coordinate: plan.firstAlight.coordinate, anchor: .bottom) {
                            TransitStopMarker(number: "2", title: L.t("BAJA", "EXIT"), color: .orange)
                        }
                        Annotation(transfer.board.nombre, coordinate: transfer.board.coordinate, anchor: .bottom) {
                            TransitStopMarker(number: "3", title: L.t("CAMBIA", "CHANGE"), color: transfer.route.color)
                        }
                    }
                    MapPolyline(coordinates: plan.walkToDestination)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                    Annotation(L.t("Sube aquí", "Board here"), coordinate: plan.board.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: "1", title: L.t("SUBE", "BOARD"), color: .secondary)
                    }
                    Annotation(L.t("Baja aquí", "Get off here"), coordinate: plan.alight.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: plan.transfer == nil ? "2" : "4", title: L.t("BAJA", "EXIT"), color: .appPrimary)
                    }
                }

                // 4. Marcador del Destino Buscado (ej. UPAO, Casa, Mall Plaza)
                if let res = vm.busquedaResultado, res.titulo != "UTP", !marcadorEsDestinoActual {
                    Annotation(res.titulo, coordinate: res.coordenada) {
                        MarcadorDestinoBuscado(titulo: res.titulo)
                    }
                }

                // 4b. Marcador dejado por el usuario. Va POR ENCIMA del
                // marcador pulsante de su posición, que es decorativo: si
                // coinciden, el pin es el que informa.
                if let marcador = marcadorUsuario {
                    Annotation(L.t("Mi punto", "My point"),
                               coordinate: marcador,
                               anchor: MarcadorPin.ancla) {
                        MarcadorPin { despejarMarcador() }
                    }
                }

                // 5. Marcadores de Buses Animados en Tiempo Real.
                // Tope de 8 en el mapa por rendimiento; las cards del panel
                // muestran TODAS las líneas que pasan por el punto.
                //
                // El marcador lleva el modelo 3D del bus y la etiqueta de la
                // línea encima. El ancla no es el centro de la vista: con la
                // etiqueta arriba, centrarla dejaría el vehículo dibujado por
                // debajo del punto real.
                ForEach(vm.busesAnimados.prefix(8)) { bus in
                    Annotation(L.t("Línea", "Line") + " \(bus.linea)",
                               coordinate: bus.coordinate,
                               anchor: BusMarker3D.ancla) {
                        Button {
                            campoEnfocado = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                vm.busSeleccionado = bus
                            }
                        } label: {
                            BusMarker3D(
                                linea: bus.linea,
                                color: bus.color,
                                heading: bus.heading,
                                seleccionado: vm.busSeleccionado?.id == bus.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .ignoresSafeArea()
            // Cada movimiento reinicia la espera, incluido el deslizamiento
            // por inercia: nunca confirmar el centro anterior mientras se arrastra.
            .onMapCameraChange(frequency: .continuous) { context in
                centroMapa = context.region.center
                if modoColocarMarcador { programarConfirmacionMarcador() }
            }
            // Las anotaciones gestionan sus toques; la ficha se cierra con su X.
            // Un gesto en el Map padre competía con la selección del micro.

            // ── UI FLOTANTE ──
            VStack(spacing: 0) {
                // Todo lo de ARRIBA (header, buscador y resumen del itinerario) viaja como un solo bloque:
                // así se retira hacia arriba de un tirón y no pieza a pieza.
                VStack(spacing: 0) {
                    if !mostrandoRuta {
                        header
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Panel de búsqueda. Se aparta en cuanto hay un itinerario
                    // resuelto: a partir de ahí mandan la guía del viaje, el
                    // panel de transportes y los accesos al mapa. El buscador
                    // vuelve al limpiar la ruta (la X de la guía).
                    if vm.itinerario == nil {
                        searchPanel
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if vm.busquedaResultado != nil {
                        resumenItinerario
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                .offset(y: panelesRetirados ? -desplazamientoFueraDePantalla : 0)
                .opacity(panelesRetirados ? 0 : 1)
                // Sin esto el bloque se sigue dibujando fuera de pantalla y
                // seguiría robando toques al mapa.
                .allowsHitTesting(!panelesRetirados)

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
                        bottomPanel
                            .padding(.bottom, tabBarHeight + 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .offset(y: panelesRetirados ? desplazamientoFueraDePantalla : 0)
                .opacity(panelesRetirados ? 0 : 1)
                .allowsHitTesting(!panelesRetirados)
            }
            .animation(
                panelesRetirados
                ? .easeIn(duration: 0.26)
                : .spring(response: 0.42, dampingFraction: 0.86),
                value: panelesRetirados
            )
            // Entrada/salida del buscador según haya o no itinerario resuelto.
            .animation(.easeInOut(duration: 0.28), value: vm.itinerario != nil)

            // ── POPUP DETALLE DE BUS ANIMADO ──
            if let bus = vm.busSeleccionado {
                VStack {
                    Spacer()
                    BusDetailPopup(
                        bus: bus,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.busSeleccionado = nil
                            }
                        },
                        onVerRuta: {
                            vm.busSeleccionado = nil
                            // Abre el detalle de ESA línea en Rutas, no la
                            // lista genérica.
                            router.rutaPendiente = bus.rutaId
                            router.navigate(to: .rutas)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, tabBarHeight + 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
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
            overlayColocandoMarcador
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
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.3), value: mostrandoRuta)
        .onAppear {
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
            cancelarPreguntaDeViaje()
            confirmacionMarcador?.cancel()
            modoColocarMarcador = false
            vm.detener()
        }
        .onChange(of: scenePhase) { _, phase in
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

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { mostrarDrawer = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Abrir menú", "Open menu"))

            Text(L.t("Mapa", "Map"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)

            if vm.fuenteFlota == .real {
                // Tener credenciales no demuestra que hayan llegado posiciones.
                // El proveedor elimina los vehículos cuando sus datos caducan.
                let hayDatosRecientes = vm.hayPosicionesRealesRecientes
                Text(hayDatosRecientes
                     ? L.t("DATOS RECIENTES", "RECENT DATA")
                     : L.t("ESPERANDO DATOS", "WAITING FOR DATA"))
                    .font(.system(size: 9, weight: .bold))
                    .appTracking(AppTracking.wideLabel)
                    .foregroundStyle(hayDatosRecientes ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(
                        (hayDatosRecientes ? Color.green : Color.secondary).opacity(0.14)
                    ))
                    .accessibilityLabel(hayDatosRecientes
                        ? L.t("Posiciones recientes de vehículos", "Recent vehicle positions")
                        : L.t("Esperando posiciones de vehículos confirmados", "Waiting for confirmed vehicle positions"))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appSurface.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// Botón al final del buscador: abre el mapa para elegir el destino
    /// con un tap (ícono de flecha tipo Google Maps, gris claro).
    private var botonElegirEnMapa: some View {
        Button {
            AppHaptics.impact(.light)
            campoEnfocado = false
            showElegirEnMapa = true
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(.systemGray2))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color.surfaceContainerHighest)
                )
                .overlay(
                    Circle().stroke(Color.outlineVariant.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Elegir destino en el mapa", "Pick destination on map"))
    }

    // MARK: - Search panel
    private var searchPanel: some View {
        VStack(spacing: 10) {
            // TextField
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.onSurfaceVariant)
                    .font(.system(size: 16))
                TextField(L.t("¿A dónde vas hoy?", "Where to today?"), text: $vm.textoBusqueda)
                    .font(.system(size: 15))
                    .foregroundStyle(.onSurface)
                    .focused($campoEnfocado)
                    .submitLabel(.search)
                    .onSubmit {
                        campoEnfocado = false
                        vm.buscarTexto(vm.textoBusqueda)
                    }
                    .onChange(of: vm.textoBusqueda) { _, nuevo in
                        // Solo se autocompleta mientras el usuario escribe en
                        // el campo. Cuando el texto lo pone el código (al
                        // elegir un chip, un resultado o un lugar guardado) el
                        // campo no está enfocado y no hay que consultar nada.
                        guard campoEnfocado else { return }
                        vm.actualizarTextoBusqueda(nuevo)
                    }
                if vm.buscando {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !vm.textoBusqueda.isEmpty {
                    Button {
                        vm.limpiar()
                        campoEnfocado = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.onSurfaceVariant.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                // Elegir destino tocando el mapa (ícono tipo Google Maps).
                botonElegirEnMapa
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.surfaceContainerLow))

            // Lista de Sugerencias Autocompletadas (ej. UPAO)
            if !vm.sugerenciasBusqueda.isEmpty && campoEnfocado {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.sugerenciasBusqueda.prefix(5), id: \.self) { sug in
                        Button {
                            campoEnfocado = false
                            vm.seleccionarSugerencia(sug)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Color.appPrimary)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sug.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.onSurface)
                                        .lineLimit(1)
                                    if !sug.subtitle.isEmpty {
                                        Text(sug.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if sug != vm.sugerenciasBusqueda.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.surfaceContainerLowest))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                )
            }

            // Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.destinos) { destino in
                        chip(destino)
                    }
                }
                // Respiración para la manita del distintivo: el ScrollView
                // recorta todo lo que sale del contenido y la parte de arriba
                // (y la derecha del último chip) se veía a la mitad.
                .padding(.leading, 2)
                .padding(.trailing, 10)
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
    }

    private func chip(_ destino: DestinoChip) -> some View {
        let activo = vm.destinoSeleccionado?.id == destino.id
        let acento: Color = {
            switch destino.id {
            case 1: return Color(light: "#A80033", dark: "#FF91AD")
            case 2: return Color(light: "#796000", dark: "#F4D35E")
            case 3: return Color(light: "#006779", dark: "#65CCD8")
            default: return Color(light: "#3C5D9C", dark: "#99B8FE")
            }
        }()
        return Button {
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: destino.claveSenia) {
                campoEnfocado = false
                vm.seleccionar(destino: destino)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: destino.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(acento)
                    .frame(width: 20)
                Text(destino.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if activo {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(acento)
                }
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(acento.opacity(activo ? 0.22 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(acento.opacity(activo ? 0.8 : 0.25), lineWidth: 1))
            // Compacto a la vista, con un área cómoda para tocar.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(activo ? L.t("Seleccionado", "Selected") : "")
        .accessibilityHint(L.t("Mostrar este destino en el mapa", "Show this destination on the map"))
        .seniable(destino.claveSenia, conGesto: false)
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
        .accessibilityHint(L.t("Mueve el mapa. El punto se selecciona tras un segundo sin moverlo",
                               "Move the map. The point is selected after one second without movement"))
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
        let centro = centroMapa ?? vm.region.center
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

    /// Lo que se ve mientras se elige el punto: el pin clavado en el centro y
    /// una barra con la instrucción y la salida.
    @ViewBuilder
    private var overlayColocandoMarcador: some View {
        if modoColocarMarcador {
            ZStack {
                // El pin va en el centro geométrico de la pantalla, que es
                // justo lo que se está viendo. Se posiciona con el `ZStack`
                // y no con `UIScreen.main.bounds`: esa API está deprecada y
                // en iPad multitasking mide la pantalla, no la ventana.
                PinEnColocacion()
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(L.t("Mueve el mapa. Al parar 1 s, se calcula la ruta",
                                 "Move the map. Pause for 1 s to calculate the route"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .allowsHitTesting(false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                    Button(action: cancelarMarcador) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                            Text(L.t("Cancelar", "Cancel"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(PressableCapsuleStyle())
                    .accessibilityLabel(L.t("Cancelar el marcador", "Cancel the marker"))
                    // Único punto del overlay que debe recibir toques: el resto
                    // deja pasar el gesto hasta el mapa, que es quien coloca
                    // el marcador.
                    .allowsHitTesting(true)

                    Spacer().frame(height: tabBarHeight + 16)
                }
            }
            .transition(.opacity)
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
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.appPrimary)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .seniable("mapa.reportar", conGesto: false)
    }

    // MARK: - Bottom panel
    // CORREGIDO V3: frame explicito de 168pt para que las cards no se corten
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                botonReportar

                Spacer()

                if !panelColapsado {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.signable("mapa.cercanos", "Transportes cercanos", "Nearby transport"))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.onSurface)
                            .seniable("mapa.cercanos")
                        Text(textoEstadoLineas)
                            .font(.system(size: 11))
                            .foregroundStyle(.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    // Al colapsar el texto se desliza a la derecha, hacia el
                    // ícono de bus (su ancla fija), y se funde detrás de él.
                    // Al expandir aparece ya en su sitio, sin arrastre.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
                }

                // Ícono de bus: fijo en el borde derecho, centrado bajo el
                // botón de Mi Ubicación. Los 4pt extra de padding cuadran
                // centros (36 vs 44pt de ancho) con los 20pt del botón GPS.
                Button {
                    AppHaptics.impact(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panelColapsado.toggle()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primaryContainer)
                            .frame(width: 36, height: 36)
                        Image(systemName: "bus.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.onPrimaryContainer)
                    }
                }
                .buttonStyle(PressableCapsuleStyle())
                .padding(.trailing, 4)
                .accessibilityLabel(panelColapsado
                                    ? L.t("Mostrar transportes cercanos", "Show nearby transport")
                                    : L.t("Ocultar transportes cercanos", "Hide nearby transport"))
            }
            .padding(.horizontal, 20)

            // Cards de buses con altura suficiente (rutas reales del feed GTFS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if vm.busesAnimados.isEmpty && vm.cargandoLineas {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.surfaceContainerLow)
                                .frame(width: 180, height: 100)
                                .overlay(
                                    ProgressView()
                                        .tint(.onSurfaceVariant)
                                )
                        }
                    } else if vm.busesAnimados.isEmpty {
                        // Consulta terminada y sin resultado: el feed no
                        // tiene ninguna línea que pase por el punto.
                        HStack(spacing: 8) {
                            Image(systemName: "bus")
                                .foregroundStyle(.onSurfaceVariant)
                            Text(L.t("Ninguna línea pasa por aquí todavía",
                                     "No lines pass by here yet"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        .padding(14)
                        .frame(width: 256, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.surfaceContainerLow)
                        )
                    } else {
                        ForEach(vm.busesAnimados) { bus in
                            BusCard(
                                linea: L.t("LÍNEA", "LINE") + " \(bus.linea)",
                                empresa: bus.empresa,
                                minutos: bus.etiquetaLlegada,
                                tipo: bus.tipo,
                                placa: bus.ramalTexto,
                                colorLinea: bus.color
                            )
                            .frame(height: 100)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    vm.busSeleccionado = bus
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 112)
        }
        .frame(height: 168)
        // Fondo con degradado para separar el panel de las etiquetas del mapa
        .background(
            LinearGradient(
                colors: [Color.appBackground.opacity(0.0),
                         Color.appBackground.opacity(0.92),
                         Color.appBackground],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }
    /// Subtítulo del panel "Transportes cercanos": refleja las líneas del
    /// feed GTFS que realmente pasan por el punto actual (destino elegido
    /// o campus UTP si no hay destino).
    private var textoEstadoLineas: String {
        if vm.cargandoLineas {
            return L.t("Buscando líneas…", "Finding lines…")
        }
        let cantidad = vm.busesAnimados.count
        if cantidad == 0 {
            return vm.busquedaResultado != nil
                ? L.t("Ninguna línea pasa por aquí", "No lines pass by here")
                : L.t("Buscando líneas cerca del campus…", "Finding lines near campus…")
        }
        if let destino = vm.busquedaResultado {
            return cantidad == 1
                ? String(format: L.t("1 línea pasa por %@", "1 line passes by %@"), destino.titulo)
                : String(format: L.t("%d líneas pasan por %@", "%d lines pass by %@"), cantidad, destino.titulo)
        }
        return cantidad == 1
            ? L.t("1 línea operando ahora", "1 line running now")
            : String(format: L.t("%d líneas operando ahora", "%d lines running now"), cantidad)
    }
}

// MARK: - Bus card
private struct BusCard: View {
    let linea: String
    let empresa: String
    let minutos: String
    let tipo: String
    let placa: String
    let colorLinea: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(linea)
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Text(empresa)
                .font(.headlineSm)
                .foregroundStyle(.onSurface)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(minutos)
                    .font(.labelCapsMd)
                    .foregroundStyle(colorLinea == .appPrimary ? Color.onPrimaryContainer : Color.onSecondaryContainer)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorLinea == .appPrimary ? Color.primaryContainer : Color.secondaryContainer)
                    )
                Text("\(tipo) • \(placa)")
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 256, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.appSurface.opacity(0.55))
                )
        )
        .overlay(
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorLinea)
                    .frame(width: 4, height: 56)
                Spacer()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Elegir destino tocando el mapa
/// Mapa a pantalla completa lanzado desde el buscador: el usuario toca el
/// punto exacto y se convierte en el destino (con dirección real vía
/// geocodificación inversa).
private struct ElegirDestinoEnMapa: View {
    /// Destino ya elegido antes de abrir (si existe): centra el mapa ahí.
    let coordenadaInicial: CLLocationCoordinate2D?
    /// Devuelve (título, coordenada) del punto elegido.
    var onElegir: (String, CLLocationCoordinate2D) -> Void
    var onCerrar: () -> Void

    @State private var coordenada: CLLocationCoordinate2D? = nil
    @State private var resolviendoDireccion = false

    var body: some View {
        ZStack {
            MapaElegirLugar(
                coordenada: coordenada ?? coordenadaInicial,
                onTocar: { coord in
                    AppHaptics.impact(.light)
                    coordenada = coord
                }
            )
            .ignoresSafeArea()

            VStack {
                barraSuperior
                Spacer()
                pie
            }
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(L.t("¿A dónde vas hoy?", "Where to today?"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))

            Spacer()

            Button(action: onCerrar) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(
                        Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Abajo: instrucción mientras no haya pin; confirmar cuando sí.
    @ViewBuilder
    private var pie: some View {
        if coordenada != nil {
            Button(action: confirmar) {
                HStack(spacing: 8) {
                    if resolviendoDireccion {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(resolviendoDireccion
                         ? L.t("Buscando dirección…", "Looking up address…")
                         : L.t("Usar este destino", "Use this destination"))
                        .font(.headlineSm)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appPrimary)
                        .shadow(color: .appPrimary.opacity(0.35), radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(PressableCapsuleStyle())
            .disabled(resolviendoDireccion)
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(L.t("Toca el mapa donde quieres ir", "Tap the map where you want to go"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }

    /// Convierte el punto en el destino: resuelve su dirección real (con
    /// respaldo si el geocoder no responde) y lo entrega al Mapa.
    private func confirmar() {
        guard let coordenada, !resolviendoDireccion else { return }
        resolviendoDireccion = true
        Task { @MainActor in
            let titulo = await Self.nombreDelLugar(coordenada)
            resolviendoDireccion = false
            onElegir(titulo, coordenada)
        }
    }

    /// Delega en el helper compartido: la misma resolución la usan el guardado
    /// de lugares y el punto de subida.
    static func nombreDelLugar(_ coord: CLLocationCoordinate2D) async -> String {
        await Geocodificacion.nombreDelLugar(coord)
    }
}

// MARK: - Popup de Detalle de Bus Animado
private struct BusDetailPopup: View {
    let bus: BusAnimado
    let onClose: () -> Void
    let onVerRuta: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bus.color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(bus.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L.t("LÍNEA", "LINE") + " \(bus.linea)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.onSurface)
                        Text(bus.etiquetaLlegada)
                            .font(.labelCapsSm)
                            .foregroundStyle(.white)
                            .appTracking(AppTracking.wideLabel)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(bus.color))
                    }
                    Text("\(bus.empresa) • \(bus.tipo) (\(bus.ramalTexto))")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if bus.fuente == .real {
                Text(bus.minutosLlegada == nil
                     ? L.t("Llegada no disponible: faltan datos suficientes para estimarla.",
                           "Arrival unavailable: not enough data to estimate it.")
                     : L.t("Llegada aproximada al punto consultado de la ruta. Puede variar por tráfico y paradas.",
                           "Approximate arrival at the queried point on the route. Traffic and stops may change it."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            BusOccupancyPanel(vehicleID: bus.fuente == .real && bus.id.hasPrefix("real-")
                              ? String(bus.id.dropFirst(5)) : nil)
                .id(bus.id)

            Button(action: onVerRuta) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L.t("Ver Ruta Completa", "View full route"))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bus.color)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(bus.color.opacity(0.35), lineWidth: 1)
        )
    }
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
