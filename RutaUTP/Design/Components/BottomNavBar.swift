//
//  BottomNavBar.swift
//  RutaUTP
//
//  CORREGIDO V5: Diseño nativo y flexible.
//  - Control de altura simple mediante padding inferior.
//  - Eliminado cálculo manual de safe area para evitar iconos caídos.
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

    var icon: String {
        switch self {
        case .mapa:      return "map"
        case .rutas:     return "bus"
        case .guardado:  return "bookmark"
        case .seguridad: return "lock"
        case .perfil:    return "person"
        }
    }

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
            Text(tab.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    isActive ? Color.appPrimary : Color.onSurfaceVariant.opacity(0.65)
                )
                .lineLimit(1)
        }
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
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        router.navigate(to: tab.screen)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            // 💡 MODIFICA ESTE NÚMERO:
            // 12 es un excelente estándar. Si quieres los iconos más altos, súbelo a 16 o 20.
            // SwiftUI se encargará de sumarle el espacio de la barra del iPhone automáticamente.
            .padding(.bottom, 12)
        }
        // El fondo blanco se extiende hasta abajo del todo (borde físico),
        // pero gracias a SwiftUI, el contenido de arriba respeta la barra del iPhone de forma segura.
        .background(
            Color.appSurface
                .ignoresSafeArea(edges: .bottom)
        )
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
