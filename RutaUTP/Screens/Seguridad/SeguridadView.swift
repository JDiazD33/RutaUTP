//
//  SeguridadView.swift
//  RutaUTP
//
//  Pantalla de seguridad. Layout ZStack(alignment: .bottom) + ignoresSafeArea.
//  FAB anclado a navbarHeight + 12 para estar pegado encima de la navbar.
//

import SwiftUI
import UIKit

struct SeguridadView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var showReportarSheet = false
    @State private var showLlamarAlert = false
    @State private var selectedReporte: ReporteComunidad?
    @State private var selectedRutaIndex: Int? = nil

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

    private let reportes: [ReporteComunidad] = [
        ReporteComunidad(
            iniciales: "JD", nombre: "Jorge D.", hace: "HACE 5 MIN",
            tipo: .alerta,
            cuerpo: "Micro lleno en Av. Larco. Pasaron 3 sin parar hacia la UTP.",
            utiles: 12, comentarios: 2
        ),
        ReporteComunidad(
            iniciales: "MA", nombre: "Maria A.", hace: "HACE 15 MIN",
            tipo: .trafico,
            cuerpo: "Demora en Óvalo Papal por obras. Considerar 10 min adicionales.",
            utiles: 45, comentarios: 8, utilMarcado: true,
            avatarColor: .secondaryContainer, avatarForeground: .onSecondaryContainer
        ),
        ReporteComunidad(
            iniciales: "RC", nombre: "Rosa C.", hace: "HACE 1 HORA",
            tipo: .sugerencia,
            cuerpo: "Tomar Av. Miraflores a las 7:30 AM evita el tráfico de España.",
            utiles: 28, comentarios: 5,
            avatarColor: .tertiaryContainer, avatarForeground: .onTertiaryContainer
        )
    ]

    private let rutasSeguras: [RutaSegura] = [
        RutaSegura(id: 0,
                   titulo: "Zona Segura: Óvalo Papal",
                   descripcion: "Patrullaje activo y alta iluminación hasta las 11:00 PM.",
                   icono: "moon.zzz.fill", iconoBg: .tertiary, iconoFg: .onTertiary,
                   accent: .tertiary),
        RutaSegura(id: 1,
                   titulo: "Paradero UTP (Entrada)",
                   descripcion: "Monitoreo por cámaras de seguridad municipal.",
                   icono: "eye.fill", iconoBg: .secondary, iconoFg: .onSecondary,
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
                        greetingCard
                        lugaresSection
                        rutasSegurasSection
                        comunidadSection
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
            #endif
        }
        .sheet(isPresented: $showReportarSheet) {
            ReportarSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedReporte) { reporte in
            ReporteDetailSheet(reporte: reporte)
                .presentationDetents([.medium, .large])
        }
        .alert("Llamar al 105", isPresented: $showLlamarAlert) {
            Button("Llamar") {
                if let url = URL(string: "tel://105") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se abrirá la aplicación de teléfono para llamar a la central de emergencias.")
        }
        .alert(selectedRutaIndex != nil ? rutasSeguras[selectedRutaIndex ?? 0].titulo : "",
               isPresented: Binding(
                get: { selectedRutaIndex != nil },
                set: { if !$0 { selectedRutaIndex = nil } }
               )) {
            Button("Ver en mapa") {
                router.navigate(to: .mapaPrincipal)
                selectedRutaIndex = nil
            }
            Button("Cerrar", role: .cancel) { selectedRutaIndex = nil }
        } message: {
            if let idx = selectedRutaIndex {
                Text(rutasSeguras[idx].descripcion)
            }
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
                Text("Seguridad")
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
                    Text("Reportar")
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
                Text("Alertas hoy: **2**")
                    .font(.bodySmMedium)
                Text("Paraderos iluminados: **24**")
                    .font(.bodySmMedium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showLlamarAlert = true
            } label: {
                Text("Llamar 105")
                    .font(.bodyXsMedium)
                    .foregroundStyle(.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceContainerHigh))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Llamar al 105 emergencias")
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
                Text("Lugares Guardados")
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
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
                        Text(modoEdicion ? "LISTO" : "EDITAR")
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
        lugarTile(nombre: modoEdicion ? "Añadir" : (tilesActuales.count <= 1 ? "Añadir" : "Elegir"),
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
                Text("Rutas Seguras Hoy")
                    .font(.headlineSm)
            }

            Button {
                router.navigate(to: .mapaPrincipal)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [Color.tertiary.opacity(0.65), Color.secondary.opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        Path { p in
                            p.move(to: CGPoint(x: 20, y: h * 0.65))
                            p.addLine(to: CGPoint(x: w * 0.4, y: h * 0.50))
                            p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.30))
                            p.addLine(to: CGPoint(x: w - 20, y: h * 0.20))
                        }
                        .stroke(Color.tertiaryFixedDim.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
                    }
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.60)],
                        startPoint: .top, endPoint: .bottom
                    )
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.tertiaryFixedDim)
                        Text("Paraderos iluminados activos: 24")
                            .font(.bodySm)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.85)
                    )
                    .padding(12)
                }
                .frame(height: 192)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            VStack(spacing: 12) {
                ForEach(rutasSeguras) { ruta in
                    Button {
                        selectedRutaIndex = ruta.id
                    } label: {
                        rutaSeguraRow(ruta: ruta)
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    Text(ruta.descripcion)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
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

    // MARK: - Comunidad
    private var comunidadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.appPrimary)
                    Text("Comunidad")
                        .font(.headlineSm)
                }
                Spacer()
                Button {
                    showReportarSheet = true
                } label: {
                    Text("AÑADIR")
                        .font(.labelCapsSm)
                        .foregroundStyle(.appPrimary)
                        .appTracking(AppTracking.wideLabel)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 12) {
                ForEach(reportes) { r in
                    Button {
                        selectedReporte = r
                    } label: {
                        ReporteCard(reporte: r)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }



    // MARK: - Helpers
    private var saludoDinamico: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Buenos días"
        case 12..<19: return "Buenas tardes"
        default:      return "Buenas noches"
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
private struct ReportarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reportar incidente")
                    .font(.headlineMd)
                VStack(alignment: .leading, spacing: 8) {
                    Text("TIPO DE REPORTE")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Picker("Tipo", selection: $tipo) {
                        Text("Alerta").tag(TipoReporte.alerta)
                        Text("Tráfico").tag(TipoReporte.trafico)
                        Text("Sugerencia").tag(TipoReporte.sugerencia)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("DESCRIPCIÓN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    TextField("¿Qué sucede?", text: $descripcion, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                }
                Spacer()
                Button {
                    showSuccess = true
                } label: {
                    Text("Enviar reporte")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                }
                .buttonStyle(.plain)
                .disabled(descripcion.isEmpty)
                .opacity(descripcion.isEmpty ? 0.5 : 1.0)
            }
            .padding(20)
        }
        .alert("Reporte enviado", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Gracias por colaborar con la comunidad.")
        }
    }
}

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
            Text("Guardar selección")
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

