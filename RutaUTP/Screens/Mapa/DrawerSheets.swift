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
import UIKit
// Estos sheets eran `private` cuando vivían junto al drawer. Ahora cruzan de
// archivo (el drawer los instancia desde SideDrawer.swift y DatosPersonalesSheet
// usa SheetHeader), así que son internos al módulo. Siguen sin salir del target.

// MARK: - 1. NOTIFICACIONES SHEET
struct NotificacionesSheet: View {
    var body: some View { NotificacionesView() }
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
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator

    /// El consentimiento no se aplica al tocar el interruptor: primero se
    /// explica el alcance. Es un permiso para publicar tu ubicación, y el
    /// usuario tiene que poder saber qué se envía y cuándo antes de aceptarlo.
    @State private var mostrarConsentimiento = false
    @State private var mostrarDetallesContribucion = false
    @State private var mostrarNotificaciones = false

    var body: some View {
        ScrollView {
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

                // La temática es independiente del modo claro/oscuro.
                SelectorTematicaEmpresa()

                SelectorSedeTrabajo()

                Button { mostrarNotificaciones = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.t("Notificaciones", "Notifications")).font(.headline)
                            TimelineView(.periodic(from: .now, by: 60)) { contexto in
                                Text(NotificacionesService.shared.resumen(ahora: contexto.date)).font(.subheadline)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .foregroundStyle(.onSurface)
                    .padding(16)
                    .frame(minHeight: 44)
                    .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                // Contribución asociada a la cuenta de instalación y al viaje.
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("CONTRIBUCIÓN", "CONTRIBUTION"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)

                    Toggle(isOn: Binding(
                        get: { trackingCoordinator.isEnabled },
                        set: { activar in
                            if activar {
                                mostrarConsentimiento = true
                            } else {
                                trackingCoordinator.setContributionEnabled(false)
                            }
                        }
                    )) {
                        Text(L.t("Ayudar con ubicaciones", "Help with locations"))
                            .font(.bodyMdMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(.appPrimary)
                    .disabled(!trackingCoordinator.isPublisherConfigured)
                    .padding(16)
                    .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHint(TextoConsentimientoContribucion.pistaAccesibilidad)

                    TextoContribucionJustificado(texto: descripcionContribucion, color: .onSurfaceVariant)
                        .frame(maxWidth: .infinity)

                    Button(L.t("Ver detalles", "View details")) {
                        mostrarDetallesContribucion = true
                    }
                    .font(.bodyXsMedium)
                    .foregroundStyle(.appPrimary)
                    .accessibilityHint(L.t("Muestra qué datos se envían y cuándo", "Shows which data is sent and when"))
                }

                Spacer()
            }
            .padding(20)
        }
        .sheet(isPresented: $mostrarNotificaciones) {
            NotificacionesView().seguirTemaForzado().presentationDetents([.large])
        }
        .confirmationDialog(
            L.t("Ayudar con ubicaciones en tiempo real",
                "Help with real-time locations"),
            isPresented: $mostrarConsentimiento,
            titleVisibility: .visible
        ) {
            Button(L.t("Aceptar y activar", "Accept and turn on")) {
                trackingCoordinator.setContributionEnabled(true)
            }

            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            // El alcance se declara ANTES de pedir el consentimiento, no
            // después: la baliza solo transmite con la app abierta, y prometer
            // continuidad en segundo plano sería anunciar algo que el sistema
            // no hace con la configuración actual.
            Text(TextoConsentimientoContribucion.confirmacion)
        }
        .alert(L.t("Contribución de ubicaciones", "Location contribution"),
               isPresented: $mostrarDetallesContribucion) {
            Button(L.t("Entendido", "OK"), role: .cancel) {}
        } message: {
            Text(TextoConsentimientoContribucion.explicacion)
        }
    }

    private var descripcionContribucion: String {
        if !trackingCoordinator.isPublisherConfigured {
            return L.t("La ayuda con ubicaciones estará disponible cuando se configure el servicio de esta instalación.",
                       "Location sharing will be available once the service is configured for this installation.")
        }
        if trackingCoordinator.isEnabled {
            return L.t("Estás ayudando con ubicaciones. Consulta el estado de tu viaje en la tarjeta inferior del mapa.",
                       "You are sharing locations. Check your trip status in the card at the bottom of the map.")
        }
        return L.t("Al confirmar tu viaje, ayudas a ubicar buses. Solo se envían datos con la app abierta.",
                   "After confirming your trip, you help locate buses. Data is sent only while the app is open.")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Apariencia ", "Appearance ") + label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Resumen compacto; la explicación completa se consulta mediante «Ver detalles».
private struct TextoContribucionJustificado: UIViewRepresentable {
    let texto: String
    let color: Color

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 3
        label.textAlignment = .justified
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = texto
        uiView.font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: uiView.traitCollection)
        uiView.textColor = UIColor(color).resolvedColor(with: UITraitCollection(
            userInterfaceStyle: context.environment.colorScheme == .dark ? .dark : .light
        ))
        uiView.accessibilityLabel = texto
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

// MARK: - 4. SOPORTE SHEET
struct SoporteSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var busqueda = ""
    @State private var preguntaAbierta: Int?

    private struct Pregunta: Identifiable {
        let id: Int
        let icono: String
        let titulo: String
        let respuesta: String
    }

    private var preguntas: [Pregunta] {
        [
            Pregunta(id: 0, icono: "exclamationmark.bubble.fill",
                     titulo: L.t("¿Cómo reporto un incidente?", "How do I report an incident?"),
                     respuesta: L.t("Toca el botón REPORTAR en el mapa o en Seguridad y describe la situación.",
                                    "Tap the REPORT button on the map or in Safety and describe the situation.")
                        + "\n\n" + L.t("En esta versión de prueba, los reportes no se envían a un servidor.",
                                             "In this trial version, reports are not sent to a server.")),
            Pregunta(id: 1, icono: "bookmark.fill",
                     titulo: L.t("¿Cómo guardo un lugar?", "How do I save a place?"),
                     respuesta: L.t("En la pantalla de Guardado, presiona + Añadir y completa los datos.",
                                    "In the Saved screen, tap + Add and fill in the details.")),
            Pregunta(id: 2, icono: "location.fill",
                     titulo: L.t("¿Cómo cambio mi destino?", "How do I change my destination?"),
                     respuesta: L.t("En el mapa, toca un chip (tu sede, Centro, Huanchaco o tus lugares guardados) para cambiar rápido. Elige tu sede en Ajustes.",
                                    "On the map, tap a chip (your workplace, Downtown, Huanchaco or your saved places) to switch quickly. Choose your workplace in Settings.")),
            Pregunta(id: 3, icono: "arrow.triangle.2.circlepath",
                     titulo: L.t("¿Cómo actualizo una ruta?", "How do I refresh a route?"),
                     respuesta: L.t("El catálogo de líneas y paraderos viene incluido en la app. Sus cambios llegan con las actualizaciones de la app.",
                                    "The route and stop catalog is included in the app. Changes arrive with app updates."))
        ]
    }

    private var preguntasFiltradas: [Pregunta] {
        let consulta = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else { return preguntas }
        let locale = IdiomaManager.shared.idioma.locale
        return preguntas.filter { pregunta in
            [pregunta.titulo, pregunta.respuesta].contains { texto in
                texto.range(of: consulta, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }

    var body: some View {
        MenuDetailSheet(title: L.t("Soporte", "Support")) {
            MenuDetailHero(
                icon: "headphones",
                title: L.t("¿En qué te ayudamos?", "How can we help?"),
                subtitle: L.t("Encuentra respuestas para usar la app y moverte por Trujillo.",
                              "Find answers about using the app and getting around Trujillo.")
            )

            buscador

            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Preguntas frecuentes", "Frequently asked questions"))
                    .font(.headline)
                    .foregroundStyle(.onSurface)
                    .accessibilityAddTraits(.isHeader)

                if preguntasFiltradas.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t("No encontramos respuestas", "No answers found"))
                            .font(.headline)
                            .foregroundStyle(.onSurface)
                        Text(L.t("Prueba con otra palabra o borra la búsqueda.",
                                 "Try another word or clear the search."))
                            .font(.subheadline)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    ForEach(preguntasFiltradas) { pregunta in
                        preguntaRow(pregunta)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.appPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("Ayuda sin conexión", "Offline help"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.onSurface)
                    Text(L.t("Puedes consultar estas respuestas aunque no tengas internet.",
                             "You can read these answers even without an internet connection."))
                        .font(.footnote)
                        .foregroundStyle(.onSurfaceVariant)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var buscador: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.onSurfaceVariant)
                .accessibilityHidden(true)
            TextField(L.t("Buscar en la ayuda", "Search help"), text: $busqueda)
                .font(.body)
                .foregroundStyle(.onSurface)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel(L.t("Buscar en la ayuda", "Search help"))
            if !busqueda.isEmpty {
                Button {
                    busqueda = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Borrar búsqueda", "Clear search"))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, busqueda.isEmpty ? 16 : 4)
        .frame(minHeight: 52)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.outlineVariant, lineWidth: 1)
        }
    }

    private func preguntaRow(_ pregunta: Pregunta) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { preguntaAbierta == pregunta.id },
            set: { abierta in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    preguntaAbierta = abierta ? pregunta.id : nil
                }
            }
        )) {
            Text(pregunta.respuesta)
                .font(.body)
                .foregroundStyle(.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 4)
        } label: {
            HStack(spacing: 12) {
                MenuDetailIcon(icon: pregunta.icono)
                Text(pregunta.titulo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .tint(.appPrimary)
        .padding(16)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - 5. SOBRE NOSOTROS SHEET
struct SobreNosotrosSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var tamanoMarca = 30
    @ScaledMetric(relativeTo: .body) private var tamanoIcono = 18
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    /// Leer la version instalada evita que el texto quede desfasado del bundle.
    private var version: String? {
        guard let numero = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !numero.isEmpty else { return nil }
        return L.f("Versión {0}", "Version {0}", [numero])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identidad

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Sobre la app", "About the app"))
                            .font(.headline)
                            .foregroundStyle(.onSurface)
                            .accessibilityAddTraits(.isHeader)
                        Text(L.t("Aplicación prototipo de movilidad en Trujillo para estudiantes y colaboradores. Permite elegir una sede de trabajo, buscar rutas de micros y combis, guardar lugares y consultar reportes comunitarios y seguimiento.",
                                 "Prototype mobility app in Trujillo for students and employees. Choose a workplace, find bus and van routes, save places, and view community reports and tracking."))
                            .font(.body)
                            .foregroundStyle(.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        featureRow(icon: "map.fill", title: L.t("Rutas", "Routes"),
                                   detail: L.t("Explora líneas y paraderos para planificar tu viaje.",
                                               "Explore routes and stops to plan your trip."))
                        Divider().padding(.horizontal, 18)
                        featureRow(icon: "bookmark.fill", title: L.t("Guardado", "Saved"),
                                   detail: L.t("Ten a mano tus lugares y líneas favoritas.",
                                               "Keep your favorite places and routes close at hand."))
                        Divider().padding(.horizontal, 18)
                        featureRow(icon: "location.fill", title: L.t("Tu viaje", "Your trip"),
                                   detail: L.t("Sigue tu avance durante el recorrido.",
                                               "Follow your progress along the route."))
                    }
                    .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Equipo de desarrollo", "Development team"))
                            .font(.headline)
                            .foregroundStyle(.onSurface)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 18) {
                            creditoRow(L.t("Diseño y desarrollo", "Design and development"),
                                       "Universidad Tecnológica del Perú S.A.C")
                            Divider()
                            creditoRow(L.t("Institución", "Institution"), "Universidad Tecnológica del Perú")
                            Divider()
                            Link(destination: URL(string: "https://www.flaticon.com/uicons")!) {
                                HStack(spacing: 12) {
                                    Text("Uicons by Flaticon")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.up.right")
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                                .foregroundStyle(.appPrimary)
                            }
                            .accessibilityLabel(L.t("Iconos de negocios por Flaticon", "Business icons by Flaticon"))
                        }
                        .padding(20)
                        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L.t("Sobre Nosotros", "About Us"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(acento)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var identidad: some View {
        VStack(spacing: 10) {
            Image(systemName: "bus")
                .font(.system(size: min(tamanoMarca, 40), weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("Ruta UTP Trujillo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(L.t("Tu ciudad, más cerca.", "Your city, closer."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let version {
                Text(version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MenuDetailIcon(icon: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.onSurface)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .accessibilityElement(children: .combine)
    }

    private func creditoRow(_ rol: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rol)
                .font(.footnote)
                .foregroundStyle(.onSurfaceVariant)
            Text(nombre)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentacion compartida de Soporte y Sobre Nosotros
private struct MenuDetailSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.onSurface)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceContainerHigh, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cerrar", "Close"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.appSurface.ignoresSafeArea())
        .accessibilityAction(.escape) { dismiss() }
    }
}

private struct MenuDetailHero: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.onPrimaryFill)
                .frame(width: 60, height: 60)
                .background(Color.onPrimaryFill.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
            }
            .foregroundStyle(.onPrimaryFill)
            .fixedSize(horizontal: false, vertical: true)

            if let badge {
                Text(badge)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surfaceContainerLowest, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct MenuDetailIcon: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.onPrimaryContainer)
            .frame(width: 40, height: 40)
            .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
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
                        .foregroundStyle(.onPrimaryFill)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primaryFill)
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
