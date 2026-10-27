//
//  SideDrawer.swift
//  RutaUTP
//
//  Drawer lateral del Mapa. Cada item abre un mini card (sheet) con
//  animación nativa de SwiftUI.
//
//  El archivo contiene SOLO el panel: sus hojas viven en archivos propios
//  (NotificacionesSheet, CiudadSheet, AjustesSheet, SoporteSheet,
//  SobreNosotrosSheet, CerrarSesionSheet y la cabecera SheetHeader), el
//  formulario de datos personales en `DatosPersonalesSheet.swift`, el
//  selector de cámara en `Design/Components/ImagePicker.swift` y la foto de
//  perfil en `Services/Imagenes/ProfileImageStore.swift`.
//

import SwiftUI
import UIKit
// MARK: - Menu Item Identifier
enum DrawerItem: String, Identifiable {
    case idioma
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGFloat = 0
    @State private var activeSheet: DrawerItem? = nil
    /// Foto del header: la misma que el usuario sube en Datos Personales
    /// (ProfileImageStore). Se recarga al abrir el drawer y al cerrar el sheet.
    @State private var fotoPerfil: UIImage? = nil
    @State private var revisionFoto = UUID()
    @AccessibilityFocusState(for: .voiceOver) private var enfocarMenu: Bool

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(340, max(0, geometry.size.width - 32))
            ZStack(alignment: .leading) {
                // Backdrop
                Color.black
                    .opacity(isOpen ? 0.35 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isOpen)
                    .accessibilityHidden(true)

                // Panel
                drawerContent
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.appSurface.ignoresSafeArea(edges: .vertical))
                    .offset(x: isOpen ? dragOffset : -drawerWidth - 20)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isOpen)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                if v.translation.width < 0,
                                   abs(v.translation.width) > abs(v.translation.height) {
                                    dragOffset = v.translation.width
                                }
                            }
                            .onEnded { v in
                                if v.translation.width < -60,
                                   abs(v.translation.width) > abs(v.translation.height) {
                                    close()
                                } else {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .accessibilityAction(.escape) { close() }
        .onAppear { enfocarMenu = isOpen }
        // Sheets para cada item del menu
        .sheet(item: $activeSheet) { item in
            sheetContent(for: item)
                // El sheet vive en su propia UIWindow: se le fuerza el tema
                // elegido en Ajustes (no hereda el de la ventana principal).
                .seguirTemaForzado()
                .presentationDetents(
                    [.idioma, .ciudad, .soporte, .sobreNosotros, .notificaciones, .datosPersonales].contains(item) ? [.large] : [.medium, .large]
                )
                .presentationDragIndicator(.visible)
        }
        // La foto pudo cambiar en Datos Personales: recargar al abrir el
        // drawer y cuando vuelve de un sheet.
        .task(id: revisionFoto) {
            let foto = await ProfileImageStore.load()
            guard !Task.isCancelled else { return }
            fotoPerfil = foto
        }
        .onChange(of: isOpen) { _, abierto in
            enfocarMenu = abierto
            if abierto {
                revisionFoto = UUID()
            } else {
                dragOffset = 0
                activeSheet = nil
            }
        }
        .onChange(of: activeSheet) { _, sheet in
            if sheet == nil { revisionFoto = UUID() }
        }
        // La confirmación de cierre de sesión vive DENTRO de CerrarSesionSheet:
        // un alert declarado aquí se disparaba desde detrás de la hoja, donde
        // SwiftUI no lo presenta de forma fiable.
    }

    private func close() {
        dragOffset = 0
        isOpen = false
    }

    // MARK: - Switch de sheets
    @ViewBuilder
    private func sheetContent(for item: DrawerItem) -> some View {
        switch item {
        case .idioma:         SelectorIdioma()
        case .notificaciones: NotificacionesSheet()
        case .ciudad:         CiudadSheet()
        case .ajustes:        AjustesSheet()
        case .soporte:        SoporteSheet()
        case .sobreNosotros:  SobreNosotrosSheet()
        case .cerrarSesion:   CerrarSesionSheet(onConfirm: { activeSheet = nil })
        case .datosPersonales: DatosPersonalesSheet()
        }
    }

    // MARK: - Drawer content
    private var drawerContent: some View {
        VStack(spacing: 0) {
            encabezado

            List {
                Section {
                    accesoPerfil
                }

                Section {
                    Button {
                        AppHaptics.impact(.medium)
                        SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "perfil.idioma") {
                            activeSheet = .idioma
                        }
                    } label: {
                        DrawerRowLabel(icon: "globe", iconColor: acento,
                                       label: L.signable("perfil.idioma", "Idioma", "Language"),
                                       detail: IdiomaManager.shared.idioma.nombreNativo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.f("Cambiar idioma. Idioma actual: {0}", "Change language. Current language: {0}", [IdiomaManager.shared.idioma.nombreNativo]))
                    .seniable("perfil.idioma", conGesto: false)

                    DrawerItemRow(icon: "bell", iconColor: acento, label: L.t("Notificaciones", "Notifications")) {
                        activeSheet = .notificaciones
                    }
                    DrawerItemRow(icon: "building.2", iconColor: acento, label: L.t("Ciudad", "City")) {
                        activeSheet = .ciudad
                    }
                }

                Section {
                    DrawerItemRow(icon: "gearshape", iconColor: acento, label: L.t("Ajustes", "Settings")) {
                        activeSheet = .ajustes
                    }
                    DrawerItemRow(icon: "headphones", iconColor: acento, label: L.t("Soporte", "Support")) {
                        activeSheet = .soporte
                    }
                    DrawerItemRow(icon: "info.circle", iconColor: acento, label: L.t("Sobre Nosotros", "About Us")) {
                        activeSheet = .sobreNosotros
                    }
                    // Se conserva el acceso existente a la pantalla de tracking.
                    DrawerItemRow(icon: "location", iconColor: acento, label: L.t("Demo de seguimiento", "Tracking demo")) {
                        router.navigate(to: .trackingDemo)
                    }
                }

                Section {
                    DrawerItemRow(icon: "rectangle.portrait.and.arrow.right",
                                  iconColor: .red,
                                  label: L.t("Cerrar Sesión", "Log out"),
                                  destructive: true) {
                        activeSheet = .cerrarSesion
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 56, for: .scrollContent)
        }
    }

    private var encabezado: some View {
        HStack(spacing: 12) {
            Text(L.t("Menú principal", "Main menu"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($enfocarMenu)
                .accessibilityAction(named: Text(L.t("Cerrar menú", "Close menu"))) { close() }

            Spacer(minLength: 8)

            Button {
                AppHaptics.impact(.light)
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.surfaceContainerLow, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar menú", "Close menu"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var accesoPerfil: some View {
        Button {
            AppHaptics.impact(.light)
            activeSheet = .datosPersonales
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.surfaceContainerLow)
                    if let fotoPerfil {
                        Image(uiImage: fotoPerfil)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(DatosPersonalesSheet.inicialesPersona)
                            .font(.headline)
                            .foregroundStyle(Color.onSurface)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(DatosPersonalesSheet.nombrePersona)
                        .font(.headline)
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Datos personales", "Personal details"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Datos personales", "Personal details"))
        .accessibilityValue(DatosPersonalesSheet.nombrePersona)
        .accessibilityHint(L.t("Doble toque para ver y editar tus datos personales", "Double tap to view and edit your personal details"))
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
        Button(role: destructive ? .destructive : nil) {
            AppHaptics.impact(.light)
            action()
        } label: {
            DrawerRowLabel(icon: icon, iconColor: iconColor, label: label,
                           destructive: destructive)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L.t("Doble toque para abrir ", "Double tap to open ") + label)
    }
}

private struct DrawerRowLabel: View {
    let icon: String
    let iconColor: Color
    let label: String
    var detail: String? = nil
    var destructive: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(destructive ? Color.red : Color.onSurface)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
