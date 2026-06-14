//
//  BottomNavBar.swift
//  RutaUTP
//
//  Barra de navegación inferior compartida entre las pantallas principales.
//  Se renderiza como overlay flotante (NO es un TabView).
//
//  - 5 tabs distribuidos uniformemente en HStack
//  - El tab "Seguridad" NO muestra icono (solo texto)
//  - El background se extiende con ignoresSafeArea para tapar el area
//    inferior del dispositivo (fix de safe area)
//

import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case mapa      = "Mapa"
    case rutas     = "Rutas"
    case guardado  = "Guardado"
    case seguridad = "Seguridad"
    case perfil    = "Perfil"

    var id: String { rawValue }

    /// Solo Mapa, Rutas, Guardado y Perfil tienen icono.
    /// Seguridad se renderiza sin icono segun requerimiento de diseno.
    var icon: String? {
        switch self {
        case .mapa:      return "map.fill"
        case .rutas:     return "bus.fill"
        case .guardado:  return "bookmark.fill"
        case .perfil:    return "person.fill"
        case .seguridad: return nil
        }
    }

    var screen: AppScreen {
        switch self {
        case .mapa:      return .mapaPrincipal
        case .rutas:     return .detalleRuta
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
        case .mapaPrincipal: return .mapa
        case .detalleRuta:   return .rutas
        case .guardado:      return .guardado
        case .seguridad:     return .seguridad
        case .perfil:        return .perfil
        case .bienvenida:    return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NavTab.allCases) { tab in
                tabButton(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            // El background se extiende mas alla del safe area inferior
            // para tapar completamente la parte baja del dispositivo.
            Color.appSurface
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.35))
                .frame(height: 1),
            alignment: .top
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: -4)
    }

    @ViewBuilder
    private func tabButton(_ tab: NavTab) -> some View {
        let isActive = (activeTab == tab)
        Button {
            router.navigate(to: tab.screen)
        } label: {
            VStack(spacing: 4) {
                // Contenedor de icono: real o invisible (para mantener altura consistente)
                if let icon = tab.icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 20)
                } else {
                    // Contenedor invisible del mismo tamano que el icono
                    Color.clear.frame(height: 20)
                }

                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isActive ? Color.onPrimaryContainer : Color.onSurfaceVariant.opacity(0.75))
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
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
