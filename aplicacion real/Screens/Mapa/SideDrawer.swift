//
//  SideDrawer.swift
//  RutaUTP
//
//  Drawer lateral del Mapa. Anima con spring y permite cerrar
//  con tap en backdrop o swipe a la izquierda.
//

import SwiftUI

struct SideDrawer: View {
    @Binding var isOpen: Bool
    @EnvironmentObject private var router: AppRouter

    @State private var dragOffset: CGFloat = 0
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
    }

    private func close() {
        dragOffset = 0
        isOpen = false
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
                DrawerItem(icon: "bell.fill", iconColor: .tertiary, label: "Notificaciones") {}
                DrawerItem(icon: "building.2.fill", iconColor: .secondary, label: "Ciudad") {}
                Divider().padding(.leading, 56)
                DrawerItem(icon: "gearshape.fill", iconColor: .onSurfaceVariant, label: "Ajustes") {}
                DrawerItem(icon: "headphones", iconColor: .onSurfaceVariant, label: "Soporte") {}
                DrawerItem(icon: "info.circle.fill", iconColor: .onSurfaceVariant, label: "Sobre Nosotros") {}
                Spacer()
                DrawerItem(icon: "rectangle.portrait.and.arrow.right",
                           iconColor: .appPrimary,
                           label: "Cerrar Sesión",
                           destructive: true) {}
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Drawer row
private struct DrawerItem: View {
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
