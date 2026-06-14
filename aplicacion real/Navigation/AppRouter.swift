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
}

final class AppRouter: ObservableObject {
    @Published var currentScreen: AppScreen = .bienvenida

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
