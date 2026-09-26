import SwiftUI
import MapKit

struct RouteChangesSheet: View {
    @ObservedObject var service: RouteChangesService
    var initialRouteID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [RutaGTFS] = []
    @State private var routeID = ""
    @State private var reason = "works"
    @State private var place = ""
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var showExpandedMap = false

    private var route: RutaGTFS? { routes.first { $0.id == routeID } }
    private var canSend: Bool {
        service.ready && !service.sending && route != nil && point != nil
        && place.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
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
                        if !service.ready {
                            Text(L.t("No podemos consultar ni enviar cambios ahora. Puedes preparar tu reporte aquí.",
                                     "We can't retrieve or send changes now. You can prepare your report here."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
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
                                Text(L.t("\(alert.confirmations) cuentas · vigente hasta ",
                                         "\(alert.confirmations) accounts · valid until ")
                                     + Date(timeIntervalSince1970: alert.expiresAt).formatted(date: .omitted, time: .shortened))
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
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section {
                        Picker(L.t("Línea y ramal", "Line and branch"), selection: Binding(get: { routeID }, set: { value in
                            routeID = value
                            point = nil
                            place = ""
                            camera = .automatic
                        })) {
                            Text(L.t("Selecciona una ruta", "Select a route")).tag("")
                            ForEach(routes) { route in
                                Text("\(route.linea) · \(route.variante) · \(route.recorrido)").tag(route.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        Picker(L.t("¿Qué ocurre?", "What's happening?"), selection: $reason) {
                            ForEach(["works", "closure", "detour"], id: \.self) { value in
                                Text(reasonTitle(value)).tag(value)
                            }
                        }
                        if let route {
                            Text(L.t("Toca el lugar afectado en el mapa", "Tap the affected location on the map"))
                                .font(.subheadline)
                            RouteIncidentMap(route: route, point: $point, camera: $camera)
                                .frame(height: 210)
                            Button { showExpandedMap = true } label: {
                                Label(L.t("Ampliar mapa", "Expand map"),
                                      systemImage: "arrow.up.left.and.arrow.down.right")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            TextField(L.t("Calle o referencia (obligatorio)", "Street or landmark (required)"), text: $place)
                                .onChange(of: place) { _, value in place = String(value.prefix(120)) }
                            if point == nil {
                                Text(L.t("Falta marcar el punto afectado.", "Mark the affected point to continue."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            guard let point else { return }
                            service.send(routeID: routeID, reason: reason, lat: point.latitude, lon: point.longitude,
                                         place: place.trimmingCharacters(in: .whitespacesAndNewlines))
                        } label: {
                            HStack {
                                if service.sending { ProgressView() }
                                Text(service.sending ? L.t("Enviando…", "Sending…") : L.t("Reportar cambio", "Report change"))
                            }
                        }
                        .disabled(!canSend)
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
                }
            }
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
                    }
                }
            }
            .task {
                routes = await GTFSRepository.shared.rutas()
                if let initialRouteID { routeID = initialRouteID }
            }
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

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                MapPolyline(coordinates: route.shape).stroke(.blue, lineWidth: 4)
                if let point {
                    Marker(L.t("Lugar afectado", "Affected location"), coordinate: point)
                        .tint(.orange)
                }
            }
            .onTapGesture { location in
                if let coordinate = proxy.convert(location, from: .local) {
                    point = coordinate
                }
            }
        }
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
                        .disabled(point == nil)
                    }
                }
        }
    }
}
