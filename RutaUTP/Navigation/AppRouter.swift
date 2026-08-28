//
//  AppRouter.swift
//  RutaUTP
//
//  Router central. Toda la navegación pasa por aquí (no se usa NavigationStack).
//

import SwiftUI
import CoreLocation

enum AppScreen: Equatable {
    case bienvenida
    case mapaPrincipal
    case rutas
    case guardado
    case seguridad
    case perfil
    case trackingDemo         // Pantalla de prueba aislada (no entra por BottomNavBar).
}

/// Petición pendiente entre pantallas: "muéstrame la ruta / transporte
/// cerca de este lugar". La publica quien origina la acción (ej. Guardado)
/// y la consume la pantalla destino.
struct DestinoPendiente: Identifiable, Equatable {
    let id = UUID()
    let titulo: String
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
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

    /// Consume en MapaView: calcular ruta hacia el lugar desde la posición actual.
    @Published var destinoPendiente: DestinoPendiente?

    /// Consume en RutasView: filtrar rutas que pasan cerca del lugar.
    @Published var lugarCercanoPendiente: DestinoPendiente?

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

