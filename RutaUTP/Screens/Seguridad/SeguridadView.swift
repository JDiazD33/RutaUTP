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

    // 24 publicaciones demo: una con foto y tres de texto por ventana de cuatro minutos.
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
            ("Los paraderos nuevos de Av. España tienen techo y cámaras, bien ahí.", .otro)
        ]
        let englishPosts = [
            "Buses are full on Av. Larco. Three passed without stopping on the way to UTP.",
            "Roadworks are causing delays at Óvalo Papal. Allow an extra 10 minutes.",
            "Taking Av. Miraflores at 7:30 AM avoids traffic on España.",
            "The C-01 driver was very kind and waited for an older woman running to the stop.",
            "Watch out for pickpockets at the Mercado Mayorista stop during rush hour.",
            "Av. América Sur is gridlocked after 6 PM. Mansiche may be a better option.",
            "The C-07 is quiet on Saturday mornings; seats are usually available.",
            "The stop across from UTP has had no lighting since Monday. I reported it to 105.",
            "A parade is slowing traffic on Av. César Vallejo. Try La Ribera.",
            "Tip: getting off one block before UTP on Piérola avoids about 5 minutes of traffic.",
            "A mototaxi ran a red light at España and Mansiche. Luckily it stopped in time.",
            "Huanchaco's waterfront is busy on Sundays. Leave early.",
            "The 6:20 AM bus reaches the Urb. El Recreo stop nearly empty.",
            "A combi crashed near Óvalo Faustino Sánchez. Traffic has been blocked for 40 minutes.",
            "The M-05 takes unusual detours to avoid traffic, but arrives quickly.",
            "The C-01 fare is S/ 2.50. Some drivers try to charge more at night.",
            "Av. Larco in Huanchaco gets congested around noon because of visitors.",
            "The new stops on Av. España have roofs and cameras. Great improvement."
        ]
        let tiempos = ["HACE 3 MIN", "HACE 8 MIN", "HACE 12 MIN", "HACE 20 MIN",
                       "HACE 35 MIN", "HACE 1 HORA", "HACE 2 HORAS"]
        let avatares: [(Color, Color)] = [
            (.primaryContainer, .onPrimaryContainer),
            (.secondaryContainer, .onSecondaryContainer),
            (.tertiaryContainer, .onTertiaryContainer)
        ]

        let originales = cuerpos.enumerated().map { i, par in
            let persona = nombres[i % nombres.count]
            let avatar = avatares[i % avatares.count]
            return ReporteComunidad(
                iniciales: persona.1,
                nombre: persona.0,
                hace: tiempos[(i * 3 + 1) % tiempos.count],
                tipo: par.1,
                cuerpo: par.0,
                cuerpoIngles: englishPosts[i],
                utiles: 6 + (i * 13) % 78,
                dislikes: 1 + (i * 7) % 9,
                comentarios: (i * 5) % 11,
                utilMarcado: i % 6 == 0,
                avatarColor: avatar.0,
                avatarForeground: avatar.1
            )
        }
        let ilustrados: [(String, String, TipoReporte, FotoComunidad, String, String)] = [
            ("Andrea M.", "AM", .alerta, .centro,
             "Ojo al esperar el micro en el centro: hay vehículos junto a la vereda. Busquen un punto de subida que deje libre el paso peatonal.",
             "Take care while waiting for a bus downtown: vehicles are next to the sidewalk. Choose a boarding point that keeps pedestrian access clear."),
            ("Víctor S.", "VS", .trafico, .papal,
             "Los accesos al Óvalo Papal pueden demorar el viaje. Salgan con tiempo y revisen su línea antes de ir al paradero.",
             "The approaches to Óvalo Papal can delay your trip. Leave with time to spare and check your line before heading to the stop."),
            ("Rocío F.", "RF", .sugerencia, .pizarro,
             "Para moverme a pie por el centro prefiero el paseo Pizarro. Al buscar un micro, reviso en el mapa el paradero de subida fuera del tramo peatonal.",
             "I prefer the Pizarro pedestrian street when walking downtown. To catch a bus, I check the map for a boarding stop outside the pedestrian section."),
            ("Héctor Z.", "HZ", .otro, .papal,
             "Comparto esta referencia del Óvalo Papal para quienes recién conocen Trujillo. Confirmen el sentido de su línea antes de abordar.",
             "Sharing this reference of Óvalo Papal for newcomers to Trujillo. Check your line's direction before boarding."),
            ("Natalia O.", "NO", .alerta, .pizarro,
             "Al salir del paseo Pizarro, atentos a los cruces con calles vehiculares. Antes de seguir hacia el paradero, miren ambos lados.",
             "Watch for crossings with vehicle traffic when leaving Pizarro street. Look both ways before continuing to your stop."),
            ("Iván P.", "IP", .trafico, .centro,
             "En las calles del centro se comparte espacio con taxis y vehículos de reparto. Evitemos pedir al micro que se detenga en una esquina.",
             "Downtown streets share space with taxis and delivery vehicles. Avoid asking the bus to stop at a corner.")
        ]
        // Cada bloque conserva los reportes existentes y añade una publicación con foto.
        return ilustrados.enumerated().flatMap { index, dato -> [ReporteComunidad] in
            let nuevo = ReporteComunidad(iniciales: dato.1, nombre: dato.0,
                hace: "HACE 3 MIN", tipo: dato.2, cuerpo: dato.4, cuerpoIngles: dato.5,
                foto: dato.3, utiles: 8 + index * 3, comentarios: 2,
                avatarColor: .secondaryContainer, avatarForeground: .onSecondaryContainer)
            return [nuevo] + Array(originales[(index * 3)..<(index * 3 + 3)])
        }
    }()

    /// Índice de ventana de 4 minutos (6 ventanas para 24 reportes de a 4).
    /// DEBUG: --comunidad N fuerza la ventana para pruebas visuales.
    private var indiceVentana: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--comunidad"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            return n % (Self.reportes.count / 4)
        }
        #endif
        let epoch = Int(Date().timeIntervalSinceReferenceDate)
        return (epoch / 240) % (Self.reportes.count / 4)
    }

    private var reportesVisibles: [ReporteComunidad] {
        let inicio = indiceVentana * 4
        return Array(Self.reportes[inicio..<(inicio + 4)])
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
                        if buscandoZona { ProgressView().tint(.white) }
                        Label(L.t("Ver ubicación en el mapa", "View location on map"), systemImage: "map.fill")
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.appPrimary))
                }.disabled(buscandoZona)
                Spacer(minLength: 0)
            }
            .padding(24).presentationDetents([.medium, .large]).seguirTemaForzado()
            .onAppear { errorZona = nil }
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
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.appPrimary))
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
                Text(L.t("Alertas hoy:", "Alerts today:") + " **2**")
                    .font(.bodySmMedium)
                Text(L.t("Paraderos para explorar: \(paraderosIluminados.count)", "Stops to explore: \(paraderosIluminados.count)"))
                    .font(.bodySmMedium)
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
        if let seleccion {
            guardarTilesSeleccion(seleccion)
            elegidos = noFijos.filter { seleccion.contains($0.id) }
        } else if let idsGuardados = idsTilesGuardados() {
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
                    .accessibilityLabel(L.t("Eliminar \(lugar.nombre)", "Remove \(lugar.nombre)"))
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
                Text(L.signable("seguridad.rutas_seguras", "Paraderos y referencias", "Stops and landmarks"))
                    .font(.headlineSm)
                    .seniable("seguridad.rutas_seguras", distintivoDx: 10)
            }

            Button {
                AppHaptics.impact(.light)
                showParaderosMap = true
            } label: {
                BannerParaderosPreview(cantidad: paraderosIluminados.count)
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
        let names = ["Óvalo Papal", "Avenida España 1450", "Comisaría Víctor Larco", "Real Plaza",
                     "Plaza de Armas", "Mall Aventura", "Paseo de los Héroes", "Hospital Belén",
                     "Estadio Mansiche", "Cineplanet"]
        Task { @MainActor in
            defer { buscandoZona = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = names[zona.id] + ", Trujillo, Perú"
            request.region = MKCoordinateRegion(center: GTFSRepository.coordenadaUTP,
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

    // MARK: - Comunidad (24 publicaciones, rotan cada 4 minutos)
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
                        Text(L.t("Opiniones de demostración · cada 4 min", "Demo posts · rotate every 4 min"))
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

            // Se re-evalúa cada 4 min → rota la ventana de opiniones.
            TimelineView(.periodic(from: .now, by: 240)) { _ in
                VStack(spacing: 12) {
                    ForEach(reportesVisibles) { r in
                        ReporteCard(reporte: r, reacciones: reacciones)
                        .onTapGesture { selectedReporte = r }
                        .accessibilityAction(named: Text(L.t("Ver publicación", "View post"))) { selectedReporte = r }
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
        f.locale = Locale(identifier: L.esIngles ? "en_US" : "es_PE")
        f.dateFormat = L.esIngles ? "EEEE, MMMM d" : "EEEE d 'de' MMMM"
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

// MARK: - Votos de la comunidad (like / dislike)
/// Reacción del usuario por reporte. Vive en la sesión (demo; no persiste).
/// Tocar el mismo voto lo retira; votar el lado opuesto cambia el voto.
final class ComunidadReacciones: ObservableObject {
    enum Voto { case ninguno, util, noUtil }

    @Published private var votos: [UUID: Voto] = [:]

    func voto(para reporte: ReporteComunidad) -> Voto {
        votos[reporte.id] ?? .ninguno
    }

    func votar(_ reporte: ReporteComunidad, a nuevo: Voto) {
        votos[reporte.id] = (voto(para: reporte) == nuevo) ? .ninguno : nuevo
        AppHaptics.selection()
    }

    func utiles(_ reporte: ReporteComunidad) -> Int {
        reporte.utiles + (voto(para: reporte) == .util ? 1 : 0)
    }

    func noUtiles(_ reporte: ReporteComunidad) -> Int {
        reporte.dislikes + (voto(para: reporte) == .noUtil ? 1 : 0)
    }
}

// MARK: - Reporte card
private struct ReporteCard: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(reporte.avatarColor).frame(width: 40, height: 40)
                    Text(reporte.iniciales)
                        .font(.labelCapsMd)
                        .foregroundStyle(reporte.avatarForeground)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reporte.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(reporte.tiempoLocalizado)
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
                Spacer()
                Text(reporte.tipo.titulo.uppercased())
                    .font(.labelCapsSm)
                    .foregroundStyle(reporte.tipo.foreground)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(reporte.tipo.background))
            }

            Text(reporte.cuerpoLocalizado)
                .font(.system(size: 15))
                .lineSpacing(3)
                .lineLimit(4)
                .foregroundStyle(.onSurface)

            if let foto = reporte.foto {
                FotoReporteView(foto: foto)
            }

            Divider().overlay(Color.outlineVariant.opacity(0.2))
            HStack(spacing: 8) {
                votoButton(.util)
                votoButton(.noUtil)

                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(reporte.comentarios)")
                        .font(.bodySm)
                }
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L.t("\(reporte.comentarios) comentarios", "\(reporte.comentarios) comments"))

                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func votoButton(_ tipo: ComunidadReacciones.Voto) -> some View {
        let esUtil = tipo == .util
        let activo = reacciones.voto(para: reporte) == tipo
        let cantidad = esUtil ? reacciones.utiles(reporte) : reacciones.noUtiles(reporte)
        let color: Color = esUtil ? .appPrimary : .appError

        Button {
            reacciones.votar(reporte, a: tipo)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: esUtil
                      ? (activo ? "hand.thumbsup.fill" : "hand.thumbsup")
                      : (activo ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                    .font(.system(size: 13, weight: .semibold))
                if esUtil {
                    Text(L.t("Útil", "Useful") + " (\(cantidad))")
                        .font(.bodySm)
                } else {
                    Text("\(cantidad)")
                        .font(.bodySm)
                }
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(esUtil ? L.t("Me es útil", "Helpful") : L.t("No me es útil", "Not helpful"))
        .accessibilityValue(L.t("\(cantidad) votos", "\(cantidad) votes"))
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

// MARK: - Reporte Detail Sheet
private struct ReporteDetailSheet: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones
    @Environment(\.dismiss) private var dismiss

    /// Comentarios de muestra, deterministas por reporte (misma semilla →
    /// mismos comentarios mientras la sesión esté viva).
    private var comentariosMuestra: [(nombre: String, iniciales: String, texto: String)] {
        let semilla = reporte.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let autores = [("Luisa P.", "LP"), ("Marco T.", "MT"), ("Diana R.", "DR"),
                       ("Sergio V.", "SV"), ("Pilar A.", "PA"), ("César H.", "CH")]
        let textos = [
            L.t("Totalmente de acuerdo.", "Totally agree."),
            L.t("Gracias por avisar a tiempo.", "Thanks for the heads-up."),
            L.t("Me pasó igual ayer por la mañana.", "Same thing happened to me yesterday morning."),
            L.t("Justo venía de ahí, horrible.", "I was just there, it was awful."),
            L.t("Buen dato, no lo sabía.", "Good to know, I had no idea."),
            L.t("Hay que tener cuidado ahí siempre.", "We always have to be careful there."),
            L.t("Confirmo, sigue igual.", "Confirmed, still the same.")
        ]
        return (0..<reporte.comentarios).map { k in
            let autor = autores[(semilla + k) % autores.count]
            let texto = textos[(semilla + k * 2) % textos.count]
            return (autor.0, autor.1, texto)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Autor
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
                            Text(reporte.tiempoLocalizado)
                                .font(.labelCapsSm)
                                .foregroundStyle(.onSurfaceVariant)
                                .appTracking(AppTracking.wideLabel)
                        }
                        Spacer()
                        Text(reporte.tipo.titulo.uppercased())
                            .font(.labelCapsMd)
                            .foregroundStyle(reporte.tipo.foreground)
                            .appTracking(AppTracking.wideLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(reporte.tipo.background))
                    }

                    Text(reporte.cuerpoLocalizado)
                        .font(.bodyLg)
                        .foregroundStyle(.onSurface)

                    if let foto = reporte.foto {
                        FotoReporteView(foto: foto, detalle: true)
                    }

                    // Votos interactivos
                    HStack(spacing: 10) {
                        votoButton(.util)
                        votoButton(.noUtil)
                        Spacer()
                    }

                    Divider()

                    // Comentarios
                    Text(L.t("COMENTARIOS (\(reporte.comentarios))", "COMMENTS (\(reporte.comentarios))"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)

                    if reporte.comentarios == 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 18))
                                .foregroundStyle(.onSurfaceVariant.opacity(0.5))
                            Text(L.t("Aún no hay comentarios. Sé el primero en comentar.",
                                     "No comments yet. Be the first to comment."))
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(comentariosMuestra.enumerated()), id: \.offset) { _, c in
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color.surfaceContainerHigh).frame(width: 30, height: 30)
                                        Text(c.iniciales)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.onSurfaceVariant)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.nombre)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.onSurface)
                                        Text(c.texto)
                                            .font(.bodySm)
                                            .foregroundStyle(.onSurfaceVariant)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.surfaceContainerLow)
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }

            Button { dismiss() } label: {
                Text(L.t("Cerrar", "Close"))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                    .foregroundStyle(.white)
                    .font(.bodyMdMedium)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func votoButton(_ tipo: ComunidadReacciones.Voto) -> some View {
        let esUtil = tipo == .util
        let activo = reacciones.voto(para: reporte) == tipo
        let cantidad = esUtil ? reacciones.utiles(reporte) : reacciones.noUtiles(reporte)
        let color: Color = esUtil ? .appPrimary : .appError

        Button {
            reacciones.votar(reporte, a: tipo)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: esUtil
                      ? (activo ? "hand.thumbsup.fill" : "hand.thumbsup")
                      : (activo ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                    .font(.system(size: 14, weight: .semibold))
                Text(esUtil
                     ? L.t("Útil", "Useful") + " (\(cantidad))"
                     : L.t("No útil", "Not helpful") + " (\(cantidad))")
                    .font(.bodySmMedium)
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.outlineVariant.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
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
                Text(L.t("Elige los lugares que verás aquí", "Choose which places appear here"))
                    .font(.headlineMd)
                Text(L.t("Tus lugares guardados de la pestaña Guardado. UTP siempre aparece.", "Your saved places. UTP always appears."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)

                if lugares.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.onSurfaceVariant)
                        Text(L.t("Aún no tienes lugares guardados", "No saved places yet"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        Button {
                            irAGuardado()
                        } label: {
                            Label(L.t("Ir a Guardado", "Go to Saved"), systemImage: "plus.circle.fill")
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
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
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
                            p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                            p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
                        }
                    }
                    .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(.horizontal, 8)

                    Path { p in
                        for calle in Self.calles {
                            p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                            p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
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
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                Label(L.t("EXPLORA TU CIUDAD", "EXPLORE YOUR CITY"), systemImage: "map.fill")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(Color(hex: "#8FD8FF"))
                Text(L.t("Encuentra tu próxima parada", "Find your next stop"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .bottom) {
            // Cápsula de info
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#8fd8ff"))
                Text(L.t("\(cantidad) paraderos por explorar", "\(cantidad) stops to explore"))
                    .font(.bodySm)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(L.t("VER MAPA", "OPEN MAP"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.white)
                    .appTracking(AppTracking.wideLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(12)
        }
        .frame(height: 212)
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


// MARK: - Foto de referencia compartida entre publicación y detalle
private struct FotoReporteView: View {
    let foto: FotoComunidad
    var detalle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if detalle {
                    Image(foto.asset).resizable().scaledToFit()
                } else {
                    GeometryReader { geo in
                        Image(foto.asset).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: 180)
                            .clipped()
                    }
                    .frame(height: 180)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(L.t("Foto de archivo: ", "Archive photo: ") + foto.lugar)
            Label(foto.lugar, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onSurface)
            Text(L.t("PUBLICACIÓN DEMO · FOTO DE REFERENCIA", "DEMO POST · REFERENCE PHOTO"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.onSurfaceVariant)
            Text("© " + foto.autor + " · " + foto.fecha + " · CC BY-SA " + foto.licencia)
                .font(.system(size: 10))
                .foregroundStyle(Color.onSurfaceVariant)
            if detalle {
                Text(L.t("Autor del post ficticio. La foto es de archivo y no documenta un incidente actual. Vista previa recortada; imagen completa arriba.",
                         "Fictional post author. This archive photo does not document a current incident. Cropped preview; full image above."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                HStack(spacing: 16) {
                    if let url = URL(string: foto.fuente) { Link(L.t("Ver fuente", "View source"), destination: url) }
                    if let url = URL(string: foto.licenciaURL) { Link(L.t("Licencia", "License"), destination: url) }
                }
                .font(.caption.weight(.medium))
            }
        }
    }
}
