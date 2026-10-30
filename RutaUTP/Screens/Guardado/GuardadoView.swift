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
    let locationService: LocationServiceProtocol
    @EnvironmentObject private var router: AppRouter
    @Environment(\.bottomNavBarHeight) private var tabBarHeight
    @Environment(\.mainNavigationHostedExternally) private var navigationHostedExternally
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @Namespace private var indicadorTab
    @ScaledMetric(relativeTo: .body) private var tamanoIcono = 20
    @ScaledMetric(relativeTo: .title) private var tamanoEstado = 32
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }
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
    @State private var showParaderosMap = false
    @State private var confirmarReinicioLineas = false
    @State private var errorReinicioLineas = false
    @State private var respaldoLineas: URL?

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
                accionesGuardado
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .lugares: lugaresSection
                        case .lineas:  lineasSection
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.bottom, tabBarHeight)

            if !navigationHostedExternally { BottomNavBar() }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            vm.cargar()
            procesarHookDebug()
        }
        .task { await vm.cargarCatalogo() }
        .alert(L.t("¿Empezar una nueva lista de líneas?", "Start a new saved lines list?"),
               isPresented: $confirmarReinicioLineas) {
            Button(L.t("Respaldar y reiniciar", "Back up and reset"), role: .destructive) {
                do { respaldoLineas = try vm.respaldarYReiniciarLineas() }
                catch { errorReinicioLineas = true }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Se guardará una copia de los datos originales en tus documentos y la lista de líneas quedará vacía. Tus lugares no cambian.",
                     "A copy of the original data will be saved in your documents and the saved lines list will be empty. Your saved places stay the same."))
        }
        .alert(L.t("No se pudo crear el respaldo", "Unable to create backup"), isPresented: $errorReinicioLineas) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Comprueba el espacio disponible e inténtalo de nuevo.",
                     "The original data has been preserved. Check available storage and try again."))
        }
        .sheet(isPresented: $showAddLugar) {
            AddLugarSheet(locationService: locationService) { vm.añadirLugar($0) }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) { vm.eliminarLugar(lugar) }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddLinea) {
            AddLineaSheet(
                catalogo: vm.lineasGTFS,
                cargando: !vm.catalogoCargado || vm.cargandoCatalogo,
                errorCatalogo: vm.errorCatalogo,
                onRetry: { Task { await vm.cargarCatalogo(reintentar: true) } },
                yaGuardadas: vm.idsLineasGuardadas
            ) { vm.añadirLinea($0) }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLinea) { linea in
            LineaDetailSheet(linea: linea,
                             onExplorar: {
                                 selectedLinea = nil
                                 rutaParaExplorar = linea
                             },
                             onQuitar: { vm.eliminarLinea(linea) })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $rutaParaExplorar) { linea in
            ExploradorRutaView(ruta: linea, locationService: locationService)
        }
        .fullScreenCover(isPresented: $showParaderosMap, onDismiss: { vm.cargar() }) {
            ParaderosIluminadosView(paraderos: [], locationService: locationService)
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

    // MARK: - Cabecera y acciones
    private var header: some View {
        HStack {
            Text(L.signable("guardado.titulo", "Guardado", "Saved"))
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .seniable("guardado.titulo", distintivoDx: 10)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 28)
            Image(systemName: "bookmark.fill")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    private var accionesGuardado: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(resumenGuardado)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            botonAñadir
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var resumenGuardado: String {
        if selectedTab == .lugares {
            guard !vm.datosLugaresInvalidos else { return L.t("Lugares", "Places") }
            return vm.lugares.count == 1 ? L.t("1 guardado", "1 saved")
                : L.f("{0} guardados", "{0} saved", ["\(vm.lugares.count)"])
        }
        guard vm.catalogoCargado, !vm.cargandoCatalogo,
              vm.errorCatalogo == nil, !vm.datosLineasInvalidos else { return L.t("Líneas", "Lines") }
        return vm.lineasGuardadas.count == 1 ? L.t("1 línea", "1 line")
            : L.f("{0} líneas", "{0} lines", ["\(vm.lineasGuardadas.count)"])
    }

    /// Botón "Añadir" contextual: añade lugar o línea según el tab activo.
    private var botonAñadir: some View {
        Button {
            AppHaptics.impact(.medium)
            // Modo Señas: deja ver el videito antes de que el sheet tape el miniplayer.
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: selectedTab == .lugares ? "guardado.anadir_lugar" : "guardado.anadir_linea") {
                withAnimation(reducirMovimiento ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                    switch selectedTab {
                    case .lugares: showAddLugar = true
                    case .lineas:  showAddLinea = true
                    }
                }
            }
        } label: {
            Label {
                Text(selectedTab == .lugares
                     ? L.signable("guardado.anadir_lugar", "Añadir lugar", "Add place")
                     : L.signable("guardado.anadir_linea", "Añadir línea", "Add line"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "plus").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(Color.primaryFill)
        .foregroundStyle(Color.onPrimaryFill)
        .disabled(selectedTab == .lugares ? vm.datosLugaresInvalidos : vm.datosLineasInvalidos)
        .accessibilityLabel(selectedTab == .lugares ? L.t("Añadir lugar guardado", "Add saved place") : L.t("Añadir línea guardada", "Add saved line"))
        .seniable(selectedTab == .lugares ? "guardado.anadir_lugar" : "guardado.anadir_linea", conGesto: false)
    }

    // MARK: - Tabs
    private var tabs: some View {
        HStack(spacing: 20) {
            ForEach(Tab.allCases) { t in
                Button {
                    AppHaptics.selection()
                    let clave = t == .lugares ? "guardado.lugares" : "guardado.lineas"
                    SeniasPresenter.shared.ejecutarTrasVerSenia(clave: clave) {
                        withAnimation(reducirMovimiento ? nil : .easeInOut(duration: 0.2)) { selectedTab = t }
                    }
                } label: {
                    Label {
                        Text(t == .lugares
                             ? L.signable("guardado.lugares", "Lugares", "Places")
                             : L.signable("guardado.lineas", "Líneas", "Lines"))
                            .seniable(t == .lugares ? "guardado.lugares" : "guardado.lineas",
                                      distintivoDx: 10, conGesto: false)
                    } icon: {
                        Image(systemName: t == .lugares ? "mappin.and.ellipse" : "bus")
                            .accessibilityHidden(true)
                    }
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(selectedTab == t ? acento : Color(uiColor: .secondaryLabel))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if selectedTab == t {
                            Capsule().fill(acento).frame(height: 3)
                                .matchedGeometryEffect(id: "tab", in: indicadorTab)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == t ? .isSelected : [])
            }
        }
        .background(alignment: .bottom) {
            Color(uiColor: .separator).opacity(0.35).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Lugares
    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.datosLugaresInvalidos {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("No se pudieron leer tus lugares. Los datos originales se conservaron; no se guardarán cambios hasta poder leerlos.",
                             "Your places could not be read. The original data was preserved; changes will not be saved until it can be read."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.t("Reintentar lectura", "Retry reading")) {
                        vm.reintentarLecturaLugares()
                    }
                    .buttonStyle(.bordered)
                    .tint(acento)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        encabezadoLugares(L.t("Lugares guardados", "Saved places"),
                                          cantidad: vm.lugaresPersonales.count)
                        if vm.lugaresPersonales.isEmpty {
                            emptyState(icono: "bookmark.slash",
                                       titulo: L.t("Aún no tienes lugares guardados", "No saved places yet"),
                                       subtitulo: L.t("Toca Añadir lugar para guardar tu primer lugar.", "Tap Add place to save your first place."))
                        } else {
                            filasLugares(vm.lugaresPersonales)
                                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    paraderosGuardadosSection
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func encabezadoLugares(_ titulo: String, cantidad: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(titulo)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let cantidad {
                Text("\(cantidad)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var paraderosGuardadosSection: some View {
        let paraderos = vm.paraderosGuardados
        let catalogoDisponible = vm.catalogoCargado && !vm.cargandoCatalogo && vm.errorCatalogo == nil
        return VStack(alignment: .leading, spacing: 12) {
            encabezadoLugares(L.t("Paraderos guardados", "Saved stops"),
                              cantidad: catalogoDisponible || !paraderos.isEmpty ? paraderos.count : nil)
            VStack(alignment: .leading, spacing: 0) {
                if !paraderos.isEmpty {
                    filasLugares(paraderos, esParadero: true)
                    Divider().padding(.horizontal, 16)
                }
                if !vm.catalogoCargado || vm.cargandoCatalogo {
                    ProgressView(L.t("Cargando paraderos…", "Loading stops…"))
                        .font(.subheadline)
                        .tint(acento)
                        .padding(16)
                } else if let error = vm.errorCatalogo {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error.mensajeUsuario)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L.t("Reintentar", "Try again")) {
                            Task { await vm.cargarCatalogo(reintentar: true) }
                        }
                        .buttonStyle(.bordered)
                        .tint(acento)
                    }
                    .padding(16)
                } else if paraderos.isEmpty {
                    Text(L.t("Guarda un paradero en el mapa y lo encontrarás aquí.",
                             "Save a stop on the map to find it here."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding([.horizontal, .top], 16)
                }
                Button {
                    AppHaptics.impact(.light)
                    showParaderosMap = true
                } label: {
                    Label(L.t("Explorar paraderos", "Explore stops"), systemImage: "map")
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(acento)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func filasLugares(_ lugares: [LugarGuardado], esParadero: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(lugares) { lugar in
                if lugar.id != lugares.first?.id {
                    Divider().padding(.leading, 72).padding(.trailing, 16)
                }
                lugarRow(lugar, esParadero: esParadero)
            }
        }
    }

    private func lugarRow(_ lugar: LugarGuardado, esParadero: Bool) -> some View {
        Button {
            AppHaptics.selection()
            selectedLugar = lugar
        } label: {
            HStack(spacing: 12) {
                iconoLugar(lugar, esParadero: esParadero)
                VStack(alignment: .leading, spacing: 5) {
                    Text(lugar.nombre)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !lugar.direccion.isEmpty {
                        Text(lugar.direccion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    if lugar.esFrecuente {
                        Label(L.t("Frecuente", "Frequent"), systemImage: "star.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lugar.nombre)
        .accessibilityValue(lugar.direccion + (lugar.esFrecuente ? L.t(". Frecuente", ". Frequent") : ""))
        .accessibilityHint(esParadero
                           ? L.t("Muestra las opciones del paradero guardado", "Shows saved stop options")
                           : L.t("Muestra las opciones del lugar guardado", "Shows saved place options"))
    }

    private func iconoLugar(_ lugar: LugarGuardado, esParadero: Bool) -> some View {
        Image(systemName: esParadero && lugar.iconoPersonalizado == nil ? "bus" : lugar.icono)
            .font(.system(size: min(tamanoIcono, 24), weight: .medium))
            .foregroundStyle(lugar.esFijo || esParadero ? acento : Color(uiColor: .secondaryLabel))
            .frame(width: 44, height: 44)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Líneas guardadas
    private var lineasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let respaldoLineas {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("El original se guardó antes de reiniciar las líneas.",
                             "The original data was backed up before resetting saved lines."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ShareLink(item: respaldoLineas) {
                        Label(L.t("Compartir respaldo", "Share backup"), systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline.weight(.medium))
                    .tint(acento)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            if vm.datosLineasInvalidos {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("No se pudieron leer tus líneas guardadas. Los datos originales se conservan y los cambios están bloqueados.",
                             "Your saved lines could not be read. The original data has been preserved and changes are blocked."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.t("Reintentar lectura", "Retry reading")) { vm.cargarLineas() }
                        .buttonStyle(.bordered)
                        .tint(acento)
                    Button(L.t("Respaldar y reiniciar líneas", "Back up and reset saved lines"), role: .destructive) {
                        confirmarReinicioLineas = true
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            if !vm.catalogoCargado || vm.cargandoCatalogo {
                ProgressView(L.t("Cargando líneas…", "Loading routes…"))
                    .font(.subheadline)
                    .tint(acento)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if let error = vm.errorCatalogo {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error.mensajeUsuario)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.t("Reintentar", "Try again")) {
                        Task { await vm.cargarCatalogo(reintentar: true) }
                    }
                    .buttonStyle(.bordered)
                    .tint(acento)
                    .disabled(vm.cargandoCatalogo)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if vm.lineasGuardadas.isEmpty {
                if !vm.datosLineasInvalidos {
                    emptyState(icono: "bus.badge.clock",
                               titulo: L.t("No tienes líneas guardadas", "No saved lines"),
                               subtitulo: L.t("Toca Añadir línea para consultar el catálogo oficial.", "Tap Add line to browse the official catalog."))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.lineasGuardadas) { linea in
                        if linea.id != vm.lineasGuardadas.first?.id {
                            Divider().padding(.leading, 32).padding(.trailing, 16)
                        }
                        lineaRow(linea)
                    }
                }
                .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
    }

    private func lineaRow(_ linea: RutaOpcion) -> some View {
        Button {
            AppHaptics.selection()
            selectedLinea = linea
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(linea.colorLinea)
                    .frame(width: 4, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("Línea ", "Line ") + linea.lineaConLetra)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(linea.empresa)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    Text(linea.recorridoLocalizado)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    Label(linea.frecuenciaTexto, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Línea ", "Line ") + linea.lineaConLetra + ", " + linea.empresa)
        .accessibilityValue(linea.recorridoLocalizado + ". " + L.t("frecuencia", "frequency") + ": " + linea.frecuenciaTexto)
    }

    // MARK: - Estados vacíos
    private func emptyState(icono: String, titulo: String, subtitulo: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icono)
                .font(.system(size: min(tamanoEstado, 40), weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(titulo)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitulo)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Sample data
    // El seed vive en LugaresStore (compartido con SeguridadView).
}

#Preview {
    GuardadoView(locationService: LocationService()).environmentObject(AppRouter())
}
