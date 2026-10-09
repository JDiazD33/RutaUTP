import SwiftUI
import MapKit

struct MapBusSelectionOverlay: View {
    let vm: MapaViewModel
    @EnvironmentObject private var router: AppRouter
    let tabBarHeight: CGFloat

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
                    onVerRuta: {
                        vm.busSeleccionado = nil
                        // Abre el detalle de ESA línea en Rutas, no la
                        // lista genérica.
                        router.rutaPendiente = bus.rutaId
                        router.navigate(to: .rutas)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarHeight + 16)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
