import SwiftUI
import MapKit

struct NearbyTransportPanel<MapControls: View>: View {
    let vm: MapaViewModel
    let mapControls: MapControls

    // MARK: - Bottom panel
    var body: some View {
        VStack(spacing: 16) {
            mapControls

            if vm.cargandoLineas || (vm.errorLineas == nil && !vm.tarjetasDelPanel.isEmpty) {
                // Conserva espacio para las tarjetas y el desplazamiento horizontal.
                ScrollView(.horizontal, showsIndicators: false) {
                    tarjetas
                }
                .frame(height: 112)
            } else {
                // Un aviso ocupa su altura real, sin reservar una fila de buses vacia.
                tarjetas
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 16)
        // Fondo con degradado para separar el panel de las etiquetas del mapa
        .background(
            LinearGradient(
                colors: [Color.appBackground.opacity(0.0),
                         Color.appBackground.opacity(0.92),
                         Color.appBackground],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }

    private var tarjetas: some View {
        HStack(spacing: 12) {
            if vm.cargandoLineas {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                        .frame(width: 180, height: 100)
                        .overlay(
                            ProgressView()
                                .tint(.onSurfaceVariant)
                        )
                }
            } else if let error = vm.errorLineas {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.mensajeUsuario)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                    Button(L.t("Reintentar", "Try again")) { vm.reintentarCatalogo() }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
            } else if vm.tarjetasDelPanel.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bus")
                        .foregroundStyle(vm.busesUTPActivos ? Color.red : Color.onSurfaceVariant)
                        .accessibilityHidden(true)
                    Text(vm.mensajePanelSinBuses)
                        .font(.subheadline)
                        .foregroundStyle(.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                )
            } else {
                ForEach(vm.tarjetasDelPanel) { bus in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            vm.seleccionarBus(id: bus.id)
                        }
                    } label: {
                        BusCard(
                            linea: L.t("LÍNEA", "LINE") + " \(bus.linea)",
                            empresa: bus.empresa,
                            minutos: bus.etiquetaLlegada,
                            tipo: bus.tipo,
                            placa: bus.ramalTexto,
                            colorLinea: bus.color
                        )
                        .frame(height: 100)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L.t("Muestra información de esta línea", "Shows information for this line"))
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
