//
//  RutasView.swift
//  RutaUTP
//
//  Vista de Rutas (tab "Rutas" del BottomNavBar).
//  - Estado 1 (sin ruta seleccionada): mapa no interactivo + lista de rutas.
//  - Estado 2 (con ruta seleccionada): DetalleRutaView con transición slide.
//

import SwiftUI
import MapKit

// MARK: - Modelo
struct RutaOpcion: Identifiable, Equatable {
    let id: String              // route_id del feed GTFS
    let linea: String           // "C-01"
    let empresa: String         // agencia GTFS
    let recorrido: String       // "Av. Grau → Av. Libertad"
    let frecuenciaMin: Int      // headway GTFS (sale uno cada N min)
    let duracionMin: Int        // duración del viaje según stop_times
    let costo: String           // tarifa fare_attributes
    let numParaderos: Int
    let distanciaKm: Double
    let colorLinea: Color       // route_color del feed
    let shape: [CLLocationCoordinate2D]   // recorrido real (shapes.txt)
    let paraderos: [ParaderoGTFS]         // paraderos en orden (stops + stop_times)
    let paradaInicio: String
    let paradaFin: String

    var frecuenciaTexto: String {
        frecuenciaMin > 0 ? L.t("cada \(frecuenciaMin) min", "every \(frecuenciaMin) min") : "—"
    }

    var tiempoTexto: String {
        duracionMin > 0 ? "\(duracionMin) min" : "—"
    }

    // Identidad por route_id: el shape no participa en la comparación.
    static func == (lhs: RutaOpcion, rhs: RutaOpcion) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ViewModel (carga GTFS)
@MainActor
final class RutasViewModel: ObservableObject {
    @Published private(set) var rutas: [RutaOpcion] = []
    @Published private(set) var cargando: Bool = true
    @Published var textoBusqueda: String = ""

    /// Filtro "rutas que pasan cerca de X" (activado desde Guardado).
    @Published var filtroCerca: DestinoPendiente?
    @Published private(set) var distanciaALugar: [String: Double] = [:]

    static let radioCercaMetros: Double = 300

    var rutasFiltradas: [RutaOpcion] {
        if filtroCerca != nil {
            return rutas
                .filter { (distanciaALugar[$0.id] ?? .infinity) <= Self.radioCercaMetros }
                .sorted { (distanciaALugar[$0.id] ?? .infinity) < (distanciaALugar[$1.id] ?? .infinity) }
        }
        let t = textoBusqueda.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return rutas }
        return rutas.filter {
            $0.linea.localizedCaseInsensitiveContains(t)
            || $0.empresa.localizedCaseInsensitiveContains(t)
            || $0.recorrido.localizedCaseInsensitiveContains(t)
        }
    }

    /// Texto "a X m del lugar" para la card bajo el filtro.
    func distanciaTexto(ruta: RutaOpcion) -> String? {
        guard filtroCerca != nil, let d = distanciaALugar[ruta.id] else { return nil }
        return d < 1000 ? L.t("a \(Int((d / 10).rounded() * 10)) m del lugar", "\(Int((d / 10).rounded() * 10)) m from place")
                        : String(format: "a %.1f km del lugar", d / 1000)
    }

    func cargar() async {
        guard cargando else { return }
        let feed = await GTFSRepository.shared.rutas()
        rutas = Self.convertir(feed)
        cargando = false
    }

    /// Convierte el feed GTFS en el modelo de lista. Reutilizado por
    /// GuardadoView para las líneas guardadas.
    static func convertir(_ feed: [RutaGTFS]) -> [RutaOpcion] {
        feed.map { ruta in
            RutaOpcion(
                id: ruta.id,
                linea: ruta.linea,
                empresa: ruta.empresa,
                recorrido: ruta.recorrido,
                frecuenciaMin: ruta.headwayMin,
                duracionMin: ruta.duracionMin,
                costo: ruta.precioTexto,
                numParaderos: ruta.paraderos.count,
                distanciaKm: ruta.distanciaKm,
                colorLinea: ruta.color,
                shape: ruta.shape,
                paraderos: ruta.paraderos,
                paradaInicio: ruta.paraderos.first?.nombre ?? L.t("Paradero inicial", "First stop"),
                paradaFin: ruta.paraderos.last?.nombre ?? L.t("Paradero final", "Last stop")
            )
        }
    }

    /// Activa el filtro "cerca de": mide la distancia de cada shape al lugar.
    func activarFiltroCerca(destino: DestinoPendiente) {
        filtroCerca = destino
        var distancias: [String: Double] = [:]
        for ruta in rutas where ruta.shape.count >= 2 {
            var minima = Double.greatestFiniteMagnitude
            for punto in ruta.shape {
                let d = PolylineMatching.distanceMeters(punto, destino.coordinate)
                if d < minima { minima = d }
                if d < Self.radioCercaMetros { break }   // ya califica; no seguir
            }
            distancias[ruta.id] = minima
        }
        distanciaALugar = distancias
    }

    func limpiarFiltroCerca() {
        filtroCerca = nil
        distanciaALugar = [:]
    }
}

// MARK: - Vista principal
struct RutasView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel = RutasViewModel()
    @State private var rutaSeleccionada: RutaOpcion? = nil

    #if DEBUG
    @State private var debugExplorador: Bool = false
    @State private var debugNavegacion: Bool = false
    #endif

    private let tabBarHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {
            if let ruta = rutaSeleccionada {
                DetalleRutaView(ruta: ruta, onBack: {
                    withAnimation(.spring(response: 0.3)) { rutaSeleccionada = nil }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else {
                listaScreen
                    .transition(.opacity)
            }
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.3), value: rutaSeleccionada == nil)
        .task {
            await viewModel.cargar()
            procesarHookDebug()
            consumirLugarCercano()
        }
        .onChange(of: router.lugarCercanoPendiente) { _ in
            consumirLugarCercano()
        }
        #if DEBUG
        .fullScreenCover(isPresented: $debugExplorador) {
            if let ruta = rutaSeleccionada { ExploradorRutaView(ruta: ruta) }
        }
        .fullScreenCover(isPresented: $debugNavegacion) {
            if let ruta = rutaSeleccionada {
                NavegacionRutaView(ruta: ruta, onFinish: { debugNavegacion = false })
            }
        }
        #endif
    }

    /// Recibe el "Buscar transporte cercano" de Guardado y filtra el GTFS.
    private func consumirLugarCercano() {
        guard let lugar = router.lugarCercanoPendiente else { return }
        router.lugarCercanoPendiente = nil
        viewModel.limpiarFiltroCerca()
        viewModel.textoBusqueda = ""
        viewModel.activarFiltroCerca(destino: lugar)
    }

    #if DEBUG
    /// Hook de pruebas: `--ruta <n>` abre el detalle; `--vista explorador|navegacion`
    /// abre esa pantalla directamente sobre la ruta elegida.
    private func procesarHookDebug() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ruta"), i + 1 < args.count,
              let indice = Int(args[i + 1]),
              viewModel.rutas.indices.contains(indice) else { return }
        rutaSeleccionada = viewModel.rutas[indice]
        if let j = args.firstIndex(of: "--vista"), j + 1 < args.count {
            switch args[j + 1] {
            case "explorador":  debugExplorador = true
            case "navegacion":  debugNavegacion = true
            default: break
            }
        }
    }
    #else
    private func procesarHookDebug() {}
    #endif

    // MARK: - Lista screen
    private var listaScreen: some View {
        VStack(spacing: 0) {
            // Header
            header
            buscador
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    RutasMapView()
                        .frame(height: 280)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.signable("rutas.elegir", "Elige tu ruta", "Pick your route"))
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                    .seniable("rutas.elegir")
                                Text(viewModel.cargando
                                     ? L.t("Cargando rutas oficiales…", "Loading official routes…")
                                     : (viewModel.filtroCerca != nil
                                        ? L.t("Líneas que pasan cerca de", "Lines passing near") + " \(viewModel.filtroCerca!.titulo)"
                                        : L.t("\(viewModel.rutas.count) rutas oficiales · ordenadas por cercanía a UTP", "\(viewModel.rutas.count) official routes · sorted by distance to UTP")))
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                        }
                        .padding(.top, 20)

                        if viewModel.cargando {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Parseando feed GTFS…")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else if viewModel.rutasFiltradas.isEmpty {
                            Text(viewModel.filtroCerca != nil
                                 ? L.t("Ninguna línea pasa a menos de \(Int(RutasViewModel.radioCercaMetros)) m de este lugar", "No line passes within \(Int(RutasViewModel.radioCercaMetros)) m of this place")
                                 : "No hay rutas que coincidan con “\(viewModel.textoBusqueda)”")
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .multilineTextAlignment(.center)
                        } else {
                            ForEach(viewModel.rutasFiltradas) { ruta in
                                RutaOpcionCard(ruta: ruta, distanciaLugar: viewModel.distanciaTexto(ruta: ruta))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3)) {
                                            rutaSeleccionada = ruta
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, tabBarHeight + 30)
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Buscador de rutas
    private var buscador: some View {
        VStack(spacing: 8) {
            if let cerca = viewModel.filtroCerca {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L.t("Líneas cerca de", "Lines near") + " \(cerca.titulo)")
                            .font(.bodySm)
                            .fontWeight(.semibold)
                            .foregroundStyle(.onPrimaryContainer)
                        Text(String(format: L.t("%1$d of %2$d routes pass within %3$d m", "%1$d of %2$d routes pass within %3$d m"), viewModel.rutasFiltradas.count, viewModel.rutas.count, Int(RutasViewModel.radioCercaMetros)))
                            .font(.system(size: 10))
                            .foregroundStyle(.onPrimaryContainer.opacity(0.8))
                    }
                    Spacer()
                    Button {
                        withAnimation { viewModel.limpiarFiltroCerca() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.onPrimaryContainer.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar filtro")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primaryContainer)
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                    TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $viewModel.textoBusqueda)
                        .font(.bodySm)
                        .autocorrectionDisabled()
                    if !viewModel.textoBusqueda.isEmpty {
                        Button {
                            viewModel.textoBusqueda = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.40), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bus.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text(L.signable("rutas.titulo", "Rutas", "Routes"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
                .seniable("rutas.titulo")
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Ruta Opcion Card
private struct RutaOpcionCard: View {
    let ruta: RutaOpcion
    var distanciaLugar: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(ruta.colorLinea)
                .frame(width: 4, height: 56)

            ZStack {
                Circle()
                    .fill(ruta.colorLinea.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(ruta.linea)
                    .font(.system(size: 14, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(ruta.colorLinea)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ruta.empresa)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                    .lineLimit(1)
                Text(ruta.recorrido)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
                if let distanciaLugar {
                    Text(distanciaLugar)
                        .font(.labelCapsSm)
                        .foregroundStyle(ruta.colorLinea)
                        .lineLimit(1)
                        .appTracking(AppTracking.wideLabel)
                } else {
                    Text(L.t("\(ruta.numParaderos) paraderos", "\(ruta.numParaderos) stops") + " · \(String(format: "%.1f", ruta.distanciaKm)) km")
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant.opacity(0.8))
                        .lineLimit(1)
                        .appTracking(AppTracking.wideLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ruta.frecuenciaTexto)
                    .font(.bodyMdMedium)
                    .foregroundStyle(ruta.colorLinea)
                Text(L.t("frecuencia", "frequency"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.40), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Mapa no interactivo para RutasView
private struct RutasMapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )
    private let marcadores: [MapaAnotacion] = [
        MapaAnotacion(id: 1, lat: -8.098247879173792, lon: -79.03818104755645, tipo: .utp),
        MapaAnotacion(id: 2, lat: -8.1180, lon: -79.0350, tipo: .usuario)
    ]

    var body: some View {
            Map(coordinateRegion: $region, annotationItems: marcadores) { m in
            MapAnnotation(coordinate: m.coordinate) {
                switch m.tipo {
                case .utp:          MarcadorUTP()
                case .usuario:      PulsingUserMarker()
                case .bus:           EmptyView()
                case .usuarioReal:   EmptyView()    // No se dibuja en RutasView (pantalla de listado).
                case .conductor:    EmptyView()    // Idem: solo aplica en vista de tracking real.
                case .busqueda:     EmptyView()
                }
            }
        }
        .disabled(true)
        .overlay(
            // Gradient fade al bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.appBackground.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .allowsHitTesting(false)
            }
        )
    }
}

// MARK: - Detalle de la ruta (sub-vista con back)
private struct DetalleRutaView: View {
    let ruta: RutaOpcion
    let onBack: () -> Void

    @State private var showCarPlay: Bool = false
    @State private var showExplorador: Bool = false
    private let tabBarHeight: CGFloat = 64
    private let ctaHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Mapa con el recorrido real: tocable → explorador fullscreen
                    RutaMapKitView(ruta: ruta)
                        .overlay(alignment: .bottom) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .bold))
                                Text(L.t("Toca para ver el recorrido completo", "Tap to see the full route"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(.bottom, 10)
                        }
                        .frame(height: 280)
                        .contentShape(Rectangle())
                        .onTapGesture { showExplorador = true }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(spacing: 20) {
                        // Info card
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ruta.colorLinea)
                                .frame(width: 6, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(ruta.empresa)")
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                Text(ruta.recorrido)
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(L.signable("rutas.frecuencia", "FRECUENCIA", "FREQUENCY"))
                                    .font(.labelCapsMd)
                                    .foregroundStyle(.onPrimaryContainer)
                                    .appTracking(AppTracking.wideLabel)
                                    .seniable("rutas.frecuencia")
                                Text(ruta.frecuenciaTexto)
                                    .font(.displayNumberMd)
                                    .foregroundStyle(.onPrimaryContainer)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primaryContainer))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.surfaceContainerLowest)
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                        )

                        // Stats grid (datos del feed GTFS)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            StatTile(icon: "clock.fill", iconColor: .appPrimary,
                                     label: L.signable("rutas.tiempo", "TIEMPO VIAJE", "TRIP TIME"), value: ruta.tiempoTexto)
                                .seniable("rutas.tiempo")
                            StatTile(icon: "creditcard.fill", iconColor: .appPrimary,
                                     label: L.signable("rutas.costo", "COSTO", "FARE"), value: ruta.costo)
                                .seniable("rutas.costo")
                            StatTile(icon: "mappin.and.ellipse", iconColor: .appPrimary,
                                     label: L.signable("rutas.paraderos", "PARADEROS", "STOPS"), value: "\(ruta.numParaderos)")
                                .seniable("rutas.paraderos")
                            StatTile(icon: "point.topleft.down.curvedto.point.bottomright.up",
                                     iconColor: .secondary,
                                     label: L.signable("rutas.recorrido", "RECORRIDO", "DISTANCE"), value: String(format: "%.1f km", ruta.distanciaKm))
                                .seniable("rutas.recorrido")
                        }

                        // Pasos
                        VStack(alignment: .leading, spacing: 18) {
                            Text(L.signable("rutas.guia", "Guía paso a paso", "Step-by-step guide"))
                                .font(.headlineXs)
                                .foregroundStyle(.onSurface)
                                .seniable("rutas.guia")

                            VStack(spacing: 0) {
                                pasoRow("1", L.t("Ve al paradero \(ruta.paradaInicio)", "Go to \(ruta.paradaInicio) stop"),
                                        L.t("Sale uno \(ruta.frecuenciaTexto)", "One departs \(ruta.frecuenciaTexto)"),
                                        "figure.walk", .surfaceContainerHighest, .onSurface, isLast: false)
                                pasoRow("2", L.t("Sube a la línea \(ruta.linea)", "Board line \(ruta.linea)"),
                                        L.t("\(ruta.empresa) • \(ruta.tiempoTexto) de viaje", "\(ruta.empresa) • \(ruta.tiempoTexto) trip"),
                                        "bus.fill", ruta.colorLinea, .white, isLast: false)
                                pasoRow("3", L.t("Baja en \(ruta.paradaFin)", "Get off at \(ruta.paradaFin)"),
                                        L.t("Fin del recorrido", "End of the route"),
                                        "flag.checkered.fill", .tertiary, .white, isLast: true)
                            }
                        }

                        // Botón de iniciar navegación integrado al final del scroll
                        ctaButton
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .padding(.bottom, bottomSafeArea() > 0 ? bottomSafeArea() + 64 : 68)
        }
        .background(Color.appBackground.ignoresSafeArea())
        // Explorador del recorrido (se abre tocando el mapa)
        .fullScreenCover(isPresented: $showExplorador) {
            ExploradorRutaView(ruta: ruta)
        }
        // Navegación activa sobre el recorrido GTFS
        .fullScreenCover(isPresented: $showCarPlay) {
            NavegacionRutaView(
                ruta: ruta,
                onFinish: { showCarPlay = false }
            )
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volver")

            Image(systemName: "bus.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Ruta \(ruta.linea)")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
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

    // MARK: - CTA (dentro del ScrollView)
    private var ctaButton: some View {
        Button {
            showCarPlay = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                Text(L.signable("nav.iniciar", "Iniciar Navegación", "Start Navigation"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryContainer)
                    .shadow(color: .primaryContainer.opacity(0.35), radius: 12, x: 0, y: 6)
            )
            .contentShape(Rectangle()) // ✅ CORREGIDO V3
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Iniciar navegación")
        .seniable("nav.iniciar")
    }

    private func bottomSafeArea() -> CGFloat {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first
        else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private func pasoRow(_ n: String, _ title: String, _ subtitle: String,
                          _ icon: String, _ bg: Color, _ fg: Color, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(bg).frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(fg)
                }
                if !isLast {
                    Rectangle().fill(Color.surfaceContainerHighest)
                        .frame(width: 2, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)")
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
                Text(subtitle)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(.top, 1)
            Spacer()
        }
    }
}

// MARK: - Stat tile
private struct StatTile: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(value)
                    .font(.headlineXs)
                    .foregroundStyle(iconColor == .secondary ? Color.secondary : Color.onSurface)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
    }
}

#Preview {
    RutasView().environmentObject(AppRouter())
}