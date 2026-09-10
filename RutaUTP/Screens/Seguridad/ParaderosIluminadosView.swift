import SwiftUI
import MapKit
import CoreLocation

/// Muestra estable del feed. GTFS no informa sobre iluminación ni vigilancia.
enum ParaderosIluminados {
    static func seleccionar(_ feed: [RutaGTFS], cantidad: Int = 24) -> [ParaderoGTFS] {
        guard cantidad > 0 else { return [] }
        var seen = Set<String>()
        let stops = feed.flatMap(\.paraderos).sorted { $0.id < $1.id }.filter {
            let key = "\(Int(($0.lat * 1e6).rounded())):\(Int(($0.lon * 1e6).rounded()))"
            return seen.insert(key).inserted
        }
        guard !stops.isEmpty else { return [] }
        let nearCampus = stops.sorted {
            PolylineMatching.distanceMeters($0.coordinate, GTFSRepository.coordenadaUTP) <
            PolylineMatching.distanceMeters($1.coordinate, GTFSRepository.coordenadaUTP)
        }
        // Incluye opciones próximas al campus y una muestra repartida por la red.
        var result = Array(nearCampus.prefix(min(8, cantidad)))
        let remaining = stops.filter { stop in !result.contains { $0.id == stop.id } }
        let slots = min(cantidad - result.count, remaining.count)
        if slots > 0 {
            for i in 0..<slots { result.append(remaining[i * remaining.count / slots]) }
        }
        return result
    }
}

struct ParaderosIluminadosView: View {
    let paraderos: [ParaderoGTFS]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @AppStorage("isDarkMode") private var dark = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: GTFSRepository.coordenadaUTP,
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)))
    @State private var loadedStops: [ParaderoGTFS] = []
    @State private var routes: [RutaGTFS] = []
    @State private var selectedID: String?
    @State private var cardID: String?
    @State private var query = ""
    @State private var radius = 0
    @State private var loading = true
    @State private var locating = false
    @State private var location: CLLocationCoordinate2D?
    @State private var locationMessage: String?
    @State private var locationService = LocationService()
    @State private var locationTask: Task<Void, Never>?
    @State private var walkingTask: Task<Void, Never>?
    @State private var walkingLine: MKPolyline?
    @State private var walkingDistance: Double?
    @State private var walkingLoading = false
    @State private var walkingMessage: String?
    @State private var savedIDs = Set<String>()
    @State private var satellite = false
    @FocusState private var searchFocused: Bool

    private let accent = Color(light: "#1669A8", dark: "#78C9FF")
    private var anchor: CLLocationCoordinate2D { location ?? GTFSRepository.coordenadaUTP }
    private var stops: [ParaderoGTFS] { loadedStops.isEmpty ? paraderos : loadedStops }
    private var visible: [ParaderoGTFS] {
        stops.filter { stop in
            (query.isEmpty || stop.nombre.localizedCaseInsensitiveContains(query)) &&
            (radius == 0 || distance(stop) <= Double(radius))
        }.sorted {
            let a = distance($0), b = distance($1)
            return abs(a - b) < 0.1 ? $0.id < $1.id : a < b
        }
    }
    private var selected: ParaderoGTFS? { visible.first { $0.id == selectedID } }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            Annotation("UTP", coordinate: GTFSRepository.coordenadaUTP) { MarcadorUTP() }
            if radius > 0 {
                MapCircle(center: anchor, radius: Double(radius))
                    .foregroundStyle(accent.opacity(0.1))
            }
            if let walkingLine {
                MapPolyline(walkingLine)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
            }
            ForEach(visible) { stop in
                Annotation(stop.nombre, coordinate: stop.coordinate, anchor: .bottom) {
                    Button { select(stop) } label: {
                        SafetyStopPin(selected: selectedID == stop.id, saved: savedIDs.contains(stop.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(stop.nombre)
                    .accessibilityHint(L.t("Ver detalles del paradero", "View stop details"))
                    .accessibilityAddTraits(selectedID == stop.id ? .isSelected : [])
                }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .overlay(alignment: .trailing) { mapControls.padding(.trailing, 16) }
        .preferredColorScheme(dark ? .dark : .light)
        .task {
            routes = await GTFSRepository.shared.rutas()
            guard !Task.isCancelled else { return }
            loadedStops = paraderos.isEmpty ? ParaderosIluminados.seleccionar(routes) : paraderos
            loading = false
            refreshSaved()
            if let first = visible.first { select(first) }
        }
        .onChange(of: cardID) { _, id in
            guard let id, id != selectedID, let stop = visible.first(where: { $0.id == id }) else { return }
            select(stop)
        }
        .onChange(of: query) { _, _ in reconcileSelection() }
        .onChange(of: radius) { _, _ in reconcileSelection(); fitAll() }
        .onDisappear {
            locationTask?.cancel()
            walkingTask?.cancel()
            locationService.stopUpdating()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.surfaceContainerLowest))
                }
                .accessibilityLabel(L.t("Volver a Seguridad", "Back to Safety"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("Explora paraderos", "Explore bus stops"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(L.t("Tu próxima parada, más cerca", "Your next stop, closer"))
                        .font(.system(size: 12)).foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "bus.fill").foregroundStyle(accent)
                    .font(.system(size: 20)).frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(accent)
                TextField(L.t("Busca una avenida o paradero", "Search a street or stop"), text: $query)
                    .font(.system(size: 14)).focused($searchFocused).submitLabel(.search)
                    .onSubmit { searchFocused = false; fitAll() }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L.t("Limpiar búsqueda", "Clear search"))
                }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.surfaceContainerLowest))
            Picker(L.t("Radio de búsqueda", "Search radius"), selection: $radius) {
                Text(L.t("Todos", "All")).tag(0)
                Text("1 km").tag(1000)
                Text("3 km").tag(3000)
            }.pickerStyle(.segmented)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(.regularMaterial)
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            control("square.3.layers.3d", label: L.t("Cambiar tipo de mapa", "Change map style")) { satellite.toggle() }
            control("arrow.up.left.and.arrow.down.right", label: L.t("Ver todos los paraderos", "Show all stops")) { fitAll() }
            control(locating ? "ellipsis" : "location.fill", label: L.t("Buscar cerca de mí", "Find stops near me")) { locate() }
        }
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button { searchFocused = false; AppHaptics.selection(); action() } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent).frame(width: 46, height: 46)
                .background(Circle().fill(Color.surfaceContainerLowest))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }.accessibilityLabel(label)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("PARADEROS", "BUS STOPS")).font(.system(size: 11, weight: .bold)).tracking(1.4)
                Text("\(visible.count)").font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(accent.opacity(0.12)))
                Spacer()
                Text(location == nil ? L.t("Desde UTP", "From UTP") : L.t("Cerca de ti", "Near you"))
                    .font(.system(size: 11)).foregroundStyle(Color.onSurfaceVariant)
            }.padding(.horizontal, 18)
            if let message = locationMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Color.appError).padding(.horizontal, 18)
            }
            if loading {
                HStack { ProgressView(); Text(L.t("Cargando paraderos…", "Loading stops…")) }.padding(18)
            } else if visible.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash.circle").font(.system(size: 26)).foregroundStyle(accent)
                    Text(L.t("No hay paraderos en esta búsqueda", "No stops match this search")).font(.system(size: 14, weight: .semibold))
                    Button(L.t("Ver todos", "Show all")) { query = ""; radius = 0; fitAll() }
                }.frame(maxWidth: .infinity).padding(16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(visible) { stop in
                            stopCard(stop).containerRelativeFrame(.horizontal).id(stop.id)
                        }
                    }.scrollTargetLayout()
                }
                .contentMargins(.horizontal, 18, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $cardID)
                .frame(height: 222)
            }
            Label(L.t("Iluminación y vigilancia sin verificar", "Lighting and surveillance not verified"), systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 18)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.top, 14).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 26).fill(.regularMaterial).ignoresSafeArea(edges: .bottom))
    }

    private func stopCard(_ stop: ParaderoGTFS) -> some View {
        let lines = routes.filter { route in route.paraderos.contains { $0.id == stop.id || PolylineMatching.distanceMeters($0.coordinate, stop.coordinate) < 20 } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bus.fill").font(.system(size: 20)).foregroundStyle(accent)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.nombre).font(.system(size: 15, weight: .bold)).lineLimit(2)
                    Text(L.t("\(Int(distance(stop))) m en línea recta", "\(Int(distance(stop))) m straight-line distance"))
                        .font(.system(size: 11)).foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Button { toggleSaved(stop) } label: {
                    Image(systemName: savedIDs.contains(stop.id) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(accent).frame(width: 36, height: 44)
                }.accessibilityLabel(savedIDs.contains(stop.id) ? L.t("Quitar de guardados", "Remove from saved") : L.t("Guardar paradero", "Save stop"))
            }
            HStack(spacing: 5) {
                ForEach(Array(lines.prefix(3))) { line in
                    Text(line.linea).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.onSurface).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(line.color.opacity(0.18)))
                }
                if lines.count > 3 { Text("+\(lines.count - 3)").font(.system(size: 10, weight: .bold)) }
                Spacer()
                Text(L.t("Paradero del feed", "Feed stop")).font(.system(size: 10)).foregroundStyle(Color.onSurfaceVariant)
            }
            if selectedID == stop.id, let meters = walkingDistance {
                Label(L.t("\(Int(ceil(meters / 84))) min a pie · \(Int(meters)) m", "\(Int(ceil(meters / 84))) min walk · \(Int(meters)) m"), systemImage: "figure.walk")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            } else {
                Text(selectedID == stop.id ? (walkingMessage ?? L.t("Desliza para explorar más paraderos", "Swipe to explore more stops")) : L.t("Toca para ver este paradero", "Tap to view this stop"))
                    .font(.system(size: 11)).foregroundStyle(Color.onSurfaceVariant).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { select(stop); walk(to: stop) } label: {
                    Label(selectedID == stop.id && walkingLoading ? L.t("Calculando…", "Calculating…") : L.t("Cómo llegar", "Directions"), systemImage: "figure.walk")
                        .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary))
                }.disabled(walkingLoading)
                Button {
                    router.lugarCercanoPendiente = DestinoPendiente(titulo: stop.nombre, lat: stop.lat, lon: stop.lon)
                    dismiss(); router.navigate(to: .rutas)
                } label: {
                    Label(L.t("Ver líneas", "Bus lines"), systemImage: "bus")
                        .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(accent).background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.1)))
                }
            }.buttonStyle(.plain)
        }
        .padding(14).frame(height: 218)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.surfaceContainerLowest))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selectedID == stop.id ? accent.opacity(0.45) : Color.outlineVariant.opacity(0.3), lineWidth: 1))
        .onTapGesture { select(stop) }
    }

    private func distance(_ stop: ParaderoGTFS) -> Double { PolylineMatching.distanceMeters(anchor, stop.coordinate) }
    private func select(_ stop: ParaderoGTFS) {
        searchFocused = false
        if selectedID != stop.id {
            walkingTask?.cancel(); walkingLine = nil; walkingDistance = nil; walkingMessage = nil; walkingLoading = false
        }
        selectedID = stop.id
        withAnimation(.easeInOut(duration: 0.3)) {
            cardID = stop.id
            camera = .region(MKCoordinateRegion(center: stop.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
        }
    }
    private func reconcileSelection() {
        if !visible.contains(where: { $0.id == selectedID }) {
            walkingTask?.cancel(); walkingLine = nil; walkingDistance = nil; walkingMessage = nil; walkingLoading = false
            selectedID = nil; cardID = nil
            if let stop = visible.first { select(stop) }
        }
    }
    private func fitAll() {
        guard !visible.isEmpty else { return }
        var rect = MKMapRect.null
        for stop in visible {
            let point = MKMapPoint(stop.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let padding = max(700, max(rect.width, rect.height) * 0.16)
        withAnimation { camera = .rect(rect.insetBy(dx: -padding, dy: -padding)) }
    }
    private func locate() {
        guard !locating else { return }
        locating = true; locationMessage = nil
        locationTask?.cancel()
        locationTask = Task { @MainActor in
            let status = await locationService.requestPermission()
            guard !Task.isCancelled else { return }
            guard status.isAuthorized else {
                locating = false
                locationMessage = L.t("Activa Ubicación en Ajustes. Las distancias usan UTP como referencia.", "Enable Location in Settings. Distances currently use UTP as the reference.")
                return
            }
            locationService.startUpdating()
            let timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                locating = false
                locationMessage = L.t("No recibimos señal GPS. Inténtalo de nuevo.", "No GPS signal received. Please try again.")
                locationService.stopUpdating()
            }
            defer { timeout.cancel(); locating = false }
            for await fix in locationService.currentLocation() {
                guard !Task.isCancelled else { return }
                location = fix.coordinate; locating = false
                walkingTask?.cancel(); walkingLine = nil; walkingDistance = nil; walkingLoading = false
                if let first = visible.first { select(first) } else { reconcileSelection() }
                locationService.stopUpdating()
                break
            }
        }
    }
    private func walk(to stop: ParaderoGTFS) {
        walkingTask?.cancel(); walkingLoading = true; walkingMessage = nil
        let origin = anchor
        walkingTask = Task { @MainActor in
            do {
                let result = try await RouteCalculationService().calculateRoute(from: origin, to: stop.coordinate, transportType: .walking)
                guard !Task.isCancelled, selectedID == stop.id else { return }
                walkingLine = result.polyline; walkingDistance = result.distance; walkingLoading = false
                withAnimation { camera = .rect(result.polyline.boundingMapRect.insetBy(dx: -600, dy: -600)) }
            } catch {
                guard !Task.isCancelled, selectedID == stop.id else { return }
                walkingLoading = false
                walkingMessage = L.t("No se pudo calcular la caminata. Revisa tu conexión.", "Walking directions unavailable. Check your connection.")
            }
        }
    }
    private func refreshSaved() {
        let places = LugaresStore.cargar()
        savedIDs = Set(stops.filter { stop in
            places.contains { place in
                place.nombre == stop.nombre && place.coordinate.map {
                    PolylineMatching.distanceMeters($0, stop.coordinate) < 5
                } == true
            }
        }.map(\.id))
    }
    private func toggleSaved(_ stop: ParaderoGTFS) {
        var places = LugaresStore.cargar()
        if let index = places.firstIndex(where: { $0.nombre == stop.nombre && $0.coordinate.map { PolylineMatching.distanceMeters($0, stop.coordinate) < 5 } == true && !$0.esFijo }) {
            places.remove(at: index)
        } else {
            places.append(LugarGuardado(nombre: stop.nombre, direccion: "Trujillo", categoria: .otro, lat: stop.lat, lon: stop.lon))
        }
        LugaresStore.guardar(places); refreshSaved(); AppHaptics.success()
    }
}

private struct SafetyStopPin: View {
    let selected: Bool
    let saved: Bool
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: saved ? "bookmark.fill" : "bus.fill")
                .font(.system(size: selected ? 20 : 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: selected ? 48 : 38, height: selected ? 48 : 38)
                .background(RoundedRectangle(cornerRadius: 15).fill(selected ? Color.appPrimary : Color.secondary))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.appSurface, lineWidth: 3))
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10))
                .foregroundStyle(selected ? Color.appPrimary : Color.secondary).offset(y: -1)
        }
        .frame(minWidth: 44, minHeight: 52)
        .shadow(color: .black.opacity(0.2), radius: selected ? 7 : 3, y: 3)
        .animation(.spring(response: 0.3), value: selected)
    }
}

#Preview {
    ParaderosIluminadosView(paraderos: []).environmentObject(AppRouter())
}
