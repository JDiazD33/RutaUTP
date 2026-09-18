//
//  DrawerSheets.swift
//  RutaUTP
//
//  Sheets del menú lateral (drawer) del Mapa.
//  
//  Estaban dentro de `SideDrawer.swift`, que mezclaba el panel, sus
//  siete hojas y el formulario de datos personales. Se separan aquí
//  para que el archivo del drawer contenga el drawer.

import SwiftUI
// Estos sheets eran `private` cuando vivían junto al drawer. Ahora cruzan de
// archivo (el drawer los instancia desde SideDrawer.swift y DatosPersonalesSheet
// usa SheetHeader), así que son internos al módulo. Siguen sin salir del target.

// MARK: - 1. NOTIFICACIONES SHEET
struct NotificacionesSheet: View {
    @AppStorage(PreferenciasApp.notificaciones) private var notificacionesOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(icon: "bell.fill", iconColor: .tertiary,
                            title: L.t("Notificaciones", "Notifications"))
                Toggle(isOn: $notificacionesOn) {
                    Text(L.t("Preferencia de notificaciones", "Notification preference"))
                        .font(.bodyMdMedium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(.appPrimary)
                .padding(16)
                .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))

                Text(L.t("Esta preferencia se guarda en este dispositivo y es la misma que aparece en Perfil. Esta versión no envía notificaciones ni programa pausas. El ajuste no cambia los permisos de iOS.",
                         "This preference is saved on this device and is shared with Profile. This version does not send notifications or schedule pauses. The setting does not change iOS permissions."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }
}

// MARK: - 2. CIUDAD SHEET
// La app solo tiene datos GTFS de Trujillo: es la única ciudad seleccionable.
// Las demás se muestran bloqueadas ("Próximamente") para comunicar la visión
// del producto sin prometer algo que aún no existe.
struct CiudadSheet: View {
    @AppStorage("ciudadSeleccionada") private var ciudadSeleccionada: String = "Trujillo"

    private struct Ciudad: Identifiable {
        let nombre: String
        let disponible: Bool
        var id: String { nombre }
    }

    private let ciudades: [Ciudad] = [
        Ciudad(nombre: "Trujillo", disponible: true),
        Ciudad(nombre: "Lima", disponible: false),
        Ciudad(nombre: "Chiclayo", disponible: false),
        Ciudad(nombre: "Piura", disponible: false),
        Ciudad(nombre: "Arequipa", disponible: false),
        Ciudad(nombre: "Cuzco", disponible: false)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(icon: "building.2.fill", iconColor: .secondary,
                            title: L.t("Ciudad", "City"))

                Text(L.t("RutaUTP opera con datos de transporte de Trujillo. Estamos trabajando para llegar a más ciudades.",
                         "RutaUTP runs on Trujillo transit data. We're working on more cities."))
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)

                VStack(spacing: 8) {
                    ForEach(ciudades) { ciudad in
                        ciudadRow(ciudad)
                    }
                }

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.onSurfaceVariant)
                    Text(L.t("Trujillo es nuestra primera ciudad. ¿Quieres la tuya? Escríbenos desde Soporte.",
                             "Trujillo is our first city. Want yours? Reach us via Support."))
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.bodyXs)
                        .foregroundStyle(.onSurfaceVariant)
                    Spacer()
                }
                .padding(.top, 8)

            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appSurface)
    }

    @ViewBuilder
    private func ciudadRow(_ ciudad: Ciudad) -> some View {
        if ciudad.disponible {
            // Trujillo: seleccionada y fija (no tiene sentido deseleccionarla)
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.appPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ciudad.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(L.t("Rutas y paraderos activos", "Routes and stops active"))
                        .font(.bodyXs)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.appPrimary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primaryContainer.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.appPrimary.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ciudad.nombre + L.t(", ciudad actual", ", current city"))
            .accessibilityAddTraits(.isSelected)
            .onAppear { ciudadSeleccionada = "Trujillo" }
        } else {
            // Bloqueada: próximamente
            Button {
                AppHaptics.warning()
            } label: {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        .frame(width: 24)
                    Text(ciudad.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurfaceVariant.opacity(0.7))
                    Spacer()
                    Text(L.t("PRÓXIMAMENTE", "COMING SOON"))
                        .font(.system(size: 10, weight: .bold))
                        .appTracking(AppTracking.wideLabel)
                        .foregroundStyle(.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.surfaceContainerHigh)
                        )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surfaceContainerLow.opacity(0.6))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ciudad.nombre + L.t(", próximamente", ", coming soon"))
            .accessibilityHint(L.t("Esta ciudad aún no está disponible", "This city is not available yet"))
        }
    }
}

// MARK: - 3. AJUSTES SHEET
struct AjustesSheet: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(icon: "gearshape.fill", iconColor: .onSurfaceVariant,
                        title: L.t("Ajustes", "Settings"))

            // Tema
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("APARIENCIA", "APPEARANCE"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                HStack(spacing: 12) {
                    temaButton(.light, icon: "sun.max.fill", label: L.t("Claro", "Light"))
                    temaButton(.dark, icon: "moon.fill", label: L.t("Oscuro", "Dark"))
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private enum TemaOpcion { case light, dark }

    private func temaButton(_ tema: TemaOpcion, icon: String, label: String) -> some View {
        let isSelected: Bool = {
            switch tema {
            case .light: return !isDarkMode
            case .dark:  return isDarkMode
            }
        }()
        return Button {
            // Sin withAnimation: animar la escritura de isDarkMode es parte
            // de lo que dejaba el tema "pegado" en oscuro. El cross-fade
            // visual lo pone UIKit; aquí solo se anima el resaltado.
            isDarkMode = (tema == .dark)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                Text(label)
                    .font(.bodyMdMedium)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .foregroundStyle(isSelected ? Color.onPrimaryContainer : Color.onSurface)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.primaryContainer : Color.surfaceContainerLow)
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. SOPORTE SHEET
struct SoporteSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var faqs: [(icon: String, q: String, a: String)] {
        [
        ("exclamationmark.bubble.fill",
         L.t("¿Cómo reporto un incidente?", "How do I report an incident?"),
         L.t("Toca el botón REPORTAR en el mapa o en Seguridad y describe la situación.",
             "Tap the REPORT button on the map or in Safety and describe the situation.")),
        ("bookmark.fill",
         L.t("¿Cómo guardo un lugar?", "How do I save a place?"),
         L.t("En la pantalla de Guardado, presiona + Añadir y completa los datos.",
             "In the Saved screen, tap + Add and fill in the details.")),
        ("location.fill",
         L.t("¿Cómo cambio mi destino?", "How do I change my destination?"),
         L.t("En el mapa, toca un chip (UTP, Centro, Huanchaco o tus lugares guardados) para cambiar rápido.",
             "On the map, tap a chip (UTP, Downtown, Huanchaco or your saved places) to switch quickly.")),
        ("arrow.triangle.2.circlepath",
         L.t("¿Cómo actualizo una ruta?", "How do I refresh a route?"),
         L.t("Las rutas se actualizan automáticamente cada pocos segundos.",
             "Routes refresh automatically every few seconds."))
        ]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(icon: "headphones", iconColor: .secondary, title: L.t("Soporte", "Support"))

                // Boton de contacto
                Button {
                    // En un proyecto real: mailto: o telefono
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(L.t("Contactar Soporte Técnico", "Contact Technical Support"))
                    }
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary)
                    )
                }
                .buttonStyle(.plain)

                // FAQ
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("PREGUNTAS FRECUENTES", "FREQUENTLY ASKED QUESTIONS"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    VStack(spacing: 8) {
                        ForEach(faqs.indices, id: \.self) { i in
                            faqRow(faqs[i])
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
    }

    private func faqRow(_ faq: (icon: String, q: String, a: String)) -> some View {
        DisclosureGroup {
            Text(faq.a)
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: faq.icon)
                    .foregroundStyle(.appPrimary)
                Text(faq.q)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceContainerLow)
        )
    }
}

// MARK: - 5. SOBRE NOSOTROS SHEET
struct SobreNosotrosSheet: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Logo
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 96, height: 96)
                        Image(systemName: "bus.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Ruta UTP Trujillo")
                        .font(.headlineMd)
                    Text("v1.0.0")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.surfaceContainerLow))
                }
                .padding(.top, 12)

                // Descripcion
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("SOBRE LA APP", "ABOUT THE APP"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Text(L.t("Aplicación prototipo que ayuda a los estudiantes de la UTP Trujillo a encontrar rutas de micros y combis hacia el campus. Incluye lugares guardados, reportes comunitarios y seguimiento en tiempo real.",
                             "Prototype app that helps UTP Trujillo students find bus and van routes to campus. It includes saved places, community reports and live tracking."))
                        .font(.bodyMd)
                        .foregroundStyle(.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Creditos
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("EQUIPO DE DESARROLLO", "DEVELOPMENT TEAM"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    creditoRow(L.t("Diseño y desarrollo", "Design and development"), "Universidad Tecnológica del Perú S.A.C")
                    creditoRow(L.t("Institución", "Institution"), "Universidad Tecnológica del Perú")
                    Link("Uicons by Flaticon", destination: URL(string: "https://www.flaticon.com/uicons")!)
                        .font(.bodySm)
                        .foregroundStyle(Color.appPrimary)
                        .accessibilityLabel(L.t("Iconos de negocios por Flaticon", "Business icons by Flaticon"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 40)
            }
            .padding(20)
        }
    }

    private func creditoRow(_ rol: String, _ nombre: String) -> some View {
        HStack {
            Text(rol)
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
            Spacer()
            Text(nombre)
                .font(.bodySmMedium)
                .foregroundStyle(.onSurface)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 6. CERRAR SESION SHEET
struct CerrarSesionSheet: View {
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lloraScale: CGFloat = 1.0
    /// Confirmación final. Vive aquí y no en el drawer: un alert declarado en
    /// la vista de fondo, con este sheet ya presentado, no aparece de forma
    /// fiable en SwiftUI.
    @State private var confirmarCierre = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            // Carita llorando animada
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.10))
                    .frame(width: 140, height: 140)
                Image(systemName: "face.dashed")
                    .font(.system(size: 80))
                    .foregroundStyle(.appPrimary)
                    .scaleEffect(lloraScale)
            }

            VStack(spacing: 8) {
                Text(L.t("¿Te vas?", "Leaving already?"))
                    .font(.displayLg)
                    .foregroundStyle(.onSurface)
                Text(L.t("Lamentamos verte partir. Puedes volver cuando quieras.",
                          "We hate to see you go. You can come back whenever you want."))
                    .font(.bodyMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    confirmarCierre = true
                } label: {
                    Text(L.t("Sí, cerrar sesión", "Yes, log out"))
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appPrimary)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text(L.t("Cancelar", "Cancel"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                lloraScale = 1.1
            }
        }
        .alert(L.t("Cerrar sesión", "Log out"), isPresented: $confirmarCierre) {
            Button(L.t("Cerrar sesión", "Log out"), role: .destructive) {
                onConfirm()
                dismiss()
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        } message: {
            Text(L.t("Tendrás que volver a iniciar sesión para usar la app.",
                       "You will need to sign in again to use the app."))
        }
    }
}


// MARK: - Sheet Header (compartido)
struct SheetHeader: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.headlineMd)
                .foregroundStyle(.onSurface)
            Spacer()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

