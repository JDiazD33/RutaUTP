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

    init() {
        // Solo DEBUG: permite abrir directo en una pantalla desde consola,
        // p.ej. xcrun simctl launch ... apolito.RutaUTP --pantalla rutas
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--pantalla"), i + 1 < args.count {
            switch args[i + 1] {
            case "mapa":     AppRouter.pantallaInicial = .mapaPrincipal
            case "rutas":    AppRouter.pantallaInicial = .rutas
            case "guardado": AppRouter.pantallaInicial = .guardado
            case "seguridad":AppRouter.pantallaInicial = .seguridad
            case "perfil":   AppRouter.pantallaInicial = .perfil
            default:         break
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            switch router.currentScreen {
            case .bienvenida:    BienvenidaView()
            case .mapaPrincipal: MapaView()
            case .rutas:         RutasView()
            case .guardado:      GuardadoView()
            case .seguridad:     SeguridadView()
            case .perfil:        PerfilView()
            case .trackingDemo:  RouteTrackingDemoView()
            }
        }
        .ignoresSafeArea(edges: .bottom) // permite que BottomNavBar llegue al borde físico
        .environmentObject(router)
        .animation(.easeInOut(duration: 0.25), value: router.currentScreen)
        // Modo Señas: una sola instancia en la raíz, así se dibuja por encima
        // de cualquier pantalla sin duplicarla en cada vista.
        .overlay { SeniasOverlay() }
    }
}

#Preview {
    RootView()
}
