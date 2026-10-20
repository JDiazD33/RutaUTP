import SwiftUI
import MapKit
import Combine

/// Consulta el mismo canal de cambios de ruta que Reportar, sin crear GPS,
/// notificaciones ni viajes. Las referencias se leen del almacén de Guardado.
struct AvisosLineasSeguridad: View {
    let rutas: [RutaGTFS]
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var viaje: PassiveTrackingCoordinator
    @Environment(\.scenePhase) private var fase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var guardado = GuardadoViewModel()
    @StateObject private var servicio = RouteChangesService()
    @State private var visible = false
    @State private var mostrarTodos = false
    @State private var seleccionado: RouteChangeAlert?

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var rutaActiva: DetectionRouteGeometry? {
        viaje.tripStartedAt == nil ? nil : viaje.selectedTripRoute
    }
    private var ids: Set<String> {
        // Una lectura dañada no se interpreta como una lista vacía ni se escribe.
        var resultado = guardado.datosLineasInvalidos ? [] : guardado.idsLineasGuardadas
        if let rutaActiva { resultado.insert(rutaActiva.id) }
        return resultado
    }
    private var avisos: [RouteChangeAlert] {
        guard servicio.ready else { return [] }
        return servicio.alerts.filter { ids.contains($0.routeId) }.sorted {
            let a = $0.routeId == rutaActiva?.id
            let b = $1.routeId == rutaActiva?.id
            if a != b { return a }
            if $0.expiresAt != $1.expiresAt { return $0.expiresAt < $1.expiresAt }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Avisos de tus líneas", "Your line alerts"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("Tus guardadas y tu viaje activo", "Your saved lines and active trip"))
                    .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
            }
            VStack(alignment: .leading, spacing: 0) {
                if guardado.datosLineasInvalidos {
                    estado(L.t("No pudimos leer tus líneas guardadas", "Couldn't read your saved lines"),
                           detalle: L.t("Reintenta la lectura para incluirlas en los avisos.", "Try reading them again to include them in alerts."),
                           icono: "bookmark.slash") {
                        Button(L.t("Reintentar", "Retry")) { guardado.cargarLineas() }
                    }
                    if !ids.isEmpty { Divider().padding(.horizontal, 16) }
                }
                if ids.isEmpty {
                    if !guardado.datosLineasInvalidos {
                        estado(L.t("Empieza con tus líneas", "Start with your lines"),
                               detalle: L.t("Guarda una línea para ver sus obras, cierres y desvíos aquí.", "Save a line to see its roadworks, closures and detours here."),
                               icono: "bus") {
                            Button(L.t("Elegir líneas", "Choose lines")) { router.navigate(to: .guardado) }
                        }
                    }
                } else if !servicio.ready {
                    estado(L.t("Sin información actualizada", "No up-to-date information"),
                           detalle: L.t("No podemos consultar los avisos ahora. Se actualizarán al conectar.", "We can't check alerts now. They'll update when connected."),
                           icono: "wifi.slash") {
                        Button(L.t("Actualizar", "Refresh")) {
                            servicio.stop()
                            actualizarServicio()
                        }
                    }
                } else if avisos.isEmpty {
                    estado(L.t("Sin avisos vigentes", "No current alerts"),
                           detalle: L.t("No hay avisos confirmados para tus líneas ahora.", "No confirmed alerts for your lines right now."),
                           icono: "bell") {
                        EmptyView()
                    }
                } else {
                    let visibles = mostrarTodos ? avisos : Array(avisos.prefix(2))
                    ForEach(visibles) { aviso in
                        if aviso.id != visibles.first?.id { Divider().padding(.horizontal, 16) }
                        fila(aviso)
                    }
                    if avisos.count > 2 {
                        Divider().padding(.horizontal, 16)
                        Button {
                            mostrarTodos.toggle()
                        } label: {
                            Text(mostrarTodos ? L.t("Ver menos", "Show less")
                                 : L.f("Ver todos los avisos ({0})", "View all alerts ({0})", ["\(avisos.count)"]))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if servicio.ready && !avisos.isEmpty {
                Text(L.t("Reportes de la comunidad", "Community reports"))
                    .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                    .padding(.horizontal, 4)
            }
        }
        .tint(acento)
        .onAppear {
            visible = true
            guardado.cargarLineas()
            actualizarServicio()
        }
        .onDisappear {
            visible = false
            servicio.stop()
        }
        .onChange(of: fase) { _, _ in
            if fase == .active { guardado.cargarLineas() }
            actualizarServicio()
        }
        .onChange(of: ids) { _, _ in actualizarServicio() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            guardado.cargarLineas()
        }
        .sheet(item: $seleccionado) { aviso in
            AvisoLineaMapa(inicial: aviso, linea: tituloLinea(aviso.routeId), servicio: servicio)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
    }

    private func actualizarServicio() {
        if visible && fase == .active && !ids.isEmpty { servicio.start() }
        else { servicio.stop() }
    }

    private func tituloLinea(_ id: String) -> String {
        if let ruta = rutas.first(where: { $0.id == id }) { return ruta.lineaConLetra }
        if let activa = rutaActiva, activa.id == id { return activa.lineaConLetra }
        // Conserva el aviso aunque el catálogo falle, sin mostrar ids técnicos.
        return L.t("Línea guardada", "Saved line")
    }

    private func estado<Accion: View>(_ titulo: String, detalle: String, icono: String,
                                     @ViewBuilder accion: () -> Accion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icono).font(.title3).foregroundStyle(acento).accessibilityHidden(true)
            Text(titulo).font(.subheadline.weight(.semibold)).foregroundStyle(Color.onSurface)
            Text(detalle).font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            accion().font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fila(_ aviso: RouteChangeAlert) -> some View {
        Button {
            AppHaptics.impact(.light)
            seleccionado = aviso
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(tituloLinea(aviso.routeId)).font(.subheadline.weight(.semibold)).foregroundStyle(acento)
                if aviso.routeId == rutaActiva?.id {
                    Label(L.t("En tu viaje", "On your trip"), systemImage: "bus.fill")
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                Label(aviso.tituloMotivo, systemImage: aviso.iconoMotivo)
                    .font(.headline).foregroundStyle(Color.onSurface)
                Text(aviso.place).font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Text(aviso.detalleVigencia).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                Label(L.t("Ver en mapa", "View on map"), systemImage: "map")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(acento).padding(.top, 4)
            }
            .multilineTextAlignment(.leading)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension RouteChangeAlert {
    var tituloMotivo: String {
        switch reason {
        case "works": return L.t("Obras en la vía", "Roadworks")
        case "closure": return L.t("Vía cerrada", "Road closed")
        default: return L.t("Desvío de ruta", "Route detour")
        }
    }
    var iconoMotivo: String {
        switch reason {
        case "works": return "hammer"
        case "closure": return "nosign"
        default: return "arrow.triangle.branch"
        }
    }
    var coordenada: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordenada, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
    }
    var detalleVigencia: String {
        L.f("{0} cuentas · hasta {1}", "{0} accounts · until {1}", ["\(confirmations)",
            Date(timeIntervalSince1970: expiresAt).formatted(
                Date.FormatStyle(date: .omitted, time: .shortened).locale(FormatoFecha.localeActivo))])
    }
}

/// El punto afectado se consulta directamente; nunca calcula una ruta hacia
/// un cierre. Si vence o se pierde conexión, el detalle deja de llamarlo vigente.
private struct AvisoLineaMapa: View {
    let inicial: RouteChangeAlert
    let linea: String
    @ObservedObject var servicio: RouteChangesService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var camara: MapCameraPosition

    init(inicial: RouteChangeAlert, linea: String, servicio: RouteChangesService) {
        self.inicial = inicial
        self.linea = linea
        self.servicio = servicio
        _camara = State(initialValue: .region(inicial.region))
    }

    private var aviso: RouteChangeAlert { servicio.alerts.first { $0.id == inicial.id } ?? inicial }
    private var vigente: Bool { servicio.ready && servicio.alerts.contains { $0.id == inicial.id } }
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(linea).font(.subheadline.weight(.semibold)).foregroundStyle(acento)
                    Label(aviso.tituloMotivo, systemImage: aviso.iconoMotivo).font(.title2.weight(.semibold))
                    Text(aviso.place).font(.body).foregroundStyle(Color.onSurfaceVariant)
                    Map(position: $camara) {
                        Marker(aviso.tituloMotivo, coordinate: aviso.coordenada).tint(acento)
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if vigente {
                        Text(aviso.detalleVigencia).font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                    } else {
                        Label(servicio.ready
                              ? L.t("Este aviso ya no está vigente", "This alert is no longer current")
                              : L.t("Sin información actualizada", "No up-to-date information"), systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                    }
                    Text(L.t("Reportes de la comunidad", "Community reports"))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Lugar del aviso", "Alert location"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.t("Cerrar", "Close")) { dismiss() } }
            }
            .onChange(of: aviso) { anterior, nuevo in
                if anterior.lat != nuevo.lat || anterior.lon != nuevo.lon { camara = .region(nuevo.region) }
            }
        }
        .tint(acento)
    }
}
