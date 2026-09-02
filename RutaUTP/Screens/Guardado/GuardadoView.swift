//
//  GuardadoView.swift
//  RutaUTP
//
//  Lugares y líneas guardadas. Tabs + sheets de detalle + sheets para añadir.
//
//  - Lugares: persistidos en UserDefaults con coordenadas; el mapa del
//    detalle muestra el lugar correcto y los botones trabajan sobre él.
//  - Líneas: se guardan referencias a rutas REALES del feed GTFS
//    (route_id); el detalle y el explorador usan los datos oficiales.
//  - El botón "Añadir" es contextual según el tab activo.
//

import SwiftUI
import MapKit
import CoreLocation

struct GuardadoView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedTab: Tab = .lugares

    // Lugares
    @State private var lugares: [LugarGuardado] = []
    @State private var showAddLugar = false
    @State private var selectedLugar: LugarGuardado?

    // Líneas (referencias a rutas GTFS reales)
    @State private var lineaRefs: [LineaGuardadaRef] = []
    @State private var lineasGTFS: [RutaOpcion] = []      // catálogo completo
    @State private var showAddLinea = false
    @State private var selectedLinea: RutaOpcion?
    @State private var rutaParaExplorar: RutaOpcion?

    private static let lineasKey = "lineas.guardadas.v1"

    enum Tab: String, CaseIterable, Identifiable {
        case lugares = "Lugares"
        case lineas  = "Líneas"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabs
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .lugares: lugaresSection
                        case .lineas:  lineasSection
                        }
                    }
                    .padding(.bottom, 90)
                }
            }
            .padding(.bottom, 64)

            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            cargarLugares()
            cargarLineas()
            procesarHookDebug()
        }
        .task {
            // Catálogo GTFS para resolver las líneas guardadas y el selector.
            let feed = await GTFSRepository.shared.rutas()
            lineasGTFS = RutasViewModel.convertir(feed)
        }
        .sheet(isPresented: $showAddLugar) {
            AddLugarSheet { nuevo in
                lugares.insert(nuevo, at: lugaresUTPFin() + 1 > lugares.count ? lugares.count : lugaresUTPFin() + 1)
                guardarLugares()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) {
                lugares.removeAll { $0.id == lugar.id }
                guardarLugares()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddLinea) {
            AddLineaSheet(
                catalogo: lineasGTFS,
                yaGuardadas: Set(lineaRefs.map(\.routeId))
            ) { ruta in
                lineaRefs.append(LineaGuardadaRef(routeId: ruta.id))
                guardarLineas()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedLinea) { linea in
            LineaDetailSheet(linea: linea,
                             onExplorar: {
                                 selectedLinea = nil
                                 rutaParaExplorar = linea
                             },
                             onQuitar: {
                                 lineaRefs.removeAll { $0.routeId == linea.id }
                                 guardarLineas()
                             })
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $rutaParaExplorar) { linea in
            ExploradorRutaView(ruta: linea)
        }
    }

    /// Índice después del último lugar fijo (UTP) para insertar lugares nuevos.
    private func lugaresUTPFin() -> Int {
        lugares.firstIndex { !$0.esFijo } ?? lugares.count
    }

    // MARK: - Persistencia (delegada en LugaresStore)
    private func cargarLugares() {
        lugares = LugaresStore.cargar()
    }

    private func guardarLugares() {
        LugaresStore.guardar(lugares)
    }

    private func cargarLineas() {
        if let data = UserDefaults.standard.data(forKey: Self.lineasKey),
           let refs = try? JSONDecoder().decode([LineaGuardadaRef].self, from: data) {
            lineaRefs = refs
        }
    }

    private func guardarLineas() {
        if let data = try? JSONEncoder().encode(lineaRefs) {
            UserDefaults.standard.set(data, forKey: Self.lineasKey)
        }
    }

    #if DEBUG
    /// Hook de pruebas: `--tab lineas` cambia de tab; `--add` abre el sheet
    /// de añadir del tab activo; `--lugar <n>` abre el detalle del lugar;
    /// `--accion ruta|cercano` dispara esos botones.
    private func procesarHookDebug() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count, args[i + 1] == "lineas" {
            selectedTab = .lineas
        }
        if args.contains("--add") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if selectedTab == .lugares { showAddLugar = true } else { showAddLinea = true }
            }
            return
        }
        guard let i = args.firstIndex(of: "--lugar"), i + 1 < args.count,
              let indice = Int(args[i + 1]), lugares.indices.contains(indice) else { return }
        let lugar = lugares[indice]
        if let j = args.firstIndex(of: "--accion"), j + 1 < args.count {
            switch args[j + 1] {
            case "ruta":
                if let coord = lugar.coordinate {
                    router.destinoPendiente = DestinoPendiente(
                        titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude)
                }
                router.navigate(to: .mapaPrincipal)
            case "cercano":
                if let coord = lugar.coordinate {
                    router.lugarCercanoPendiente = DestinoPendiente(
                        titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude)
                }
                router.navigate(to: .rutas)
            default:
                selectedLugar = lugar
            }
        } else {
            selectedLugar = lugar
        }
    }
    #else
    private func procesarHookDebug() {}
    #endif

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text(L.signable("guardado.titulo", "Guardado", "Saved"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
                .seniable("guardado.titulo")
            Spacer()
            botonAñadir
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// Botón "Añadir" contextual: añade lugar o línea según el tab activo.
    private var botonAñadir: some View {
        Button {
            AppHaptics.impact(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                switch selectedTab {
                case .lugares: showAddLugar = true
                case .lineas:  showAddLinea = true
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selectedTab == .lugares ? "plus.circle.fill" : "bus.doubledecker.fill")
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text(selectedTab == .lugares
                     ? L.signable("guardado.anadir_lugar", "Añadir lugar", "Add place")
                     : L.signable("guardado.anadir_linea", "Añadir línea", "Add line"))
                    .font(.labelCapsMd)
                    .appTracking(AppTracking.wideLabel)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [.appPrimary, .appPrimary.opacity(0.78)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .appPrimary.opacity(0.40), radius: 7, x: 0, y: 3)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .accessibilityLabel(selectedTab == .lugares ? L.t("Añadir lugar guardado", "Add saved place") : L.t("Añadir línea guardada", "Add saved line"))
        .seniable(selectedTab == .lugares ? "guardado.anadir_lugar" : "guardado.anadir_linea")
    }

    // MARK: - Tabs
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    AppHaptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = t }
                } label: {
                    VStack(spacing: 6) {
                        Text(t == .lugares
                             ? L.signable("guardado.lugares", "Lugares", "Places")
                             : L.signable("guardado.lineas", "Líneas", "Lines"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(selectedTab == t ? Color.appPrimary : Color.onSurfaceVariant)
                        Rectangle()
                            .fill(selectedTab == t ? Color.appPrimary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .seniable(t == .lugares ? "guardado.lugares" : "guardado.lineas")
            }
        }
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Lugares section
    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Toca un lugar para ver más opciones.", "Tap a place for more options."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if lugares.isEmpty {
                emptyState(icono: "bookmark.slash",
                           titulo: L.t("Aún no tienes lugares guardados", "No saved places yet"),
                           subtitulo: L.t("Toca Añadir lugar para guardar tu primer lugar.", "Tap Add place to save your first place."))
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(lugares) { lugar in
                        lugarRow(lugar)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func lugarRow(_ lugar: LugarGuardado) -> some View {
        Button {
            AppHaptics.selection()
            selectedLugar = lugar
        } label: {
            HStack(spacing: 14) {
                iconCircle(lugar: lugar)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(lugar.nombre)
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        if lugar.esFrecuente {
                            Text("FRECUENTE")
                                .font(.labelCapsMd)
                                .foregroundStyle(.onTertiary)
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.tertiary))
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                        Text(lugar.direccion)
                            .font(.bodySm)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func iconCircle(lugar: LugarGuardado) -> some View {
        let isPrimary = lugar.esFijo
        let bg: Color = isPrimary ? .appPrimary : .primaryContainer.opacity(0.15)
        let fg: Color = isPrimary ? .white : .appPrimary
        return ZStack {
            Circle().fill(bg).frame(width: 48, height: 48)
            Image(systemName: lugar.categoria.icono)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(fg)
        }
    }

    // MARK: - Lineas section (líneas GTFS guardadas)
    private var lineasGuardadas: [RutaOpcion] {
        let porId = Dictionary(uniqueKeysWithValues: lineasGTFS.map { ($0.id, $0) })
        return lineaRefs.compactMap { porId[$0.routeId] }
    }

    private var lineasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lineasGuardadas.isEmpty
                 ? L.t("Guarda líneas oficiales del feed para tenerlas a la mano.", "Save official feed lines to have them handy.")
                 : String(format: L.t("%d línea(s) guardada(s) del feed oficial.", "%d saved line(s) from the official feed."), lineasGuardadas.count))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if lineasGuardadas.isEmpty {
                emptyState(icono: "bus.badge.clock",
                           titulo: L.t("No tienes líneas guardadas", "No saved lines"),
                           subtitulo: L.t("Toca Añadir línea y elige una de las \(lineasGTFS.isEmpty ? "102" : "\(lineasGTFS.count)") líneas oficiales.", "Tap Add line and pick one of the \(lineasGTFS.isEmpty ? "102" : "\(lineasGTFS.count)") official lines."))
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(lineasGuardadas) { linea in
                        lineaRow(linea)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func lineaRow(_ linea: RutaOpcion) -> some View {
        Button {
            AppHaptics.selection()
            selectedLinea = linea
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(linea.colorLinea)
                    .frame(width: 4, height: 46)
                ZStack {
                    Circle().fill(linea.colorLinea.opacity(0.14)).frame(width: 42, height: 42)
                    Text(linea.linea)
                        .font(.system(size: 13, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(linea.colorLinea)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(linea.empresa)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    Text(linea.recorrido)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(linea.frecuenciaTexto)
                        .font(.bodyMdMedium)
                        .foregroundStyle(linea.colorLinea)
                    Text("frecuencia")
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state
    private func emptyState(icono: String, titulo: String, subtitulo: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.onSurfaceVariant)
            Text(titulo)
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
            Text(subtitulo)
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Sample data
    // El seed vive en LugaresStore (compartido con SeguridadView).
}

// MARK: - Estilo presionable del botón Añadir
struct PressableCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Mapa para elegir ubicación (tocable para mover el pin)
private struct MapaElegirLugar: UIViewRepresentable {
    /// Coordenada actual del pin (nil = sin pin todavía).
    let coordenada: CLLocationCoordinate2D?
    /// Avisa cuando el usuario toca el mapa para mover el pin.
    var onTocar: (CLLocationCoordinate2D) -> Void
    /// Cambia para re-centrar el mapa sobre `coordenada` (ej. al geocodificar).
    var recentrarTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onTocar: onTocar)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.setRegion(
            MKCoordinateRegion(
                center: coordenada ?? .init(latitude: -8.1096, longitude: -79.0287),
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            ), animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.mapaTocado(_:)))
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Pin
        if let coordenada {
            if let pin = coordinator.pin {
                pin.coordinate = coordenada
            } else {
                let pin = MKPointAnnotation()
                pin.coordinate = coordenada
                pin.title = "Aquí"
                mapView.addAnnotation(pin)
                coordinator.pin = pin
            }
        } else if let pin = coordinator.pin {
            mapView.removeAnnotation(pin)
            coordinator.pin = nil
        }

        // Re-centrado cuando el padre lo pide (geocodificación, no taps)
        if coordinator.ultimoRecentrado != recentrarTrigger {
            coordinator.ultimoRecentrado = recentrarTrigger
            if let coordenada {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: coordenada,
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ), animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var pin: MKPointAnnotation?
        var ultimoRecentrado = 0
        var onTocar: (CLLocationCoordinate2D) -> Void

        init(onTocar: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onTocar = onTocar
        }

        @objc func mapaTocado(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let punto = gesture.location(in: mapView)
            let coord = mapView.convert(punto, toCoordinateFrom: mapView)
            onTocar(coord)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "pin-elegir"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                        ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor(Color.appPrimary)
            view.glyphImage = UIImage(systemName: "mappin.circle.fill")
            view.glyphTintColor = .white
            view.canShowCallout = false
            return view
        }
    }
}

// MARK: - Lugar Detail Sheet
struct LugarDetailSheet: View {
    let lugar: LugarGuardado
    var onEliminar: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    /// Centro del mapa: coordenadas del lugar si las tiene; si no, fallback
    /// al campus UTP mientras el geocoder resuelve.
    @State private var lugarCoord: CLLocationCoordinate2D = CLLocationCoordinate2D(
        latitude: -8.098247879173792, longitude: -79.03818104755645
    )
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    @State private var buscandoCoord: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Mapa preview centrado en el lugar
            ZStack(alignment: .bottomTrailing) {
                Map(position: $camera) {
                    Annotation(lugar.nombre, coordinate: lugarCoord) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            Image(systemName: lugar.categoria.icono)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))

                if buscandoCoord {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text(L.t("Buscando ubicación…", "Finding location…"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.onSurface)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(10)
                }
            }
            .frame(height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(lugar.esFijo ? Color.appPrimary : Color.primaryContainer.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: lugar.categoria.icono)
                            .font(.system(size: 28))
                            .foregroundStyle(lugar.esFijo ? .white : .appPrimary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(lugar.nombre)
                                .font(.headlineMd)
                            if lugar.esFrecuente {
                                Text("FRECUENTE")
                                    .font(.labelCapsSm)
                                    .foregroundStyle(.onTertiary)
                                    .appTracking(AppTracking.wideLabel)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.tertiary))
                            }
                        }
                        Text(lugar.direccion)
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    Spacer()
                }

                Divider()

                // Botones de acción (funcionales con las coordenadas del lugar)
                VStack(spacing: 10) {
                    Button {
                        // Mapa: traza la ruta desde mi posición hasta este lugar
                        if let coord = lugar.coordinate {
                            router.destinoPendiente = DestinoPendiente(
                                titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude
                            )
                        }
                        router.navigate(to: .mapaPrincipal)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text(L.t("Ver ruta desde mi posición", "See route from my location"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                        .foregroundStyle(.white)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Rutas: muestra las líneas que pasan cerca del lugar
                        if let coord = lugar.coordinate {
                            router.lugarCercanoPendiente = DestinoPendiente(
                                titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude
                            )
                        }
                        router.navigate(to: .rutas)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "bus.fill")
                            Text(lugar.coordinate == nil
                                 ? L.t("Ver rutas disponibles", "See available routes")
                                 : L.t("Buscar transporte cercano", "Find nearby transport"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryContainer))
                        .foregroundStyle(.onPrimaryContainer)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)

                    if lugar.esFijo {
                        HStack(spacing: 8) {
                            Image(systemName: "pin.fill")
                            Text(L.t("Lugar fijo de la app · no se puede eliminar", "Fixed app place · cannot be removed"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                        .foregroundStyle(.onSurfaceVariant)
                        .font(.bodyMdMedium)
                    } else {
                        Button {
                            onEliminar()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text(L.t("Eliminar de guardados", "Remove from saved"))
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.errorContainer))
                            .foregroundStyle(.onErrorContainer)
                            .font(.bodyMdMedium)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear { resolverCoordenadas() }
    }

    /// Si el lugar trae coordenadas las usa directo; si no, geocodifica
    /// su dirección para centrar el mapa correctamente.
    private func resolverCoordenadas() {
        if let coord = lugar.coordinate {
            centrar(coord)
            return
        }
        buscandoCoord = true
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString("\(lugar.direccion), Trujillo, Perú") { placemarks, _ in
            DispatchQueue.main.async {
                buscandoCoord = false
                if let coord = placemarks?.first?.location?.coordinate {
                    centrar(coord)
                }
            }
        }
    }

    private func centrar(_ coord: CLLocationCoordinate2D) {
        lugarCoord = coord
        withAnimation(.spring(response: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
    }
}

// MARK: - Linea Detail Sheet (línea GTFS real)
private struct LineaDetailSheet: View {
    let linea: RutaOpcion
    var onExplorar: () -> Void
    var onQuitar: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(linea.colorLinea.opacity(0.15)).frame(width: 64, height: 64)
                    Text(linea.linea)
                        .font(.system(size: 18, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(linea.colorLinea)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(linea.empresa)
                        .font(.headlineSm)
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                        Text(linea.frecuenciaTexto)
                            .font(.labelCapsMd)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .foregroundStyle(linea.colorLinea)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(linea.colorLinea.opacity(0.12)))
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("RECORRIDO")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(linea.recorrido)
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
            }

            // Datos del feed GTFS
            HStack(spacing: 0) {
                dato(icono: "clock.fill", valor: linea.tiempoTexto, etiqueta: "Viaje")
                divisor
                dato(icono: "creditcard.fill", valor: linea.costo, etiqueta: "Tarifa")
                divisor
                dato(icono: "mappin.and.ellipse", valor: "\(linea.numParaderos)", etiqueta: "Paraderos")
                divisor
                dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
                     valor: String(format: "%.1f km", linea.distanciaKm), etiqueta: "Longitud")
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))

            VStack(alignment: .leading, spacing: 8) {
                Text("EXTREMOS")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(linea.colorLinea)
                    Text(linea.paradaInicio).font(.bodySm).lineLimit(1)
                    Spacer()
                    Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(.red)
                    Text(linea.paradaFin).font(.bodySm).lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onExplorar()
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text(L.t("Ver recorrido en el mapa", "View route on map"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                    .foregroundStyle(.white)
                    .font(.headlineSm)
                }
                .buttonStyle(.plain)

                Button {
                    onQuitar()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text(L.t("Quitar de guardados", "Remove from saved"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.errorContainer))
                    .foregroundStyle(.onErrorContainer)
                    .font(.bodyMdMedium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private var divisor: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.35))
            .frame(width: 1, height: 34)
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appPrimary)
            Text(valor)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.onSurface)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Lugar sheet (con mapa en vivo)
private struct AddLugarSheet: View {
    var onSave: (LugarGuardado) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var nombre: String = ""
    @State private var direccion: String = ""
    @State private var categoria: CategoriaLugar = .otro

    // Ubicación elegida (por geocodificación o toque en el mapa)
    @State private var coordElegida: CLLocationCoordinate2D? = nil
    @State private var buscandoUbicacion = false
    @State private var direccionNoEncontrada = false
    @State private var recentrarTrigger = 0
    @State private var geocodeTask: Task<Void, Never>?
    @State private var ajusteManual = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(coordElegida == nil
                         ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                         : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                        .font(.headlineMd)
                        .seniable(coordElegida == nil ? nil : "guardado.guardar_lugar")

                    campoNombre
                    campoDireccion
                    estadoUbicacion
                    mapaElegir
                    selectorCategoria

                    botonGuardar
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        geocodeTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Campos
    private var campoNombre: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("NOMBRE", "NAME"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            TextField(L.t("Ej. Mi trabajo", "e.g. My job"), text: $nombre)
                .textFieldStyle(.plain)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    private var campoDireccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("DIRECCIÓN", "ADDRESS"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                TextField(L.t("Ej. Av. España 123, Trujillo", "e.g. 123 España Ave, Trujillo"), text: $direccion)
                    .font(.bodySm)
                    .autocorrectionDisabled()
                    .onChange(of: direccion) { _ in programarGeocodificacion() }
                if buscandoUbicacion {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    /// Estado de la ubicación: encontrada / buscando / ajustada a mano.
    @ViewBuilder
    private var estadoUbicacion: some View {
        if ajusteManual {
            Label("Ubicación ajustada en el mapa", systemImage: "hand.tap.fill")
                .font(.bodySm)
                .foregroundStyle(.appPrimary)
        } else if direccionNoEncontrada {
            Label("No encontramos esa dirección — toca el mapa para ubicarla tú", systemImage: "exclamationmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.orange)
        } else if coordElegida != nil {
            Label("Ubicación encontrada ✓", systemImage: "checkmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.green)
        } else {
            Label("Escribe la dirección para verla en el mapa", systemImage: "info.circle")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
        }
    }

    // MARK: Mapa
    private var mapaElegir: some View {
        ZStack(alignment: .bottom) {
            MapaElegirLugar(
                coordenada: coordElegida,
                onTocar: { coord in
                    AppHaptics.impact(.light)
                    geocodeTask?.cancel()
                    buscandoUbicacion = false
                    ajusteManual = true
                    withAnimation(.spring(response: 0.3)) {
                        coordElegida = coord
                    }
                },
                recentrarTrigger: recentrarTrigger
            )

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Toca el mapa para mover el pin")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(.bottom, 10)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
    }

    private var selectorCategoria: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("CATEGORÍA", "CATEGORY"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Picker("Categoría", selection: $categoria) {
                ForEach(CategoriaLugar.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    // MARK: Guardar
    private var puedeGuardar: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty && coordElegida != nil
    }

    private var botonGuardar: some View {
        Button {
            guard let coord = coordElegida else { return }
            AppHaptics.success()
            onSave(LugarGuardado(
                nombre: nombre.trimmingCharacters(in: .whitespaces),
                direccion: direccion.isEmpty ? "Sin dirección" : direccion,
                categoria: categoria,
                lat: coord.latitude,
                lon: coord.longitude
            ))
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: coordElegida == nil ? "location.slash.fill" : "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                Text(coordElegida == nil
                     ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                     : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: puedeGuardar
                                ? [.appPrimary, .appPrimary.opacity(0.78)]
                                : [Color.onSurfaceVariant.opacity(0.35), Color.onSurfaceVariant.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: puedeGuardar ? .appPrimary.opacity(0.35) : .clear,
                            radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .disabled(!puedeGuardar)
        .animation(.easeInOut(duration: 0.2), value: puedeGuardar)
        .seniable(puedeGuardar ? "guardado.guardar_lugar" : nil)
    }

    // MARK: Geocodificación con debounce
    /// Espera 0.7 s a que el usuario deje de escribir y geocodifica.
    private func programarGeocodificacion() {
        geocodeTask?.cancel()
        ajusteManual = false
        direccionNoEncontrada = false

        let texto = direccion.trimmingCharacters(in: .whitespaces)
        guard texto.count >= 5 else {
            if texto.isEmpty { coordElegida = nil }
            return
        }

        geocodeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await geocodificar(texto)
        }
    }

    private func geocodificar(_ texto: String) async {
        buscandoUbicacion = true
        let geocoder = CLGeocoder()
        let resultados: [CLPlacemark]? = await withCheckedContinuation { continuidad in
            geocoder.geocodeAddressString("\(texto), Trujillo, Perú") { placemarks, _ in
                continuidad.resume(returning: placemarks)
            }
        }
        guard !Task.isCancelled else { return }
        buscandoUbicacion = false

        if let coord = resultados?.first?.location?.coordinate {
            direccionNoEncontrada = false
            withAnimation(.spring(response: 0.35)) {
                coordElegida = coord
                recentrarTrigger += 1
            }
        } else {
            direccionNoEncontrada = true
        }
    }
}

// MARK: - Add Linea sheet (selector de líneas GTFS reales)
private struct AddLineaSheet: View {
    let catalogo: [RutaOpcion]
    let yaGuardadas: Set<String>
    var onSave: (RutaOpcion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var texto: String = ""

    private var filtradas: [RutaOpcion] {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return catalogo }
        return catalogo.filter {
            $0.linea.localizedCaseInsensitiveContains(t)
            || $0.empresa.localizedCaseInsensitiveContains(t)
            || $0.recorrido.localizedCaseInsensitiveContains(t)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Guardar línea", "Save line"))
                    .font(.headlineMd)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                    TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $texto)
                        .font(.bodySm)
                        .autocorrectionDisabled()
                    if !texto.isEmpty {
                        Button {
                            texto = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))

                if catalogo.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Cargando líneas oficiales…")
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(filtradas) { ruta in
                                filaCatalogo(ruta)
                            }
                            if filtradas.isEmpty {
                                Text("Sin coincidencias para “\(texto)”")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func filaCatalogo(_ ruta: RutaOpcion) -> some View {
        let guardada = yaGuardadas.contains(ruta.id)
        return Button {
            guard !guardada else { return }
            AppHaptics.success()
            onSave(ruta)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ruta.colorLinea)
                    .frame(width: 4, height: 42)
                ZStack {
                    Circle().fill(ruta.colorLinea.opacity(0.14)).frame(width: 38, height: 38)
                    Text(ruta.linea)
                        .font(.system(size: 12, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(ruta.colorLinea)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ruta.empresa)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    Text(ruta.recorrido)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                if guardada {
                    Label("Guardada", systemImage: "checkmark.circle.fill")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.appPrimary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(guardada)
        .opacity(guardada ? 0.55 : 1)
    }
}

#Preview {
    GuardadoView().environmentObject(AppRouter())
}
