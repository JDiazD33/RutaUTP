//
//  AppRouter.swift
//  RutaUTP
//
//  Router central. Toda la navegación pasa por aquí (no se usa NavigationStack).
//

import SwiftUI

enum AppScreen: Equatable {
    case bienvenida
    case mapaPrincipal
    case rutas
    case guardado
    case seguridad
    case perfil
    case trackingDemo         // Pantalla de prueba aislada (no entra por BottomNavBar).
}

final class AppRouter: ObservableObject {
    /// Pantalla de arranque (solo la cambia el hook DEBUG de RootView).
    #if DEBUG
    static var pantallaInicial: AppScreen = .bienvenida
    #endif

    @Published var currentScreen: AppScreen = {
        #if DEBUG
        return AppRouter.pantallaInicial
        #else
        return .bienvenida
        #endif
    }()

    func navigate(to screen: AppScreen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentScreen = screen
        }
    }

    func reset() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentScreen = .mapaPrincipal
        }
    }
}

