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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var acento: Color { .appAccent }
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
    @StateObject private var referenciaMapa = GeocodificacionComunidadModel()
    @State private var errorReferencia = false
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
        guard route != nil, let aqui = puntoEnMiUbicacion else { return }
        AppHaptics.impact(.light)
        // Solo se marca automáticamente si el sitio es coherente con la línea.
        // Si el usuario está a tres calles del recorrido, un pin automático
        // ahí sería ruido: se deja que marque él a mano sobre el trazado.
        // Este botón es una elección explícita: siempre muestra la ubicación.
        // La coherencia sigue controlando el aviso y el permiso para enviar.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            point = aqui
            puntoEditadoAMano = true
            camera = .region(Self.vecindad(alrededorDe: aqui))
        }
        completarReferenciaDesdeMapa()
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
                        estadoConexion
                    }
                    Section {
                        selectorRuta
                        selectorMotivo
                    } header: {
                        tituloSeccion(L.t("Reportar cambio", "Report change"))
                    } footer: {
                        Text(L.t("Confirma solo si lo has visto.", "Confirm only what you've seen."))
                    }
                    .disabled(service.sending)
                    .id("report-form")

                    if let route {
                        seccionUbicacion(route)
                            .disabled(service.sending)
                    }
                    if let result = service.result {
                        Section {
                            Label(L.aviso(result), systemImage: "info.circle")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    cambiosConfirmados(scroll: scroll)
                    Section {
                        DisclosureGroup {
                            Text(L.t("Confirma solo si lo has visto. Se necesitan dos cuentas distintas en la misma ruta, motivo y zona. Los reportes vencen a los 15 minutos. El aviso señala la incidencia; el recorrido alterno aún no está verificado.",
                                     "Confirm only what you've seen. Two different accounts must report the same route, reason and area. Reports expire after 15 minutes. The alert identifies the incident; the alternative path hasn't been verified."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } label: {
                            Label(L.t("Cómo se confirman los cambios", "How changes are confirmed"),
                                  systemImage: "info.circle")
                                .font(.subheadline)
                        }
                    }
                }
                .listSectionSpacing(20)
                .contentMargins(.top, 16, for: .scrollContent)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let ayudaEnvio {
                        Text(ayudaEnvio)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    botonReportarCambio
                }
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
                    ExpandedRouteIncidentMap(route: route, initialPoint: point, locationService: locationService,
                                             markerTint: MotivoCambioRuta(rawValue: reason)?.tinta ?? acento) { selected, position in
                        let cambiaPunto = point?.latitude != selected.latitude || point?.longitude != selected.longitude
                        point = selected
                        camera = position
                        puntoEditadoAMano = true
                        // Mover solo la cámara conserva una referencia editada.
                        if cambiaPunto || place.isEmpty { completarReferenciaDesdeMapa() }
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
                    if !routeID.isEmpty, !routes.contains(where: { $0.id == routeID }) {
                        referenciaMapa.cancelar(limpiar: true)
                        errorReferencia = false
                        routeID = ""
                        point = nil
                        puntoEditadoAMano = false
                        place = ""
                        camera = .automatic
                    }
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
        .onAppear {
            if point != nil, place.isEmpty, !referenciaMapa.buscando {
                completarReferenciaDesdeMapa()
            }
        }
        .onDisappear { referenciaMapa.cancelar() }
    }

    private func tituloSeccion(_ titulo: String) -> some View {
        Text(titulo)
            .font(.headline)
            .foregroundStyle(Color.onSurface)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private var estadoConexion: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: service.ready ? "checkmark.circle" : "wifi.slash")
                .font(.title3)
                .foregroundStyle(service.ready ? acento : Color(uiColor: .secondaryLabel))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(service.ready
                     ? L.t("Reportes compartidos en línea", "Shared reports online")
                     : service.configured
                        ? L.t("Sin información actualizada", "No up-to-date information")
                        : L.t("Alertas sin conexión", "Route alerts offline"))
                    .font(.subheadline.weight(.medium))
                if !service.ready {
                    Text(L.t("No podemos consultar ni enviar cambios ahora. Puedes preparar tu reporte aquí.",
                             "We can't retrieve or send changes now. You can prepare your report here."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if service.configured {
                        Button(L.t("Reintentar", "Retry")) {
                            service.stop()
                            service.start()
                        }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .disabled(service.sending)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var selectorRuta: some View {
        if cargandoRutas {
            ProgressView(L.t("Cargando rutas…", "Loading routes…"))
        } else if let errorCargaRutas {
            Text(L.aviso(errorCargaRutas)).foregroundStyle(.secondary)
            Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
        } else if routes.isEmpty {
            Text(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                 : L.t("El catálogo no contiene rutas.", "The catalog contains no routes."))
                .foregroundStyle(.secondary)
        } else {
            NavigationLink {
                SelectorLineaCambio(routes: routes,
                                    seleccion: Binding(get: { routeID }, set: cambiarRuta))
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bus")
                        .font(.title3)
                        .foregroundStyle(acento)
                        .frame(width: 44, height: 44)
                        .background(acento.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Línea y ramal", "Line and branch"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let route {
                            Text(route.lineaConLetra)
                                .font(.headline)
                                .foregroundStyle(Color.onSurface)
                            Text(route.recorridoLocalizado)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L.t("Selecciona una ruta", "Select a route"))
                                .font(.body)
                                .foregroundStyle(acento)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cambiarRuta(_ value: String) {
        guard routeID != value else { return }
        referenciaMapa.cancelar(limpiar: true)
        errorReferencia = false
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
        AppHaptics.selection()
    }

    private var selectorMotivo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("¿Qué ocurre?", "What's happening?"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if dynamicTypeSize >= .xxLarge {
                motivosVerticales
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(MotivoCambioRuta.allCases) { motivo in
                            botonMotivo(motivo, compacto: true)
                        }
                    }
                    motivosVerticales
                }
            }
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: reason)
    }

    private var motivosVerticales: some View {
        VStack(spacing: 8) {
            ForEach(MotivoCambioRuta.allCases) { motivo in
                botonMotivo(motivo, compacto: false)
            }
        }
    }

    private func botonMotivo(_ motivo: MotivoCambioRuta, compacto: Bool) -> some View {
        let seleccionado = reason == motivo.rawValue
        return Button {
            guard !seleccionado else { return }
            AppHaptics.selection()
            reason = motivo.rawValue
        } label: {
            Group {
                if compacto {
                    VStack(spacing: 8) {
                        Image(systemName: motivo.icono).font(.title3)
                        Text(motivo.titulo).fixedSize(horizontal: true, vertical: false)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: motivo.icono).font(.title3)
                        Text(motivo.titulo)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: seleccionado ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(seleccionado ? motivo.tinta : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: compacto ? 82 : 52)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(seleccionado ? motivo.tinta.opacity(0.12)
                          : Color(uiColor: .tertiarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(seleccionado ? motivo.tinta.opacity(0.6) : Color(uiColor: .separator).opacity(0.3))
            }
            .overlay(alignment: .topTrailing) {
                if compacto && seleccionado {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(motivo.tinta)
                        .padding(6)
                        .transition(.opacity.combined(with: .scale))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(motivo.titulo)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }

    private func seccionUbicacion(_ route: RutaGTFS) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        indicacionMapa
                        botonMiUbicacion
                    }
                } else {
                    HStack(spacing: 12) {
                        indicacionMapa
                        Spacer(minLength: 0)
                        botonMiUbicacion
                    }
                }
                RouteIncidentMap(route: route, point: $point, camera: $camera,
                                 markerTint: MotivoCambioRuta(rawValue: reason)?.tinta ?? acento,
                                 onPointChange: {
                                     puntoEditadoAMano = true
                                     completarReferenciaDesdeMapa()
                                 })
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Button { showExpandedMap = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.onSurface)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L.t("Ampliar mapa", "Expand map"))
                            .padding(10)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: reason)
                if dynamicTypeSize.isAccessibilitySize {
                    Button { showExpandedMap = true } label: {
                        Label(L.t("Ampliar mapa", "Expand map"),
                              systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                AvisoCoherencia(evaluacion: coherencia, route: route)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            campoReferencia
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            tituloSeccion(L.t("Ubicación", "Location"))
        }
    }

    private var indicacionMapa: some View {
        // El rótulo cambia con el estado: si el pin ya
        // está puesto (suelo o a mano), decir "toca"
        // sería una instrucción que ya no aplica.
        Text(point == nil
             ? L.t("Toca el lugar afectado en el mapa", "Tap the affected location on the map")
             : L.t("Lugar afectado", "Affected location"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var campoReferencia: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("Calle o referencia", "Street or landmark"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(place.count)/120")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.f("{0} caracteres restantes", "{0} characters left", ["\(120 - place.count)"]))
            }
            TextField(L.t("Calle o referencia (obligatorio)", "Street or landmark (required)"),
                      text: Binding(get: { place }, set: { value in
                          // Una edición explícita invalida cualquier respuesta pendiente.
                          referenciaMapa.cancelar(limpiar: true)
                          errorReferencia = false
                          place = String(value.prefix(120))
                      }), axis: .vertical)
                .font(.body)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(L.t("Calle o referencia (obligatorio)", "Street or landmark (required)"))
                .accessibilityHint(L.t("Puedes editar la referencia.", "You can edit the landmark."))
            if referenciaMapa.buscando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(L.t("Buscando dirección…", "Looking up address…"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(errorReferencia
                     ? L.t("No se pudo identificar la calle. Escribe una referencia.",
                           "Couldn't identify the street. Enter a landmark.")
                     : point == nil
                        ? L.t("Marca un punto para completar la referencia.", "Mark a point to fill in the landmark.")
                        : L.t("Puedes editar la referencia.", "You can edit the landmark."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if errorReferencia {
                    Button(L.t("Reintentar", "Retry"), action: completarReferenciaDesdeMapa)
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func completarReferenciaDesdeMapa() {
        guard let coordenada = point else { return }
        let rutaSolicitada = routeID
        // El texto anterior pertenece a otro punto. Nunca permite enviar una
        // referencia antigua mientras se resuelve la nueva selección.
        place = ""
        errorReferencia = false
        referenciaMapa.buscar(coordenada, demora: .milliseconds(400)) { direccion in
            guard routeID == rutaSolicitada,
                  point?.latitude == coordenada.latitude,
                  point?.longitude == coordenada.longitude,
                  place.isEmpty, !service.sending else { return }
            let texto = direccion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            place = String(texto.prefix(120))
            errorReferencia = texto.isEmpty
        }
    }

    @ViewBuilder
    private var botonMiUbicacion: some View {
        if puntoEnMiUbicacion != nil {
            Button(action: usarMiUbicacion) {
                Label(L.t("Mi ubicación", "My location"), systemImage: "location.fill")
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(acento.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.t("Coloca el marcador donde estás ahora", "Places the marker where you are now"))
        }
    }

    private func cambiosConfirmados(scroll: ScrollViewProxy) -> some View {
        Section {
            if service.alerts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: service.ready ? "checkmark.shield" : "wifi.slash")
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text(service.ready
                         ? L.t("No hay cambios confirmados recientes.", "No recent confirmed changes.")
                         : L.t("Sin información actualizada.", "No up-to-date information."))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }
            ForEach(service.alerts) { alert in
                let rutaDisponible = routes.contains { $0.id == alert.routeId }
                VStack(alignment: .leading, spacing: 10) {
                    Text(routeTitle(alert.routeId)).font(.headline)
                    Label(reasonTitle(alert.reason), systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                    Text(alert.place)
                    Text(L.f("{0} cuentas · vigente hasta ", "{0} accounts · valid until ", ["\(alert.confirmations)"])
                         + Date(timeIntervalSince1970: alert.expiresAt).formatted(
                            Date.FormatStyle(date: .omitted, time: .shortened).locale(FormatoFecha.localeActivo)))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L.t("Ver lugar y confirmar", "View location and confirm")) {
                        guard rutaDisponible, !service.sending else { return }
                        referenciaMapa.cancelar(limpiar: true)
                        errorReferencia = false
                        routeID = alert.routeId
                        reason = alert.reason
                        place = alert.place
                        let coordinate = CLLocationCoordinate2D(latitude: alert.lat, longitude: alert.lon)
                        point = coordinate
                        puntoEditadoAMano = true
                        camera = .region(Self.vecindad(alrededorDe: coordinate))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            scroll.scrollTo("report-form", anchor: .top)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .disabled(!rutaDisponible || service.sending)
                    if !rutaDisponible {
                        Text(L.t("Esta ruta no está disponible en el catálogo actual.",
                                 "This route isn't available in the current catalog."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            tituloSeccion(L.t("Cambios confirmados", "Confirmed changes"))
        }
    }

    private var ayudaEnvio: String? {
        if service.sending { return nil }
        if !service.ready { return L.t("Alertas sin conexión", "Route alerts offline") }
        if route == nil { return L.t("Selecciona una ruta", "Select a route") }
        if point == nil { return L.t("Falta marcar el punto afectado.", "Mark the affected point to continue.") }
        if !coherenciaValida {
            return L.t("Ajusta el marcador sobre el recorrido de la línea.", "Move the marker onto the line's route.")
        }
        if place.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            return L.t("Escribe al menos 3 caracteres en la referencia.", "Enter at least 3 characters for the landmark.")
        }
        return nil
    }

    private var botonReportarCambio: some View {
        Button {
            guard canSend, let point else { return }
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            point = aqui
            camera = .region(Self.vecindad(alrededorDe: aqui))
        }
        completarReferenciaDesdeMapa()
    }

    private func routeTitle(_ id: String) -> String {
        guard let route = routes.first(where: { $0.id == id }) else { return L.t("Ruta ", "Route ") + id }
        return [route.lineaConLetra, route.empresa].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private enum MotivoCambioRuta: String, CaseIterable, Identifiable {
    case obras = "works", cierre = "closure", desvio = "detour"

    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .obras: return L.t("Obras", "Roadworks")
        case .cierre: return L.t("Cierre", "Closure")
        case .desvio: return L.t("Desvío", "Detour")
        }
    }
    var icono: String {
        switch self {
        case .obras: return "cone.fill"
        case .cierre: return "xmark.octagon.fill"
        case .desvio: return "arrow.triangle.branch"
        }
    }
    var tinta: Color {
        switch self {
        case .obras: return Color(light: "#854A0E", dark: "#FFC078")
        case .cierre: return Color(light: "#B42330", dark: "#FF9A9F")
        case .desvio: return Color(light: "#075DB5", dark: "#8EC8FF")
        }
    }
}

private func reasonTitle(_ reason: String) -> String {
    switch reason {
    case "works": return L.t("Obras en la vía", "Roadworks")
    case "closure": return L.t("Vía cerrada", "Road closed")
    default: return L.t("El bus tomó un desvío", "Bus took a detour")
    }
}
