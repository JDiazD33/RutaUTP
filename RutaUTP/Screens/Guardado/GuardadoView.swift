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
    @StateObject private var vm = GuardadoViewModel()
    @State private var selectedTab: Tab = .lugares

    // Estado de PRESENTACIÓN: qué sheet está abierto y qué elemento está
    // seleccionado. Los datos, su persistencia y las reglas derivadas viven en
    // `GuardadoViewModel`.
    @State private var showAddLugar = false
    @State private var selectedLugar: LugarGuardado?
    @State private var showAddLinea = false
    @State private var selectedLinea: RutaOpcion?
    @State private var rutaParaExplorar: RutaOpcion?

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
            vm.cargar()
            procesarHookDebug()
        }
        .task { await vm.cargarCatalogo() }
        .sheet(isPresented: $showAddLugar) {
            AddLugarSheet { vm.añadirLugar($0) }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) { vm.eliminarLugar(lugar) }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddLinea) {
            AddLineaSheet(
                catalogo: vm.lineasGTFS,
                cargando: !vm.catalogoCargado,
                yaGuardadas: vm.idsLineasGuardadas
            ) { vm.añadirLinea($0) }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedLinea) { linea in
            LineaDetailSheet(linea: linea,
                             onExplorar: {
                                 selectedLinea = nil
                                 rutaParaExplorar = linea
                             },
                             onQuitar: { vm.eliminarLinea(linea) })
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $rutaParaExplorar) { linea in
            ExploradorRutaView(ruta: linea)
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
              let indice = Int(args[i + 1]), vm.lugares.indices.contains(indice) else { return }
        let lugar = vm.lugares[indice]
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
                .seniable("guardado.titulo", distintivoDx: 10)
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
            // Modo Señas: deja ver el videito antes de que el sheet tape el miniplayer.
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: selectedTab == .lugares ? "guardado.anadir_lugar" : "guardado.anadir_linea") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    switch selectedTab {
                    case .lugares: showAddLugar = true
                    case .lineas:  showAddLinea = true
                    }
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
        .seniable(selectedTab == .lugares ? "guardado.anadir_lugar" : "guardado.anadir_linea", conGesto: false)
    }

    // MARK: - Tabs
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    AppHaptics.selection()
                    let clave = t == .lugares ? "guardado.lugares" : "guardado.lineas"
                    SeniasPresenter.shared.ejecutarTrasVerSenia(clave: clave) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = t }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(t == .lugares
                             ? L.signable("guardado.lugares", "Lugares", "Places")
                             : L.signable("guardado.lineas", "Líneas", "Lines"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(selectedTab == t ? Color.appPrimary : Color.onSurfaceVariant)
                            // El distintivo va en el TEXTO (al terminar la
                            // palabra) pero SIN gesto: conGesto false.
                            .seniable(t == .lugares ? "guardado.lugares" : "guardado.lineas",
                                      distintivoDx: 10, conGesto: false)
                        Rectangle()
                            .fill(selectedTab == t ? Color.appPrimary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
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

            if vm.lugares.isEmpty {
                emptyState(icono: "bookmark.slash",
                           titulo: L.t("Aún no tienes lugares guardados", "No saved places yet"),
                           subtitulo: L.t("Toca Añadir lugar para guardar tu primer lugar.", "Tap Add place to save your first place."))
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(vm.lugares) { lugar in
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
                            Text(L.t("FRECUENTE", "FREQUENT"))
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
    private var lineasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.lineasGuardadas.isEmpty
                 ? L.t("Guarda líneas oficiales del feed para tenerlas a la mano.", "Save official feed lines to have them handy.")
                 : String(format: L.t("%d línea(s) guardada(s) del feed oficial.", "%d saved line(s) from the official feed."), vm.lineasGuardadas.count))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if vm.lineasGuardadas.isEmpty {
                emptyState(icono: "bus.badge.clock",
                           titulo: L.t("No tienes líneas guardadas", "No saved lines"),
                           subtitulo: L.t("Toca Añadir línea y elige una de las \(vm.lineasGTFS.isEmpty ? "102" : "\(vm.lineasGTFS.count)") líneas oficiales.", "Tap Add line and pick one of the \(vm.lineasGTFS.isEmpty ? "102" : "\(vm.lineasGTFS.count)") official lines."))
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(vm.lineasGuardadas) { linea in
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
                    Text(L.t("frecuencia", "frequency"))
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
/// Mapa para elegir un punto con un tap. Compartido por Guardado (elegir
/// ubicación del lugar) y Mapa (elegir destino en el mapa).
struct MapaElegirLugar: UIViewRepresentable {
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
    @State private var lugarCoord: CLLocationCoordinate2D?
    @State private var buscandoCoord = true
    @State private var intento = 0
    @State private var geocoder = CLGeocoder()
    @State private var navegando = false
    @State private var confirmarEliminar = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: GTFSRepository.coordenadaUTP,
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(L.t("LUGAR GUARDADO", "SAVED PLACE"), systemImage: "bookmark.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Color.onSurfaceVariant)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.bold())
                            .frame(width: 44, height: 44)
                            .background(Color.surfaceContainerLow, in: Circle())
                    }
                    .accessibilityLabel(L.t("Cerrar", "Close"))
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: lugar.categoria.icono)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .frame(width: 58, height: 58)
                        .background(Color.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lugar.nombre).font(.title2.bold())
                        Text(lugar.direccion).font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                        if lugar.esFrecuente {
                            Label(L.t("Frecuente", "Frequent"), systemImage: "star.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color.appPrimary)
                        }
                    }
                }

                Group {
                    if let coord = lugarCoord {
                        Map(position: $camera, interactionModes: []) {
                            Annotation(lugar.nombre, coordinate: coord) {
                                Image(systemName: lugar.categoria.icono)
                                    .font(.title3.bold()).foregroundStyle(.white)
                                    .padding(12).background(Color.appPrimary, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .accessibilityLabel(L.t("Ubicación de ", "Location of ") + lugar.nombre)
                    } else {
                        VStack(spacing: 12) {
                            if buscandoCoord {
                                ProgressView()
                                Text(L.t("Localizando el lugar…", "Locating this place…"))
                            } else {
                                Image(systemName: "mappin.slash.circle").font(.largeTitle)
                                Text(L.t("No pudimos localizar esta dirección.", "We could not locate this address."))
                                Button(L.t("Reintentar", "Try again")) { intento += 1 }
                                    .fontWeight(.bold).foregroundStyle(Color.appPrimary)
                            }
                        }
                        .font(.subheadline).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.surfaceContainerLow)
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Planea tu visita", "Plan your visit")).font(.headline)
                    accion(titulo: L.t("Transporte cerca de este lugar", "Transport near this place"),
                           detalle: L.t("Líneas con paradero a menos de 300 m del lugar.", "Routes with a stop within 300 m of this place."),
                           icono: "bus.fill", principal: true) {
                        abrirDestino(transporte: true)
                    }
                    accion(titulo: L.t("Cómo llegar", "How to get there"),
                           detalle: L.t("Traza el camino desde tu ubicación en el mapa.", "Plot the journey from your location on the map."),
                           icono: "arrow.triangle.turn.up.right.diamond.fill", principal: false) {
                        abrirDestino(transporte: false)
                    }
                }
                .disabled(lugarCoord == nil || navegando)
                .opacity(lugarCoord == nil ? 0.5 : 1)

                if lugar.esFijo {
                    Label(L.t("Lugar fijo de RutaUTP", "RutaUTP fixed place"), systemImage: "pin.fill")
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                } else {
                    Button(role: .destructive) { confirmarEliminar = true } label: {
                        Label(L.t("Quitar de mis lugares", "Remove from my places"), systemImage: "trash")
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.onSurface)
        .background(Color.appBackground)
        .presentationDragIndicator(.visible)
        .seguirTemaForzado()
        .task(id: intento) { await resolverCoordenadas() }
        .onDisappear { geocoder.cancelGeocode() }
        .confirmationDialog(L.t("¿Quitar este lugar de guardados?", "Remove this saved place?"),
                            isPresented: $confirmarEliminar, titleVisibility: .visible) {
            Button(L.t("Quitar lugar", "Remove place"), role: .destructive) {
                onEliminar()
                dismiss()
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        }
    }

    private func accion(titulo: String, detalle: String, icono: String,
                        principal: Bool, ejecutar: @escaping () -> Void) -> some View {
        Button(action: ejecutar) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.title3)
                    .frame(width: 42, height: 42)
                    .background(principal ? Color.white.opacity(0.16) : Color.appPrimary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(titulo).font(.subheadline.bold())
                    Text(detalle).font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            .padding(16)
            .foregroundStyle(principal ? Color.white : Color.onSurface)
            .background(principal ? Color.appPrimary : Color.surfaceContainerLowest,
                        in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func abrirDestino(transporte: Bool) {
        guard let coord = lugarCoord, !navegando else { return }
        navegando = true
        let destino = DestinoPendiente(titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude)
        if transporte {
            router.lugarCercanoPendiente = destino
        } else {
            router.destinoPendiente = destino
        }
        dismiss()
        router.navigate(to: transporte ? .rutas : .mapaPrincipal)
    }

    @MainActor
    private func resolverCoordenadas() async {
        buscandoCoord = true
        defer { buscandoCoord = false }
        if let coord = lugar.coordinate, CLLocationCoordinate2DIsValid(coord) {
            centrar(coord)
            return
        }
        do {
            let resultados = try await geocoder.geocodeAddressString("\(lugar.direccion), Trujillo, Perú")
            guard !Task.isCancelled,
                  let coord = resultados.first?.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coord) else { return }
            centrar(coord)
        } catch {
            // Sin ubicación válida, las acciones permanecen deshabilitadas.
        }
    }

    private func centrar(_ coord: CLLocationCoordinate2D) {
        lugarCoord = coord
        camera = .region(MKCoordinateRegion(center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
    }
}


#Preview {
    GuardadoView().environmentObject(AppRouter())
}
