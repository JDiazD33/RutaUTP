//
//  SeguridadView.swift
//  RutaUTP
//
//  Pantalla de seguridad con resumen, lugares, rutas seguras y comunidad.
//

import SwiftUI

struct SeguridadView: View {
    @EnvironmentObject private var router: AppRouter

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
        )
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                summaryBar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        greetingCard
                        lugaresSection
                        rutasSegurasSection
                        comunidadSection
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }

            BottomNavBar()
                .background(Color.clear)
                .allowsHitTesting(true)

            fab
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.shield.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Seguridad")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56, alignment: .center)
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
            Button {} label: {
                Text("Denunciar")
                    .font(.bodyXsMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            Button {} label: {
                Text("Llamar 105")
                    .font(.bodyXsMedium)
                    .foregroundStyle(.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceContainerHigh))
            }
            .buttonStyle(.plain)
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

    // MARK: - Lugares guardados (grid 3 cols)
    private var lugaresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lugares Guardados")
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                lugarTile(nombre: "Casa", icon: "house.fill", bg: Color.primaryContainer.opacity(0.12), fg: .appPrimary, border: false)
                lugarTile(nombre: "UTP Trujillo", icon: "graduationcap.fill", bg: .appPrimary, fg: .white, border: true)
                lugarTile(nombre: "Añadir", icon: "plus", bg: Color.surfaceContainerLow, fg: .outline, border: false, dashed: true)
            }
        }
    }

    private func lugarTile(nombre: String, icon: String, bg: Color, fg: Color, border: Bool, dashed: Bool = false) -> some View {
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

    // MARK: - Rutas seguras hoy
    private var rutasSegurasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.tertiary)
                Text("Rutas Seguras Hoy")
                    .font(.headlineSm)
            }

            // Mapa nocturno
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.tertiary.opacity(0.55), Color.secondary.opacity(0.45)],
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

                    ForEach([CGPoint(x: w * 0.20, y: h * 0.62),
                             CGPoint(x: w * 0.40, y: h * 0.50),
                             CGPoint(x: w * 0.70, y: h * 0.30),
                             CGPoint(x: w * 0.85, y: h * 0.25)], id: \.x) { p in
                        Circle().fill(Color.tertiaryFixedDim)
                            .frame(width: 8, height: 8)
                            .position(p)
                    }
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

            VStack(spacing: 12) {
                rutaSeguraRow(
                    icon: "moon.zzz.fill",
                    iconColor: .onTertiary,
                    iconBg: .tertiary,
                    title: "Zona Segura: Óvalo Papal",
                    subtitle: "Patrullaje activo y alta iluminación hasta las 11:00 PM.",
                    accent: .tertiary
                )
                rutaSeguraRow(
                    icon: "eye.fill",
                    iconColor: .onSecondary,
                    iconBg: .secondary,
                    title: "Paradero UTP (Entrada)",
                    subtitle: "Monitoreo por cámaras de seguridad municipal.",
                    accent: nil
                )
            }
        }
    }

    private func rutaSeguraRow(icon: String,
                               iconColor: Color,
                               iconBg: Color,
                               title: String,
                               subtitle: String,
                               accent: Color?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
            }
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(iconBg).frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(subtitle)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
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
                Text("VER TODOS")
                    .font(.labelCapsMd)
                    .foregroundStyle(.appPrimary)
                    .appTracking(AppTracking.wideLabel)
            }
            VStack(spacing: 12) {
                ForEach(reportes) { r in
                    ReporteCard(reporte: r)
                }
            }
        }
    }

    // MARK: - FAB
    private var fab: some View {
        Button {} label: {
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
        .padding(.trailing, 24)
        .padding(.bottom, 90)
        .accessibilityLabel("Reportar incidente")
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
