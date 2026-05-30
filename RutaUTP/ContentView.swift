import SwiftUI

// Enum con todas las pantallas de la app
enum AppScreen: CaseIterable {
    case bienvenida
    case mapa_principal
    case seguridad
    case detalle_ruta
    case guardado
    case perfil
}

struct ContentView: View {
    @State private var screenStack: [AppScreen] = [.bienvenida]

    var currentScreen: AppScreen {
        screenStack.last ?? .bienvenida
    }

    var body: some View {
        ZStack {
            // todos los WebViews viven en memoria,
            // solo se muestran u ocultan ,sin negrosin recarga
            ForEach(AppScreen.allCases, id: \.self) { screen in
                WebScreenView(htmlFile: screen.htmlFileName, onNavigate: navigate)
                    .ignoresSafeArea()
                    .opacity(screen == currentScreen ? 1 : 0)
                    // Desactivar interacción en pantallas ocultas
                    .allowsHitTesting(screen == currentScreen)
                    // Animación suave al cambiar de tab
                    .animation(.easeInOut(duration: 0.18), value: currentScreen)
            }
        }
    }

    // recibe el destino desde el JS bridge y actualiza el stack
    func navigate(to destination: String) {
        let screen: AppScreen
        switch destination {
        case "mapa_principal": screen = .mapa_principal
        case "seguridad":      screen = .seguridad
        case "detalle_ruta":   screen = .detalle_ruta
        case "bienvenida":     screen = .bienvenida
        case "guardado":       screen = .guardado
        case "perfil":         screen = .perfil
        default: return
        }

        if destination == "mapa_principal" {
            screenStack = [.mapa_principal]
        } else {
            if screenStack.last != screen {
                screenStack.append(screen)
            }
        }
    }
}

// extension para mapear cada case a su archivo HTML
extension AppScreen {
    var htmlFileName: String {
        switch self {
        case .bienvenida:     return "bienvenida"
        case .mapa_principal: return "mapa_principal"
        case .seguridad:      return "seguridad"
        case .detalle_ruta:   return "detalle_ruta"
        case .guardado:       return "guardado"
        case .perfil:         return "perfil"
        }
    }
}
