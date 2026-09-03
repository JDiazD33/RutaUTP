//
//  RootView.swift
//  RutaUTP
//
//  Switch central de pantallas. La transición entre pantallas
//  se anima con un ease-in-out 0.25s.
//

import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var router = AppRouter()

    /// Tema claro/oscuro. Se aplica SOLO con aplicarTemaEnVentanas (abajo):
    /// un único escritor de overrideUserInterfaceStyle. No volver a añadir
    /// .preferredColorScheme aquí ni animar el cambio de isDarkMode —
    /// cuando ambos canales escriben la misma propiedad de la ventana y el
    /// cambio va dentro de una animación, SwiftUI deja de re-aplicar el
    /// estilo al VOLVER a claro (el tema quedaba "pegado" en oscuro).
    @AppStorage("isDarkMode") private var isDarkMode = false

    /// Fuerza el tema a nivel de VENTANA (UIKit), en todas las ventanas de
    /// todas las escenas — incluye la ventana propia de los sheets (iOS 16+).
    /// Al ser imperativo pisa el trait collection completo en ambas
    /// direcciones (claro ↔ oscuro) sin depender de la invalidación de
    /// SwiftUI.
    private func aplicarTemaEnVentanas(_ oscuro: Bool) {
        let estilo: UIUserInterfaceStyle = oscuro ? .dark : .light
        for escena in UIApplication.shared.connectedScenes {
            guard let windowScene = escena as? UIWindowScene else { continue }
            windowScene.windows.forEach { $0.overrideUserInterfaceStyle = estilo }
        }
    }

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
        .onAppear { aplicarTemaEnVentanas(isDarkMode) }
        .onChange(of: isDarkMode) { _, nuevo in
            // Un único escritor del tema: inmediato y en ambos sentidos.
            aplicarTemaEnVentanas(nuevo)
        }
        .onChange(of: router.currentScreen) { _, _ in
            // Pantallas como NavegaciónRuta fuerzan .dark sobre la ventana;
            // al salir de ellas se re-afirma el tema elegido por el usuario.
            aplicarTemaEnVentanas(isDarkMode)
        }
        // Modo Señas: una sola instancia en la raíz, así se dibuja por encima
        // de cualquier pantalla sin duplicarla en cada vista.
        .overlay { SeniasOverlay() }
    }
}

#Preview {
    RootView()
}
