import SwiftUI
import MapKit
import Combine

struct RouteChangesSheet: View {
    @ObservedObject var service: RouteChangesService
    var initialRouteID: String? = nil
    /// GPS compartido de la app. Se inyecta en vez de crear uno aquí: una
    /// instancia propia sería un segundo `CLLocationManager` pidiendo precisión
    /// máxima mientras este sheet está abierto.
    var locationService: LocationServiceProtocol
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    @State private var routes: [RutaGTFS] = []
    @State private var cargandoRutas = true
    @State private var errorCargaRutas: String?
    @State private var revisionCatalogo = 0
    @State private var routeID = ""
    @State private var reason = "works"
    @State private var place = ""
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showExpandedMap = false
    /// Posición del usuario mientras este sheet está abierto. Se pide UNA vez
    /// (no un stream GPS): el reporte es un hecho puntual y la pantalla está
    /// arriba, así que una ubicación arrastrada por el movimiento del micro no
    /// ayudaría.
    @StateObject private var ubicacion = RouteChangesLocationModel()
    /// `true` cuando el marcador actual NO es el que se puso automáticamente.
    /// Así "usar mi ubicación" sigue disponible para recolocar el pin.
    @State private var puntoEditadoAMano = false

    private var puntoEnMiUbicacion: CLLocationCoordinate2D? { ubicacion.coordenada }

    private var route: RutaGTFS? { routes.first { $0.id == routeID } }

    /// Veredicto del punto actual frente al recorrido de la ruta elegida.
    private var coherencia: CoherenciaPunto? {
        guard let point, let route else { return nil }
        return VerificadorCoherencia.evaluar(point: point, ruta: route)
    }

    /// Si el punto es aceptable.
    ///
    /// `nil` (no se pudo medir) se trata como válido a propósito: pasa cuando
    /// la línea no trae shape en el feed, y en ese caso bloquear el formulario
    /// dejaría tramos imposibles de reportar sin motivo. El filtro aprieta
    /// cuando SÍ hay geometría para medir, que es el caso normal.
    private var coherenciaValida: Bool { coherencia?.esValido ?? true }

    private var canSend: Bool {
        service.ready && !service.sending && route != nil && point != nil
        && coherenciaValida
        && place.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    /// Coloca el pin donde está el usuario y centra el mapa ahí.
    private func usarMiUbicacion() {
        guard let ruta = route, let aqui = puntoEnMiUbicacion else { return }
        AppHaptics.impact(.light)
        // Solo se marca automáticamente si el sitio es coherente con la línea.
        // Si el usuario está a tres calles del recorrido, un pin automático
        // ahí sería ruido: se deja que marque él a mano sobre el trazado.
        guard let veredicto = VerificadorCoherencia.evaluar(point: aqui, ruta: ruta),
              veredicto.esValido else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            point = aqui
            puntoEditadoAMano = false
            camera = .region(Self.vecindad(alrededorDe: aqui))
        }
    }

    /// Región que encuadra el punto con aire alrededor, para que se vea el
    /// recorrido en lugar de un solo punto ampliado.
    private static func vecindad(alrededorDe punto: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: punto,
                           span: MKCoordinateSpan(latitudeDelta: 0.012,
                                                  longitudeDelta: 0.012))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section {
                        Label(service.ready
                              ? L.t("Reportes compartidos en línea", "Shared reports online")
                              : service.configured
                                ? L.t("Conectando con el servicio de alertas…", "Connecting to route alerts…")
                                : L.t("Alertas sin conexión", "Route alerts offline"),
                              systemImage: service.ready ? "checkmark.circle" : "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(service.ready ? acento : Color(uiColor: .secondaryLabel))
                        if !service.ready {
                            Text(L.t("No podemos consultar ni enviar cambios ahora. Puedes preparar tu reporte aquí.",
                                     "We can't retrieve or send changes now. You can prepare your report here."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        if cargandoRutas {
                            ProgressView(L.t("Cargando rutas…", "Loading routes…"))
                        } else if let errorCargaRutas {
                            Text(L.aviso(errorCargaRutas)).foregroundStyle(.secondary)
                            Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
                        } else if routes.isEmpty {
                            Text(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                                 : L.t("El catálogo no contiene rutas.", "The catalog contains no routes."))
                                .foregroundStyle(.secondary)
                        }
                        Picker(L.t("Línea y ramal", "Line and branch"), selection: Binding(get: { routeID }, set: { value in
                            routeID = value
                            // Al cambiar de línea el punto anterior ya no
                            // significa nada: pertenecía a otro recorrido.
                            // Se suelta para que `colocarAutomaticamente` lo
                            // reponga en la nueva ruta, si procede.
                            point = nil
                            puntoEditadoAMano = false
                            place = ""
                            camera = .automatic
                            colocarAutomaticamenteSiProcede()
                        })) {
                            Text(L.t("Selecciona una ruta", "Select a route")).tag("")
                            ForEach(routes) { route in
                                Text("\(route.linea) · \(route.variante) · \(route.recorridoLocalizado)").tag(route.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        selectorMotivo
                        if let route {
                            HStack {
                                // El rótulo cambia con el estado: si el pin ya
                                // está puesto (suelo o a mano), decir "toca"
                                // sería una instrucción que ya no aplica.
                                Text(point == nil
                                     ? L.t("Toca el lugar afectado en el mapa",
                                           "Tap the affected location on the map")
                                     : L.t("Lugar afectado", "Affected location"))
                                    .font(.subheadline)
                                Spacer()
                                if puntoEnMiUbicacion != nil {
                                    Button {
                                        usarMiUbicacion()
                                    } label: {
                                        Label(L.t("Mi ubicación", "My location"),
                                              systemImage: "location.fill")
                                            .font(.subheadline.weight(.medium))
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityHint(L.t("Coloca el marcador donde estás ahora",
                                                           "Places the marker where you are now"))
                                }
                            }
                            RouteIncidentMap(route: route,
                                             point: $point,
                                             camera: $camera,
                                             onPointChange: { puntoEditadoAMano = true })
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            Button { showExpandedMap = true } label: {
                                Label(L.t("Ampliar mapa", "Expand map"),
                                      systemImage: "arrow.up.left.and.arrow.down.right")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(acento)

                            AvisoCoherencia(evaluacion: coherencia, route: route)

                            TextField(L.t("Calle o referencia (obligatorio)", "Street or landmark (required)"), text: $place, axis: .vertical)
                                .font(.body)
                                .lineLimit(1...3)
                                .textInputAutocapitalization(.sentences)
                                .accessibilityLabel(L.t("Calle o referencia (obligatorio)", "Street or landmark (required)"))
                                .onChange(of: place) { _, value in place = String(value.prefix(120)) }
                            if point == nil {
                                Text(L.t("Falta marcar el punto afectado.", "Mark the affected point to continue."))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if !coherenciaValida {
                                Text(L.t("El punto no pertenece a esta ruta. Ajusta el marcador sobre el recorrido azul o cambia de línea.",
                                         "This point doesn't belong to this route. Move the marker onto the blue path or change the line."))
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                        if let result = service.result {
                            Text(result).font(.callout).accessibilityAddTraits(.updatesFrequently)
                        }
                    } header: {
                        Text(L.t("Reportar o confirmar un cambio", "Report or confirm a change"))
                    } footer: {
                        Text(L.t("Confirma solo si lo has visto. Se necesitan dos cuentas distintas en la misma ruta, motivo y zona. Los reportes vencen a los 15 minutos. El aviso señala la incidencia; el recorrido alterno aún no está verificado.",
                                 "Confirm only what you've seen. Two different accounts must report the same route, reason and area. Reports expire after 15 minutes. The alert identifies the incident; the alternative path hasn't been verified."))
                    }
                    .id("report-form")
                    Section(L.t("Cambios confirmados", "Confirmed changes")) {
                        if service.alerts.isEmpty {
                            Text(service.ready
                                 ? L.t("No hay cambios confirmados recientes.", "No recent confirmed changes.")
                                 : L.t("Sin información actualizada.", "No up-to-date information."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(service.alerts) { alert in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(routeTitle(alert.routeId)).font(.headline)
                                Label(reasonTitle(alert.reason), systemImage: "arrow.triangle.branch")
                                Text(alert.place)
                                Text(L.f("{0} cuentas · vigente hasta ", "{0} accounts · valid until ", ["\(alert.confirmations)"])
                                     + Date(timeIntervalSince1970: alert.expiresAt).formatted(
                                        Date.FormatStyle(date: .omitted, time: .shortened).locale(FormatoFecha.localeActivo)))
                                    .font(.caption).foregroundStyle(.secondary)
                                Button(L.t("Ver lugar y confirmar", "View location and confirm")) {
                                    routeID = alert.routeId
                                    reason = alert.reason
                                    place = alert.place
                                    let coordinate = CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lon)
                                    point = coordinate
                                    camera = .region(MKCoordinateRegion(center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                                    withAnimation { scroll.scrollTo("report-form", anchor: .top) }
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(acento)
                                .frame(minHeight: 44)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                botonReportarCambio
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .overlay(alignment: .top) { Divider() }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle(L.t("Cambios de ruta", "Route changes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showExpandedMap) {
                if let route {
                    ExpandedRouteIncidentMap(route: route, initialPoint: point, initialCamera: camera) { selected, position in
                        point = selected
                        camera = position
                        puntoEditadoAMano = true
                    }
                }
            }
            .task(id: revisionCatalogo) {
                cargandoRutas = true
                errorCargaRutas = nil
                do {
                    let catalogo = try await TransporteApp.repositorio.cargarRutas(reintentar: revisionCatalogo > 0)
                    guard !Task.isCancelled else { return }
                    routes = catalogo
                } catch {
                    guard !Task.isCancelled else { return }
                    errorCargaRutas = (error as? FalloCargaGTFS)?.mensajeUsuario
                        ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
                    cargandoRutas = false
                    return
                }
                cargandoRutas = false
                // La ruta que el usuario tenía seleccionada en el mapa entra
                // YA elegida. Solo se aplica si viene una y sigue existiendo
                // en el feed: un `route_id` de una versión anterior del GTFS
                // dejaría el Picker en un valor que no está en la lista y el
                // formulario en un estado que no se puede enviar.
                if routeID.isEmpty, let inicial = initialRouteID,
                   routes.contains(where: { $0.id == inicial }) {
                    routeID = inicial
                }
                await ubicacion.cargar(desde: locationService)
                guard !Task.isCancelled else { return }
                colocarAutomaticamenteSiProcede()
            }
        }
        .tint(acento)
    }

    @ViewBuilder
    private var selectorMotivo: some View {
        if dynamicTypeSize >= .xxLarge {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.t("¿Qué ocurre?", "What's happening?"))
                    .font(.headline).padding(.bottom, 8)
                ForEach(["works", "closure", "detour"], id: \.self) { value in
                    Button {
                        reason = value
                        AppHaptics.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Text(reasonTitle(value))
                                .foregroundStyle(Color.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark")
                                .foregroundStyle(acento)
                                .opacity(reason == value ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .font(.body)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == value ? .isSelected : [])
                    if value != "detour" { Divider() }
                }
            }
        } else {
            Picker(L.t("¿Qué ocurre?", "What's happening?"), selection: $reason) {
                Text(L.t("Obras", "Roadworks")).tag("works")
                Text(L.t("Cierre", "Closure")).tag("closure")
                Text(L.t("Desvío", "Detour")).tag("detour")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
        }
    }

    private var botonReportarCambio: some View {
        Button {
            guard let point else { return }
            service.send(routeID: routeID, reason: reason, lat: point.latitude, lon: point.longitude,
                         place: place.trimmingCharacters(in: .whitespacesAndNewlines))
        } label: {
            HStack(spacing: 10) {
                if service.sending { ProgressView().accessibilityHidden(true) }
                Text(service.sending ? L.t("Enviando…", "Sending…") : L.t("Reportar cambio", "Report change"))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .font(.headline)
            .foregroundStyle(canSend ? Color.onPrimaryFill : Color.onSurfaceVariant)
            .tint(Color.onSurfaceVariant)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(canSend ? Color.primaryFill : Color.surfaceContainerHigh,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    /// Pone el pin en la posición del usuario cuando esa posición es coherente
    /// con la ruta elegida. Si no lo es, no se marca nada y el mapa queda
    /// esperando a que el usuario elija el punto sobre el recorrido.
    private func colocarAutomaticamenteSiProcede() {
        guard let aqui = ubicacion.puntoAutomatico(
            para: route, puntoActual: point, editadoAMano: puntoEditadoAMano,
            mapaAmpliadoAbierto: showExpandedMap) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            point = aqui
            camera = .region(Self.vecindad(alrededorDe: aqui))
        }
    }

    private func routeTitle(_ id: String) -> String {
        guard let route = routes.first(where: { $0.id == id }) else { return L.t("Ruta ", "Route ") + id }
        return "\(route.linea) · \(route.variante) · \(route.empresa)"
    }
}

private func reasonTitle(_ reason: String) -> String {
    switch reason {
    case "works": return L.t("Obras en la vía", "Roadworks")
    case "closure": return L.t("Vía cerrada", "Road closed")
    default: return L.t("El bus tomó un desvío", "Bus took a detour")
    }
}

// Ambas vistas comparten el trazado y la selección del punto afectado.
private struct RouteIncidentMap: View {
    let route: RutaGTFS
    @Binding var point: CLLocationCoordinate2D?
    @Binding var camera: MapCameraPosition
    /// Se llama cuando el usuario toca el mapa. Permite distinguir "el pin
    /// está donde yo lo puse" de "el pin se puso solo", que es lo que decide
    /// si se recoloca al cambiar de línea.
    var onPointChange: (() -> Void)? = nil

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                MapPolyline(coordinates: route.shape).stroke(route.color, lineWidth: 4)
                if let point {
                    Marker(L.t("Lugar afectado", "Affected location"), coordinate: point)
                        .tint(.orange)
                }
            }
            .onTapGesture { location in
                if let coordinate = proxy.convert(location, from: .local) {
                    point = coordinate
                    onPointChange?()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            LeyendaCoherencia()
                .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point) {
                point = $0
                camera = .region(MKCoordinateRegion(center: $0, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
                onPointChange?()
            }
            .padding(12)
        }
    }
}

/// Texto que explica, sobre el propio mapa, si el punto marcado encaja con la
/// ruta elegida. Sin esto el usuario no tiene forma de saber que el punto está
/// mal hasta que el botón de enviar se queda inactivo.
private struct LeyendaCoherencia: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(L.t("Zona válida de la ruta", "Route's valid area"))
                .font(.caption2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}

/// Aviso bajo el mapa: dice por qué el punto no sirve, o confirma que sí.
private struct AvisoCoherencia: View {
    let evaluacion: CoherenciaPunto?
    let route: RutaGTFS

    var body: some View {
        if let evaluacion {
            switch evaluacion {
            case .coherente:
                etiqueta(L.t("El punto está sobre el recorrido de ",
                             "The point is on ") + rutaCorta(route),
                         icono: "checkmark.circle.fill", tono: .green)
            case .limite(let d):
                etiqueta(L.f("A {0} m del recorrido. Se aceptará, pero revisa que sea el lugar correcto.", "{0} m from the route. It'll be accepted, but check it's the right spot.", ["\(Int(d.rounded()))"]),
                         icono: "exclamationmark.triangle.fill", tono: .orange)
            case .fueraDeRuta(let d):
                etiqueta(L.f("Este punto está a {0} m de la ruta {1}. No corresponde a esta línea: toca el recorrido azul.", "This point is {0} m from route {1}. It doesn't belong to this line: tap the blue path.", ["\(Int(d.rounded()))", "\(rutaCorta(route))"]),
                         icono: "xmark.octagon.fill", tono: .red)
            }
        }
    }

    private func rutaCorta(_ r: RutaGTFS) -> String { "\(r.linea) \(r.variante)" }

    private func etiqueta(_ texto: String, icono: String, tono: Color) -> some View {
        Label(texto, systemImage: icono)
            .font(.footnote)
            .foregroundStyle(tono)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpandedRouteIncidentMap: View {
    let route: RutaGTFS
    let onConfirm: (CLLocationCoordinate2D, MapCameraPosition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition

    init(route: RutaGTFS, initialPoint: CLLocationCoordinate2D?, initialCamera: MapCameraPosition,
         onConfirm: @escaping (CLLocationCoordinate2D, MapCameraPosition) -> Void) {
        self.route = route
        self.onConfirm = onConfirm
        _point = State(initialValue: initialPoint)
        _camera = State(initialValue: initialCamera)
    }

    var body: some View {
        NavigationStack {
            RouteIncidentMap(route: route, point: $point, camera: $camera)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Text(L.t("Amplía con dos dedos y toca el lugar afectado.",
                                 "Pinch to zoom and tap the affected location."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        // Mismo veredicto que el formulario: ampliar el mapa no
                        // puede ser una puerta para saltarse el filtro.
                        AvisoCoherencia(evaluacion: coherencia, route: route)
                        Button {
                            withAnimation { camera = .automatic }
                        } label: {
                            Label(L.t("Ver ruta completa", "Show full route"), systemImage: "map")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
                .navigationTitle(L.t("Línea ", "Line ") + route.linea + " · " + route.variante)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L.t("Cancelar", "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.t("Usar punto", "Use point")) {
                            guard let point else { return }
                            onConfirm(point, camera)
                            dismiss()
                        }
                        .disabled(point == nil || !coherenciaValida)
                    }
                }
        }
    }

    private var coherencia: CoherenciaPunto? {
        guard let point else { return nil }
        return VerificadorCoherencia.evaluar(point: point, ruta: route)
    }

    private var coherenciaValida: Bool { coherencia?.esValido ?? true }
}
