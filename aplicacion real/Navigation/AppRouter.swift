//
//  AppRouter.swift
//  RutaUTP
//
//  Router central. Toda la navegación pasa por aquí.
//  NO se usa NavigationStack / NavigationLink en este proyecto.
//

import SwiftUI

enum AppScreen: Equatable {
    case bienvenida
    case mapaPrincipal
    case detalleRuta
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
