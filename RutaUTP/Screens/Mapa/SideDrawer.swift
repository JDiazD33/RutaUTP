//
//  SideDrawer.swift
//  RutaUTP
//
//  Drawer lateral del Mapa. Cada item abre un mini card (sheet) con
//  animacion nativa de SwiftUI.
//

import SwiftUI
import UIKit

// MARK: - Haptics (feedback no visual para accesibilidad y acciones clave)
enum AppHaptics {
    static func selection() {
        guard UIAccessibility.isVoiceOverRunning else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        // Con VoiceOver, el dispositivo ya vibra por defecto: evitamos duplicar.
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Menu Item Identifier
enum DrawerItem: String, Identifiable {
    case notificaciones
    case ciudad
    case ajustes
    case soporte
    case sobreNosotros
    case cerrarSesion
    case datosPersonales

    var id: String { rawValue }
}

struct SideDrawer: View {
    @Binding var isOpen: Bool
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var idioma: IdiomaManager

    @State private var dragOffset: CGFloat = 0
    @State private var activeSheet: DrawerItem? = nil
    @State private var showLogoutConfirm = false
    /// Foto del header: la misma que el usuario sube en Datos Personales
    /// (ProfileImageStore). Se recarga al abrir el drawer y al cerrar el sheet.
    @State private var fotoPerfil: UIImage? = nil

    private let drawerWidth: CGFloat = 300

    var body: some View {
        ZStack(alignment: .leading) {
            // Backdrop
            Color.black
                .opacity(isOpen ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .animation(.easeInOut(duration: 0.28), value: isOpen)
                .accessibilityLabel("Cerrar menú")
                .accessibilityHint("Doble toque para cerrar el panel lateral")

            // Panel
            drawerContent
                .frame(width: drawerWidth)
                .background(Color.appSurface)
                .offset(x: isOpen ? dragOffset : -drawerWidth - 20)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOpen)
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if v.translation.width < 0 {
                                dragOffset = v.translation.width
                            }
                        }
                        .onEnded { v in
                            if v.translation.width < -60 {
                                close()
                            } else {
                                dragOffset = 0
                            }
                        }
                )
        }
        // Sheets para cada item del menu
        .sheet(item: $activeSheet) { item in
            sheetContent(for: item)
                // El sheet vive en su propia UIWindow: se le fuerza el tema
                // elegido en Ajustes (no hereda el de la ventana principal).
                .seguirTemaForzado()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // La foto pudo cambiar en Datos Personales: recargar al abrir el
        // drawer y cuando vuelve de un sheet.
        .onAppear { fotoPerfil = ProfileImageStore.load() }
        .onChange(of: isOpen) { _, abierto in
            if abierto { fotoPerfil = ProfileImageStore.load() }
        }
        .onChange(of: activeSheet) { _, sheet in
            if sheet == nil { fotoPerfil = ProfileImageStore.load() }
        }
        // Alerta nativa para cerrar sesion
        .alert("¿Te vas?", isPresented: $showLogoutConfirm) {
            Button("Cerrar sesión", role: .destructive) {
                activeSheet = nil
                // Aqui iria la logica real de logout
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Tendrás que volver a iniciar sesión para usar la app.")
        }
    }

    private func close() {
        dragOffset = 0
        isOpen = false
    }

    // MARK: - Switch de sheets
    @ViewBuilder
    private func sheetContent(for item: DrawerItem) -> some View {
        switch item {
        case .notificaciones: NotificacionesSheet()
        case .ciudad:         CiudadSheet()
        case .ajustes:        AjustesSheet()
        case .soporte:        SoporteSheet()
        case .sobreNosotros:  SobreNosotrosSheet()
        case .cerrarSesion:   CerrarSesionSheet(onConfirm: { showLogoutConfirm = true })
        case .datosPersonales: DatosPersonalesSheet()
        }
    }

    // MARK: - Drawer content
    private var drawerContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    AppHaptics.impact(.light)
                    activeSheet = .datosPersonales
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 52, height: 52)
                            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 2))
                        if let fotoPerfil {
                            Image(uiImage: fotoPerfil)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        } else {
                            Text("JD")
                                .font(.headlineMd)
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel(L.t("Foto de perfil", "Profile photo"))
                    .accessibilityAddTraits(.isImage)
                    .overlay(alignment: .bottomTrailing) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.appPrimary.opacity(0.15), lineWidth: 0.5))
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.appPrimary)
                        }
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fotoPerfil == nil ? "Foto de perfil, JD" : "Foto de perfil")
                .accessibilityHint("Doble toque para ver y editar tus datos personales")

                Text("Ruta UTP Trujillo")
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                Text("Menú principal")
                    .font(.bodyXs)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 48)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)
            .background(Color.appPrimary)

            // Items
            VStack(spacing: 0) {
                // Cambio de idioma ES/EN (aplica al instante en toda la app)
                Button {
                    AppHaptics.impact(.medium)
                    idioma.alternar()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primaryContainer)
                                .frame(width: 38, height: 38)
                            Image(systemName: "globe")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.onPrimaryContainer)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L.signable("perfil.idioma", "Idioma", "Language"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(.onSurface)
                            Text(idioma.esIngles ? "Switch to Español" : "Switch to English")
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        Spacer()
                        Text(idioma.etiqueta)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.onPrimaryContainer)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primaryContainer))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.surfaceContainerLow)
                    )
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cambiar idioma", "Change language"))
                .seniable("perfil.idioma")

                Divider().padding(.leading, 56).padding(.top, 6)

                DrawerItemRow(icon: "bell.fill", iconColor: .tertiary, label: L.t("Notificaciones", "Notifications")) {
                    activeSheet = .notificaciones
                }
                DrawerItemRow(icon: "building.2.fill", iconColor: .secondary, label: L.t("Ciudad", "City")) {
                    activeSheet = .ciudad
                }
                Divider().padding(.leading, 56)
                DrawerItemRow(icon: "gearshape.fill", iconColor: .onSurfaceVariant, label: L.t("Ajustes", "Settings")) {
                    activeSheet = .ajustes
                }
                DrawerItemRow(icon: "headphones", iconColor: .onSurfaceVariant, label: L.t("Soporte", "Support")) {
                    activeSheet = .soporte
                }
                DrawerItemRow(icon: "info.circle.fill", iconColor: .onSurfaceVariant, label: L.t("Sobre Nosotros", "About Us")) {
                    activeSheet = .sobreNosotros
                }
                // TEMPORAL: botón para abrir la pantalla de prueba de tracking real.
                // No aparece en el README ni en la doc oficial — se quita cuando tracking
                // esté integrado en el flujo principal.
                DrawerItemRow(icon: "location.fill", iconColor: .secondary, label: "Tracking Demo") {
                    router.navigate(to: .trackingDemo)
                }
                Spacer()
                DrawerItemRow(icon: "rectangle.portrait.and.arrow.right",
                              iconColor: .appPrimary,
                              label: "Cerrar Sesión",
                              destructive: true) {
                    activeSheet = .cerrarSesion
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Drawer row
private struct DrawerItemRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.bodySmMedium)
                    .foregroundStyle(destructive ? Color.appPrimary : Color.onSurface)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Doble toque para abrir \(label)")
    }
}

// MARK: - 1. NOTIFICACIONES SHEET
private struct NotificacionesSheet: View {
    @State private var notificacionesOn: Bool = true
    @State private var pausaSeleccionada: PausaNotificaciones? = nil

    enum PausaNotificaciones: String, CaseIterable, Identifiable {
        case treintaMin = "30 minutos"
        case unaHora    = "1 hora"
        case tresHoras  = "3 horas"
        case indefinido = "Indefinido"
        var id: String { rawValue }
        // Orden: menor a mayor duracion
        var orden: Int {
            switch self {
            case .treintaMin: return 0
            case .unaHora:    return 1
            case .tresHoras:  return 2
            case .indefinido: return 3
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(icon: "bell.fill", iconColor: .tertiary, title: "Notificaciones")

            // Toggle principal
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activar notificaciones")
                        .font(.bodyMdMedium)
                    Text("Recibe alertas de rutas y reportes")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Toggle("", isOn: $notificacionesOn)
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceContainerLow)
            )

            // Pausa de notificaciones (solo si el toggle esta activo)
            if notificacionesOn {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PAUSAR NOTIFICACIONES")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    VStack(spacing: 8) {
                        ForEach(PausaNotificaciones.allCases.sorted { $0.orden < $1.orden }) { opcion in
                            pausaRow(opcion)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func pausaRow(_ opcion: PausaNotificaciones) -> some View {
        let isSelected = (pausaSeleccionada == opcion)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                pausaSeleccionada = isSelected ? nil : opcion
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.onSurfaceVariant)
                Text(opcion.rawValue)
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
                Spacer()
                if opcion == .indefinido {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.primaryContainer.opacity(0.30) : Color.surfaceContainerLow)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. CIUDAD SHEET
// La app solo tiene datos GTFS de Trujillo: es la única ciudad seleccionable.
// Las demás se muestran bloqueadas ("Próximamente") para comunicar la visión
// del producto sin prometer algo que aún no existe.
private struct CiudadSheet: View {
    @AppStorage("ciudadSeleccionada") private var ciudadSeleccionada: String = "Trujillo"
    @Environment(\.dismiss) private var dismiss

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
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(icon: "building.2.fill", iconColor: .secondary,
                        title: L.t("Ciudad", "City"))

            Text(L.t("RutaUTP opera con datos de transporte de Trujillo. Estamos trabajando para llegar a más ciudades.",
                     "RutaUTP runs on Trujillo transit data. We're working on more cities."))
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
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
                Spacer()
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
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
            .accessibilityLabel("\(ciudad.nombre), ciudad actual")
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
            .accessibilityLabel("\(ciudad.nombre), próximamente")
            .accessibilityHint("Esta ciudad aún no está disponible")
        }
    }
}

// MARK: - 3. AJUSTES SHEET
private struct AjustesSheet: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @Environment(\.dismiss) private var dismiss

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
private struct SoporteSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let faqs: [(icon: String, q: String, a: String)] = [
        ("exclamationmark.bubble.fill",
         "¿Cómo reporto un incidente?",
         "Toca el botón REPORTAR en el mapa o en Seguridad y describe la situación."),
        ("bookmark.fill",
         "¿Cómo guardo un lugar?",
         "En la pantalla de Guardado, presiona + Añadir y completa los datos."),
        ("location.fill",
         "¿Cómo cambio mi destino?",
         "En el mapa, toca un chip (UTP, Centro, Huanchaco o tus lugares guardados) para cambiar rápido."),
        ("arrow.triangle.2.circlepath",
         "¿Cómo actualizo una ruta?",
         "Las rutas se actualizan automáticamente cada pocos segundos.")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(icon: "headphones", iconColor: .secondary, title: "Soporte")

                // Boton de contacto
                Button {
                    // En un proyecto real: mailto: o telefono
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Contactar Soporte Técnico")
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
                    Text("PREGUNTAS FRECUENTES")
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
private struct SobreNosotrosSheet: View {
    @Environment(\.dismiss) private var dismiss

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
                    Text("SOBRE LA APP")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Text("Aplicación prototipo que ayuda a los estudiantes de la UTP Trujillo a encontrar rutas de micros y combis hacia el campus. Incluye lugares guardados, reportes comunitarios y seguimiento en tiempo real.")
                        .font(.bodyMd)
                        .foregroundStyle(.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Creditos
                VStack(alignment: .leading, spacing: 10) {
                    Text("EQUIPO DE DESARROLLO")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    creditoRow("Diseño y desarrollo", "Universidad Tecnológica del Perú S.A.C")
                    creditoRow("Institución", "Universidad Tecnológica del Perú")
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
private struct CerrarSesionSheet: View {
    var onConfirm: () -> Void
    @State private var lloraScale: CGFloat = 1.0

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
                Text("¿Te vas?")
                    .font(.displayLg)
                    .foregroundStyle(.onSurface)
                Text("Lamentamos verte partir. Puedes volver cuando quieras.")
                    .font(.bodyMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                } label: {
                    Text("Sí, cerrar sesión")
                        .font(.headlineSm)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appPrimary)
                        )
                }
                .buttonStyle(.plain)

                Button {} label: {
                    Text("Cancelar")
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
    }
}

// MARK: - Image Picker (cámara) wrapper
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let img { parent.onImagePicked(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Persistencia de foto de perfil (Documents)
enum ProfileImageStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("perfil_foto.jpg")
    }

    static func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Lista de parentesco
enum Parentesco: String, CaseIterable, Identifiable {
    case padreMadre          = "Padre/Madre"
    case tutorApoderado      = "Tutor/Apoderado"
    case conyugePareja       = "Conyuge/Pareja de hecho"
    case hermano             = "Hermano(a)"
    case hijo                = "Hijo(a)"
    case otro                = "Otro"

    var id: String { rawValue }
}

// MARK: - Selector de parentesco (ventanita)
private struct ParentescoPickerSheet: View {
    @Binding var seleccion: String
    @Environment(\.dismiss) private var dismiss
    @State private var local: String

    init(seleccion: Binding<String>) {
        self._seleccion = seleccion
        self._local = State(initialValue: seleccion.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(icon: "person.2.fill", iconColor: .appPrimary, title: "Parentesco")

            VStack(spacing: 8) {
                ForEach(Parentesco.allCases) { op in
                    Button {
                        AppHaptics.selection()
                        local = op.rawValue
                    } label: {
                        HStack {
                            Image(systemName: local == op.rawValue ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(local == op.rawValue ? Color.appPrimary : Color.onSurfaceVariant)
                                .accessibilityHidden(true)
                            Text(op.rawValue)
                                .font(.bodyMd)
                                .foregroundStyle(.onSurface)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(local == op.rawValue ? Color.primaryContainer.opacity(0.25) : Color.surfaceContainerLow)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(op.rawValue)
                    .accessibilityValue(local == op.rawValue ? "Seleccionado" : "No seleccionado")
                    .accessibilityHint("Doble toque para elegir \(op.rawValue)")
                    .accessibilityAddTraits(local == op.rawValue ? [.isButton, .isSelected] : .isButton)
                }
            }

            Spacer()

            Button {
                AppHaptics.success()
                seleccion = local
                dismiss()
            } label: {
                Text("Aceptar")
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aceptar parentesco")
            .accessibilityHint("Doble toque para confirmar la selección")
        }
        .padding(20)
    }
}

// MARK: - 7. DATOS PERSONALES SHEET
struct DatosPersonalesSheet: View {
    // Datos institucionales (solo lectura)
    private let nombresCompletos = "Joaquín Díaz"
    private let carrera = "Ingeniería de Software"
    private let correoInstitucional = "joaquin.diaz@utp.edu.pe"
    private let codigoUTP = "1234567"
    private let dni = "76543210"
    private let modalidad = "Presencial"
    private let campus = "Trujillo"

    // Datos personales editables (persisten)
    @AppStorage("perfil_telefono") private var telefono: String = "999888777"
    @AppStorage("perfil_correoPersonal") private var correoPersonal: String = "joaquin.diaz@gmail.com"

    // Datos del contacto de emergencia (persisten)
    @AppStorage("emergencia_nombre") private var emergenciaNombre: String = ""
    @AppStorage("emergencia_parentesco") private var emergenciaParentesco: String = ""
    @AppStorage("emergencia_numero") private var emergenciaNumero: String = ""

    // Edición datos personales
    @State private var editandoDatos: Bool = false
    @State private var telefonoInput: String = ""
    @State private var correoPersonalInput: String = ""
    @State private var showCorreoTooltip: Bool = false

    // Foto de perfil
    @State private var perfilImage: UIImage? = nil
    @State private var showCamera: Bool = false

    // Edición contacto de emergencia
    @State private var editandoEmergencia: Bool = false
    @State private var emergenciaNombreInput: String = ""
    @State private var emergenciaParentescoInput: String = ""
    @State private var emergenciaNumeroInput: String = ""
    @State private var showParentescoPicker: Bool = false

    private let boxShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                SheetHeader(icon: "person.crop.circle.fill", iconColor: .appPrimary, title: "Datos Personales")

                // ── Cabecera: foto + nombres + carrera + correo institucional ──
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .accessibilityHidden(true)
                            if let img = perfilImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                    .accessibilityLabel("Foto de perfil")
                                    .accessibilityAddTraits(.isImage)
                            } else {
                                Text("JD")
                                    .font(.headlineMd)
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                AppHaptics.impact(.light)
                                showCamera = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Color.purple, lineWidth: 1.5))
                                        .accessibilityHidden(true)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.purple)
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: 4)
                            .accessibilityLabel("Tomar foto de perfil")
                            .accessibilityHint("Doble toque para abrir la cámara y capturar tu foto")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(nombresCompletos)
                                .font(.headlineSm)
                                .foregroundStyle(.onSurface)
                            Text(carrera)
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.appPrimary)
                            .accessibilityHidden(true)
                        Text(correoInstitucional)
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Correo institucional: \(correoInstitucional)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ── Cuadro: Código UTP / DNI / Modalidad / Campus ──
                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        datoInstitucional(titulo: "CÓDIGO UTP", valor: codigoUTP)
                        Rectangle()
                            .fill(Color.outlineVariant.opacity(0.5))
                            .frame(width: 1, height: 48)
                        datoInstitucional(titulo: "DNI", valor: dni)
                    }

                    Divider()

                    datoHorizontal(titulo: "MODALIDAD DE CARRERA", valor: modalidad)

                    Divider()

                    datoHorizontal(titulo: "CAMPUS", valor: campus)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Datos institucionales")
                .accessibilityValue("Código UTP \(codigoUTP), DNI \(dni), modalidad \(modalidad), campus \(campus)")

                // ── Mis datos personales + editar ──
                HStack {
                    Text("Mis datos personales")
                        .font(.headlineXs)
                        .foregroundStyle(.onSurface)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        toggleEdicion()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: editandoDatos ? "checkmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(editandoDatos ? "Listo" : "editar datos")
                                .font(.labelCapsSm)
                                .appTracking(AppTracking.wideLabel)
                        }
                        .foregroundStyle(Color.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editandoDatos ? "Listo" : "Editar datos personales")
                    .accessibilityHint(editandoDatos ? "Doble toque para guardar los cambios" : "Doble toque para editar tu teléfono y correo personal")
                }

                // ── Cuadro teléfono ──
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.appPrimary)
                    }
                    .accessibilityHidden(true)
                    if editandoDatos {
                        TextField("999 888 777", text: Binding(
                            get: { telefonoInput },
                            set: { newValue in
                                let filtrado = newValue.filter { $0.isNumber }
                                telefonoInput = String(filtrado.prefix(9))
                            }
                        ))
                        .font(.bodyMd)
                        .foregroundStyle(.onSurface)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Teléfono, 9 dígitos")
                    } else {
                        Text(telefono)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                        Spacer()
                    }
                }
                .padding(14)
                .background(boxShape.fill(Color.surfaceContainerLow))
                .overlay(boxShape.stroke(Color.outlineVariant.opacity(editandoDatos ? 0.6 : 0.25), lineWidth: 1))
                .accessibilityElement(children: editandoDatos ? .contain : .combine)
                .accessibilityLabel(editandoDatos ? "Teléfono" : "Teléfono: \(telefono)")

                // ── Cuadro correo personal + signo de exclamación ──
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.appPrimary)
                    }
                    .accessibilityHidden(true)
                    if editandoDatos {
                        TextField("correo@ejemplo.com", text: $correoPersonalInput)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("Correo personal")
                    } else {
                        Text(correoPersonal)
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                    }
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCorreoTooltip.toggle()
                        }
                    } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.purple.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Información sobre el correo personal")
                    .accessibilityHint("Doble toque para leer para qué se usa este correo")
                    .accessibilityAddTraits(.isButton)
                }
                .padding(14)
                .background(boxShape.fill(Color.surfaceContainerLow))
                .overlay(boxShape.stroke(Color.outlineVariant.opacity(editandoDatos ? 0.6 : 0.25), lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(editandoDatos ? "Correo personal" : "Correo personal: \(correoPersonal)")

                // Tooltip del correo personal
                if showCorreoTooltip {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.purple)
                            .accessibilityHidden(true)
                        Text("Correo personal utilizado para recuperar contraseña del correo institucional")
                            .font(.bodyXs)
                            .foregroundStyle(.onSurfaceVariant)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Correo personal utilizado para recuperar contraseña del correo institucional")
                }

                // ── Contacto de Emergencia + editar ──
                HStack {
                    Text("Contacto de Emergencia")
                        .font(.headlineXs)
                        .foregroundStyle(.onSurface)
                    Spacer()
                    Button {
                        AppHaptics.impact(.light)
                        toggleEdicionEmergencia()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: editandoEmergencia ? "checkmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(editandoEmergencia ? "Listo" : "editar datos")
                                .font(.labelCapsSm)
                                .appTracking(AppTracking.wideLabel)
                        }
                        .foregroundStyle(Color.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editandoEmergencia ? "Listo" : "Editar contacto de emergencia")
                    .accessibilityHint(editandoEmergencia ? "Doble toque para cerrar la edición" : "Doble toque para editar el contacto de emergencia")
                }

                if editandoEmergencia {
                    // ── Formulario inline de contacto de emergencia ──
                    VStack(alignment: .leading, spacing: 14) {
                        // Nombre del contacto
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nombre del contacto")
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            TextField("Ingresa el nombre del contacto", text: Binding(
                                get: { emergenciaNombreInput },
                                set: { newValue in
                                    let filtrado = newValue.filter { $0.isLetter || $0.isWhitespace }
                                    emergenciaNombreInput = String(filtrado.prefix(20))
                                }
                            ))
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(boxShape.fill(Color.surfaceContainerLow))
                            .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.6), lineWidth: 1))
                            .accessibilityLabel("Nombre del contacto, solo letras, máximo 20")
                        }

                        // Parentesco (combo box)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Parentesco")
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            Button {
                                AppHaptics.impact(.light)
                                showParentescoPicker = true
                            } label: {
                                HStack {
                                    Text(emergenciaParentescoInput.isEmpty ? "Seleccionar" : emergenciaParentescoInput)
                                        .font(.bodyMd)
                                        .foregroundStyle(emergenciaParentescoInput.isEmpty ? Color.onSurfaceVariant : Color.onSurface)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.purple)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(boxShape.fill(Color.surfaceContainerLow))
                                .overlay(boxShape.stroke(Color.purple.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Parentesco del contacto")
                            .accessibilityValue(emergenciaParentescoInput.isEmpty ? "No seleccionado" : emergenciaParentescoInput)
                            .accessibilityHint("Doble toque para elegir una opción de parentesco")
                            .accessibilityAddTraits(.isButton)
                        }

                        // Número del contacto
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Número del Contacto")
                                .font(.bodySmMedium)
                                .foregroundStyle(.onSurface)
                            TextField("99999999999", text: Binding(
                                get: { emergenciaNumeroInput },
                                set: { newValue in
                                    let filtrado = newValue.filter { $0.isNumber }
                                    emergenciaNumeroInput = String(filtrado.prefix(11))
                                }
                            ))
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(boxShape.fill(Color.surfaceContainerLow))
                            .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.6), lineWidth: 1))
                            .accessibilityLabel("Número del contacto, solo números, máximo 11 dígitos")
                        }

                        // Botones Guardar / Cancelar
                        Button {
                            AppHaptics.success()
                            guardarEmergencia()
                        } label: {
                            Text("Guardar")
                                .font(.bodyMdMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Guardar contacto de emergencia")
                        .accessibilityHint("Doble toque para guardar los datos del contacto")

                        Button {
                            AppHaptics.impact(.light)
                            cancelarEmergencia()
                        } label: {
                            Text("Cancelar")
                                .font(.bodyMdMedium)
                                .foregroundStyle(Color.purple)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancelar edición del contacto")
                        .accessibilityHint("Doble toque para descartar los cambios")
                    }
                } else {
                    // ── Datos guardados del contacto de emergencia ──
                    VStack(spacing: 12) {
                        emergenciaFila(icon: "person.fill", titulo: "Nombre", valor: emergenciaNombre)
                        Divider().padding(.leading, 48).accessibilityHidden(true)
                        emergenciaFila(icon: "person.2.fill", titulo: "Parentesco", valor: emergenciaParentesco)
                        Divider().padding(.leading, 48).accessibilityHidden(true)
                        emergenciaFila(icon: "phone.fill", titulo: "Número", valor: emergenciaNumero)
                    }
                    .padding(14)
                    .background(boxShape.fill(Color.surfaceContainerLow))
                    .overlay(boxShape.stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Contacto de emergencia guardado")
                    .accessibilityValue("Nombre \(emergenciaNombre.isEmpty ? "vacío" : emergenciaNombre), parentesco \(emergenciaParentesco.isEmpty ? "vacío" : emergenciaParentesco), número \(emergenciaNumero.isEmpty ? "vacío" : emergenciaNumero)")
                }

                Spacer(minLength: 24)

                // ── Cerrar sesión (solo de diseño) ──
                Button {
                    AppHaptics.warning()
                    // Solo de diseño: no ejecuta acción real
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Cerrar sesión")
                            .font(.bodyMdMedium)
                    }
                    .foregroundStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primaryFixed)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar sesión")
                .accessibilityHint("Botón de diseño, sin acción real en este prototipo")
            }
            .padding(20)
        }
        .onAppear {
            telefonoInput = telefono
            correoPersonalInput = correoPersonal
            emergenciaNombreInput = emergenciaNombre
            emergenciaParentescoInput = emergenciaParentesco
            emergenciaNumeroInput = emergenciaNumero
            if perfilImage == nil {
                perfilImage = ProfileImageStore.load()
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { img in
                perfilImage = img
                ProfileImageStore.save(img)
            }
            .seguirTemaForzado()
        }
        .sheet(isPresented: $showParentescoPicker) {
            ParentescoPickerSheet(seleccion: $emergenciaParentescoInput)
                .seguirTemaForzado()
        }
    }

    // MARK: - Subvistas
    @ViewBuilder
    private func datoInstitucional(titulo: String, valor: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(titulo)
                .font(.labelCapsSm)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Text(valor)
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func datoHorizontal(titulo: String, valor: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(valor)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
            }
            Spacer()
        }
    }

    // MARK: - Acciones
    private func toggleEdicion() {
        if editandoDatos {
            telefono = telefonoInput
            correoPersonal = correoPersonalInput
            editandoDatos = false
        } else {
            telefonoInput = telefono
            correoPersonalInput = correoPersonal
            editandoDatos = true
        }
    }

    @ViewBuilder
    private func emergenciaFila(icon: String, titulo: String, valor: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.appPrimary.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
                Text(valor.isEmpty ? "—" : valor)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titulo): \(valor.isEmpty ? "vacío" : valor)")
    }

    // MARK: - Contacto de emergencia: acciones
    private func toggleEdicionEmergencia() {
        if editandoEmergencia {
            editandoEmergencia = false
        } else {
            emergenciaNombreInput = emergenciaNombre
            emergenciaParentescoInput = emergenciaParentesco
            emergenciaNumeroInput = emergenciaNumero
            editandoEmergencia = true
        }
    }

    private func guardarEmergencia() {
        emergenciaNombre = emergenciaNombreInput
        emergenciaParentesco = emergenciaParentescoInput
        emergenciaNumero = emergenciaNumeroInput
        editandoEmergencia = false
    }

    private func cancelarEmergencia() {
        emergenciaNombreInput = emergenciaNombre
        emergenciaParentescoInput = emergenciaParentesco
        emergenciaNumeroInput = emergenciaNumero
        editandoEmergencia = false
    }
}

// MARK: - Sheet Header (compartido)
private struct SheetHeader: View {
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

