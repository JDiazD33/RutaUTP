//
//  SideDrawer.swift
//  RutaUTP
//
//  Drawer lateral del Mapa. Cada item abre un mini card (sheet) con
//  animación nativa de SwiftUI.
//
//  El archivo contiene SOLO el panel: sus hojas viven en `DrawerSheets.swift`,
//  el formulario de datos personales en `DatosPersonalesSheet.swift`, el
//  selector de cámara en `Design/Components/ImagePicker.swift` y la foto de
//  perfil en `Services/Imagenes/ProfileImageStore.swift`.
//

import SwiftUI
import UIKit
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

    @State private var dragOffset: CGFloat = 0
    @State private var activeSheet: DrawerItem? = nil
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
                .accessibilityLabel(L.t("Cerrar menú", "Close menu"))
                .accessibilityHint(L.t("Doble toque para cerrar el panel lateral", "Double tap to close the side panel"))

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
                .presentationDetents(item == .ciudad ? [.large] : [.medium, .large])
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
                .accessibilityLabel(fotoPerfil == nil
                    ? L.t("Foto de perfil, JD", "Profile photo, JD")
                    : L.t("Foto de perfil", "Profile photo"))
                .accessibilityHint(L.t("Doble toque para ver y editar tus datos personales", "Double tap to view and edit your personal details"))

                Text("Ruta UTP Trujillo")
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                Text(L.t("Menú principal", "Main menu"))
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
                    SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "perfil.idioma") {
                        IdiomaManager.shared.alternar()
                    }
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
                            Text(IdiomaManager.shared.esIngles ? "Switch to Español" : "Switch to English")
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        Spacer()
                        Text(IdiomaManager.shared.etiqueta)
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cambiar idioma", "Change language"))
                .seniable("perfil.idioma", conGesto: false)
                .padding(.horizontal, 8)

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
                              label: L.t("Cerrar Sesión", "Log out"),
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
        .accessibilityHint(L.t("Doble toque para abrir ", "Double tap to open ") + label)
    }
}

