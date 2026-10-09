// Tracking Demo: tema persistido, transporte GTFS y tramos a pie diferenciados.
// El usuario puede buscar un destino y escoger un radio de 200, 500 u 800 metros.
// Los comercios son datos demo, distribuidos según el área visible del mapa.

import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct RouteTrackingDemoView: View {
    @StateObject private var store: ScreenModelStore<RouteTrackingViewModel>

    init(locationService: LocationServiceProtocol) {
        _store = StateObject(wrappedValue: ScreenModelStore(
            RouteTrackingViewModel(locationService: locationService)
        ))
    }

    /// RootView retiene el mismo modelo cuando esta vista deja de existir.
    init(model: RouteTrackingViewModel) {
        _store = StateObject(wrappedValue: ScreenModelStore(model))
    }

    var body: some View {
        TrackingScreenContent(vm: store.model)
    }
}

private struct TrackingScreenContent: View {
    @EnvironmentObject private var router: AppRouter
    @Bindable var vm: RouteTrackingViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pantallaVisible = false
    @Environment(\.dismiss) private var dismiss

    // Las anotaciones cambian durante la simulación: nunca usar encuadre automático.
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: GTFSRepository.coordenadaUTP,
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)))
    @State private var seguir: Bool = true
    @State private var ultimoCentroCamara: CLLocationCoordinate2D?
    @State private var rumboCamara: Double?
    @State private var ultimaActualizacionCamara: Date = .distantPast
    /// Chip tocado; nil conserva el destino del viaje o usa UTP por defecto.
    @State private var destinoElegido: RouteTrackingViewModel.DestinoDemo?

    /// Tema elegido en Ajustes. La pantalla de tracking está estilizada en
    /// oscuro (navegación), pero la card de negocio es contenido flotante y
    /// debe seguir el tema del usuario como el resto del app.
    @AppStorage("isDarkMode") private var isDarkMode = false

    // Los negocios en ruta viven en el ViewModel: son datos y una consulta,
    // no presentación.

    // ── Interacción con vehículos ──
    /// ID del bus tocado en el mapa (la card se alimenta del stream en vivo).
    @State private var vehiculoSeleccionadoID: String?

    /// Confirmación antes de cortar un viaje en curso.
    @State private var confirmarDetener: Bool = false
    @State private var destinoTexto = ""
    @FocusState private var destinationFocused: Bool
    @State private var showDestinationSearch = false
    @State private var destinationSearchError: String?
    @State private var destinationSearchTask: Task<Void, Never>?

    /// Al recrear la pantalla, el destino del viaje sigue siendo el seleccionado.
    private var destinoActual: RouteTrackingViewModel.DestinoDemo {
        destinoElegido ?? vm.destinoSeleccionado ?? vm.destinos[0]
    }

    /// Color de la ruta activa: el oficial de la línea GTFS o el del tema.
    private var colorRuta: Color {
        vm.rutaGTFS?.color ?? Color.primaryContainer
    }

    /// Datos del vehículo tocado, siempre frescos (el stream actualiza 4 Hz).
    private var vehiculoSeleccionado: VehiclePosition? {
        guard let id = vehiculoSeleccionadoID else { return nil }
        return vm.vehiculos.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            TrackingMapCanvas(vm: vm, cameraPosition: $cameraPosition,
                              vehiculoSeleccionadoID: $vehiculoSeleccionadoID,
                              destinoActual: destinoActual)

            VStack(spacing: 0) {
                topBar
                Spacer()

                // Controles flotantes de cámara (seguir / encuadrar ruta).
                HStack {
                    Spacer()
                    controlesMapa
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                // Card del negocio o del vehículo tocado: directamente sobre
                // el panel inferior, sin taparlo nunca. La de negocio sigue el
                // tema elegido en Ajustes (la pantalla fuerza oscuro; esa no).
                if let negocio = vm.negocioSeleccionado {
                    // La tarjeta puede crecer con Dynamic Type. Comparte el
                    // espacio disponible con el panel y permite leerla completa.
                    ScrollView {
                        NegocioDetailCard(
                            negocio: negocio,
                            ubicacion: vm.posicion,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.negocioSeleccionado = nil
                                }
                            }
                        )
                        .environment(\.colorScheme, isDarkMode ? .dark : .light)
                        .padding(.horizontal, 14)
                    }
                    .frame(maxHeight: 360)
                    .scrollBounceBehavior(.basedOnSize)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let vehiculo = vehiculoSeleccionado {
                    VehiclePopupCard(
                        vehiculo: vehiculo,
                        velocidadMs: vm.velocidadesVehiculos[vehiculo.id],
                        distanciaM: vm.posicion.map {
                            PolylineMatching.distanceMeters($0, vehiculo.coordinate)
                        },
                        enVivo: vm.fuenteVehiculos == .real,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vehiculoSeleccionadoID = nil
                            }
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ScrollView(showsIndicators: false) {
                    panelInferior
                }
                .frame(maxHeight: vm.tripInProgress ? 410 : 360)
                .scrollBounceBehavior(.basedOnSize)
            }

            // Resumen de llegada con dim que enfoca la card.
            if vm.estado == .finalizado, let resumen = vm.resumen {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ResumenLlegadaCard(
                        resumen: resumen,
                        destino: vm.destinoSeleccionado?.label ?? L.t("tu destino", "your destination"),
                        onCerrar: { vm.cancelTrip() }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showDestinationSearch, onDismiss: {
            destinationFocused = false
            destinationSearchTask?.cancel()
            destinationSearchTask = nil
        }) {
            destinationSearchSheet
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.actualizarActividadVisual(pantallaVisible && scenePhase == .active)
            await vm.requestPermissionAndStart()
        }
        .onAppear {
            pantallaVisible = true
            vm.actualizarActividadVisual(scenePhase == .active)
        }
        .onDisappear {
            pantallaVisible = false
            vm.suspenderPantalla()
        }
        .onChange(of: scenePhase) { _, phase in
            vm.actualizarActividadVisual(pantallaVisible && phase == .active)
        }
        .onChange(of: vm.posicionTick) { _, _ in
            vm.refrescarNegocios()
            seguirPosicion()
        }
        // Al arrancar el viaje: encuadre de toda la ruta (el usuario decide
        // cuándo pasar a seguimiento con el botón flotante).
        .onChange(of: vm.calculandoRuta) { _, calculating in
            if !calculating && vm.itinerary != nil { encuadrarRuta() }
        }
        .onChange(of: vm.tripInProgress) { _, activo in
            if activo { encuadrarRuta() }
        }
        // Activar el demo implica querer VER el avance: seguimiento automático.
        .onChange(of: vm.modoDemo) { _, activo in
            if activo {
                seguir = true
                if let pos = vm.posicion { moverCamara(a: pos) }
            }
        }
        // Feedback háptico en los cambios de estado clave.
        .onChange(of: vm.estado) { _, nuevo in
            switch nuevo {
            case .fueraDeRuta:  AppHaptics.warning()
            case .cercaDestino: AppHaptics.impact(.medium)
            case .finalizado:   AppHaptics.success()
            default: break
            }
        }
        .confirmationDialog(L.t("¿Finalizar el viaje?", "End the trip?"),
                            isPresented: $confirmarDetener,
                            titleVisibility: .visible) {
            Button(L.t("Sí, finalizar", "Yes, end it"), role: .destructive) {
                vm.cancelTrip()
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Cámara: seguimiento suave con rumbo

    /// Persigue la posición sin pelear con el usuario: solo recentra si se
    /// alejó ≥ 18 m del centro o giró ≥ 30°, con un mínimo de 0.35 s entre
    /// movimientos para no apilar animaciones en el modo demo.
    private func seguirPosicion() {
        guard seguir, let nueva = vm.posicion else { return }

        let movido = ultimoCentroCamara.map { PolylineMatching.distanceMeters($0, nueva) }
            ?? .greatestFiniteMagnitude
        let giro: Double = {
            guard let rumboCamara, vm.rumbo >= 0 else { return 0 }
            let delta = abs(rumboCamara - vm.rumbo).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta)
        }()
        guard movido >= 18 || giro >= 30 else { return }
        guard Date().timeIntervalSince(ultimaActualizacionCamara) >= 0.35 else { return }

        moverCamara(a: nueva)
    }

    /// Recentra la cámara. En viaje: vista 3D (pitch 55) rotando con el
    /// rumbo; en reposo: norte arriba, plano y más abierto.
    private func moverCamara(a coord: CLLocationCoordinate2D) {
        ultimoCentroCamara = coord
        let enViaje = vm.tripInProgress
        let heading = (enViaje && vm.rumbo >= 0) ? vm.rumbo : 0
        rumboCamara = heading
        ultimaActualizacionCamara = Date()
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coord,
                          distance: enViaje ? 550 : 1100,
                          heading: heading,
                          pitch: enViaje ? 55 : 0)
            )
        }
    }

    /// Encuadra toda la ruta calculada (vista general antes de arrancar el
    /// seguimiento). Desactiva `seguir` para no saltar de inmediato a la
    /// cámara de persecución: el botón late invitando al tap.
    private func encuadrarRuta() {
        guard let polyline = vm.routePolyline else { return }
        seguir = false
        var rect = polyline.boundingMapRect
        let margen = max(rect.width, rect.height) * 0.22
        rect = MKMapRect(x: rect.minX - margen, y: rect.minY - margen,
                         width: rect.width + margen * 2, height: rect.height + margen * 2)
        withAnimation(.easeInOut(duration: 0.7)) {
            cameraPosition = .region(MKCoordinateRegion(rect))
        }
    }

    // MARK: - Controles flotantes del mapa

    private var controlesMapa: some View {
        VStack(spacing: 10) {
            if vm.tripInProgress, vm.routePolyline != nil {
                BotonFlotanteMapa(
                    icono: "arrow.up.left.and.down.right.magnifyingglass",
                    etiqueta: L.t("Ver toda la ruta", "See the full route")
                ) {
                    encuadrarRuta()
                }
            }

            BotonFlotanteMapa(
                icono: seguir ? "location.fill" : "location",
                etiqueta: seguir ? L.t("Siguiendo tu ubicación", "Following your location")
                                 : L.t("Centrar en mi ubicación", "Center on my location"),
                destacado: seguir,
                pulsante: vm.tripInProgress && !seguir
            ) {
                seguir = true
                if let pos = vm.posicion { moverCamara(a: pos) }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                vm.stop()
                router.navigate(to: .mapaPrincipal)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.onSurface.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar demo", "Close demo"))

            VStack(alignment: .leading, spacing: 2) {
                Text("TRACKING DEMO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onSurface.opacity(0.6))
                    .appTracking(AppTracking.wideLabel)
                Text(L.t("Tu viaje, paso a paso", "Your journey, step by step"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.onSurface)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isDarkMode.toggle()
            } label: {
                Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.onSurface)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.surfaceContainerLowest))
            }
            .accessibilityLabel(L.t("Cambiar tema claro u oscuro", "Toggle light or dark theme"))
            badgeFuente
            badgePermiso
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color.appBackground.opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    /// Fuente de los vehículos del mapa (VehicleTrackingProviding.source).
    private var badgeFuente: some View {
        let enVivo = vm.fuenteVehiculos == .real
        return Text(enVivo ? L.t("EN VIVO", "LIVE") : "DEMO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(enVivo ? (isDarkMode ? Color.black : Color.white) : Color.onSurface)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(enVivo ? Color(light: "#087C55", dark: "#8affc1") : Color.onSurface.opacity(0.14)))
    }

    private var badgePermiso: some View {
        let status = vm.authStatus
        let (text, color): (String, Color) = {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: return ("GPS ON", Color(light: "#087C55", dark: "#8affc1"))
            case .denied, .restricted:                    return ("GPS OFF", .appError)
            case .notDetermined:                          return (L.t("SIN GPS", "NO GPS"), .gray)
            @unknown default:                             return ("GPS", .gray)
            }
        }()
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(status.isAuthorized ? (isDarkMode ? Color.black : Color.white) : Color.onSurface)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
    }

    // MARK: - Panel inferior

    private var panelInferior: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackingInstructionPanel(vm: vm)

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.onErrorContainer)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.errorContainer))
            }

            // Banner de recálculo (desvío sostenido detectado).
            if vm.recalculando {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.orange)
                        .controlSize(.small)
                    Text(L.t("Recalculando ruta…", "Recalculating route…"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if vm.tripInProgress {
                // Identidad de la ruta: línea real del GTFS o avisos de respaldo.
                if let rutaReal = vm.rutaGTFS {
                    HStack(spacing: 6) {
                        Circle().fill(rutaReal.color).frame(width: 7, height: 7)
                        Text(L.t("Ruta real · ", "Real route · ") + (vm.itinerary?.lineDescription ?? rutaReal.linea))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(light: "#087C55", dark: "#8affc1"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(light: "#087C55", dark: "#8affc1").opacity(0.10)))
                } else if vm.rutaAproximada {
                    // El trazado es el respaldo directo: mismo aviso, con el
                    // motivo cambiado, para no tener dos lenguajes distintos.
                    AvisoRutaAproximada(motivo: .rutaSinDatos)
                }

                if let installed = vm.installedItinerary {
                    itinerarySummary(installed)
                }
                TrackingProgressPanel(vm: vm)
                controlesViaje
            } else {
                if let stop = vm.nearestStop, let meters = vm.nearestStopMeters {
                    Label(L.t("Paradero cercano: ", "Nearest stop: ") + stop.nombre + " · \(Int(meters)) m",
                          systemImage: "bus.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                selectorDestino
                    .disabled(vm.calculandoRuta)
            }

            if vm.estado == .sinPermiso {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(L.t("Abrir Ajustes", "Open Settings"), systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.surfaceContainerLowest.opacity(0.96))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.onSurface.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Selección de destino (chips = chips fijos del Mapa)

    private var selectorDestino: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("DESTINO", "DESTINATION"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.onSurface.opacity(0.5))
                .appTracking(AppTracking.wideLabel)

            Button {
                destinationSearchError = nil
                showDestinationSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(destinoActual.id == 999 ? destinoActual.label : L.t("Busca una dirección o lugar", "Search an address or place"))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.onSurface)
                .padding(12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerHigh))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Buscar destino", "Search destination"))
            Picker(L.t("Caminata máxima en cada extremo", "Maximum walk at each end"), selection: $vm.radioParadero) {
                ForEach(RouteTrackingViewModel.Preferencia.radio.valoresPermitidos, id: \.self) { radio in
                    Text("\(Int(radio)) m").tag(radio)
                }
            }
            .pickerStyle(.segmented)
            Text(L.t("Paraderos a menos de \(Int(vm.radioParadero)) m del origen y destino",
                     "Stops within \(Int(vm.radioParadero)) m of origin and destination"))
                .font(.system(size: 10)).foregroundStyle(Color.onSurfaceVariant)
            HStack(spacing: 8) {
                ForEach(vm.destinos) { destino in
                    let seleccionado = destino.id == destinoActual.id
                    Button {
                        AppHaptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            destinoElegido = destino
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destino.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(destino.label)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(seleccionado ? Color.white : Color.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(seleccionado ? Color.appPrimary
                                                                : Color.onSurface.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                destinationFocused = false
                Task { await vm.iniciar(destino: destinoActual) }
            } label: {
                HStack(spacing: 8) {
                    if vm.calculandoRuta {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                        Text(L.t("Calculando ruta…", "Calculating route…"))
                            .font(.system(size: 15, weight: .heavy))
                    } else {
                        Image(systemName: "play.fill")
                        Text(L.t("Iniciar viaje a \(destinoActual.label)",
                                 "Start trip to \(destinoActual.label)"))
                            .font(.system(size: 15, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vm.posicion == nil ? Color.onSurface.opacity(0.25) : Color.primaryContainer))
            }
            .buttonStyle(.plain)
            .disabled(vm.posicion == nil || vm.calculandoRuta || vm.buscandoDestino)
            .accessibilityHint(L.t("Calcula la ruta real y activa el tracking",
                                   "Calculates the real route and starts tracking"))
        }
    }

    // MARK: - Controles del viaje (demo / velocidad / detener)

    private var controlesViaje: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Modo demo: simula el avance por la ruta (prueba en simulador).
                Button {
                    AppHaptics.impact(.light)
                    vm.modoDemo.toggle()
                } label: {
                    Label(vm.modoDemo ? L.t("Pausar demo", "Pause demo")
                                      : L.t("Simular avance", "Simulate progress"),
                          systemImage: vm.modoDemo ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(vm.modoDemo ? Color.white : Color.onSurface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(vm.modoDemo ? Color.appPrimary
                                                               : Color.onSurface.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Simular avance por la ruta", "Simulate progress along the route"))

                Button {
                    confirmarDetener = true
                } label: {
                    Label(L.t("Detener", "Stop"), systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
            }

            // Velocidad de la simulación (visible solo con el demo corriendo).
            // 1× = ritmo real de la ruta activa; 3× y 10× para no esperar.
            if vm.modoDemo {
                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        ForEach(RouteTrackingViewModel.Preferencia.velocidad.valoresPermitidos, id: \.self) { factor in
                            let activo = vm.velocidadDemo == factor
                            Button {
                                AppHaptics.selection()
                                vm.velocidadDemo = factor
                            } label: {
                                Text("\(Int(factor))×")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activo ? Color.white : Color.onSurface.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(activo ? Color.appPrimary : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(Color.onSurface.opacity(0.10)))
                    .accessibilityLabel(L.t("Velocidad de la simulación", "Simulation speed"))

                    Text(L.t("1× = ritmo real (~\(vm.velocidadSimKmh) km/h)",
                             "1× = real pace (~\(vm.velocidadSimKmh) km/h)"))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.onSurface.opacity(0.45))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Helpers

    // MARK: Negocios en ruta

    /// Al mover el mapa selecciona negocios espaciados según el zoom.
    /// En seguimiento, las actualizaciones de cámara mantienen el área al día.

    /// Hoja independiente: el campo queda arriba y respeta el teclado de iOS.
    private var destinationSearchSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.onSurfaceVariant)
                    TextField(L.t("Dirección o lugar en Trujillo", "Address or place in Trujillo"), text: $destinoTexto)
                        .font(.body)
                        .foregroundStyle(Color.onSurface)
                        .tint(Color.appPrimary)
                        .submitLabel(.search)
                        .focused($destinationFocused)
                        .onSubmit { searchDestination() }
                    if !destinoTexto.isEmpty {
                        Button {
                            destinoTexto = ""
                            destinationSearchError = nil
                            destinationFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.onSurfaceVariant)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(L.t("Borrar búsqueda", "Clear search"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .background(Color.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))

                Button(action: searchDestination) {
                    HStack {
                        if vm.buscandoDestino { ProgressView().tint(.white) }
                        Text(vm.buscandoDestino ? L.t("Buscando…", "Searching…") : L.t("Buscar destino", "Search destination"))
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appPrimary)
                .disabled(vm.buscandoDestino || destinoTexto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error = destinationSearchError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color.appError)
                } else {
                    Text(L.t("Escribe el nombre del lugar o su dirección. Al encontrarlo, lo seleccionaremos como destino del viaje.",
                             "Enter a place name or address. Once found, it will be selected as your trip destination."))
                        .font(.callout)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.appBackground)
            .navigationTitle(L.t("Buscar destino", "Search destination"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { showDestinationSearch = false }
                }
            }
            .task { destinationFocused = true }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func searchDestination() {
        guard !vm.buscandoDestino,
              !destinoTexto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        destinationFocused = false
        destinationSearchError = nil
        let query = destinoTexto
        destinationSearchTask?.cancel()
        destinationSearchTask = Task {
            let destination = await vm.buscarDestino(query)
            guard !Task.isCancelled, showDestinationSearch else { return }
            if let destination {
                destinoElegido = destination
                seguir = false
                cameraPosition = .region(MKCoordinateRegion(center: destination.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                showDestinationSearch = false
            } else {
                destinationSearchError = vm.errorMessage
            }
        }
    }

    private func itinerarySummary(_ installed: InstalledTransitItinerary) -> some View {
        let plan = installed.plan
        let metrics = installed.metrics
        return VStack(alignment: .leading, spacing: 8) {
            Label("1 · " + plan.board.nombre + " · \(Int(metrics.walkToBoardMeters)) m " + L.t("a pie", "walk"),
                  systemImage: "figure.walk")
            Label(L.t("Micro ", "Bus ") + plan.route.linea + " · " + plan.route.precioTexto,
                  systemImage: "bus.fill")
            if let transfer = plan.transfer {
                Text(L.t("1 transbordo", "1 transfer")).fontWeight(.bold)
                Label(L.t("Baja en ", "Get off at ") + plan.firstAlight.nombre, systemImage: "mappin.and.ellipse")
                Label(L.t("Camina ", "Walk ") + "\(Int(ceil(metrics.transferWalkMeters))) m · " + transfer.board.nombre,
                      systemImage: "figure.walk")
                Label(L.t("Luego toma ", "Then take ") + transfer.route.linea + " · " + transfer.route.precioTexto,
                      systemImage: "arrow.triangle.swap")
                Text(L.t("El tiempo incluye una espera estimada para el segundo micro.",
                         "Time includes an estimated wait for the second bus."))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            Label((plan.transfer == nil ? "2 · " : "4 · ") + plan.alight.nombre + " · \(Int(metrics.walkToDestinationMeters)) m " + L.t("al destino", "to destination"),
                  systemImage: "flag.checkered")
            Text(L.t("··· Caminata     ━ Recorrido del micro", "··· Walk     ━ Bus route"))
                .font(.system(size: 10)).foregroundStyle(Color.onSurfaceVariant)
            if plan.walkingApproximate {
                AvisoRutaAproximada()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerHigh))
    }


}

#Preview {
    RouteTrackingDemoView(locationService: LocationService())
        .environmentObject(AppRouter())
}
