//
//  MapaView.swift
//  RutaUTP
//
//  Pantalla principal del mapa.
//  - Mapa (MapKit) de fondo con marcadores UTP, usuario y buses animados.
//  - Header con botón de menú y título "Mapa".
//  - Panel de búsqueda con TextField funcional y chips de destino.
//  - Al seleccionar destino: mapa hace zoom + aparecen 6 puntos rojos animados.
//  - Bottom panel con botón REPORTAR y cards de buses.
//

import SwiftUI
import MapKit

struct MapaView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var vm = MapaViewModel()
    @State private var mostrarDrawer = false
    @State private var showReportarSheet = false
    @State private var showReportSuccess = false
    /// Panel "Transportes cercanos" colapsado: solo queda el ícono de bus
    /// debajo del botón de mi ubicación.
    @State private var panelColapsado = false
    @FocusState private var campoEnfocado: Bool

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )

    private let tabBarHeight: CGFloat = 64

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
                } else {
                    Annotation(L.t("Mi Ubicación", "My Location"), coordinate: CLLocationCoordinate2D(latitude: -8.1180, longitude: -79.0350)) {
                        PulsingUserMarker()
                    }
                }

                // 3. Trazo de Ruta Real (Polyline MKDirections - como Demo Tracking)
                if let polyline = vm.routePolyline {
                    MapPolyline(polyline)
                        .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                // 4. Marcador del Destino Buscado (ej. UPAO, Casa, Mall Plaza)
                if let res = vm.busquedaResultado, res.titulo != "UTP" {
                    Annotation(res.titulo, coordinate: res.coordenada) {
                        MarcadorDestinoBuscado(titulo: res.titulo)
                    }
                }

                // 5. Marcadores de Buses Animados en Tiempo Real
                ForEach(vm.busesAnimados) { bus in
                    Annotation(L.t("Línea", "Line") + " \(bus.linea)", coordinate: bus.coordinate) {
                        AnimatedBusMarker(
                            linea: bus.linea,
                            color: bus.color,
                            heading: bus.heading
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                vm.busSeleccionado = bus
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onTapGesture {
                campoEnfocado = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.busSeleccionado = nil
                }
            }

            // ── UI FLOTANTE ──
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 0)

                // Panel de búsqueda
                searchPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Info de Ruta Calculada (ETA + Distancia)
                if let eta = vm.etaMinutos, let dist = vm.distanciaKm, let res = vm.busquedaResultado {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.primaryContainer).frame(width: 38, height: 38)
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.onPrimaryContainer)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t("Ruta hacia", "Route to") + " \(res.titulo)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.onSurface)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text("\(eta) MIN")
                                    .font(.labelCapsSm)
                                    .foregroundStyle(Color.onPrimaryContainer)
                                    .appTracking(AppTracking.wideLabel)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primaryContainer))
                                Text("\(dist, specifier: "%.1f") km • \(L.t("Ruta activa", "Active route"))")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                        }
                        Spacer()
                        Button {
                            vm.limpiar()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Botón "Mi Ubicación" GPS: siempre en la misma posición.
                HStack {
                    Spacer()
                    botonMiUbicacion
                        .padding(.trailing, 20)
                        .padding(.bottom, 8)
                }

                // Bottom panel: REPORTAR + cards siempre visibles; solo el
                // encabezado "Transportes cercanos" se desliza al colapsar.
                bottomPanel
                    .padding(.bottom, tabBarHeight + 8)
            }

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

            // ── NAVBAR ──
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
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
        .onDisappear { vm.detenerSimulacionBuses() }
        .onChange(of: router.destinoPendiente) { _ in
            consumirDestinoPendiente()
        }
        .onChange(of: vm.region.center.latitude) { _ in
            withAnimation {
                cameraPosition = .region(vm.region)
            }
        }
        .onChange(of: vm.region.center.longitude) { _ in
            withAnimation {
                cameraPosition = .region(vm.region)
            }
        }
        .onChange(of: vm.recentrarToken) { _ in
            // Recentrado explícito (botón flecha): siempre mueve la cámara,
            // sin depender de que `region` cambie de valor.
            withAnimation(.spring(response: 0.5)) {
                cameraPosition = .region(vm.region)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: mostrarDrawer)
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet()
                .presentationDetents([.medium, .large])
        }
        .alert("Reporte enviado", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tu reporte fue enviado a la comunidad. Gracias por colaborar.")
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
            .accessibilityLabel("Abrir menú")

            Text(L.t("Mapa", "Map"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)

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
                    .onChange(of: vm.textoBusqueda) { nuevo in
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
                .padding(.horizontal, 2)
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
        return Button {
            campoEnfocado = false
            vm.seleccionar(destino: destino)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: destino.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(destino.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(activo ? Color.onSecondaryContainer : Color.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(activo ? Color.secondaryContainer : Color.surfaceContainerHighest)
            )
        }
        .buttonStyle(.plain)
        .seniable(destino.claveSenia)
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
        Button {
            AppHaptics.impact(.light)
            vm.recenterOnUser()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(vm.userRealCoordinate != nil ? Color.appPrimary : Color.onSurfaceVariant)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.surfaceContainerLowest))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressableCapsuleStyle())
        .accessibilityLabel("Centrar en mi ubicación")
    }

    // MARK: - Bottom panel
    // CORREGIDO V3: frame explicito de 168pt para que las cards no se corten
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Button {
                    showReportarSheet = true
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
                .seniable("mapa.reportar")

                Spacer()

                // Ícono de bus: fijo en su lugar (nivel REPORTAR). Solo los
                // textos se deslizan a la derecha al colapsar.
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
                .accessibilityLabel(panelColapsado ? "Mostrar transportes cercanos" : "Ocultar transportes cercanos")

                if !panelColapsado {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.signable("mapa.cercanos", "Transportes cercanos", "Nearby transport"))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.onSurface)
                            .seniable("mapa.cercanos")
                        Text(vm.busesAnimados.isEmpty
                             ? L.t("Buscando líneas cerca del campus…", "Finding lines near campus…")
                             : String(format: L.t("%d líneas operando ahora", "%d lines running now"), vm.busesAnimados.count))
                            .font(.system(size: 11))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 20)

            // Cards de buses con altura suficiente (rutas reales del feed GTFS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if vm.busesAnimados.isEmpty {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.surfaceContainerLow)
                                .frame(width: 180, height: 100)
                                .overlay(
                                    ProgressView()
                                        .tint(.onSurfaceVariant)
                                )
                        }
                    } else {
                        ForEach(vm.busesAnimados) { bus in
                            BusCard(
                                linea: "LÍNEA \(bus.linea)",
                                empresa: bus.empresa,
                                minutos: "\(bus.minutosLlegada) MIN",
                                tipo: bus.tipo,
                                placa: bus.placa,
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
                        Text("\(bus.minutosLlegada) MIN")
                            .font(.labelCapsSm)
                            .foregroundStyle(.white)
                            .appTracking(AppTracking.wideLabel)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(bus.color))
                    }
                    Text("\(bus.empresa) • \(bus.tipo) (\(bus.placa))")
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

            Button(action: onVerRuta) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ver Ruta Completa")
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
    MapaView().environmentObject(AppRouter())
}

