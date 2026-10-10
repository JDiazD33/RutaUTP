//
//  BienvenidaView.swift
//  RutaUTP
//
//  Pantalla de bienvenida con hero, cards de features y CTA.
//

import SwiftUI

struct BienvenidaView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLegalSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                header
                TabView(selection: $selectedPage) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            llegandocard.padding(.top, 8)
                            busImage.padding(.horizontal, 20)
                            heroText.padding(.horizontal, 20)
                            featureGrid.padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                        .frame(maxWidth: 428)
                        .frame(maxWidth: .infinity)
                    }
                    .tag(0)

                    newsPage(
                        icon: "bus.fill",
                        badge: L.t("NUEVO · TU VIAJE", "NEW · YOUR TRIP"),
                        title: L.t("Tu micro, mejor identificado", "Help identify your bus"),
                        description: L.t("Ahora puedes indicar qué línea tomaste y cómo va de llena, desde el mapa.",
                                         "You can now choose your bus line and report how full it is, right from the map."),
                        highlights: [
                            ("hand.tap.fill", L.t("Busca tu ruta y confirma «Sí, ya subí» cuando estés en el micro.",
                                                 "Find your route and confirm ‘Yes, I'm on board’ once you've boarded.")),
                            ("person.2.fill", L.t("Elige la línea y, si quieres, indica si va vacío, con espacio o lleno.",
                                                 "Choose your line and optionally report empty, room available or full.")),
                            ("checkmark.circle.fill", L.t("La app comprueba el viaje; al bajar, toca «Ya bajé».",
                                                         "The app checks your trip; tap ‘I've got off’ when you leave."))
                        ]
                    )
                    .tag(1)

                    newsPage(
                        icon: "mappin.and.ellipse",
                        badge: L.t("NUEVO · TUS PARADEROS", "NEW · YOUR STOPS"),
                        title: L.t("Guarda los puntos que te sirven", "Keep the stops you need"),
                        description: L.t("Encuentra tus paraderos guardados en Seguridad, antes de Comunidad.",
                                         "Find your saved stops in Safety, before Community."),
                        highlights: [
                            ("bookmark.fill", L.t("Guarda un paradero desde «Paraderos y referencias».",
                                                 "Save a stop from ‘Stops and landmarks’.")),
                            ("map.fill", L.t("En tu viaje puedes marcar dónde subiste o escribir una referencia. Es opcional.",
                                            "During trip setup, optionally mark where you boarded or write a landmark.")),
                            ("iphone", L.t("Las referencias de subida se guardan en tu teléfono para futuros paraderos de alumnos.",
                                           "Boarding references stay on your phone for future student stops."))
                        ]
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    pageDots
                    ctaButton
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 428)
                .frame(maxWidth: .infinity)

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
            Text(L.t("Ruta UTP Trujillo", "Ruta UTP Trujillo"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
            Spacer()
            Button {
                router.navigate(to: .mapaPrincipal, claveSenia: "bienvenida.saltar")
            } label: {
                Text(L.signable("bienvenida.saltar", "Saltar", "Skip"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Saltar introducción", "Skip intro"))
            .seniable("bienvenida.saltar", conGesto: false)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appBackground)
    }

    private var llegandocard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.primaryFill)
                    .frame(width: 48, height: 48)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 8, x: 0, y: 2)
                Image(systemName: "bus.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.onPrimaryFill)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("LLEGANDO EN", "ARRIVING IN"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabelCaps)
                Text(L.t("3 min", "3 min"))
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
            Text(L.t("Llega a la UTP sin perderte", "Get to UTP without getting lost"))
                .font(.displayLg)
                .foregroundStyle(.onSurface)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .frame(maxWidth: .infinity)
            Text(L.t("Encuentra la ruta exacta desde tu ubicación hasta el campus sin complicaciones.", "Find the exact route from your location to campus, hassle-free."))
                .font(.bodyLg)
                .foregroundStyle(.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
        }
    }

    private var pageDots: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { page in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            selectedPage = page
                        }
                    } label: {
                        Capsule()
                            .fill(selectedPage == page ? Color.primaryFill : Color.gray.opacity(0.3))
                            .frame(width: selectedPage == page ? 36 : 8, height: 8)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Página \(page + 1) de 3", "Page \(page + 1) of 3"))
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            Text(L.t("Desliza para conocer las novedades", "Swipe to discover what's new"))
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private func newsPage(icon: String, badge: String, title: String, description: String,
                          highlights: [(String, String)]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(LinearGradient(colors: [Color.appPrimary.opacity(0.16), Color.surfaceContainerLowest],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().stroke(Color.appPrimary.opacity(0.15), lineWidth: 1)
                        .frame(width: 170, height: 170)
                    Circle().fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 128, height: 128)
                    Image(systemName: icon)
                        .font(.system(size: 58, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                }
                .frame(height: 210)
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(badge).font(.caption.weight(.bold))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.appPrimary.opacity(0.08), in: Capsule())
                    Text(title).font(.displayLg)
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(Color.onSurface).multilineTextAlignment(.center)
                    Text(description).font(.bodyLg)
                        .foregroundStyle(Color.onSurfaceVariant).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(highlights.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: highlights[index].0)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.appPrimary).frame(width: 26)
                                .accessibilityHidden(true)
                            Text(highlights[index].1).font(.bodyMd).foregroundStyle(Color.onSurface)
                        }
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(20)
            .frame(maxWidth: 428)
            .frame(maxWidth: .infinity)
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            FeatureCard(
                icon: "shield.fill",
                iconColor: .appPrimary,
                label: L.t("SEGURIDAD", "SAFETY"),
                title: L.t("Rutas nocturnas monitoreadas.", "Monitored night routes.")
            )
            FeatureCard(
                icon: "creditcard.fill",
                iconColor: .tertiary,
                label: L.t("AHORRO", "SAVINGS"),
                title: L.t("Precios de micros y combis actualizados.", "Updated bus and van fares.")
            )
        }
    }

    private var ctaButton: some View {
        Button {
            router.navigate(to: .mapaPrincipal, claveSenia: "bienvenida.comenzar")
        } label: {
            HStack(spacing: 8) {
                Text(L.signable("bienvenida.comenzar", "Comenzar", "Get Started"))
                    .font(.displayLgPhone)
                    .foregroundStyle(.onPrimaryFill)
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.onPrimaryFill)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryFill)
                    .shadow(color: .appPrimary.opacity(0.35), radius: 14, x: 0, y: 8)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(L.t("Comenzar a usar la aplicación", "Start using the app"))
        .seniable("bienvenida.comenzar", conGesto: false)
    }

    private var legalFooter: some View {
        // El pie se compone como AttributedString para que SOLO la frase
        // "Términos de Servicio" sea tocable. Con el Text concatenado
        // anterior, la frase salía subrayada (la convención de enlace) pero
        // no tenía gesto, y showLegalSheet nunca se activaba: la hoja legal
        // era inalcanzable desde toda la app.
        Text(textoLegal)
            .font(.bodySm)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .environment(\.openURL, OpenURLAction { _ in
                showLegalSheet = true
                return .handled
            })
    }

    /// Frase legal con el enlace de términos marcado como tal. El URL es
    /// propio de la app y no sale de ella: lo intercepta el OpenURLAction
    /// de arriba para abrir la hoja, en vez de abrir un navegador.
    private var textoLegal: AttributedString {
        var intro = AttributedString(
            L.t("Al continuar, aceptas nuestros ", "By continuing, you accept our ")
        )
        intro.foregroundColor = .onSurfaceVariant

        var enlace = AttributedString(L.t("Términos de Servicio", "Terms of Service"))
        enlace.link = URL(string: "rutautp://terminos")
        enlace.foregroundColor = .appPrimary
        enlace.underlineStyle = .single

        return intro + enlace
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
                Text(L.t("Términos de Servicio", "Terms of Service"))
                    .font(.headlineMd)
                Text(L.t("Ruta UTP Trujillo es una aplicación prototipo que facilita la orientación de transporte público hacia el campus de la Universidad Tecnológica del Perú (sede Trujillo). Al usar esta app aceptas las condiciones aquí descritas.",
                         "Ruta UTP Trujillo is a prototype app that helps you navigate public transport to the Universidad Tecnológica del Perú campus (Trujillo). By using this app you accept the conditions described here."))
                    .font(.bodyMd)
                Text(L.t("Privacidad", "Privacy"))
                    .font(.headlineSm)
                Text(L.t("Si autorizas el acceso, la app utiliza tu ubicación real para mostrar dónde estás, buscar paraderos cercanos y seguir tu avance durante un viaje. Las posiciones de los buses que aparecen en el mapa son simuladas.",
                         "If you grant permission, the app uses your real location to show where you are, find nearby stops and track your progress during a trip. Bus positions shown on the map are simulated."))
                    .font(.bodyMd)
                Text(L.t("La búsqueda de lugares y el cálculo de indicaciones utilizan servicios de Apple Maps. Para resolver esas consultas se envían a Apple los textos de búsqueda, direcciones o coordenadas necesarios, que pueden incluir tu ubicación como punto de partida.",
                         "Place searches and directions use Apple Maps services. These requests send Apple the necessary search text, addresses or coordinates, which may include your location as the starting point."))
                    .font(.bodyMd)
                Text(L.t("Los datos personales que introduces, tus lugares y líneas guardados, las fotos de perfil y carné y las referencias de tarjetas se guardan localmente. El monedero usa saldo de demostración y no procesa pagos reales. Los reportes y publicaciones comunitarias de esta versión no se envían a un servidor ni se comparten con otros usuarios.",
                         "The personal details you enter, saved places and routes, profile and student card photos, and card references are stored locally. The wallet uses a demo balance and does not process real payments. Reports and community posts in this version are not sent to a server or shared with other users."))
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
