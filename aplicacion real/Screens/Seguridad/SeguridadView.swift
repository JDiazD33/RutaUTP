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

            // FAB anclado a navbarHeight + 12
            fab

            // Navbar
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
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
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "heart.shield.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            Text("Seguridad")
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

    // MARK: - Summary bar
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
                showReportarSheet = true
            } label: {
                Text("Denunciar")
                    .font(.bodyXsMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Denunciar incidente")
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

    // MARK: - Lugares guardados
    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lugares Guardados")
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
                Spacer()
                Button {
                    router.navigate(to: .guardado)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                        Text("EDITAR")
                            .font(.labelCapsSm)
                            .appTracking(AppTracking.wideLabel)
                    }
                    .foregroundStyle(.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                lugarTile(nombre: "Casa", icon: "house.fill", bg: Color.primaryContainer.opacity(0.12), fg: .appPrimary, border: false) {
                    router.navigate(to: .guardado)
                }
                lugarTile(nombre: "UTP Trujillo", icon: "graduationcap.fill", bg: .appPrimary, fg: .white, border: true) {
                    router.navigate(to: .mapaPrincipal)
                }
                lugarTile(nombre: "Añadir", icon: "plus", bg: Color.surfaceContainerLow, fg: .outline, border: false, dashed: true) {
                    router.navigate(to: .guardado)
                }
            }
        }
    }

    private func lugarTile(nombre: String, icon: String, bg: Color, fg: Color, border: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
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

    // MARK: - FAB (anclado a navbarHeight + 12)
    private var fab: some View {
        HStack {
            Spacer()
            Button {
                showReportarSheet = true
            } label: {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(Color.appPrimary)
                            .shadow(color: .appPrimary.opacity(0.40), radius: 14, x: 0, y: 8)
                    )
            }
            .buttonStyle(FABStyle())
            .accessibilityLabel("Reportar incidente")
        }
        .padding(.trailing, 24)
        .padding(.bottom, tabBarHeight + 12)
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
