//
//  BottomNavBar.swift
//  RutaUTP
//
//  Etiquetas escalables y altura medida para reservar espacio en las pantallas.
//

import SwiftUI

struct BottomNavBarHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BottomNavBarHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 64
}

private struct MainNavigationHostedExternallyKey: EnvironmentKey {
    static let defaultValue = false
}

struct MapNavigationBarPresentation: Equatable {
    var isVisible = true
    var accessibilityHidden = false
}

struct MapNavigationBarPresentationKey: PreferenceKey {
    static let defaultValue: MapNavigationBarPresentation? = nil
    static func reduce(value: inout MapNavigationBarPresentation?, nextValue: () -> MapNavigationBarPresentation?) {
        value = nextValue() ?? value
    }
}

extension EnvironmentValues {
    var mainNavigationHostedExternally: Bool {
        get { self[MainNavigationHostedExternallyKey.self] }
        set { self[MainNavigationHostedExternallyKey.self] = newValue }
    }

    var bottomNavBarHeight: CGFloat {
        get { self[BottomNavBarHeightEnvironmentKey.self] }
        set { self[BottomNavBarHeightEnvironmentKey.self] = newValue }
    }
}

// MARK: - Tab enum
enum NavTab: CaseIterable, Hashable {
    case mapa, rutas, guardado, seguridad, perfil

    var accessibilityID: String {
        switch self {
        case .mapa: return "main-navigation.mapa"
        case .rutas: return "main-navigation.rutas"
        case .guardado: return "main-navigation.guardado"
        case .seguridad: return "main-navigation.seguridad"
        case .perfil: return "main-navigation.perfil"
        }
    }

    var label: String {
        switch self {
        case .mapa:      return L.t("Mapa", "Map")
        case .rutas:     return L.t("Rutas", "Routes")
        case .guardado:  return L.t("Guardado", "Saved")
        case .seguridad: return L.t("Seguridad", "Safety")
        case .perfil:    return L.t("Perfil", "Profile")
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
                    isActive ? Color.appAccent : Color.onSurfaceVariant.opacity(0.65)
                )
            Text(tab.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    isActive ? Color.appAccent : Color.onSurfaceVariant.opacity(0.65)
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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

            HStack(alignment: .top, spacing: 0) {
                ForEach(NavTab.allCases, id: \.self) { tab in
                    Button {
                        router.navigate(to: tab.screen)
                    } label: {
                        NavTabItem(tab: tab, isActive: router.currentScreen == tab.screen)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tab.label)
                    .accessibilityIdentifier(tab.accessibilityID)
                    .accessibilityAddTraits(router.currentScreen == tab.screen ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: BottomNavBarHeightPreferenceKey.self,
                                       value: geometry.size.height)
            }
        }
        // El fondo blanco se extiende hasta abajo del todo (borde físico),
        // pero gracias a SwiftUI, el contenido de arriba respeta la barra del iPhone de forma segura.
        .background(
            Color.appSurface
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Navegación principal", "Main navigation"))
        .accessibilityIdentifier("main-navigation")
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
