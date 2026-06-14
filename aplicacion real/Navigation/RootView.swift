//
//  RootView.swift
//  RutaUTP
//
//  Switch central de pantallas. La transición entre pantallas
//  se anima con un ease-in-out 0.25s.
//

import SwiftUI

struct RootView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            switch router.currentScreen {
            case .bienvenida:    BienvenidaView()
            case .mapaPrincipal: MapaView()
            case .detalleRuta:   DetalleRutaView()
            case .rutas:         RutasView()
            case .guardado:      GuardadoView()
            case .seguridad:     SeguridadView()
            case .perfil:        PerfilView()
            }
        }
        .environmentObject(router)
        .animation(.easeInOut(duration: 0.25), value: router.currentScreen)
    }
}

#Preview {
    RootView()
}
