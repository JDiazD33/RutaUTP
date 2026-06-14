//
//  BottomNavBar.swift
//  RutaUTP
//
//  Barra de navegación inferior.
//  - 5 tabs distribuidos uniformemente (HStack + maxWidth: .infinity).
//  - El background se extiende al borde físico inferior del dispositivo
//    usando ignoresSafeArea(edges: .bottom) en el contenedor padre y
//    padding(.bottom, bottomSafeArea()) para el contenido (respeta
//    el home indicator).
//  - Tab "Seguridad" usa ícono lock.fill / lock.
//

import SwiftUI
import UIKit

// MARK: - Tab enum
enum NavTab: CaseIterable, Hashable {
    case mapa, rutas, guardado, seguridad, perfil

    var label: String {
        switch self {
        case .mapa:      return "Mapa"
        case .rutas:     return "Rutas"
        case .guardado:  return "Guardado"
        case .seguridad: return "Seguridad"
        case .perfil:    return "Perfil"
        }
    }

    /// Ícono outline (tab inactivo)
    var icon: String {
        switch self {
        case .mapa:      return "map"
        case .rutas:     return "bus"
        case .guardado:  return "bookmark"
        case .seguridad: return "lock"
        case .perfil:    return "person"
        }
    }

    /// Ícono filled (tab activo)
    var iconFill: String {
        switch self {
        case .mapa:      return "map.fill"
        case .rutas:     return "bus.fill"
        case .guardado:  return "bookmark.fill"
        case .seguridad: return "lock.fill"
        case .perfil:    return "person.fill"
        }
    }

    var screen: AppScreen {
        switch self {
        case .mapa:      return .mapaPrincipal
        case .rutas:     return .rutas
        case .guardado:  return .guardado
        case .seguridad: return .seguridad
        case .perfil:    return .perfil
        }
    }
}

// MARK: - Tab Item
struct NavTabItem: View {
    let tab: NavTab
    let isActive: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: isActive ? tab.iconFill : tab.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(
                    isActive ? Color.appPrimary : Color.onSurfaceVariant.opacity(0.65)
                )
                .frame(height: 26)
            Text(tab.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    isActive ? Color.appPrimary : Color.onSurfaceVariant.opacity(0.65)
                )
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Bottom NavBar
struct BottomNavBar: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            // Separador superior
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.20))
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: 0) {
                ForEach(NavTab.allCases, id: \.self) { tab in
                    NavTabItem(
                        tab: tab,
                        isActive: router.currentScreen == tab.screen
                    )
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        router.navigate(to: tab.screen)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            .padding(.bottom, bottomSafeArea())
        }
        .background(Color.appSurface)
    }

    /// Devuelve la altura del safe area inferior real del dispositivo.
    /// Esto permite que el contenido de la navbar quede por encima del
    /// home indicator sin dejar un gap visual.
    private func bottomSafeArea() -> CGFloat {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first
        else { return 16 }
        let inset = window.safeAreaInsets.bottom
        return inset > 0 ? inset : 12
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VStack {
            Spacer()
            BottomNavBar()
        }
    }
    .environmentObject(AppRouter())
}
