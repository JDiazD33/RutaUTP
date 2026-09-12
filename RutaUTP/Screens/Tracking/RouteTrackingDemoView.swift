// Tracking Demo: tema persistido, transporte GTFS y tramos a pie diferenciados.
// El usuario puede buscar un destino y escoger un radio de 200, 500 u 800 metros.
// Los comercios son datos demo, distribuidos según el área visible del mapa.

import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct RouteTrackingDemoView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm: RouteTrackingViewModel
    @Environment(\.dismiss) private var dismiss

    // Las anotaciones cambian durante la simulación: nunca usar encuadre automático.
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: GTFSRepository.coordenadaUTP,
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)))
    @State private var seguir: Bool = true
    @State private var ultimoCentroCamara: CLLocationCoordinate2D?
    @State private var rumboCamara: Double?
    @State private var ultimaActualizacionCamara: Date = .distantPast
    /// Chip tocado; nil = el primero del selector (UTP).
    @State private var destinoElegido: RouteTrackingViewModel.DestinoDemo?

    /// Tema elegido en Ajustes. La pantalla de tracking está estilizada en
    /// oscuro (navegación), pero la card de negocio es contenido flotante y
    /// debe seguir el tema del usuario como el resto del app.
    @AppStorage("isDarkMode") private var isDarkMode = false

    // ── Negocios en ruta (fase 1) ──
    /// Burbujas visibles: los 4 negocios más cercanos a la posición actual,
    /// refrescados cada ~120 m para que "vayan apareciendo" en el micro.
    @State private var negociosCerca: [Negocio] = []
    @State private var negocioSeleccionado: Negocio?
    @State private var ultimoRefreshNegocios: CLLocationCoordinate2D?

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
    @State private var businessMapCenter: CLLocationCoordinate2D?
    @State private var businessMapRadius: Double = 1800
    @State private var businessViewportRevision = 0

    init(locationService: LocationServiceProtocol = LocationService()) {
        _vm = StateObject(wrappedValue: RouteTrackingViewModel(locationService: locationService))
    }

    /// Destino activo: el chip tocado o el primero por defecto.
    private var destinoActual: RouteTrackingViewModel.DestinoDemo {
        destinoElegido ?? vm.destinos[0]
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

            mapa

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
                if let negocio = negocioSeleccionado {
                    NegocioDetailCard(
                        negocio: negocio,
                        ubicacion: vm.posicion,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                negocioSeleccionado = nil
                            }
                        }
                    )
                    .environment(\.colorScheme, isDarkMode ? .dark : .light)
                    .padding(.horizontal, 14)
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
            await vm.requestPermissionAndStart()
        }
        .onDisappear {
            vm.stop()
        }
        .onChange(of: vm.posicionTick) { _, _ in
            refrescarNegocios()
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

    // MARK: - Mapa (iOS 17+)

    private var mapa: some View {
        Map(position: $cameraPosition) {
            // Destinos del demo = chips fijos del Mapa.
            ForEach(vm.destinos) { destino in
                Annotation(destino.label, coordinate: destino.coordinate) {
                    if destino.label == "UTP" {
                        MarcadorUTP()
                    } else {
                        MarcadorDestinoBuscado(titulo: destino.label)
                    }
                }
            }

            // Posición actual (GPS real o simulada por el modo demo) con
            // cono de rumbo estilo navegación.
            if let pos = vm.posicion {
                Annotation(L.t("Mi posición", "My position"), coordinate: pos) {
                    UserNavMarker(heading: vm.rumbo)
                }
            }

            if let plan = vm.itinerary {
                MapPolyline(coordinates: plan.walkToBoard)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                MapPolyline(coordinates: plan.bus)
                    .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: plan.bus)
                    .stroke(colorRuta, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: plan.walkToDestination)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                Annotation(L.t("Sube aquí", "Board here"), coordinate: plan.board.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "1", title: L.t("SUBE", "BOARD"), color: .secondary)
                }
                Annotation(L.t("Baja aquí", "Get off here"), coordinate: plan.alight.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "2", title: L.t("BAJA", "EXIT"), color: .appPrimary)
                }
            } else if let stop = vm.nearestStop {
                Annotation(stop.nombre, coordinate: stop.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "", title: L.t("PARADERO", "STOP"), color: .secondary)
                }
            }
            if destinoActual.id == 999 {
                Annotation(destinoActual.label, coordinate: destinoActual.coordinate) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 30)).foregroundStyle(Color.appPrimary)
                        .background(Circle().fill(Color.appSurface))
                }
            }

            // Vehículos en tiempo real vía provider: tap → popup en vivo.
            ForEach(vm.vehiculos) { vehiculo in
                Annotation(L.t("Línea", "Line") + " \(vehiculo.linea)", coordinate: vehiculo.coordinate) {
                    AnimatedBusMarker(
                        linea: vehiculo.linea,
                        color: colorDeLinea(vehiculo.linea),
                        heading: vehiculo.heading
                    )
                    .scaleEffect(vehiculoSeleccionadoID == vehiculo.id ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7),
                               value: vehiculoSeleccionadoID)
                    .onTapGesture {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            // Toggle: segundo tap sobre el mismo bus cierra.
                            vehiculoSeleccionadoID = (vehiculoSeleccionadoID == vehiculo.id)
                                ? nil : vehiculo.id
                            negocioSeleccionado = nil
                        }
                    }
                }
            }

            // Catálogo demo espaciado según el área visible, también al explorar la ciudad.
            ForEach(negociosCerca) { negocio in
                Annotation(negocio.nombre, coordinate: negocio.coordinate, anchor: .bottom) {
                    NegocioBubbleMarker(
                        negocio: negocio,
                        seleccionado: negocioSeleccionado?.id == negocio.id
                    )
                    .onTapGesture {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            negocioSeleccionado = negocio
                            vehiculoSeleccionadoID = nil
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            let center = context.region.center
            let radius = max(500, min(16000, context.region.span.latitudeDelta * 111_320 * 0.6))
            let moved = businessMapCenter.map {
                NegociosService.distanciaMetros($0, center) >= 120
            } ?? true
            let zoomChanged = abs(radius - businessMapRadius) >= max(50, businessMapRadius * 0.1)
            guard moved || zoomChanged else { return }
            businessMapCenter = center
            businessMapRadius = radius
            businessViewportRevision += 1
        }
        // Publicar anotaciones fuera del callback de MapKit; agrupar movimientos rápidos.
        .task(id: businessViewportRevision) {
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            guard !Task.isCancelled else { return }
            refrescarNegocios(force: true)
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .ignoresSafeArea()
        // SIN .onTapGesture aquí: un gesto de tap sobre el Map entero compite
        // con los taps de las Annotations y las burbujas dejaban de responder.
        // Las cards se cierran con su botón X o tocando otra burbuja.
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
            // Instrucción principal según estado
            HStack(spacing: 12) {
                Image(systemName: iconoEstado)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colorEstado)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(colorEstado.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(instruccion)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.onSurface)
                        .lineLimit(2)
                    Text(subtitulo)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.onSurface.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }

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
                        Text(L.t("Ruta real · Línea \(rutaReal.linea) · \(rutaReal.empresa)",
                                 "Real route · Line \(rutaReal.linea) · \(rutaReal.empresa)"))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(light: "#087C55", dark: "#8affc1"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(light: "#087C55", dark: "#8affc1").opacity(0.10)))
                } else if vm.rutaAproximada {
                    // Aviso cuando la ruta es el trazo directo de respaldo.
                    Label(L.t("Ruta aproximada · sin datos de MapKit",
                              "Approximate route · no MapKit data"),
                          systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.9))
                }

                if let plan = vm.itinerary {
                    itinerarySummary(plan)
                }
                barraProgreso
                statsRow
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
                        .foregroundStyle(isDarkMode ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(light: "#087C55", dark: "#8affc1")))
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

    // MARK: - Progreso + stats del viaje

    private var barraProgreso: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.onSurface.opacity(0.15))
                    Capsule()
                        .fill(colorRuta)
                        .frame(width: max(8, geo.size.width * vm.progreso))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.3), value: vm.progreso)

            HStack {
                Text(L.t("Avance del recorrido", "Trip progress"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.onSurface.opacity(0.5))
                Spacer()
                Text("\(Int(vm.progreso * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colorRuta)
                    .monospacedDigit()
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(icono: "clock.badge.checkmark",
                 valor: horaLlegadaTexto,
                 etiqueta: L.t("Llegada", "Arrival"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "clock.fill",
                 valor: "\(vm.minutosRestantes) min",
                 etiqueta: L.t("Restante", "Remaining"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                 valor: vm.distanciaRestanteTexto,
                 etiqueta: L.t("Por recorrer", "To go"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "record.circle",
                 valor: "\(vm.sesion?.puntosRecorridos.count ?? 0)",
                 etiqueta: L.t("Puntos GPS", "GPS points"))
                .frame(maxWidth: .infinity)
        }
    }

    /// Hora de llegada estimada al ritmo de la ruta calculada.
    private var horaLlegadaTexto: String {
        guard vm.etaTotalSeg != nil else { return "—" }
        let fecha = Date().addingTimeInterval(vm.remainingSeconds)
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: fecha)
    }

    private func stat(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.onSurface.opacity(0.55))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.onSurface.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
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
                    Text(destinoElegido?.id == 999 ? destinoActual.label : L.t("Busca una dirección o lugar", "Search an address or place"))
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
                Text("200 m").tag(200.0)
                Text("500 m").tag(500.0)
                Text("800 m").tag(800.0)
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
                        .foregroundStyle(seleccionado ? (isDarkMode ? Color.black : Color.white) : Color.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(seleccionado ? Color(light: "#087C55", dark: "#8affc1")
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
                        .foregroundStyle(vm.modoDemo ? (isDarkMode ? Color.black : Color.white) : Color.onSurface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(vm.modoDemo ? Color(light: "#087C55", dark: "#8affc1")
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
                        ForEach([1.0, 3.0, 10.0], id: \.self) { factor in
                            let activo = vm.velocidadDemo == factor
                            Button {
                                AppHaptics.selection()
                                vm.velocidadDemo = factor
                            } label: {
                                Text("\(Int(factor))×")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(activo ? (isDarkMode ? Color.black : Color.white) : Color.onSurface.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(activo ? Color(light: "#087C55", dark: "#8affc1") : .clear))
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

    // MARK: - Estado → UI

    private var iconoEstado: String {
        switch vm.estado {
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash.fill"
        case .listo:         return "location.fill"
        case .enRuta:        return vm.journeyLeg == .riding ? "bus.fill" : "figure.walk"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    private var colorEstado: Color {
        switch vm.estado {
        case .esperandoGPS:  return Color.onSurface
        case .sinPermiso:    return .red
        case .listo:         return Color(light: "#087C55", dark: "#8affc1")
        case .enRuta:        return Color.primaryContainer
        case .fueraDeRuta:   return .orange
        case .cercaDestino:  return Color(light: "#946200", dark: "#FFD166")
        case .finalizado:    return Color(light: "#087C55", dark: "#8affc1")
        }
    }

    private var instruccion: String {
        switch vm.estado {
        case .esperandoGPS:
            return L.t("Buscando señal GPS…", "Looking for GPS signal…")
        case .sinPermiso:
            return L.t("Activa la ubicación para navegar", "Enable location to navigate")
        case .listo:
            return L.t("GPS listo · elige un destino", "GPS ready · pick a destination")
        case .enRuta:
            switch vm.journeyLeg {
            case .walkingToBoard: return L.t("Camina al paradero de subida", "Walk to your boarding stop")
            case .riding: return L.t("Toma el micro \(vm.rutaGTFS?.linea ?? "")", "Take bus \(vm.rutaGTFS?.linea ?? "")")
            case .walkingToDestination: return L.t("Baja y camina a tu destino", "Get off and walk to your destination")
            }
        case .fueraDeRuta(let metros):
            return L.t("Te alejaste de la ruta (\(Int(metros)) m)",
                       "You went off route (\(Int(metros)) m)")
        case .cercaDestino:
            return L.t("Prepárate para llegar", "Get ready to arrive")
        case .finalizado:
            return L.t("¡Llegaste a tu destino!", "You arrived at your destination!")
        }
    }

    private var subtitulo: String {
        switch vm.estado {
        case .esperandoGPS:
            return L.t("Esperando el primer fix del GPS", "Waiting for the first GPS fix")
        case .sinPermiso:
            return L.t("Ajustes → Privacidad → Ubicación", "Settings → Privacy → Location")
        case .listo:
            return L.t("Inicia el viaje para probar el tracking", "Start the trip to test tracking")
        case .enRuta:
            guard let plan = vm.itinerary else { return "" }
            switch vm.journeyLeg {
            case .walkingToBoard: return plan.board.nombre
            case .riding: return L.t("Baja en ", "Get off at ") + plan.alight.nombre
            case .walkingToDestination: return vm.destinoSeleccionado?.label ?? ""
            }
        case .fueraDeRuta:
            return L.t("Recalculando automáticamente", "Recalculating automatically")
        case .cercaDestino:
            return L.t("Llegando a \(vm.destinoSeleccionado?.label ?? "…")",
                       "Arriving at \(vm.destinoSeleccionado?.label ?? "…")")
        case .finalizado:
            return vm.destinoSeleccionado?.label ?? L.t("Destino", "Destination")
        }
    }

    // MARK: Helpers

    // MARK: Negocios en ruta

    /// Al mover el mapa selecciona negocios espaciados según el zoom.
    /// En seguimiento, las actualizaciones de cámara mantienen el área al día.
    private func refrescarNegocios(force: Bool = false) {
        let pos = businessMapCenter ?? vm.posicion ?? GTFSRepository.coordenadaUTP
        if !force, let ultimo = ultimoRefreshNegocios,
           NegociosService.distanciaMetros(ultimo, pos) < 120 { return }
        ultimoRefreshNegocios = pos
        let nuevos = NegociosService.shared.distribuidos(cercaDe: pos, radioMetros: businessMapRadius, limite: 14)
        if nuevos.map(\.id) != negociosCerca.map(\.id) {
            negociosCerca = nuevos
        }
        // El negocio abierto se mantiene aunque salga del top cercano: el
        // usuario ya mostró interés; se cierra solo con el botón.
    }

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

    private func itinerarySummary(_ plan: TransitItinerary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("1 · " + plan.board.nombre + " · \(Int(plan.walkToBoardMeters)) m " + L.t("a pie", "walk"),
                  systemImage: "figure.walk")
            Label(L.t("Micro ", "Bus ") + plan.route.linea + " · " + plan.route.precioTexto,
                  systemImage: "bus.fill")
            Label("2 · " + plan.alight.nombre + " · \(Int(plan.walkToDestinationMeters)) m " + L.t("al destino", "to destination"),
                  systemImage: "flag.checkered")
            Text(L.t("··· Caminata     ━ Recorrido del micro", "··· Walk     ━ Bus route"))
                .font(.system(size: 10)).foregroundStyle(Color.onSurfaceVariant)
            if plan.walkingApproximate {
                Text(L.t("Caminata aproximada: sin cobertura peatonal. Distancias estimadas.",
                         "Approximate walk: pedestrian directions unavailable. Estimated distances."))
                    .font(.system(size: 10)).foregroundStyle(Color.appError)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerHigh))
    }

    /// Color estable por línea para los vehículos del provider.
    private func colorDeLinea(_ linea: String) -> Color {
        let paleta: [Color] = [.primaryContainer, .secondary, .tertiaryContainer,
                               .secondaryContainer, .tertiary, .appError]
        let suma = linea.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paleta[suma % paleta.count]
    }
}

#Preview {
    RouteTrackingDemoView()
        .environmentObject(AppRouter())
}
