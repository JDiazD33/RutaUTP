import SwiftUI

struct MarkerPlacementOverlay: View {
    let modoColocarMarcador: Bool
    let tabBarHeight: CGFloat
    let cancelarMarcador: () -> Void

    /// Instrucción y salida; el objetivo se dibuja dentro del mapa para
    /// compartir su espacio de coordenadas y sus áreas seguras.
    @ViewBuilder
    var body: some View {
        if modoColocarMarcador {
            ZStack {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(L.t("Pon el círculo sobre tu destino. Al parar 1 s, se calcula la ruta",
                                 "Place the circle over your destination. Pause for 1 s to calculate the route"))
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .allowsHitTesting(false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                    Button(action: cancelarMarcador) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                            Text(L.t("Cancelar", "Cancel"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(PressableCapsuleStyle())
                    .accessibilityLabel(L.t("Cancelar el marcador", "Cancel the marker"))
                    // Único punto del overlay que debe recibir toques: el resto
                    // deja pasar el gesto hasta el mapa, que es quien coloca
                    // el marcador.
                    .allowsHitTesting(true)

                    Spacer().frame(height: tabBarHeight + 16)
                }
            }
            .transition(.opacity)
        }
    }
}
