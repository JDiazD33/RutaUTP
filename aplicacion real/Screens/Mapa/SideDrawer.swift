//
//  SideDrawer.swift
//  RutaUTP
//
//  Drawer lateral del Mapa. Cada item abre un mini card (sheet) con
//  animacion nativa de SwiftUI.
//

import SwiftUI

// MARK: - Menu Item Identifier
enum DrawerItem: String, Identifiable {
    case notificaciones
    case ciudad
    case ajustes
    case soporte
    case sobreNosotros
    case cerrarSesion

    var id: String { rawValue }
}

struct SideDrawer: View {
    @Binding var isOpen: Bool
    @EnvironmentObject private var router: AppRouter

    @State private var dragOffset: CGFloat = 0
    @State private var activeSheet: DrawerItem? = nil
    @State private var showLogoutConfirm = false

    private let drawerWidth: CGFloat = 300

    var body: some View {
        ZStack(alignment: .leading) {
            // Backdrop
            Color.black
                .opacity(isOpen ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .animation(.easeInOut(duration: 0.28), value: isOpen)

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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        }
    }

    // MARK: - Drawer content
    private var drawerContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 52, height: 52)
                        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 2))
                    Text("JD")
                        .font(.headlineMd)
                        .foregroundStyle(.white)
                }
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
                DrawerItemRow(icon: "bell.fill", iconColor: .tertiary, label: "Notificaciones") {
                    activeSheet = .notificaciones
                }
                DrawerItemRow(icon: "building.2.fill", iconColor: .secondary, label: "Ciudad") {
                    activeSheet = .ciudad
                }
                Divider().padding(.leading, 56)
                DrawerItemRow(icon: "gearshape.fill", iconColor: .onSurfaceVariant, label: "Ajustes") {
                    activeSheet = .ajustes
                }
                DrawerItemRow(icon: "headphones", iconColor: .onSurfaceVariant, label: "Soporte") {
                    activeSheet = .soporte
                }
                DrawerItemRow(icon: "info.circle.fill", iconColor: .onSurfaceVariant, label: "Sobre Nosotros") {
                    activeSheet = .sobreNosotros
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
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                Text(label)
                    .font(.bodySmMedium)
                    .foregroundStyle(destructive ? Color.appPrimary : Color.onSurface)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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
private struct CiudadSheet: View {
    @AppStorage("ciudadSeleccionada") private var ciudadSeleccionada: String = "Trujillo"
    @Environment(\.dismiss) private var dismiss

    private let ciudades = ["Lima", "Chiclayo", "Piura", "Cuzco", "Arequipa"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(icon: "building.2.fill", iconColor: .secondary, title: "Ciudad")

            Text("Selecciona tu ciudad para ver rutas y paraderos actualizados.")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)

            VStack(spacing: 8) {
                ForEach(ciudades, id: \.self) { ciudad in
                    ciudadRow(ciudad)
                }
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.onSurfaceVariant)
                Text("Pronto añadiremos más ciudades.")
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
                Spacer()
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
    }

    private func ciudadRow(_ ciudad: String) -> some View {
        let isSelected = (ciudad == ciudadSeleccionada)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                ciudadSeleccionada = ciudad
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: "building.fill")
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.onSurfaceVariant)
                    .frame(width: 24)
                Text(ciudad)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.appPrimary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.primaryContainer.opacity(0.20) : Color.surfaceContainerLow)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. AJUSTES SHEET
private struct AjustesSheet: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("lenguajeApp") private var lenguajeApp: String = "es"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(icon: "gearshape.fill", iconColor: .onSurfaceVariant, title: "Ajustes")

            // Tema
            VStack(alignment: .leading, spacing: 8) {
                Text("APARIENCIA")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                HStack(spacing: 12) {
                    temaButton(.light, icon: "sun.max.fill", label: "Claro")
                    temaButton(.dark, icon: "moon.fill", label: "Oscuro")
                }
            }

            // Idioma
            VStack(alignment: .leading, spacing: 8) {
                Text("IDIOMA")
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Picker("Idioma", selection: $lenguajeApp) {
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isDarkMode = (tema == .dark)
            }
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
         "En el mapa, toca los chips de Casa / UTP / Trabajo para cambiar rápido."),
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
                    creditoRow("Diseño y desarrollo", "Joaquín Díaz")
                    creditoRow("Curso", "Productos y Servicios - Ciclo 7")
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
            Text(title)
                .font(.headlineMd)
                .foregroundStyle(.onSurface)
            Spacer()
        }
        .padding(.bottom, 4)
    }
}
