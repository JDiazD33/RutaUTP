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
    @EnvironmentObject private var router: AppRouter

    @State private var showReportarSheet = false
    @State private var showLlamarAlert = false
    @State private var selectedReporte: ReporteComunidad?
    @State private var paginaZona: Int? = 0            // página del carrusel
    @State private var zonaSeleccionada: RutaSegura? = nil  // detalle (alert)

    // Paraderos iluminados (reales del feed GTFS) + mapa fullscreen
    @State private var paraderosIluminados: [ParaderoGTFS] = []
    @State private var showParaderosMap = false

    // Lugares guardados (mismos datos que GuardadoView, vía LugaresStore)
    @State private var lugares: [LugarGuardado] = []
    @State private var selectedLugar: LugarGuardado?
    @State private var showElegirLugares = false

    // Modo edición (estilo Springboard): jiggle + borrar + reordenar
    @State private var modoEdicion = false
    @State private var tilesActuales: [LugarGuardado] = []
    @State private var arrastrando: LugarGuardado?

    private static let tilesKey = "seguridad.tiles.v1"
    private static let ordenKey = "seguridad.tiles.orden.v1"

    private let tabBarHeight: CGFloat = 64

    /// DEBUG: --comunidad N (solo comunidad) / --zonas (solo zonas seguras).
    private static let soloComunidadDebug = ProcessInfo.processInfo.arguments.contains("--comunidad")
    private var soloComunidadDebug: Bool { Self.soloComunidadDebug }
    private static let soloZonasDebug = ProcessInfo.processInfo.arguments.contains("--zonas")
    private var soloZonasDebug: Bool { Self.soloZonasDebug }

    /// Caché para el preview del banner (BannerParaderosPreview).
    static var paraderosCache: [ParaderoGTFS]? = nil

    // Pool de 30 opiniones de la comunidad; se muestran 3 por vez y la
    // ventana rota cada 5 minutos (10 ventanas antes de repetir).
    private static let reportes: [ReporteComunidad] = {
        let nombres: [(String, String)] = [
            ("Jorge D.", "JD"), ("Maria A.", "MA"), ("Rosa C.", "RC"),
            ("Luis F.", "LF"), ("Ana P.", "AP"), ("Carlos M.", "CM"),
            ("Gabriela S.", "GS"), ("Pedro L.", "PL"), ("Fernanda R.", "FR"),
            ("Diego V.", "DV"), ("Lucía T.", "LT"), ("Marco E.", "ME"),
            ("Karla B.", "KB"), ("Renzo Q.", "RQ"), ("Valeria H.", "VH"),
            ("Oscar N.", "ON"), ("Pamela G.", "PG"), ("Julio C.", "JC"),
            ("Andrea M.", "AM"), ("Victor S.", "VS"), ("Rocío F.", "RF"),
            ("Héctor Z.", "HZ"), ("Natalia O.", "NO"), ("Iván P.", "IP"),
            ("Silvia R.", "SR"), ("Bruno A.", "BA"), ("Katia L.", "KL"),
            ("Ricardo T.", "RT"), ("Elena V.", "EV"), ("Fausto M.", "FM")
        ]
        let cuerpos: [(String, TipoReporte)] = [
            ("Micro lleno en Av. Larco. Pasaron 3 sin parar hacia la UTP.", .alerta),
            ("Demora en Óvalo Papal por obras. Considerar 10 min adicionales.", .trafico),
            ("Tomar Av. Miraflores a las 7:30 AM evita el tráfico de España.", .sugerencia),
            ("El chofer de la C-01 muy amable, esperó a una señora mayor que corría.", .otro),
            ("Cuidado con los carteristas en el paradero del Mercado Mayorista, hora punta.", .alerta),
            ("Colapso total en Av. América Sur desde las 6 PM, mejor ir por Mansiche.", .trafico),
            ("La línea C-07 va despejada sábados por la mañana, casi siempre hay asiento.", .sugerencia),
            ("Paradero frente a la UTP sin luz desde el lunes, Reporté al 105.", .alerta),
            ("Tráfico lento en Av. César Vallejo por desfile, tomar La Ribera.", .trafico),
            ("Tip: bajarse 1 cuadra antes de la UTP por Piérola ahorra 5 min de embotellamiento.", .sugerencia),
            ("Moto-taxista se pasó el semáforo en España con Mansiche. Suerte que frenó a tiempo.", .alerta),
            ("En Huanchaco hay tráfico pesado los domodos por el malecón, ir temprano.", .trafico),
            ("El micro de las 6:20 AM llega vacío al paradero de Urb. El Recreo.", .sugerencia),
            ("Se accidentó un combi cerca del Óvalo Faustino Sánchez, colapso 40 min.", .alerta),
            ("Ruta M-05 toma caminos raros para evitar tráfico, pero llega rápido.", .otro),
            ("Tarifa S/ 2.50 en la C-01 confirmado. Algunos intentan cobrar más de noche.", .alerta),
            ("Av. Larco de Huanchaco congestionada al mediodía por turistas.", .trafico),
            ("Los paraderos nuevos de Av. España tienen techo y cámaras, bien ahí.", .otro),
            ("Consejo: apps de mapa no reflejan el desvío en Prolongación Unión, ojo.", .sugerencia),
            ("Robo de celulares reportado en la C-28 cerca de Balazar. Guarden sus cosas.", .alerta),
            ("Obras en Av. Frecuencia España: solo un carril, agregar 15 min.", .trafico),
            ("Sábado por la mañana es lo más fluido: 20 min desde La Esperanza a UTP.", .sugerencia),
            ("El fiscal de la M-34 hace respetar la fila de preferencia, felicidades.", .otro),
            ("Choca-choque en Av. Nicolás de Piérola frente al campus, tráfico lento.", .trafico),
            ("Bajan muy rápido en las curvas de Víctor Larco, debería haber fiscalización.", .alerta),
            ("Irse temprano de clase evita la avalancha de micros entre 7 y 8 PM.", .sugerencia),
            ("Policía de tránsito nuevo en el cruce de América con César Vallejo, fluye mejor.", .otro),
            ("Cuidado al bajar en el paradero del Americano, acera estrecha y motores acelerando.", .alerta),
            ("El tramo Mansiche–España amanece despejado, viaje de 15 min.", .trafico),
            ("Sugerencia para la app: avisar cuando el micro va lleno antes de que llegue.", .sugerencia)
        ]
        let tiempos = ["HACE 3 MIN", "HACE 8 MIN", "HACE 12 MIN", "HACE 20 MIN",
                       "HACE 35 MIN", "HACE 1 HORA", "HACE 2 HORAS"]
        let avatares: [(Color, Color)] = [
            (.primaryContainer, .onPrimaryContainer),
            (.secondaryContainer, .onSecondaryContainer),
            (.tertiaryContainer, .onTertiaryContainer)
        ]

        return cuerpos.enumerated().map { i, par in
            let persona = nombres[i % nombres.count]
            let avatar = avatares[i % avatares.count]
            return ReporteComunidad(
                iniciales: persona.1,
                nombre: persona.0,
                hace: tiempos[(i * 7 + 3) % tiempos.count],
                tipo: par.1,
                cuerpo: par.0,
                utiles: 6 + (i * 13) % 78,
                comentarios: (i * 5) % 11,
                utilMarcado: i % 6 == 0,
                avatarColor: avatar.0,
                avatarForeground: avatar.1
            )
        }
    }()

    /// Índice de ventana de 5 minutos (10 ventanas para 30 reportes de a 3).
    /// DEBUG: --comunidad N fuerza la ventana para pruebas visuales.
    private var indiceVentana: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--comunidad"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            return n % (Self.reportes.count / 3)
        }
        #endif
        let epoch = Int(Date().timeIntervalSinceReferenceDate)
        return (epoch / 300) % (Self.reportes.count / 3)
    }

    private var reportesVisibles: [ReporteComunidad] {
        let inicio = indiceVentana * 3
        return Array(Self.reportes[inicio..<(inicio + 3)])
    }

    // 10 puntos/zonas de seguridad de Trujillo; se deslizan como carrusel.
    private let rutasSeguras: [RutaSegura] = [
        RutaSegura(id: 0,
                   titulo: L.t("Zona Segura: Óvalo Papal", "Safe Zone: Óvalo Papal"),
                   descripcion: L.t("Patrullaje activo y alta iluminación hasta las 11:00 PM.", "Active patrol and high lighting until 11:00 PM."),
                   icono: "moon.zzz.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: .tertiary),
        RutaSegura(id: 1,
                   titulo: L.t("Serenazgo más cercano: Av. España 1450", "Nearest city patrol: Av. España 1450"),
                   descripcion: L.t("Punto del serenazgo municipal a 2 cuadras del campus. Atiende 24 h.", "City patrol point 2 blocks from campus. Open 24 h."),
                   icono: "shield.lefthalf.filled", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 2,
                   titulo: L.t("Comisaría Víctor Larco", "Víctor Larco Police Station"),
                   descripcion: L.t("A 1.5 km del campus por Mansiche. Emergencias: 105.", "1.5 km from campus via Mansiche. Emergencies: 105."),
                   icono: "lock.shield.fill", iconoBg: .appPrimary, iconoFg: .white,
                   accent: .appPrimary),
        RutaSegura(id: 3,
                   titulo: L.t("Av. América – Real Plaza", "Av. América – Real Plaza Mall"),
                   descripcion: L.t("Zona comercial vigilada con cámaras, bien iluminada hasta tarde.", "Commercial area with cameras, well lit until late."),
                   icono: "camera.on.rectangle.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 4,
                   titulo: L.t("Plaza de Armas (Centro Histórico)", "Main Square (Historic Downtown)"),
                   descripcion: L.t("Serenazgo 24 h y alta afluencia de personas todo el día.", "24 h city patrol and busy foot traffic all day."),
                   icono: "building.columns.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 5,
                   titulo: L.t("Mall Aventura – Av. América Sur", "Mall Aventura – Av. América Sur"),
                   descripcion: L.t("Seguridad privada y botón de emergencia en estacionamientos.", "Private security and emergency button in parking lots."),
                   icono: "storefront.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 6,
                   titulo: L.t("Av. Mansiche – Paseo de los Héroes", "Av. Mansiche – Paseo de los Héroes"),
                   descripcion: L.t("Corredor iluminado y transitado hasta las 11:00 PM.", "Lit, busy corridor until 11:00 PM."),
                   icono: "lightbulb.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil),
        RutaSegura(id: 7,
                   titulo: L.t("Hospital Belén – Emergencias 24 h", "Hospital Belén – 24 h ER"),
                   descripcion: L.t("Urgencias a 1.8 km del campus. Referencia segura de noche.", "ER 1.8 km from campus. Safe reference at night."),
                   icono: "cross.case.fill", iconoBg: .errorContainer, iconoFg: .onErrorContainer,
                   accent: nil),
        RutaSegura(id: 8,
                   titulo: L.t("Estadio Mansiche – Perímetro", "Mansiche Stadium – Perimeter"),
                   descripcion: L.t("Luces perimetrales y guardias durante eventos y entrenamientos.", "Perimeter lights and guards during events and training."),
                   icono: "sportscourt.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: nil),
        RutaSegura(id: 9,
                   titulo: L.t("Frente a CinePlanet Trujillo", "Across from CinePlanet Trujillo"),
                   descripcion: L.t("Área vigilada por cámaras privadas, con movimiento constante.", "Area monitored by private cameras, constant foot traffic."),
                   icono: "video.fill", iconoBg: .secondary, iconoFg: .onSecondary,
                   accent: nil)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            // Contenido scrollable
            VStack(spacing: 0) {
                header
                summaryBar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        if soloComunidadDebug {
                            comunidadSection
                        } else if soloZonasDebug {
                            rutasSegurasSection
                        } else {
                            greetingCard
                            lugaresSection
                            rutasSegurasSection
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
            lugares = LugaresStore.cargar()
            reconstruirTiles()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--editar") {
                modoEdicion = true
            }
            if ProcessInfo.processInfo.arguments.contains("--paraderos") {
                showParaderosMap = true
            }
            #endif
        }
        .task {
            // Paraderos iluminados: selección determinista sobre el feed GTFS.
            if paraderosIluminados.isEmpty {
                let feed = await GTFSRepository.shared.rutas()
                paraderosIluminados = ParaderosIluminados.seleccionar(feed)
                Self.paraderosCache = paraderosIluminados
            }
        }
        // Mapa fullscreen de paraderos iluminados (desde el banner)
        .fullScreenCover(isPresented: $showParaderosMap) {
            ParaderosIluminadosView(paraderos: paraderosIluminados)
        }
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedReporte) { reporte in
            ReporteDetailSheet(reporte: reporte)
                .presentationDetents([.medium, .large])
        }
        .alert(L.t("Llamar al 105", "Call 911"), isPresented: $showLlamarAlert) {
            Button("Llamar") {
                if let url = URL(string: "tel://105") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se abrirá la aplicación de teléfono para llamar a la central de emergencias.")
        }
        .alert(item: $zonaSeleccionada) { zona in
            Alert(
                title: Text(zona.titulo),
                message: Text(zona.descripcion),
                primaryButton: .default(Text("Ver en mapa")) {
                    router.navigate(to: .mapaPrincipal)
                },
                secondaryButton: .cancel(Text("Cerrar"))
            )
        }
        // Detalle del lugar (mismo sheet que Guardado: info + acciones reales)
        .sheet(item: $selectedLugar) { lugar in
            LugarDetailSheet(lugar: lugar) {
                LugaresStore.eliminar(lugar)
                lugares = LugaresStore.cargar()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    tilesActuales.removeAll { $0.id == lugar.id }
                }
                persistirOrden()
            }
            .presentationDetents([.medium, .large])
        }
        // Añadir: elegir qué lugares guardados aparecen como tiles
        .sheet(isPresented: $showElegirLugares) {
            ElegirLugaresSheet(
                lugares: lugares.filter { !$0.esFijo },
                seleccion: Set(tilesActuales.filter { !$0.esFijo }.map(\.id)),
                irAGuardado: { showElegirLugares = false; router.navigate(to: .guardado) }
            ) { nuevaSeleccion in
                reconstruirTiles(seleccion: nuevaSeleccion)
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
                        .fill(Color(hex: "#ffdadb"))
                        .frame(width: 48, height: 48)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                Text(L.t("Seguridad", "Safety"))
                    .font(.headlineLgMobile)
                    .foregroundStyle(.appPrimary)
            }
            Spacer()
            // Lado derecho: boton Reportar
            Button {
                showReportarSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(L.signable("seguridad.reportar", "Reportar", "Report"))
                        .font(.labelCapsMd)
                        .appTracking(AppTracking.wideLabel)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reportar incidente")
            .seniable("seguridad.reportar")
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
                Text(L.t("Alertas hoy:", "Alerts today:") + " **2**")
                    .font(.bodySmMedium)
                Text("Paraderos iluminados: **\(paraderosIluminados.count)**")
                    .font(.bodySmMedium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showLlamarAlert = true
            } label: {
                Text(L.signable("seguridad.emergencia", "Llamar 105", "Call 911"))
                    .font(.bodyXsMedium)
                    .foregroundStyle(.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceContainerHigh))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Llamar al 105 emergencias")
            .seniable("seguridad.emergencia")
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
                    .seniable("seguridad.lugares_guardados")
                Spacer()
                Button {
                    AppHaptics.impact(.medium)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        modoEdicion.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: modoEdicion ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 14, weight: .semibold))
                        Text(modoEdicion ? L.t("LISTO", "DONE") : L.t("EDITAR", "EDIT"))
                            .font(.labelCapsSm)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .foregroundStyle(modoEdicion ? Color.appPrimary : Color.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(tilesActuales) { lugar in
                    lugarTileLugar(lugar)
                        .onDrag {
                            AppHaptics.impact(.light)
                            arrastrando = lugar
                            return NSItemProvider(object: lugar.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text],
                                delegate: TileDropDelegate(
                                    destino: lugar,
                                    tiles: $tilesActuales,
                                    arrastrando: $arrastrando,
                                    onPersistir: persistirOrden))
                }
                lugarTileAñadir
            }
        }
    }

    /// UTP fijo primero + extras en el orden guardado por el usuario.
    private func reconstruirTiles(seleccion: Set<UUID>? = nil) {
        let utp = lugares.first(where: { $0.esFijo })
        let noFijos = lugares.filter { !$0.esFijo }

        let elegidos: [LugarGuardado]
        if let seleccion, !seleccion.isEmpty {
            elegidos = noFijos.filter { seleccion.contains($0.id) }
        } else if let idsGuardados = idsTilesGuardados(), !idsGuardados.isEmpty {
            let porId = Dictionary(uniqueKeysWithValues: noFijos.map { ($0.id, $0) })
            elegidos = idsGuardados.compactMap { porId[$0] }
        } else {
            elegidos = Array(noFijos.prefix(2))
        }

        // Orden guardado por el usuario (arrastrar en modo edición)
        var resultado: [LugarGuardado] = []
        if let utp { resultado.append(utp) }
        if let orden = idsOrdenGuardados(), !orden.isEmpty {
            let porId = Dictionary(uniqueKeysWithValues: elegidos.map { ($0.id, $0) })
            var ordenados = orden.compactMap { porId[$0] }
            // Los que no tenían posición guardada van al final, en su orden natural.
            ordenados += elegidos.filter { s in !ordenados.contains(where: { $0.id == s.id }) }
            resultado += ordenados
        } else {
            resultado += elegidos
        }
        tilesActuales = resultado
    }

    private func idsTilesGuardados() -> [UUID]? {
        guard let data = UserDefaults.standard.data(forKey: Self.tilesKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
        return ids
    }

    private func idsOrdenGuardados() -> [UUID]? {
        guard let data = UserDefaults.standard.data(forKey: Self.ordenKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
        return ids
    }

    private func persistirOrden() {
        let ids = tilesActuales.filter { !$0.esFijo }.map(\.id)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: Self.ordenKey)
        }
    }

    private func guardarTilesSeleccion(_ ids: Set<UUID>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            UserDefaults.standard.set(data, forKey: Self.tilesKey)
        }
    }

    private func lugarTileLugar(_ lugar: LugarGuardado) -> some View {
        let esArrastrado = arrastrando?.id == lugar.id
        return lugarTile(nombre: lugar.nombre,
                         icon: lugar.categoria.icono,
                         bg: lugar.esFijo ? Color.appPrimary : Color.primaryContainer.opacity(0.12),
                         fg: lugar.esFijo ? .white : .appPrimary,
                         border: lugar.esFijo,
                         badgeFrecuente: lugar.esFrecuente,
                         faseJiggle: Double(tilesActuales.firstIndex(where: { $0.id == lugar.id }) ?? 0) * 1.7)
        {
            if modoEdicion {
                AppHaptics.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    modoEdicion = false
                }
            }
            selectedLugar = lugar
        }
        .overlay(alignment: .topLeading) {
            if modoEdicion {
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
                            tilesActuales.removeAll { $0.id == lugar.id }
                        }
                        LugaresStore.eliminar(lugar)
                        lugares = LugaresStore.cargar()
                        persistirOrden()
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
                    .accessibilityLabel("Eliminar \(lugar.nombre)")
                }
            }
        }
        .scaleEffect(esArrastrado ? 1.08 : (modoEdicion ? 0.97 : 1.0))
        .opacity(esArrastrado ? 0.75 : 1.0)
        .zIndex(esArrastrado ? 10 : 0)
    }

    private var lugarTileAñadir: some View {
        lugarTile(nombre: modoEdicion ? "Añadir" : (tilesActuales.count <= 1 ? "Añadir" : L.t("Elegir", "Choose")),
                  icon: "plus",
                  bg: Color.surfaceContainerLow,
                  fg: .outline,
                  border: false,
                  dashed: true) {
            AppHaptics.selection()
            showElegirLugares = true
        }
    }

    private func lugarTile(nombre: String, icon: String, bg: Color, fg: Color, border: Bool, badgeFrecuente: Bool = false, faseJiggle: Double = 0, dashed: Bool = false, action: @escaping () -> Void) -> some View {
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
        .modifier(JiggleEffect(active: modoEdicion && !dashed, fase: faseJiggle))
    }

    // MARK: - Rutas seguras
    private var rutasSegurasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.tertiary)
                Text(L.signable("seguridad.rutas_seguras", "Rutas Seguras Hoy", "Safe Routes Today"))
                    .font(.headlineSm)
                    .seniable("seguridad.rutas_seguras")
            }

            Button {
                AppHaptics.impact(.light)
                showParaderosMap = true
            } label: {
                BannerParaderosPreview(cantidad: paraderosIluminados.count)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver mapa de paraderos iluminados")

            // Carrusel deslizable: 10 zonas seguras de Trujillo
            TabView(selection: $paginaZona) {
                ForEach(rutasSeguras) { ruta in
                    Button {
                        zonaSeleccionada = ruta
                    } label: {
                        rutaSeguraRow(ruta: ruta)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 2)
                    .tag(ruta.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 104)
        }
    }

    private func rutaSeguraRow(ruta: RutaSegura) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let accent = ruta.accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
            }
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(ruta.iconoBg).frame(width: 40, height: 40)
                    Image(systemName: ruta.icono)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ruta.iconoFg)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ruta.titulo)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    Text(ruta.descripcion)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Comunidad (30 opiniones, rotan cada 5 minutos)
    private var comunidadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.appPrimary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L.signable("seguridad.comunidad", "Comunidad", "Community"))
                            .font(.headlineSm)
                            .seniable("seguridad.comunidad")
                        Text(L.t("Opiniones frescas · cambian cada 5 min", "Fresh takes · rotate every 5 min"))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                }
                Spacer()
                Button {
                    showReportarSheet = true
                } label: {
                    Text(L.t("AÑADIR", "ADD"))
                        .font(.labelCapsSm)
                        .foregroundStyle(.appPrimary)
                        .appTracking(AppTracking.wideLabel)
                }
                .buttonStyle(.plain)
            }

            // Se re-evalúa cada 5 min → rota la ventana de opiniones.
            TimelineView(.periodic(from: .now, by: 300)) { _ in
                VStack(spacing: 12) {
                    ForEach(reportesVisibles) { r in
                        Button {
                            selectedReporte = r
                        } label: {
                            ReporteCard(reporte: r)
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .opacity
                        ))
                    }
                }
                .id(indiceVentana)
                .animation(.easeInOut(duration: 0.4), value: indiceVentana)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f.string(from: Date()).capitalized
    }
}

// MARK: - Modelo de Ruta Segura
private struct RutaSegura: Identifiable {
    let id: Int
    let titulo: String
    let descripcion: String
    let icono: String
    let iconoBg: Color
    let iconoFg: Color
    let accent: Color?
}

// MARK: - Reporte card
private struct ReporteCard: View {
    let reporte: ReporteComunidad

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(reporte.avatarColor).frame(width: 32, height: 32)
                    Text(reporte.iniciales)
                        .font(.labelCapsMd)
                        .foregroundStyle(reporte.avatarForeground)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reporte.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(reporte.hace)
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
                Spacer()
                Text(reporte.tipo.rawValue)
                    .font(.labelCapsSm)
                    .foregroundStyle(reporte.tipo.foreground)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(reporte.tipo.background))
            }

            Text(reporte.cuerpo)
                .font(.bodyMd)
                .foregroundStyle(.onSurface)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: reporte.utilMarcado ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(reporte.utilMarcado ? Color.appPrimary : Color.onSurfaceVariant)
                    Text("Útil (\(reporte.utiles))")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                    Text("\(reporte.comentarios)")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
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
}

// MARK: - Reporte Detail Sheet
private struct ReporteDetailSheet: View {
    let reporte: ReporteComunidad
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(reporte.avatarColor).frame(width: 48, height: 48)
                    Text(reporte.iniciales)
                        .font(.headlineSm)
                        .foregroundStyle(reporte.avatarForeground)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reporte.nombre)
                        .font(.headlineSm)
                    Text(reporte.hace)
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
                Spacer()
                Text(reporte.tipo.rawValue)
                    .font(.labelCapsMd)
                    .foregroundStyle(reporte.tipo.foreground)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(reporte.tipo.background))
            }
            Divider()
            Text(reporte.cuerpo)
                .font(.bodyLg)
                .foregroundStyle(.onSurface)
            Divider()
            HStack(spacing: 24) {
                Label("Útil (\(reporte.utiles))", systemImage: reporte.utilMarcado ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(reporte.utilMarcado ? .appPrimary : .onSurfaceVariant)
                Label("\(reporte.comentarios)", systemImage: "bubble.left")
                    .foregroundStyle(.onSurfaceVariant)
                Spacer()
            }
            .font(.bodyMdMedium)
            Spacer()
            Button { dismiss() } label: {
                Text("Cerrar")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                    .foregroundStyle(.white)
                    .font(.bodyMdMedium)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
}

// MARK: - Reportar Sheet
// ReportarSheet vive en Design/Components/ReportarSheet.swift (compartido
// con el Mapa). Ver ahí el diseño completo.

// MARK: - Elegir Lugares sheet (tiles de Seguridad)
private struct ElegirLugaresSheet: View {
    let lugares: [LugarGuardado]          // sin incluir UTP (fijo, siempre está)
    let seleccion: Set<UUID>
    var irAGuardado: () -> Void
    var onGuardar: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var elegidos: Set<UUID> = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Elige los lugares que verás aquí")
                    .font(.headlineMd)
                Text("Tus lugares guardados de la pestaña Guardado. UTP siempre aparece.")
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)

                if lugares.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.onSurfaceVariant)
                        Text("Aún no tienes lugares guardados")
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        Button {
                            irAGuardado()
                        } label: {
                            Label("Ir a Guardado", systemImage: "plus.circle.fill")
                                .font(.headlineSm)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(lugares) { lugar in
                                filaLugar(lugar)
                            }
                        }
                    }
                    botonListo
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { elegidos = seleccion }
        }
    }

    private func filaLugar(_ lugar: LugarGuardado) -> some View {
        Button {
            AppHaptics.selection()
            if elegidos.contains(lugar.id) {
                elegidos.remove(lugar.id)
            } else {
                elegidos.insert(lugar.id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.primaryContainer.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: lugar.categoria.icono)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(lugar.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(lugar.direccion)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: elegidos.contains(lugar.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(elegidos.contains(lugar.id) ? Color.appPrimary : Color.outlineVariant)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(elegidos.contains(lugar.id)
                          ? Color.primaryContainer.opacity(0.25)
                          : Color.surfaceContainerLowest)
            )
        }
        .buttonStyle(.plain)
    }

    private var botonListo: some View {
        Button {
            AppHaptics.success()
            onGuardar(elegidos)
            dismiss()
        } label: {
            Text(L.t("Guardar selección", "Save selection"))
                .font(.headlineSm)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Efecto jiggle (estilo pantalla de inicio del iPhone)
/// Rotación oscilante con desfase por tile para que se muevan "en ola".
struct JiggleEffect: ViewModifier {
    let active: Bool
    var fase: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? jiggleAngle : 0))
            .animation(
                active
                ? Animation.easeInOut(duration: 0.12)
                    .repeatForever(autoreverses: true)
                    .delay(fase * 0.0)
                : .default,
                value: active
            )
    }

    /// Para el efecto "ola" real usamos una fase fija por tile en el ángulo.
    private var jiggleAngle: Double {
        1.6 * (fase.truncatingRemainder(dividingBy: 2) == 0 ? 1 : -1)
    }
}

// MARK: - Drop delegate para reordenar tiles
private struct TileDropDelegate: DropDelegate {
    let destino: LugarGuardado
    @Binding var tiles: [LugarGuardado]
    @Binding var arrastrando: LugarGuardado?
    var onPersistir: () -> Void

    func dropEntered(info: DropInfo) {
        guard let arrastrando,
              arrastrando.id != destino.id,
              !destino.esFijo, !arrastrando.esFijo,
              let desde = tiles.firstIndex(where: { $0.id == arrastrando.id }),
              let hasta = tiles.firstIndex(where: { $0.id == destino.id })
        else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            let movido = tiles.remove(at: desde)
            // Tras remover, el índice destino puede correrse: recalculamos.
            if let nuevoHasta = tiles.firstIndex(where: { $0.id == destino.id }) {
                tiles.insert(movido, at: nuevoHasta)
            } else {
                tiles.insert(movido, at: hasta)
            }
        }
        onPersistir()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        DispatchQueue.main.async { arrastrando = nil }
        return true
    }
}

// MARK: - Preview nocturno del banner de paraderos (mini-mapa con focos)
/// Ilustración animada: calles oscuras + focos azules pulsando en las
/// posiciones de los paraderos iluminados (si ya cargaron; si no, layout fijo).
private struct BannerParaderosPreview: View {
    let cantidad: Int

    // Calles del mini-mapa (proporciones del contenedor)
    private static let calles: [(from: CGPoint, to: CGPoint)] = {
        let puntos = [(0.04, 0.78), (0.22, 0.62), (0.42, 0.70), (0.60, 0.46),
                      (0.78, 0.38), (0.97, 0.22), (0.12, 0.30), (0.35, 0.16),
                      (0.58, 0.10), (0.88, 0.72), (0.30, 0.90), (0.65, 0.82)]
        return [
            (p(0), p(1)), (p(1), p(2)), (p(2), p(3)), (p(3), p(4)), (p(4), p(5)),
            (p(6), p(7)), (p(7), p(8)), (p(2), p(7)), (p(3), p(8)),
            (p(1), p(6)), (p(4), p(9)), (p(10), p(2)), (p(11), p(9))
        ]
        func p(_ i: Int) -> CGPoint { CGPoint(x: puntos[i].0, y: puntos[i].1) }
    }()

    /// Focos en fracciones del contenedor: reales si hay paraderos cargados.
    private var focos: [CGPoint] {
        if let rutas = SeguridadView.paraderosCache, !rutas.isEmpty {
            let lats = rutas.map(\.lat)
            let lons = rutas.map(\.lon)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let rangoLat = max(maxLat - minLat, 0.0001)
            let rangoLon = max(maxLon - minLon, 0.0001)
            return rutas.map { p in
                CGPoint(x: 0.08 + (p.lon - minLon) / rangoLon * 0.84,
                        y: 0.85 - (p.lat - minLat) / rangoLat * 0.72)
            }
        }
        // Fallback decorativo mientras carga el feed
        return [(0.14, 0.62), (0.30, 0.48), (0.47, 0.58), (0.63, 0.32),
                (0.80, 0.26), (0.22, 0.24), (0.55, 0.78), (0.88, 0.55)].map {
            CGPoint(x: $0.0, y: $0.1)
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 0.5, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    // Noche
                    LinearGradient(colors: [Color(hex: "#0d1b3d"), Color(hex: "#123061")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

                    // Calles
                    Path { p in
                        for calle in Self.calles {
                            p.move(to: calle.from)
                            p.addLine(to: calle.to)
                        }
                    }
                    .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(.horizontal, 8)

                    Path { p in
                        for calle in Self.calles {
                            p.move(to: calle.from)
                            p.addLine(to: calle.to)
                        }
                    }
                    .stroke(Color(hex: "#5cc8ff").opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
                    .padding(.horizontal, 8)

                    // Focos con pulso desfasado
                    ForEach(Array(focos.enumerated()), id: \.offset) { i, foco in
                        let fase = Double(i) * 0.9
                        let brillo = 0.55 + 0.45 * sin(t * 2.2 + fase)
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#7fd4ff").opacity(0.22 * brillo))
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(Color(hex: "#8fd8ff"))
                                .frame(width: 12, height: 12)
                                .shadow(color: Color(hex: "#7fd4ff").opacity(brillo), radius: 6)
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(0.95)
                        }
                        .position(x: foco.x * geo.size.width, y: foco.y * geo.size.height)
                    }
                }
                .clipped()
            }
        }
        .overlay(alignment: .bottom) {
            // Cápsula de info
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#8fd8ff"))
                Text("Paraderos iluminados activos: \(max(cantidad, 24))")
                    .font(.bodySm)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("VER MAPA")
                    .font(.labelCapsSm)
                    .foregroundStyle(.white)
                    .appTracking(AppTracking.wideLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial).opacity(0.9))
            .padding(12)
        }
        .frame(height: 192)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

// MARK: - FAB style
private struct FABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    SeguridadView().environmentObject(AppRouter())
}

