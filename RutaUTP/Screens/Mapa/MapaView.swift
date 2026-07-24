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
    @FocusState private var campoEnfocado: Bool

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.097955, longitude: -79.038186),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )

    private let tabBarHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── MAPA DE FONDO (iOS 17+ MapKit con MapPolyline) ──
            Map(position: $cameraPosition) {

                // 1. Marcador UTP Trujillo
                Annotation("UTP Trujillo", coordinate: CLLocationCoordinate2D(latitude: -8.097955, longitude: -79.038186)) {
                    MarcadorUTP()
                }

                // 2. Marcador del Usuario (GPS Real)
                if let userCoord = vm.userRealCoordinate {
                    Annotation("Mi Ubicación", coordinate: userCoord) {
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

                // 5. Buses Animados en Tiempo Real
                ForEach(vm.busesAnimados) { bus in
                    Annotation("Línea \(bus.linea)", coordinate: bus.coordinate) {
                        AnimatedBusMarker(linea: bus.linea, color: bus.color, heading: bus.heading)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    vm.busSeleccionado = bus
                                }
                            }
                    }
                }
            }
            .ignoresSafeArea()
            .onTapGesture { campoEnfocado = false }

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
                            Text("Ruta hacia \(res.titulo)")
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
                                Text("\(dist, specifier: "%.1f") km • Ruta activa")
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

                // Botón "Mi Ubicación" GPS
                HStack {
                    Spacer()
                    Button {
                        vm.recenterOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(vm.userRealCoordinate != nil ? Color.appPrimary : Color.onSurfaceVariant)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.surfaceContainerLowest))
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Centrar en mi ubicación")
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
                }

                // Popup de detalle de Bus Seleccionado
                if let bus = vm.busSeleccionado {
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
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom panel
                bottomPanel
                    .padding(.bottom, tabBarHeight + 8)
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
        .onAppear { vm.iniciarGPS() }
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

            Text("Mapa")
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
                TextField("¿A dónde vas hoy?", text: $vm.textoBusqueda)
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
                        Text("REPORTAR")
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

                Spacer()

                HStack(spacing: 6) {
                    Text("Transportes cercanos")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.onSurface.opacity(0.85))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 7, height: 7)
                        Text("En vivo")
                            .font(.labelCapsSm)
                            .foregroundStyle(.appPrimary)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primaryFixed)
                    )
                }
            }
            .padding(.horizontal, 20)

            // Cards de buses con altura suficiente
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    BusCard(
                        linea: "LÍNEA 10", empresa: "El Cortijo",
                        minutos: "4 MIN", tipo: "Micro",
                        placa: "T1B-721", colorLinea: .appPrimary
                    )
                    .frame(height: 100)
                    .onTapGesture { router.navigate(to: .rutas) }
                    BusCard(
                        linea: "LÍNEA 4", empresa: "Salaverry",
                        minutos: "12 MIN", tipo: "Combi",
                        placa: "A6N-450", colorLinea: .secondary
                    )
                    .frame(height: 100)
                    .onTapGesture { router.navigate(to: .rutas) }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 112)
        }
        .frame(height: 168)
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

// MARK: - Reportar sheet
private struct ReportarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reportar incidente")
                    .font(.headlineMd)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TIPO DE REPORTE")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Picker("Tipo", selection: $tipo) {
                        Text("Alerta").tag(TipoReporte.alerta)
                        Text("Tráfico").tag(TipoReporte.trafico)
                        Text("Sugerencia").tag(TipoReporte.sugerencia)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("DESCRIPCIÓN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    TextField("¿Qué sucede?", text: $descripcion, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }

                Spacer()

                Button {
                    showSuccess = true
                } label: {
                    Text("Enviar reporte")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
                .disabled(descripcion.isEmpty)
                .opacity(descripcion.isEmpty ? 0.5 : 1.0)
            }
            .padding(20)
        }
        .alert("Reporte enviado", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Gracias por colaborar con la comunidad.")
        }
    }
}

#Preview {
    MapaView().environmentObject(AppRouter())
}

