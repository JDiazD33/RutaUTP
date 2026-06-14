//
//  BottomNavBar.swift
//  RutaUTP
//
//  Barra de navegación inferior compartida entre las pantallas principales.
//  Se renderiza como overlay flotante (NO es un TabView).
//

import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case mapa      = "Mapa"
    case rutas     = "Rutas"
    case guardado  = "Guardado"
    case seguridad = "Seguridad"
    case perfil    = "Perfil"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mapa:      return "map.fill"
        case .rutas:     return "bus.fill"
        case .guardado:  return "bookmark.fill"
        case .seguridad: return "heart.shield.fill"
        case .perfil:    return "person.fill"
        }
    }

    var screen: AppScreen {
        switch self {
        case .mapa:      return .mapaPrincipal
        case .rutas:     return .mapaPrincipal  // Rutas vive dentro de Mapa + Detalle
        case .guardado:  return .guardado
        case .seguridad: return .seguridad
        case .perfil:    return .perfil
        }
    }
}

struct BottomNavBar: View {
    @EnvironmentObject private var router: AppRouter

    private var activeTab: NavTab? {
        switch router.currentScreen {
        case .mapaPrincipal, .detalleRuta: return .mapa
        case .guardado:                    return .guardado
        case .seguridad:                   return .seguridad
        case .perfil:                      return .perfil
        case .bienvenida:                  return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NavTab.allCases) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color.appSurface
                Color.white.opacity(0.001) // permite blur
            }
            .overlay(
                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.35))
                    .frame(height: 1),
                alignment: .top
            )
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: -4)
    }

    @ViewBuilder
    private func tabButton(_ tab: NavTab) -> some View {
        let isActive = (activeTab == tab)
        Button {
            router.navigate(to: tab.screen)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(tab.rawValue)
                    .font(.labelCapsMd)
            }
            .foregroundStyle(isActive ? Color.onPrimaryContainer : Color.onSurfaceVariant.opacity(0.70))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 48)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primaryContainer)
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
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
