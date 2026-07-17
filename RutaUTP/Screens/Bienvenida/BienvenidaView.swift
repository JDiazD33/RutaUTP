//
//  BienvenidaView.swift
//  RutaUTP
//
//  Pantalla de bienvenida con hero, cards de features y CTA.
//

import SwiftUI

struct BienvenidaView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var isPressed = false
    @State private var showLegalSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        llegandocard
                            .padding(.top, 8)

                        busImage
                            .padding(.horizontal, 20)

                        heroText
                            .padding(.horizontal, 20)

                        pageDots

                        featureGrid
                            .padding(.horizontal, 20)

                        ctaButton
                            .padding(.horizontal, 20)

                        legalFooter
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: 428)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showLegalSheet) {
            LegalSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sub-vistas

    private var progressBar: some View {
        LinearGradient(
            colors: [Color.primaryFixed.opacity(0.6), .appPrimary.opacity(0.6)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 4)
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Ruta UTP Trujillo")
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
            Button {
                router.navigate(to: .mapaPrincipal)
            } label: {
                Text("Saltar")
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Saltar introducción")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appBackground)
    }

    private var llegandocard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 48, height: 48)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 8, x: 0, y: 2)
                Image(systemName: "bus.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("LLEGANDO EN")
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabelCaps)
                Text("3 min")
                    .font(.displayNumberLg)
                    .foregroundStyle(.appPrimary)
                    .lineSpacing(-2)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
    }

    private var busImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.black)
            Image(systemName: "bus.fill")
                .resizable()
                .scaledToFit()
                .padding(60)
                .foregroundStyle(.white.opacity(0.85))
            // Si existiera la imagen "bus", la usaríamos:
            // Image("bus").resizable().scaledToFill()
        }
        .frame(height: 290)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 14)
    }

    private var heroText: some View {
        VStack(spacing: 12) {
            Text("Llega a la UTP sin perderte")
                .font(.displayLg)
                .foregroundStyle(.onSurface)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .frame(maxWidth: .infinity)
            Text("Encuentra la ruta exacta desde tu ubicación hasta el campus sin complicaciones.")
                .font(.bodyLg)
                .foregroundStyle(.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.appPrimary)
                .frame(width: 40, height: 8)
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 8, height: 8)
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 8, height: 8)
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            FeatureCard(
                icon: "heart.shield.fill",
                iconColor: .appPrimary,
                label: "SEGURIDAD",
                title: "Rutas nocturnas monitoreadas."
            )
            FeatureCard(
                icon: "creditcard.fill",
                iconColor: .tertiary,
                label: "AHORRO",
                title: "Precios de micros y combis actualizados."
            )
        }
    }

    private var ctaButton: some View {
        Button {
            router.navigate(to: .mapaPrincipal)
        } label: {
            HStack(spacing: 8) {
                Text("Comenzar")
                    .font(.displayLgPhone)
                    .foregroundStyle(.white)
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appPrimary)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 14, x: 0, y: 8)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Comenzar a usar la aplicación")
    }

    private var legalFooter: some View {
        (
            Text("Al continuar, aceptas nuestros ")
                .foregroundStyle(.onSurfaceVariant)
            + Text("Términos de Servicio")
                .foregroundStyle(.appPrimary)
                .underline()
        )
        .font(.bodySm)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feature Card
private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconColor)
                .padding(.bottom, 2)
            Text(label)
                .font(.labelCapsMd)
                .foregroundStyle(.onSurface)
                .appTracking(AppTracking.wideLabelMd)
            Text(title)
                .font(.bodyLg)
                .foregroundStyle(.onSurfaceVariant)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .frame(minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surfaceContainer)
        )
    }
}

// MARK: - Pressable button style
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Legal sheet
private struct LegalSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Términos de Servicio")
                    .font(.headlineMd)
                Text("Ruta UTP Trujillo es una aplicación prototipo que facilita la orientación de transporte público hacia el campus de la Universidad Tecnológica del Perú (sede Trujillo). Al usar esta app aceptas las condiciones aquí descritas.")
                    .font(.bodyMd)
                Text("Privacidad")
                    .font(.headlineSm)
                Text("Los datos de ubicación y reportes comunitarios son simulados para efectos de demostración. No se comparte información con terceros.")
                    .font(.bodyMd)
                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
}

#Preview {
    BienvenidaView().environmentObject(AppRouter())
}
