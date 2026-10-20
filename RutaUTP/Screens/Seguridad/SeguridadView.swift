//
//  SeguridadView.swift
//  RutaUTP
//
//  Pantalla de seguridad; reserva la altura real de la barra inferior.
//

import SwiftUI
import UIKit
import MapKit

struct SeguridadView: View {
    /// La misma instancia que Mapa y el rastreo; el valor por defecto es para previews.
    var locationService: LocationServiceProtocol = LocationService()
    @EnvironmentObject private var router: AppRouter

    @State private var showReportarSheet = false
    @State private var showPublicarComunidad = false
    @State private var showLlamarAlert = false
    @State private var showLlamarContacto = false
    @State private var showConfigurarContacto = false
    @State private var seccion: Seccion = .ayuda
    @Namespace private var indicadorSeccion
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var categoriaCercana: CategoriaAyudaCercana?
    @AppStorage(ContactoEmergencia.claveNombre) private var contactoNombre = ""
    @AppStorage(ContactoEmergencia.claveNumero) private var contactoNumero = ""
    @AppStorage(ContactoEmergencia.claveParentesco) private var contactoParentesco = ""
    @AppStorage(ContactoEmergencia.claveAlternativo) private var contactoAlternativo = ""
    @State private var selectedReporte: ReporteComunidad?
    @State private var comentarAlAbrir = false
    /// Likes/dislikes de la sección Comunidad (compartido entre las cards
    /// y el detalle para que el conteo coincida).
    @StateObject private var reacciones = ComunidadReacciones.compartida

    // Paraderos iluminados (reales del feed GTFS) + mapa fullscreen
    @State private var paraderosIluminados: [ParaderoGTFS] = []
    @State private var showParaderosMap = false
    @State private var catalogoParaderos: [ParaderoGTFS] = []
    @State private var catalogoLineas: [RutaGTFS] = []
    @State private var errorCargaParaderos: String?
    @State private var revisionCatalogo = 0
    @State private var cargandoParaderos = false

    /// Se conservan los paraderos guardados y sus datos; los tiles de lugares
    /// personales se consultan desde Guardado.
    @StateObject private var lugaresVM = SeguridadLugaresModel()
    @State private var selectedLugar: LugarGuardado?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    @Environment(\.bottomNavBarHeight) private var tabBarHeight

    private enum Seccion: String, CaseIterable, Identifiable {
        case ayuda, comunidad
        var id: String { rawValue }
        var titulo: String {
            self == .ayuda ? L.t("Ayuda", "Help") : L.t("Comunidad", "Community")
        }
        var icono: String { self == .ayuda ? "heart.text.square" : "person.2" }
    }

    /// DEBUG: `--comunidad` deja solo la sección de comunidad y `--zonas` solo
    /// la de paraderos y avisos. Van bajo `#if DEBUG` para que la lectura de
    /// argumentos no viaje al binario de distribución: en Release son `false`.
    /// Antes cada uno tenía además una propiedad de instancia que solo devolvía
    /// la estática; se usan directamente con `Self.`.
    private static let soloComunidadDebug: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--comunidad")
        #else
        false
        #endif
    }()
    private static let soloZonasDebug: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--zonas")
        #else
        false
        #endif
    }()

    private static let reportes = ReporteComunidad.publicacionesDemo

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            // Contenido scrollable
            VStack(spacing: 0) {
                header
                greetingCard
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                selectorSeccion
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 24) {
                        if Self.soloComunidadDebug {
                            comunidadSection
                        } else if Self.soloZonasDebug {
                            paraderosSection
                            AvisosLineasSeguridad(rutas: catalogoLineas)
                        } else if seccion == .ayuda {
                            accesosRapidos
                            cercaDeTi
                            paraderosSection
                            AvisosLineasSeguridad(rutas: catalogoLineas)
                            paraderosGuardadosSection
                        } else {
                            comunidadSection
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, tabBarHeight)

            // Navbar
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            lugaresVM.cargar()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--paraderos") {
                showParaderosMap = true
            }
            // Las dos hojas del formulario comparten piezas con ReportarSheet;
            // estos hooks permiten mirarlas sin tener que navegar hasta ellas.
            if ProcessInfo.processInfo.arguments.contains("--reportar") {
                showReportarSheet = true
            }
            if ProcessInfo.processInfo.arguments.contains("--publicar") {
                showPublicarComunidad = true
            }
            #endif
        }
        .task(id: revisionCatalogo) {
            // El fallo se muestra y solo el botón solicita una carga nueva.
            cargandoParaderos = true
            errorCargaParaderos = nil
            do {
                let feed = try await TransporteApp.repositorio.cargarRutas(reintentar: revisionCatalogo > 0)
                guard !Task.isCancelled else { return }
                catalogoLineas = feed
                paraderosIluminados = ParaderosIluminados.seleccionar(feed,
                    cercaDe: TransporteApp.referenciaInicio)
                catalogoParaderos = feed.flatMap(\.paraderos)
            } catch {
                guard !Task.isCancelled else { return }
                errorCargaParaderos = (error as? FalloCargaGTFS)?.mensajeUsuario
                    ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
            }
            cargandoParaderos = false
        }
        // Mapa fullscreen de paraderos iluminados (desde el banner)
        .fullScreenCover(isPresented: $showParaderosMap, onDismiss: { lugaresVM.cargar() }) {
            ParaderosIluminadosView(paraderos: paraderosIluminados, locationService: locationService)
        }
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet(locationService: locationService)
                .presentationDetents([.medium, .large])
        }
        // AÑADIR (Comunidad): sheet propio, distinto al de reportar, con foto
        // (cámara/galería) y ubicación en Apple Maps.
        .sheet(isPresented: $showPublicarComunidad) {
            PublicarComunidadSheet(locationService: locationService)
                .presentationDetents([.large])
        }
        .sheet(item: $selectedReporte) { reporte in
            ReporteDetailSheet(reporte: reporte, reacciones: reacciones, comentarAlAbrir: comentarAlAbrir)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $categoriaCercana) { categoria in
            AyudaCercanaSheet(categoria: categoria, locationService: locationService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showConfigurarContacto) {
            ContactoEmergenciaSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(L.t("Llamar a mi contacto", "Call my contact"), isPresented: $showLlamarContacto) {
            Button(L.t("Llamar", "Call")) {
                if let numero = numeroContacto, let url = URL(string: "tel://" + numero) {
                    UIApplication.shared.open(url)
                }
            }
            if let alternativo = ContactoEmergencia.telefonoValido(contactoAlternativo), alternativo != numeroContacto {
                Button(L.t("Llamar al otro número", "Call the alternate number")) {
                    if let url = URL(string: "tel://" + alternativo) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        } message: {
            Text(detalleContacto)
        }
        .alert(L.t("Llamar al 105", "Call 105"), isPresented: $showLlamarAlert) {
            Button(L.t("Llamar", "Call")) {
                if let url = URL(string: "tel://105") {
                    UIApplication.shared.open(url)
                }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        } message: {
            Text(L.t("Se abrirá la aplicación de teléfono para llamar a la central de emergencias.", "The Phone app will open to call emergency services."))
        }
        // Detalle del lugar (mismo sheet que Guardado: info + acciones reales)
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    lugaresVM.eliminar(lugar)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Cabecera y ayuda directa
    private var header: some View {
        HStack {
            Text(L.t("Seguridad", "Safety"))
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 20)
        .frame(height: 54)
    }

    private var selectorSeccion: some View {
        HStack(spacing: 20) {
            ForEach(Seccion.allCases) { opcion in
                let seleccionada = seccion == opcion
                Button {
                    AppHaptics.selection()
                    withAnimation(reducirMovimiento ? nil : .easeInOut(duration: 0.2)) {
                        seccion = opcion
                    }
                } label: {
                    Label(opcion.titulo, systemImage: opcion.icono)
                        .font(.bodyMdMedium)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(seleccionada ? acento : Color.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if seleccionada {
                                Capsule().fill(acento).frame(height: 3)
                                    .matchedGeometryEffect(id: "seccion", in: indicadorSeccion)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(seleccionada ? .isSelected : [])
            }
        }
        .background(alignment: .bottom) {
            Color.outlineVariant.opacity(0.45).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var greetingCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { contexto in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    saludoYFecha(contexto.date)
                    Spacer(minLength: 0)
                    reloj(contexto.date)
                }
                VStack(alignment: .leading, spacing: 8) {
                    saludoYFecha(contexto.date)
                    reloj(contexto.date)
                }
            }
        }
    }

    private func saludoYFecha(_ fecha: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(saludoDinamico(fecha)).font(.headlineBody).foregroundStyle(Color.onSurface)
            Text(FormatoFecha.fecha(fecha).capitalized)
                .font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func reloj(_ fecha: Date) -> some View {
        Text(FormatoFecha.fecha(fecha, plantilla: "jmm"))
            .font(.title3.weight(.semibold)).monospacedDigit()
            .foregroundStyle(acento)
            .fixedSize()
    }

    private var numeroContacto: String? { ContactoEmergencia.telefonoValido(contactoNumero) }

    private var detalleContacto: String {
        var datos = [contactoNombre, numeroContacto ?? ""]
        if let alternativo = ContactoEmergencia.telefonoValido(contactoAlternativo), alternativo != numeroContacto {
            datos.append(L.t("Teléfono alternativo", "Alternate phone") + ": " + alternativo)
        }
        return datos.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var accesosRapidos: some View {
        VStack(spacing: 10) {
            Button {
                SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "seguridad.emergencia") {
                    showLlamarAlert = true
                }
            } label: {
                Label(L.signable("seguridad.emergencia", "Emergencias", "Emergency"), systemImage: "phone.fill")
                    .font(.bodyMdMedium)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, 16)
                    .foregroundStyle(Color.onPrimaryFill)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Llamar al 105 emergencias", "Call emergency services at 105"))
            .seniable("seguridad.emergencia", conGesto: false)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                ZStack(alignment: .topTrailing) {
                    Button {
                        AppHaptics.selection()
                        if numeroContacto == nil { showConfigurarContacto = true }
                        else { showLlamarContacto = true }
                    } label: {
                        contactoLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(numeroContacto == nil
                        ? L.t("Añadir contacto", "Add contact")
                        : L.t("Llamar a mi contacto", "Call my contact"))
                    .accessibilityHint(numeroContacto == nil
                        ? L.t("Configura tu contacto de emergencia", "Set up your emergency contact")
                        : contactoNombre)
                    .contextMenu {
                        Button(L.t("Editar contacto", "Edit contact"), systemImage: "pencil") {
                            showConfigurarContacto = true
                        }
                    }
                    if numeroContacto != nil {
                        Button { showConfigurarContacto = true } label: {
                            Image(systemName: "pencil")
                                .font(.bodySmMedium)
                                .foregroundStyle(acento)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Editar contacto de emergencia", "Edit emergency contact"))
                        .padding(4)
                    }
                }
                Button {
                    SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "seguridad.reportar") {
                        showReportarSheet = true
                    }
                } label: {
                    accesoLabel(L.signable("seguridad.reportar", "Reportar", "Report"), icono: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
                .seniable("seguridad.reportar", conGesto: false)
            }
        }
    }

    private var contactoLabel: some View {
        let nombre = contactoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let iniciales = nombre.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap(\.first).map(String.init).joined().uppercased()
        let relacion = Parentesco(rawValue: contactoParentesco)?.label ?? contactoParentesco
        let detalle = numeroContacto != nil && !nombre.isEmpty
            ? [nombre, relacion].filter { !$0.isEmpty }.joined(separator: " · ")
            : L.t("Mi contacto", "My contact")
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    if numeroContacto != nil, !iniciales.isEmpty {
                        Text(iniciales).font(.bodySmMedium).lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                        Image(systemName: "person.fill").font(.bodySm)
                    }
                }
                .frame(width: 32, height: 32)
                Spacer(minLength: 4)
                Image(systemName: "plus")
                    .font(.bodySmMedium)
                    .opacity(numeroContacto == nil ? 1 : 0)
            }
            .foregroundStyle(acento)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(numeroContacto == nil ? L.t("Añadir contacto", "Add contact") : L.t("Llamar", "Call"))
                    .font(.bodyMdMedium)
                Text(detalle)
                    .font(.bodyXs)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func accesoLabel(_ titulo: String, icono: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icono).font(.title3).foregroundStyle(Color.appPrimary)
            Text(titulo).font(.bodyMdMedium).foregroundStyle(Color.onSurface)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(16)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private var cercaDeTi: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Cerca de ti", "Near you")).font(.title3.weight(.semibold))
                .foregroundStyle(Color.onSurface)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                ForEach(CategoriaAyudaCercana.allCases) { categoria in
                    Button { categoriaCercana = categoria } label: {
                        accesoCercano(categoria.titulo, icono: categoria.icono)
                    }.buttonStyle(.plain)
                }
                Button { showParaderosMap = true } label: {
                    accesoCercano(L.t("Paraderos", "Stops"), icono: "bus")
                }.buttonStyle(.plain)
            }
        }
    }

    private func accesoCercano(_ titulo: String, icono: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icono).font(.title3).foregroundStyle(acento)
            Text(titulo).font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(Rectangle())
    }


    // MARK: - Paraderos
    private var paraderosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bus")
                    .foregroundStyle(acento)
                Text(L.signable("seguridad.rutas_seguras", "Paraderos", "Stops"))
                    .font(.headlineSm)
                    .seniable("seguridad.rutas_seguras", distintivoDx: 10)
            }

            if cargandoParaderos {
                ProgressView(L.t("Cargando paraderos…", "Loading stops…"))
                    .font(.bodySm)
            } else if let errorCargaParaderos {
                Text(L.aviso(errorCargaParaderos)).font(.bodySm).foregroundStyle(Color.appError)
                Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
                    .buttonStyle(.bordered)
            }

            Button {
                AppHaptics.impact(.light)
                showParaderosMap = true
            } label: {
                BannerParaderosPreview(cantidad: paraderosIluminados.count,
                                       paraderos: paraderosIluminados)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Explorar el mapa de paraderos", "Explore the bus stop map"))
        }
    }

    private var paraderosGuardados: [LugarGuardado] {
        lugaresVM.lugares.filter { $0.esParaderoGuardado(en: catalogoParaderos) }
    }

    private var paraderosGuardadosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.appPrimary)
                Text(L.t("Paraderos guardados", "Saved stops")).font(.headlineSm)
                Spacer()
                Text("\(paraderosGuardados.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.onSurfaceVariant)
            }
            if paraderosGuardados.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Guarda un paradero en el mapa y lo encontrarás aquí.",
                             "Save a stop on the map to find it here."))
                        .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                    Button { showParaderosMap = true } label: {
                        Label(L.t("Explorar paraderos", "Explore stops"), systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(paraderosGuardados) { lugar in
                    Button { selectedLugar = lugar } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bus.fill")
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lugar.nombre).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.onSurface).multilineTextAlignment(.leading)
                                Text(L.t("Ver ubicación y opciones", "View location and options"))
                                    .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.onSurfaceVariant)
                        }
                        .padding(14)
                        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Abrir paradero guardado: ", "Open saved stop: ") + lugar.nombre)
                }
            }
        }
    }

    // MARK: - Comunidad (lista de publicaciones demo de Trujillo)
    private var comunidadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.appPrimary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L.signable("seguridad.comunidad", "Comunidad", "Community"))
                            .font(.headlineSm)
                            .seniable("seguridad.comunidad", distintivoDx: 10)
                        Text(L.t("Trujillo · publicaciones de demostración", "Trujillo · demo posts"))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                }
                Spacer()
                Button {
                    showPublicarComunidad = true
                } label: {
                    Text(L.t("AÑADIR", "ADD"))
                        .font(.labelCapsSm)
                        .foregroundStyle(.appPrimary)
                        .appTracking(AppTracking.wideLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Añadir publicación a la comunidad", "Add a community post"))
            }

            tarjetasComunidad
        }
    }



    private var tarjetasComunidad: some View {
        LazyVStack(spacing: 12) {
            ForEach(Self.reportes) { reporte in
                ReporteCard(reporte: reporte, reacciones: reacciones, abrir: {
                    comentarAlAbrir = false
                    selectedReporte = reporte
                }, comentar: {
                    comentarAlAbrir = true
                    selectedReporte = reporte
                })
            }
        }
    }

    // MARK: - Helpers
    private func saludoDinamico(_ fecha: Date) -> String {
        let h = Calendar.current.component(.hour, from: fecha)
        switch h {
        case 5..<12:  return L.t("Buenos días", "Good morning")
        case 12..<19: return L.t("Buenas tardes", "Good afternoon")
        default:      return L.t("Buenas noches", "Good evening")
        }
    }

}

// MARK: - Reportar Sheet
// ReportarSheet vive en Design/Components/ReportarSheet.swift (compartido
// con el Mapa). Ver ahí el diseño completo.
