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

    /// Alertas del feed de comunidad, contadas del MISMO array que alimenta
    /// las cards. Antes la barra de resumen mostraba un "2" escrito a mano
    /// que no correspondía a ningún dato; así el número no puede
    /// desincronizarse del contenido.
    private static var alertasEnFeed: Int {
        reportes.filter { $0.tipo == .alerta }.count
    }

    /// Publicaciones por ventana del feed de comunidad.
    private static let tamanoVentana = 4

    /// Número de ventanas del feed.
    ///
    /// Tolerante a un total que no sea múltiplo exacto del tamaño de ventana:
    /// antes se calculaba como `reportes.count / 4` y `reportesVisibles`
    /// indexaba `[inicio..<inicio+4]`, así que añadir o quitar una publicación
    /// sin respetar el bloque provocaba un índice fuera de rango al dibujar.
    private static var numeroDeVentanas: Int {
        max(1, Int(ceil(Double(reportes.count) / Double(tamanoVentana))))
    }

    /// Índice de ventana de 4 minutos (6 ventanas para 24 reportes de a 4).
    /// DEBUG: --comunidad N fuerza la ventana para pruebas visuales.
    private var indiceVentana: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--comunidad"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            return n % Self.numeroDeVentanas
        }
        #endif
        let epoch = Int(Date().timeIntervalSinceReferenceDate)
        return (epoch / 240) % Self.numeroDeVentanas
    }

    private var reportesVisibles: [ReporteComunidad] {
        let inicio = indiceVentana * Self.tamanoVentana
        let fin = min(inicio + Self.tamanoVentana, Self.reportes.count)
        guard inicio < fin else { return [] }
        return Array(Self.reportes[inicio..<fin])
    }

    // 10 puntos/zonas de seguridad de Trujillo; se deslizan como carrusel.
    private var rutasSeguras: [RutaSegura] {
        [
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
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            // Contenido scrollable
            VStack(spacing: 0) {
                header
                summaryBar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        if Self.soloComunidadDebug {
                            comunidadSection
                        } else if Self.soloZonasDebug {
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
        .task {
            // Paraderos iluminados: selección determinista sobre el feed GTFS.
            if paraderosIluminados.isEmpty {
                let feed = await GTFSRepository.shared.rutas()
                paraderosIluminados = ParaderosIluminados.seleccionar(feed)
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
                // Sin concatenar ni Markdown: el texto se resuelve como un
                // String de runtime, así que "**2**" se dibujaba con los
                // asteriscos literales a la vista.
                Text(L.t("Alertas hoy: \(Self.alertasEnFeed)",
                         "Alerts today: \(Self.alertasEnFeed)"))
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
                }
                lugarTileAñadir
            }
        }
    }

    private func lugarTileLugar(_ lugar: LugarGuardado) -> some View {
        let esArrastrado = lugaresVM.arrastrando?.id == lugar.id
        return lugarTile(nombre: lugar.nombre,
                         icon: lugar.categoria.icono,
                         bg: lugar.esFijo ? Color.appPrimary : Color.primaryContainer.opacity(0.12),
                         fg: lugar.esFijo ? .white : .appPrimary,
                         border: lugar.esFijo,
                         badgeFrecuente: lugar.esFrecuente,
                         faseJiggle: Double(lugaresVM.tilesActuales.firstIndex(where: { $0.id == lugar.id }) ?? 0) * 1.7)
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
                            lugaresVM.eliminar(lugar)
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
        .modifier(JiggleEffect(active: lugaresVM.modoEdicion && !dashed, fase: faseJiggle))
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
        let patron = L.esIngles ? "EEEE, MMMM d" : "EEEE d 'de' MMMM"
        return FormatoFecha.formateador(patron: patron, locale: FormatoFecha.localeActivo)
            .string(from: Date())
            .capitalized
    }
}

// MARK: - Reportar Sheet
// ReportarSheet vive en Design/Components/ReportarSheet.swift (compartido
// con el Mapa). Ver ahí el diseño completo.

