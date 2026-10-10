//
//  SeguridadView.swift
//  RutaUTP
//
//  Pantalla de seguridad. Layout ZStack(alignment: .bottom) + ignoresSafeArea.
//  FAB anclado a navbarHeight + 12 para estar pegado encima de la navbar.
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
    @State private var selectedReporte: ReporteComunidad?
    /// Likes/dislikes de la sección Comunidad (compartido entre las cards
    /// y el detalle para que el conteo coincida).
    @StateObject private var reacciones = ComunidadReacciones()
    @State private var buscandoZona = false
    @State private var errorZona: String?
    @State private var zonaSeleccionada: RutaSegura? = nil  // detalle (alert)

    // Paraderos iluminados (reales del feed GTFS) + mapa fullscreen
    @State private var paraderosIluminados: [ParaderoGTFS] = []
    @State private var showParaderosMap = false
    @State private var catalogoParaderos: [ParaderoGTFS] = []
    @State private var errorCargaParaderos: String?
    @State private var revisionCatalogo = 0
    @State private var cargandoParaderos = false

    /// Lugares guardados, tiles y modo edición (estilo Springboard).
    /// Los datos y sus operaciones viven en el modelo; en la vista solo queda
    /// qué sheet está abierto y qué lugar está seleccionado.
    @StateObject private var lugaresVM = SeguridadLugaresModel()
    @State private var selectedLugar: LugarGuardado?
    @State private var showElegirLugares = false

    private let tabBarHeight: CGFloat = 64

    /// DEBUG: `--comunidad` deja solo la sección de comunidad y `--zonas` solo
    /// la de zonas seguras. Van bajo `#if DEBUG` para que la lectura de
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

    /// Alertas del feed de comunidad, contadas del MISMO array que alimenta
    /// las cards. Antes la barra de resumen mostraba un "2" escrito a mano
    /// que no correspondía a ningún dato; así el número no puede
    /// desincronizarse del contenido.
    private static var alertasEnFeed: Int {
        reportes.filter { $0.tipo == .alerta }.count
    }

    // 10 puntos/zonas de seguridad de Trujillo; se deslizan como carrusel.
    private var rutasSeguras: [RutaSegura] {
        [
        RutaSegura(id: 0,
                   consultaMapa: "Óvalo Papal",
                   titulo: L.t("Zona Segura: Óvalo Papal", "Safe Zone: Óvalo Papal"),
                   descripcion: L.t("Patrullaje activo y alta iluminación hasta las 11:00 PM.", "Active patrol and high lighting until 11:00 PM."),
                   icono: "moon.zzz.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: .tertiary),
        RutaSegura(id: 1,
                   consultaMapa: "Avenida España 1450",
                   titulo: L.t("Serenazgo más cercano: Av. España 1450", "Nearest city patrol: Av. España 1450"),
                   descripcion: L.t("Punto del serenazgo municipal a 2 cuadras del campus. Atiende 24 h.", "City patrol point 2 blocks from campus. Open 24 h."),
                   icono: "shield.lefthalf.filled", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 2,
                   consultaMapa: "Comisaría Víctor Larco",
                   titulo: L.t("Comisaría Víctor Larco", "Víctor Larco Police Station"),
                   descripcion: L.t("A 1.5 km del campus por Mansiche. Emergencias: 105.", "1.5 km from campus via Mansiche. Emergencies: 105."),
                   icono: "lock.shield.fill", iconoBg: .appPrimary, iconoFg: .white,
                   accent: .appPrimary),
        RutaSegura(id: 3,
                   consultaMapa: "Real Plaza",
                   titulo: L.t("Av. América – Real Plaza", "Av. América – Real Plaza Mall"),
                   descripcion: L.t("Zona comercial vigilada con cámaras, bien iluminada hasta tarde.", "Commercial area with cameras, well lit until late."),
                   icono: "camera.on.rectangle.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 4,
                   consultaMapa: "Plaza de Armas",
                   titulo: L.t("Plaza de Armas (Centro Histórico)", "Main Square (Historic Downtown)"),
                   descripcion: L.t("Serenazgo 24 h y alta afluencia de personas todo el día.", "24 h city patrol and busy foot traffic all day."),
                   icono: "building.columns.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 5,
                   consultaMapa: "Mall Aventura",
                   titulo: L.t("Mall Aventura – Av. América Sur", "Mall Aventura – Av. América Sur"),
                   descripcion: L.t("Seguridad privada y botón de emergencia en estacionamientos.", "Private security and emergency button in parking lots."),
                   icono: "storefront.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 6,
                   consultaMapa: "Paseo de los Héroes",
                   titulo: L.t("Av. Mansiche – Paseo de los Héroes", "Av. Mansiche – Paseo de los Héroes"),
                   descripcion: L.t("Corredor iluminado y transitado hasta las 11:00 PM.", "Lit, busy corridor until 11:00 PM."),
                   icono: "lightbulb.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 7,
                   consultaMapa: "Hospital Belén",
                   titulo: L.t("Hospital Belén – Emergencias 24 h", "Hospital Belén – 24 h ER"),
                   descripcion: L.t("Urgencias a 1.8 km del campus. Referencia segura de noche.", "ER 1.8 km from campus. Safe reference at night."),
                   icono: "cross.case.fill", iconoBg: .errorContainer, iconoFg: .onErrorContainer,
                   accent: nil),
        RutaSegura(id: 8,
                   consultaMapa: "Estadio Mansiche",
                   titulo: L.t("Estadio Mansiche – Perímetro", "Mansiche Stadium – Perimeter"),
                   descripcion: L.t("Luces perimetrales y guardias durante eventos y entrenamientos.", "Perimeter lights and guards during events and training."),
                   icono: "sportscourt.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 9,
                   consultaMapa: "Cineplanet",
                   titulo: L.t("Frente a CinePlanet Trujillo", "Across from CinePlanet Trujillo"),
                   descripcion: L.t("Área vigilada por cámaras privadas, con movimiento constante.", "Area monitored by private cameras, constant foot traffic."),
                   icono: "video.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            // Contenido scrollable
            VStack(spacing: 0) {
                header
                summaryBar
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 28) {
                        if Self.soloComunidadDebug {
                            comunidadSection
                        } else if Self.soloZonasDebug {
                            rutasSegurasSection
                        } else {
                            greetingCard
                            lugaresSection
                            rutasSegurasSection
                            paraderosGuardadosSection
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
            if ProcessInfo.processInfo.arguments.contains("--editar") {
                lugaresVM.modoEdicion = true
            }
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
            ParaderosIluminadosView(paraderos: paraderosIluminados)
        }
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet(locationService: locationService)
                .presentationDetents([.medium, .large])
        }
        // AÑADIR (Comunidad): sheet propio, distinto al de reportar, con foto
        // (cámara/galería) y ubicación en Apple Maps.
        .sheet(isPresented: $showPublicarComunidad) {
            PublicarComunidadSheet()
                .presentationDetents([.large])
        }
        .sheet(item: $selectedReporte) { reporte in
            ReporteDetailSheet(reporte: reporte, reacciones: reacciones)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .sheet(item: $zonaSeleccionada) { zona in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: zona.icono).font(.system(size: 28)).foregroundStyle(Color.secondary)
                    Spacer()
                    Button(L.t("Cerrar", "Close")) { zonaSeleccionada = nil }
                }
                Text(zona.titulo).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(zona.descripcion).font(.bodyMd).foregroundStyle(Color.onSurfaceVariant)
                Label(L.t("Referencia de demostración · verifica las condiciones del lugar", "Demo reference · check conditions at the location"), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Color.onSurfaceVariant)
                if let errorZona { Text(errorZona).foregroundStyle(Color.appError).font(.bodySm) }
                Button {
                    buscarZona(zona)
                } label: {
                    HStack {
                        if buscandoZona { ProgressView().tint(.onPrimaryFill) }
                        Label(L.t("Ver ubicación en el mapa", "View location on map"), systemImage: "map.fill")
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.onPrimaryFill)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primaryFill))
                }.disabled(buscandoZona)
                Spacer(minLength: 0)
            }
            .padding(24).presentationDetents([.medium, .large]).seguirTemaForzado()
            .onAppear { errorZona = nil }
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
        // Añadir: elegir qué lugares guardados aparecen como tiles
        .sheet(isPresented: $showElegirLugares) {
            ElegirLugaresSheet(
                lugares: lugaresVM.lugares.filter { !$0.esFijo },
                seleccion: Set(lugaresVM.tilesActuales.filter { !$0.esFijo }.map(\.id)),
                irAGuardado: { showElegirLugares = false; router.navigate(to: .guardado) }
            ) { nuevaSeleccion in
                lugaresVM.reconstruirTiles(seleccion: nuevaSeleccion)
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header (✅ CORREGIDO V3: Reportar en header, icono lock.fill)
    private var header: some View {
        HStack(spacing: 12) {
            // Lado izquierdo: icono + titulo
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primaryFixed)
                        .frame(width: 48, height: 48)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                Text(L.t("Seguridad", "Safety"))
                    .font(.headlineLgMobile)
                    .foregroundStyle(.appPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            // Lado derecho: boton Reportar
            Button {
                // Modo Señas: deja ver el videito antes de que el sheet tape el miniplayer.
                SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "seguridad.reportar") { showReportarSheet = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L.signable("seguridad.reportar", "Reportar", "Report"))
                        .font(.labelCapsMd)
                        .appTracking(AppTracking.wideLabel)
                }
                .foregroundStyle(.onPrimaryFill)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.primaryFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Reportar incidente", "Report an incident"))
            .seniable("seguridad.reportar", conGesto: false)
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
    }

    // MARK: - Summary bar (✅ CORREGIDO V3: Reportar movido al header, solo queda Llamar 105)
    private var summaryBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Sin concatenar ni Markdown: el texto se resuelve como un
                // String de runtime, así que "**2**" se dibujaba con los
                // asteriscos literales a la vista.
                Text(L.t("Alertas hoy: \(Self.alertasEnFeed)",
                         "Alerts today: \(Self.alertasEnFeed)"))
                    .font(.bodySmMedium)
                if cargandoParaderos {
                    Text(L.t("Cargando paraderos…", "Loading stops…")).font(.bodySmMedium)
                } else if let errorCargaParaderos {
                    Text(errorCargaParaderos).font(.bodyXs).foregroundStyle(Color.appError)
                    Button(L.t("Reintentar", "Retry")) { revisionCatalogo += 1 }
                        .font(.bodyXsMedium)
                } else {
                    Text(L.t("Paraderos para explorar: \(paraderosIluminados.count)", "Stops to explore: \(paraderosIluminados.count)"))
                        .font(.bodySmMedium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                // Modo Señas: deja ver el videito antes de que la alerta tape el miniplayer.
                SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "seguridad.emergencia") { showLlamarAlert = true }
            } label: {
                Text(L.signable("seguridad.emergencia", "Llamar 105", "Call 105"))
                    .font(.bodyXsMedium)
                    .foregroundStyle(.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceContainerHigh))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Llamar al 105 emergencias", "Call emergency services at 105"))
            .seniable("seguridad.emergencia", conGesto: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainer)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Greeting
    private var greetingCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.tertiary.opacity(0.12)).frame(width: 48, height: 48)
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(saludoDinamico)
                    .font(.headlineBody)
                    .foregroundStyle(.onSurface)
                Text(fechaActual())
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Lugares guardados (reales, vía LugaresStore)

    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.signable("seguridad.lugares_guardados", "Lugares Guardados", "Saved Places"))
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
                    .seniable("seguridad.lugares_guardados", distintivoDx: 10)
                Spacer()
                Button {
                    AppHaptics.impact(.medium)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        lugaresVM.alternarEdicion()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: lugaresVM.modoEdicion ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 14, weight: .semibold))
                        Text(lugaresVM.modoEdicion ? L.t("LISTO", "DONE") : L.t("EDITAR", "EDIT"))
                            .font(.labelCapsSm)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .foregroundStyle(lugaresVM.modoEdicion ? Color.appPrimary : Color.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }

            if lugaresVM.datosLugaresInvalidos {
                Text(L.t("No se pudieron leer tus lugares. Se conservaron los datos originales; puedes reintentar la lectura en Guardado.",
                         "Your places could not be read. The original data was preserved; you can retry reading in Saved."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(lugaresVM.tilesActuales) { lugar in
                    lugarTileLugar(lugar)
                        .onDrag {
                            AppHaptics.impact(.light)
                            lugaresVM.arrastrando = lugar
                            return NSItemProvider(object: lugar.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text],
                                delegate: TileDropDelegate(
                                    destino: lugar,
                                    tiles: $lugaresVM.tilesActuales,
                                    arrastrando: $lugaresVM.arrastrando,
                                    onPersistir: lugaresVM.persistirOrden))
                        .accessibilityActions {
                            if lugaresVM.modoEdicion, !lugar.esFijo,
                               let indice = lugaresVM.tilesActuales.firstIndex(where: { $0.id == lugar.id }) {
                                if indice > 0, !lugaresVM.tilesActuales[indice - 1].esFijo {
                                    Button(L.t("Mover antes", "Move earlier")) { moverTileAccesible(lugar, desplazamiento: -1) }
                                }
                                if indice + 1 < lugaresVM.tilesActuales.count {
                                    Button(L.t("Mover después", "Move later")) { moverTileAccesible(lugar, desplazamiento: 1) }
                                }
                            }
                        }
                }
                lugarTileAñadir
            }
            .disabled(lugaresVM.datosLugaresInvalidos)
        }
    }

    /// Misma lista y persistencia que el arrastre; respeta el lugar fijo y los datos inválidos.
    private func moverTileAccesible(_ lugar: LugarGuardado, desplazamiento: Int) {
        guard lugaresVM.modoEdicion, !lugaresVM.datosLugaresInvalidos, !lugar.esFijo,
              let indice = lugaresVM.tilesActuales.firstIndex(where: { $0.id == lugar.id }) else { return }
        let destino = indice + desplazamiento
        guard lugaresVM.tilesActuales.indices.contains(destino),
              !lugaresVM.tilesActuales[destino].esFijo else { return }
        lugaresVM.tilesActuales.swapAt(indice, destino)
        lugaresVM.persistirOrden()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement,
                argument: L.t("\(lugar.nombre), posición \(destino + 1)", "\(lugar.nombre), position \(destino + 1)"))
        }
    }

    private func lugarTileLugar(_ lugar: LugarGuardado) -> some View {
        let esArrastrado = lugaresVM.arrastrando?.id == lugar.id
        return lugarTile(nombre: lugar.nombre,
                         icon: lugar.icono,
                         bg: lugar.esFijo ? Color.primaryFill : Color.primaryContainer.opacity(0.12),
                         fg: lugar.esFijo ? .onPrimaryFill : .appPrimary,
                         border: lugar.esFijo,
                         badgeFrecuente: lugar.esFrecuente,
                         indiceTile: lugaresVM.tilesActuales.firstIndex(where: { $0.id == lugar.id }) ?? 0)
        {
            if lugaresVM.modoEdicion {
                AppHaptics.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    lugaresVM.modoEdicion = false
                }
            }
            selectedLugar = lugar
        }
        .overlay(alignment: .topLeading) {
            if lugaresVM.modoEdicion {
                if lugar.esFijo {
                    // UTP es fijo: no se puede borrar ni mover
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.surfaceContainerHigh))
                        .overlay(Circle().stroke(Color.surfaceContainerLowest, lineWidth: 1.5))
                        .offset(x: -6, y: -6)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Button {
                        AppHaptics.warning()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            _ = lugaresVM.eliminar(lugar)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.appError))
                            .overlay(Circle().stroke(Color.surfaceContainerLowest, lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -7, y: -7)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .accessibilityLabel(L.t("Eliminar \(lugar.nombre)", "Remove \(lugar.nombre)"))
                }
            }
        }
        .scaleEffect(esArrastrado ? 1.08 : (lugaresVM.modoEdicion ? 0.97 : 1.0))
        .opacity(esArrastrado ? 0.75 : 1.0)
        .zIndex(esArrastrado ? 10 : 0)
    }

    private var lugarTileAñadir: some View {
        lugarTile(nombre: lugaresVM.modoEdicion ? L.t("Añadir", "Add")
                     : (lugaresVM.tilesActuales.count <= 1 ? L.t("Añadir", "Add") : L.t("Elegir", "Choose")),
                  icon: "plus",
                  bg: Color.surfaceContainerLow,
                  fg: .outline,
                  border: false,
                  dashed: true) {
            AppHaptics.selection()
            showElegirLugares = true
        }
    }

    private func lugarTile(nombre: String, icon: String, bg: Color, fg: Color, border: Bool, badgeFrecuente: Bool = false, indiceTile: Int = 0, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(bg).frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .strokeBorder(border ? Color.appPrimary : Color.outline.opacity(0.4),
                                              style: StrokeStyle(lineWidth: border ? 2 : 1, dash: dashed ? [3, 3] : []))
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(fg)
                }
                .overlay(alignment: .topTrailing) {
                    if badgeFrecuente {
                        Circle()
                            .fill(Color.tertiary)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.surfaceContainerLowest, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
                Text(nombre)
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurface)
                    .appTracking(AppTracking.wideLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
            )
        }
        .buttonStyle(.plain)
        .modifier(JiggleEffect(active: lugaresVM.modoEdicion && !dashed, indice: indiceTile))
    }

    // MARK: - Rutas seguras
    private var rutasSegurasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.tertiary)
                Text(L.signable("seguridad.rutas_seguras", "Paraderos y referencias", "Stops and landmarks"))
                    .font(.headlineSm)
                    .seniable("seguridad.rutas_seguras", distintivoDx: 10)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rutasSeguras) { ruta in
                        Button { zonaSeleccionada = ruta } label: { rutaSeguraRow(ruta: ruta) }
                            .buttonStyle(.plain)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            Text(L.t("Desliza para explorar los puntos de referencia", "Swipe to explore reference locations"))
                .font(.system(size: 11)).foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private func rutaSeguraRow(ruta: RutaSegura) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: ruta.icono).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ruta.iconoFg).frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 16).fill(ruta.iconoBg))
                Spacer()
                Text(String(format: "%02d", ruta.id + 1))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            Text(ruta.titulo).font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onSurface).lineLimit(2).multilineTextAlignment(.leading)
            Text(ruta.descripcion).font(.system(size: 12))
                .foregroundStyle(Color.onSurfaceVariant).lineLimit(3).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack {
                Text(L.t("Explorar ubicación", "Explore location")).font(.system(size: 12, weight: .bold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
            }.foregroundStyle(Color.secondary)
        }
        .padding(18).frame(width: 270, height: 238, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.surfaceContainerLowest))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }

    private func buscarZona(_ zona: RutaSegura) {
        guard !buscandoZona else { return }
        buscandoZona = true; errorZona = nil
        Task { @MainActor in
            defer { buscandoZona = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = zona.consultaMapa + ", Trujillo, Perú"
            request.region = MKCoordinateRegion(center: TransporteApp.referenciaInicio,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15))
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard zonaSeleccionada?.id == zona.id else { return }
                guard let item = response.mapItems.first else {
                    errorZona = L.t("No encontramos esta ubicación.", "This location was not found.")
                    return
                }
                let coord = item.placemark.coordinate
                router.destinoPendiente = DestinoPendiente(titulo: item.name ?? zona.titulo, lat: coord.latitude, lon: coord.longitude)
                zonaSeleccionada = nil
                router.navigate(to: .mapaPrincipal)
            } catch {
                guard zonaSeleccionada?.id == zona.id else { return }
                errorZona = L.t("No pudimos buscar el lugar. Revisa tu conexión.", "Could not find the location. Check your connection.")
            }
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
                    Text(L.t("Guarda un paradero en «Paraderos y referencias» y lo encontrarás aquí.",
                             "Save a stop in ‘Stops and landmarks’ to find it here."))
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
                ReporteCard(reporte: reporte, reacciones: reacciones)
                    .onTapGesture { selectedReporte = reporte }
                    .accessibilityAction(named: Text(L.t("Ver publicación", "View post"))) { selectedReporte = reporte }
            }
        }
    }

    // MARK: - Helpers
    private var saludoDinamico: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return L.t("Buenos días", "Good morning")
        case 12..<19: return L.t("Buenas tardes", "Good afternoon")
        default:      return L.t("Buenas noches", "Good evening")
        }
    }

    private func fechaActual() -> String {
        let patron = L.esIngles ? "EEEE, MMMM d" : "EEEE d 'de' MMMM"
        return FormatoFecha.formateador(patron: patron, locale: FormatoFecha.localeActivo)
            .string(from: Date())
            .capitalized
    }
}

// MARK: - Reportar Sheet
// ReportarSheet vive en Design/Components/ReportarSheet.swift (compartido
// con el Mapa). Ver ahí el diseño completo.
