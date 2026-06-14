//
//  DetalleRutaView.swift
//  RutaUTP
//
//  Detalle de una ruta: mapa superior, card de detalle, pasos y CTA.
//

import SwiftUI

struct DetalleRutaView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    mapHero
                    detailCard
                        .padding(.horizontal, 20)
                        .offset(y: -32)
                        .zIndex(10)
                    statsGrid
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    stepsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    iniciarButton
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 110)
                }
            }
            BottomNavBar()
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                router.navigate(to: .mapaPrincipal)
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volver")

            Image(systemName: "bus.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.appPrimary)
            Text("Rutas")
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

    // MARK: - Hero map
    private var mapHero: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                LinearGradient(
                    colors: [Color.tertiary.opacity(0.6), Color.secondary.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Ruta
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.85))
                        p.addCurve(
                            to: CGPoint(x: w * 0.55, y: h * 0.55),
                            control1: CGPoint(x: w * 0.25, y: h * 0.75),
                            control2: CGPoint(x: w * 0.40, y: h * 0.65)
                        )
                        p.addCurve(
                            to: CGPoint(x: w * 0.90, y: h * 0.25),
                            control1: CGPoint(x: w * 0.70, y: h * 0.45),
                            control2: CGPoint(x: w * 0.80, y: h * 0.35)
                        )
                    }
                    .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [12, 6]))
                }
            }
            .frame(height: 353)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(Color.appPrimary.opacity(0.05))

            // Badge ruta segura
            HStack(spacing: 6) {
                Image(systemName: "heart.shield.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("RUTA SEGURA")
                    .font(.labelCapsMd)
                    .appTracking(AppTracking.wideLabel)
            }
            .foregroundStyle(.onTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.tertiary.opacity(0.85)))
            )
            .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
            .padding(16)
        }
    }

    // MARK: - Detail card
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.appPrimary)
                    .frame(width: 6, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Línea B - Empresa Salaverry")
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text("Destino: UTP Trujillo")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LLEGA EN")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onPrimaryContainer)
                        .appTracking(AppTracking.wideLabel)
                    Text("4 min")
                        .font(.displayNumberMd)
                        .foregroundStyle(.onPrimaryContainer)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primaryContainer))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
        )
    }

    // MARK: - Stats grid
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            StatTile(icon: "clock.fill", iconColor: .appPrimary, label: "TIEMPO", value: "20 min")
            StatTile(icon: "creditcard.fill", iconColor: .appPrimary, label: "COSTO", value: "S/ 1.50")
            StatTile(icon: "arrow.triangle.2.circlepath", iconColor: .appPrimary, label: "TRANSBORDOS", value: "0")
            StatTile(icon: "chart.bar.fill", iconColor: .secondary, label: "CONGESTIÓN", value: "Media")
        }
    }

    // MARK: - Steps
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Guía paso a paso")
                .font(.headlineXs)
                .foregroundStyle(.onSurface)

            VStack(spacing: 0) {
                stepRow(
                    number: "1",
                    title: "Camina al paradero Av. España",
                    subtitle: "250 metros • 3 min aprox.",
                    icon: "figure.walk",
                    color: .surfaceContainerHighest,
                    foreground: .onSurface,
                    isLast: false
                )
                stepRow(
                    number: "2",
                    title: "Sube a Línea B",
                    subtitle: "Empresa Salaverry • 15 min de viaje",
                    icon: "bus.fill",
                    color: .appPrimary,
                    foreground: .white,
                    isLast: false
                )
                stepRow(
                    number: "3",
                    title: "Baja en frontis UTP",
                    subtitle: "Llegada a destino final",
                    icon: "graduationcap.fill",
                    color: .tertiary,
                    foreground: .white,
                    isLast: true
                )
            }
        }
    }

    private func stepRow(number: String,
                          title: String,
                          subtitle: String,
                          icon: String,
                          color: Color,
                          foreground: Color,
                          isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(color, lineWidth: 2))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(foreground)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.surfaceContainerHighest)
                        .frame(width: 2, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)")
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

    // MARK: - CTA
    private var iniciarButton: some View {
        Button {} label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("Iniciar Navegación")
                    .font(.headlineSm)
            }
            .foregroundStyle(.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primaryContainer)
                    .shadow(color: .primaryContainer.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Iniciar navegación")
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
                Circle().fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
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

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    DetalleRutaView().environmentObject(AppRouter())
}
