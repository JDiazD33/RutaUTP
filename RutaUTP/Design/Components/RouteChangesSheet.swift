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
    /// Desvío que grabó «Estoy en un micro»: llena el formulario y aporta la
    /// calle nueva por la que pasó el micro.
    var desvioGrabado: TrazadorDesvio.Desvio? = nil
    /// Se llama cuando el servidor aceptó el reporte que llevaba ese trazo.
    var alEnviarTrazo: (() -> Void)? = nil
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
    /// Vía por la que pasa ahora la línea. Opcional: no todo reporte la conoce.
    @State private var via = ""
    /// Punto donde la línea retoma su recorrido habitual. Opcional; con él se
    /// dibuja en el mapa el tramo que deja de atender.
    @State private var endPoint: CLLocationCoordinate2D?
    /// `true` mientras los toques del mapa colocan el punto final.
    @State private var editandoFin = false
    /// `true` mientras los toques marcan la calle por la que va ahora. Ese
    /// punto no se envía: solo escribe el nombre de la calle.
    @State private var marcandoVia = false
    @State private var puntoVia: CLLocationCoordinate2D?
    /// Recorrido que grabó «Estoy en un micro» fuera de la ruta. Se envía con
    /// el reporte y se quita en cuanto el usuario mueve uno de sus extremos.
    @State private var trazoGrabado: [CLLocationCoordinate2D] = []
    @State private var desvioAplicado = false
    /// Envío esperando recibo: qué datos se mandaron y cuántos recibos
    /// aceptados había antes. Al superarse esa cuenta, el servidor lo aceptó.
    @State private var envioEnCurso: EnvioEnCurso?
    /// Datos del último reporte aceptado. Mientras el formulario no cambie,
    /// repetirlo no suma nada y solo taparía su recibo con «Espera 30 segundos».
    @State private var firmaAceptada: String?
    @StateObject private var viaMapa = GeocodificacionComunidadModel()

    private var puntoEnMiUbicacion: CLLocationCoordinate2D? { ubicacion.coordenada }

    private var motivo: MotivoCambioRuta { MotivoCambioRuta(rawValue: reason) ?? .obras }
    /// El tramo y la vía alterna solo valen cuando cambia el recorrido: un
    /// atasco o un choque no desvían la línea por otra calle.
    private var admiteTramo: Bool { motivo.cambiaRecorrido }
    private var marcandoFin: Bool { admiteTramo && editandoFin }
    private var marcandoPuntoVia: Bool { admiteTramo && marcandoVia && !editandoFin }

    private enum PuntoMarcado: Hashable { case inicio, via, fin }

    private var puntoMarcado: Binding<PuntoMarcado> {
        Binding(get: { editandoFin ? .fin : (marcandoVia ? .via : .inicio) },
                set: { nuevo in
                    editandoFin = nuevo == .fin
                    marcandoVia = nuevo == .via
                })
    }
    private var puntoFinal: CLLocationCoordinate2D? { admiteTramo ? endPoint : nil }
    private var viaLimpia: String { via.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var viaValida: Bool { !admiteTramo || viaLimpia.isEmpty || viaLimpia.count >= 3 }
    /// Solo un cambio de recorrido con punto final lleva la calle nueva.
    private var trazoParaEnviar: [CLLocationCoordinate2D] {
        admiteTramo && puntoFinal != nil && trazoGrabado.count >= 3 ? trazoGrabado : []
    }

    private var coherenciaFin: CoherenciaPunto? {
        guard let puntoFinal, let route else { return nil }
        return VerificadorCoherencia.evaluar(point: puntoFinal, ruta: route)
    }

    /// Motivo por el que el punto final no sirve. El servidor exige entre
    /// 50 m y 5 km del inicio, sobre la misma línea; aquí se deja un margen
    /// porque cada lado mide la distancia con su propia fórmula.
    private var problemaTramo: String? {
        guard let puntoFinal else { return nil }
        if coherenciaFin?.esValido == false {
            return L.t("Ajusta el punto final sobre el recorrido de la línea.",
                       "Move the end point onto the line's route.")
        }
        guard let point else { return nil }
        let distancia = PolylineMatching.distanceMeters(point, puntoFinal)
        if distancia < 60 {
            return L.t("El punto final está demasiado cerca del inicio.",
                       "The end point is too close to the start.")
        }
        if distancia > 4_950 {
            return L.t("El tramo no puede superar 5 km.", "The stretch can't exceed 5 km.")
        }
        return nil
    }

    /// Recorrido entre el inicio y el punto final, para verlo antes de enviar.
    private var tramoBorrador: [CLLocationCoordinate2D] {
        guard let point, let puntoFinal, let route, problemaTramo == nil else { return [] }
        return TramoCambioRuta.coordenadas(desde: point, hasta: puntoFinal, en: route.shape) ?? []
    }

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
        && problemaTramo == nil && viaValida && !yaEnviado
    }

    private struct EnvioEnCurso: Equatable {
        let firma: String
        let aceptadosAntes: Int
        let conTrazo: Bool
    }

    /// Resume lo que se enviaría ahora: línea, motivo, puntos, textos y trazo.
    private var firmaFormulario: String {
        func texto(_ punto: CLLocationCoordinate2D?) -> String {
            punto.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) } ?? "-"
        }
        return [routeID, reason, texto(point), texto(puntoFinal), viaLimpia,
                place.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(trazoParaEnviar.count)"].joined(separator: "|")
    }

    /// El servidor ya aceptó exactamente este reporte.
    private var yaEnviado: Bool { firmaAceptada == firmaFormulario }

    /// Coloca el pin donde está el usuario y centra el mapa ahí.
    private func usarMiUbicacion() {
        guard route != nil, let aqui = puntoEnMiUbicacion else { return }
        AppHaptics.impact(.light)
        if marcandoPuntoVia {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                puntoVia = aqui
                camera = .region(Self.vecindad(alrededorDe: aqui))
            }
            completarViaDesdeMapa()
            return
        }
        // Recolocar un extremo deja al trazo grabado sin su inicio o su fin.
        trazoGrabado = []
        if marcandoFin {
            // «Retoma aquí»: el punto final no completa la referencia, que
            // describe dónde empieza el cambio.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                endPoint = aqui
                camera = .region(Self.vecindad(alrededorDe: aqui))
            }
            return
        }
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
                            Text(L.f("Confirma solo si lo has visto. Un cambio se muestra en el mapa cuando lo reportan {0} cuentas distintas con el mismo motivo y en la misma zona. El tráfico vence a los 30 minutos, un choque a la hora, un cierre a las 12 horas y las obras o desvíos a las 24 horas; cada reporte nuevo los renueva. La vía alterna y el tramo los indica la comunidad.",
                                     "Confirm only what you've seen. A change is shown on the map once {0} different accounts report the same reason in the same area. Traffic expires after 30 minutes, a crash after one hour, a closure after 12 hours and roadworks or detours after 24 hours; each new report renews them. The alternative street and the stretch come from the community.",
                                     ["\(service.quorum)"]))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(L.t("La calle nueva se dibuja cuando dos cuentas graban el mismo recorrido con «Estoy en un micro».",
                                     "The new street is drawn once two accounts record the same route with “I'm on a bus”."))
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
                    ExpandedRouteIncidentMap(route: route,
                                             initialPoint: marcandoFin ? endPoint : (marcandoPuntoVia ? puntoVia : point),
                                             locationService: locationService,
                                             markerTint: MotivoCambioRuta(rawValue: reason)?.tinta ?? acento) { selected, position in
                        if marcandoPuntoVia {
                            puntoVia = selected
                            camera = position
                            completarViaDesdeMapa()
                            return
                        }
                        trazoGrabado = []
                        if marcandoFin {
                            endPoint = selected
                            camera = position
                            return
                        }
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
                        soltarTramo()
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
                aplicarDesvioGrabado()
                // El mapa abre donde está el usuario aunque el pin no se coloque
                // solo; la lectura fresca puede tardar o no llegar si está quieto.
                if point == nil, let aproximada = RouteChangesLocationModel.aproximada(de: locationService) {
                    camera = .region(Self.vecindad(alrededorDe: aproximada))
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
        .onDisappear {
            referenciaMapa.cancelar()
            viaMapa.cancelar()
        }
        .onChange(of: service.reportesAceptados) { _, total in
            guard let envio = envioEnCurso, total > envio.aceptadosAntes else { return }
            envioEnCurso = nil
            firmaAceptada = envio.firma
            if envio.conTrazo { alEnviarTrazo?() }
        }
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
        soltarTramo()
        camera = .automatic
        colocarAutomaticamenteSiProcede()
        AppHaptics.selection()
    }

    /// El punto final y la vía pertenecen al recorrido de la línea anterior.
    private func soltarTramo() {
        endPoint = nil
        editandoFin = false
        marcandoVia = false
        puntoVia = nil
        via = ""
        trazoGrabado = []
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
                    // Tres columnas alineadas: cinco botones en una sola fila
                    // dejarían rótulos recortados en un iPhone.
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            ForEach(MotivoCambioRuta.allCases.prefix(3)) { motivo in
                                botonMotivo(motivo, compacto: true)
                            }
                        }
                        GridRow {
                            ForEach(MotivoCambioRuta.allCases.dropFirst(3)) { motivo in
                                botonMotivo(motivo, compacto: true)
                            }
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
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
                if admiteTramo { selectorPunto }
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
                RouteIncidentMap(route: route,
                                 point: marcandoFin ? $endPoint : (marcandoPuntoVia ? $puntoVia : $point),
                                 camera: $camera,
                                 markerTint: MotivoCambioRuta(rawValue: reason)?.tinta ?? acento,
                                 markerTitle: marcandoFin
                                    ? L.t("Retoma su ruta", "Rejoins its route")
                                    : marcandoPuntoVia ? L.t("Va por aquí", "Now goes here")
                                    : L.t("Lugar afectado", "Affected location"),
                                 secondaryPoint: marcandoFin || marcandoPuntoVia ? point : puntoFinal,
                                 secondaryTitle: marcandoFin || marcandoPuntoVia
                                    ? L.t("Lugar afectado", "Affected location")
                                    : L.t("Retoma su ruta", "Rejoins its route"),
                                 extraPoint: !admiteTramo ? nil : (marcandoPuntoVia ? puntoFinal : puntoVia),
                                 extraTitle: marcandoPuntoVia
                                    ? L.t("Retoma su ruta", "Rejoins its route")
                                    : L.t("Va por aquí", "Now goes here"),
                                 stretch: tramoBorrador,
                                 newStreet: trazoParaEnviar,
                                 onPointChange: {
                                     // La calle marcada llena «¿Por dónde va
                                     // ahora?»; no toca extremos ni el trazo.
                                     if marcandoPuntoVia {
                                         completarViaDesdeMapa()
                                         return
                                     }
                                     // Mover un extremo deja al trazo grabado
                                     // sin su inicio o su fin: se quita.
                                     trazoGrabado = []
                                     // El punto final no cambia la referencia,
                                     // que describe dónde empieza el cambio.
                                     guard !marcandoFin else { return }
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
                AvisoCoherencia(evaluacion: marcandoFin ? coherenciaFin : coherencia, route: route)
                if admiteTramo, endPoint != nil {
                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            endPoint = nil
                            editandoFin = false
                            trazoGrabado = []
                        }
                    } label: {
                        Label(L.t("Quitar el punto donde retoma", "Remove the rejoin point"),
                              systemImage: "minus.circle")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
                if !trazoParaEnviar.isEmpty {
                    filaTrazoGrabado
                }
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
            if admiteTramo {
                campoVia
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            tituloSeccion(L.t("Ubicación", "Location"))
        }
    }

    /// Elige qué punto colocan los toques del mapa. El segundo es opcional.
    @ViewBuilder
    private var selectorPunto: some View {
        let selector = Picker(L.t("Punto que marcas en el mapa", "Point you mark on the map"),
                              selection: puntoMarcado) {
            Text(L.t("Dónde empieza", "Where it starts")).tag(PuntoMarcado.inicio)
            Text(L.t("Por dónde va", "Where it goes")).tag(PuntoMarcado.via)
            Text(L.t("Dónde retoma", "Where it rejoins")).tag(PuntoMarcado.fin)
        }
        // Un segmento recorta sus rótulos con tamaños de accesibilidad.
        if dynamicTypeSize.isAccessibilitySize {
            selector.pickerStyle(.menu)
        } else {
            selector.pickerStyle(.segmented)
        }
    }

    private var indicacionMapa: some View {
        // El rótulo cambia con el estado: si el pin ya
        // está puesto (suelo o a mano), decir "toca"
        // sería una instrucción que ya no aplica.
        Text(marcandoFin
             ? (endPoint == nil
                ? L.t("Opcional: toca dónde vuelve a su recorrido", "Optional: tap where it rejoins its route")
                : L.t("Retoma su ruta", "Rejoins its route"))
             : marcandoPuntoVia
             ? (puntoVia == nil
                ? L.t("Opcional: toca la calle por la que va ahora", "Optional: tap the street it now takes")
                : L.t("Va por aquí", "Now goes here"))
             : (point == nil
                ? L.t("Toca el lugar afectado en el mapa", "Tap the affected location on the map")
                : L.t("Lugar afectado", "Affected location")))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Vía por la que pasa ahora la línea. Se muestra junto al aviso
    /// confirmado, así que el límite coincide con el del servidor.
    private var campoVia: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("¿Por dónde va ahora?", "Where does it go now?"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(via.count)/80")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.f("{0} caracteres restantes", "{0} characters left", ["\(80 - via.count)"]))
            }
            TextField(L.t("Calle o avenida (opcional)", "Street or avenue (optional)"),
                      text: Binding(get: { via }, set: { via = String($0.prefix(80)) }))
                .font(.body)
                .textInputAutocapitalization(.words)
                .accessibilityLabel(L.t("Vía por la que pasa ahora (opcional)", "Street it now uses (optional)"))
            Text(L.t("Ejemplo: Av. América Norte. Se mostrará junto al aviso en el mapa.",
                     "Example: Av. América Norte. It'll be shown with the alert on the map."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    // En una línea: el rótulo de la izquierda es el que se ajusta.
                    .fixedSize(horizontal: true, vertical: false)
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
                    Label(reasonTitle(alert.reason), systemImage: alert.motivo.icono)
                        .font(.subheadline)
                    Text(alert.place)
                    if let via = alert.textoVia {
                        Text(via).font(.subheadline.weight(.medium))
                    }
                    Text(alert.detalleVigencia)
                        .font(.caption).foregroundStyle(.secondary)
                    // Una incidencia simulada no se confirma: crearía un reporte real.
                    if !alert.esSimulado {
                        Button(L.t("Ver lugar y confirmar", "View location and confirm")) {
                            guard rutaDisponible, !service.sending else { return }
                            referenciaMapa.cancelar(limpiar: true)
                            errorReferencia = false
                            routeID = alert.routeId
                            reason = alert.reason
                            place = alert.place
                            // Confirmar repite también el tramo y la vía del aviso.
                            via = alert.via ?? ""
                            // Nunca repite la calle nueva: solo cuenta la grabada a bordo.
                            trazoGrabado = []
                            marcandoVia = false
                            puntoVia = nil
                            endPoint = alert.coordenadaFin
                            editandoFin = false
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
                    }
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
        if yaEnviado {
            return L.t("Ya enviaste este reporte. Para enviar otro, cambia algún dato.",
                       "You already sent this report. To send another, change a detail.")
        }
        if !service.ready { return L.t("Alertas sin conexión", "Route alerts offline") }
        if route == nil { return L.t("Selecciona una ruta", "Select a route") }
        if point == nil { return L.t("Falta marcar el punto afectado.", "Mark the affected point to continue.") }
        if !coherenciaValida {
            return L.t("Ajusta el marcador sobre el recorrido de la línea.", "Move the marker onto the line's route.")
        }
        if place.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            return L.t("Escribe al menos 3 caracteres en la referencia.", "Enter at least 3 characters for the landmark.")
        }
        if let problemaTramo { return problemaTramo }
        if !viaValida {
            return L.t("Escribe al menos 3 caracteres en la vía o déjala vacía.",
                       "Enter at least 3 characters for the street, or leave it empty.")
        }
        return nil
    }

    private var botonReportarCambio: some View {
        Button {
            guard canSend, let point else { return }
            let trazo = trazoParaEnviar
            envioEnCurso = EnvioEnCurso(firma: firmaFormulario, aceptadosAntes: service.reportesAceptados,
                                        conTrazo: !trazo.isEmpty)
            service.send(routeID: routeID, reason: reason, lat: point.latitude, lon: point.longitude,
                         place: place.trimmingCharacters(in: .whitespacesAndNewlines),
                         via: admiteTramo && viaLimpia.count >= 3 ? viaLimpia : nil,
                         end: puntoFinal.map { (lat: $0.latitude, lon: $0.longitude) },
                         path: trazo.isEmpty ? nil : PolilineaCodificada.codificar(trazo))
        } label: {
            HStack(spacing: 10) {
                if service.sending {
                    ProgressView().accessibilityHidden(true)
                } else if yaEnviado {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                }
                Text(service.sending ? L.t("Enviando…", "Sending…")
                     : yaEnviado ? L.t("Reporte enviado", "Report sent")
                     : L.t("Reportar cambio", "Report change"))
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
            mapaAmpliadoAbierto: showExpandedMap) else {
            // Sin pin automático (lejos de la línea), el mapa igual se centra
            // donde está el usuario en vez de mostrar toda la ruta.
            if point == nil, !showExpandedMap,
               let aqui = puntoEnMiUbicacion ?? RouteChangesLocationModel.aproximada(de: locationService) {
                camera = .region(Self.vecindad(alrededorDe: aqui))
            }
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            point = aqui
            camera = .region(Self.vecindad(alrededorDe: aqui))
        }
        completarReferenciaDesdeMapa()
    }

    /// Escribe en «¿Por dónde va ahora?» el nombre de la calle marcada.
    private func completarViaDesdeMapa() {
        guard let coordenada = puntoVia else { return }
        viaMapa.buscar(coordenada, demora: .milliseconds(400), soloCalle: true) { calle in
            guard puntoVia?.latitude == coordenada.latitude, puntoVia?.longitude == coordenada.longitude,
                  let calle = calle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  calle.count >= 3 else { return }
            via = String(calle.prefix(80))
        }
    }

    /// Llena el formulario con el desvío que grabó «Estoy en un micro». Se
    /// aplica una sola vez; después el usuario puede cambiar cualquier dato.
    private func aplicarDesvioGrabado() {
        guard !desvioAplicado, let desvio = desvioGrabado,
              routes.contains(where: { $0.id == desvio.routeID }) else { return }
        desvioAplicado = true
        referenciaMapa.cancelar(limpiar: true)
        errorReferencia = false
        routeID = desvio.routeID
        reason = MotivoCambioRuta.desvio.rawValue
        point = desvio.inicio
        endPoint = desvio.fin
        editandoFin = false
        marcandoVia = false
        puntoVia = nil
        trazoGrabado = desvio.trazo
        puntoEditadoAMano = true
        camera = .region(Self.encuadre(de: desvio.trazo))
        completarReferenciaDesdeMapa()
        // El punto más alejado de la ruta suele estar en la calle nueva.
        let rutaDelDesvio = desvio.routeID
        viaMapa.buscar(desvio.masLejano, soloCalle: true) { calle in
            guard via.isEmpty, !trazoGrabado.isEmpty, routeID == rutaDelDesvio,
                  let calle = calle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  calle.count >= 3 else { return }
            via = String(calle.prefix(80))
        }
    }

    /// Región que muestra todo el trazo grabado con aire alrededor.
    private static func encuadre(de puntos: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = puntos.map(\.latitude)
        let longitudes = puntos.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return vecindad(alrededorDe: puntos.first ?? GTFSRepository.coordenadaUTP)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.006, (maxLat - minLat) * 1.6),
                                   longitudeDelta: max(0.006, (maxLon - minLon) * 1.6)))
    }

    /// Resumen del recorrido grabado que viaja con el reporte.
    private var filaTrazoGrabado: some View {
        let largo = Measurement(value: PolylineMatching.totalLengthMeters(trazoGrabado), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(FormatoFecha.localeActivo))
        let disposicion = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 6) {
            disposicion {
                Label(L.f("Recorrido grabado: {0}", "Recorded route: {0}", [largo]),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L.t("Quitar", "Remove"), role: .destructive) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { trazoGrabado = [] }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityLabel(L.t("Quitar el recorrido grabado", "Remove the recorded route"))
            }
            Text(L.t("La línea continua es la calle por la que pasó tu micro. Si mueves un punto, se quita.",
                     "The solid line is the street your bus took. Moving a point removes it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routeTitle(_ id: String) -> String {
        guard let route = routes.first(where: { $0.id == id }) else { return L.t("Ruta ", "Route ") + id }
        return [route.lineaConLetra, route.empresa].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// Los motivos, sus iconos y colores viven en `MotivoCambioRuta`
// (RouteChangePresentation.swift): los comparten Seguridad y el mapa.
private func reasonTitle(_ reason: String) -> String {
    guard let motivo = MotivoCambioRuta(rawValue: reason), motivo != .desvio else {
        return L.t("El bus tomó un desvío", "Bus took a detour")
    }
    return motivo.tituloAviso
}
