import SwiftUI
import MapKit

struct MapBusSelectionOverlay: View {
    let vm: MapaViewModel
    @EnvironmentObject private var router: AppRouter
    let tabBarHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La ficha entra deslizándose desde abajo, entera y opaca, como una hoja de
    /// iOS. Sin fundido: el material translúcido se ve casi completo con poca
    /// opacidad y el texto no, así que fundir los dos hacía que las letras
    /// aparecieran después que la tarjeta. Con Reducir movimiento solo se funde.
    private var transicionFicha: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom)
    }

    @ViewBuilder
    var body: some View {
        if let bus = vm.busSeleccionado {
            VStack {
                Spacer()
                BusDetailPopup(
                    bus: bus,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.busSeleccionado = nil
                        }
                    },
                    onVerMicro: {
                        // La ficha sigue abierta: el micro queda en el centro,
                        // por encima de ella.
                        vm.enfocarBus(bus)
                    },
                    onVerRuta: {
                        vm.busSeleccionado = nil
                        // Abre el detalle de ESA línea en Rutas, no la
                        // lista genérica.
                        router.rutaPendiente = bus.rutaId
                        router.navigate(to: .rutas)
                    }
                )
                // Resuelve la disposición de la ficha antes de animarla: su
                // contenido se mueve con ella en vez de colocarse por separado.
                .geometryGroup()
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarHeight + 16)
            }
            .transition(transicionFicha)
        }
    }
}

/// Retira lo que queda debajo de la ficha del micro mientras está abierta.
///
/// La ficha ocupa el sitio del panel inferior: si este siguiera a la vista, sus
/// tarjetas se transparentarían a través de ella y los controles del mapa
/// asomarían a medias por su borde. Al cerrarla, todo vuelve a su sitio.
///
/// La selección se lee aquí y no en `MapaView`: se reasigna con cada posición
/// de la flota y solo debe reevaluar este modificador, no la pantalla entera.
struct OcultoConFichaDeMicro: ViewModifier {
    let vm: MapaViewModel
    /// Falso cuando la ficha no se presenta, como durante un viaje.
    let fichaDisponible: Bool

    func body(content: Content) -> some View {
        let oculto = fichaDisponible && vm.busSeleccionado != nil
        content
            .opacity(oculto ? 0 : 1)
            .allowsHitTesting(!oculto)
            .accessibilityHidden(oculto)
    }
}
