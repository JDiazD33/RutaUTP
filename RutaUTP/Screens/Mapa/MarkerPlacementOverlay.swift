import SwiftUI

struct MarkerPlacementOverlay: View {
    let modoColocarMarcador: Bool
    let tabBarHeight: CGFloat
    let cancelarMarcador: () -> Void

    /// Lo que se ve mientras se elige el punto: el pin clavado en el centro y
    /// una barra con la instrucción y la salida.
    @ViewBuilder
    var body: some View {
        if modoColocarMarcador {
            ZStack {
                // El pin va en el centro geométrico de la pantalla, que es
                // justo lo que se está viendo. Se posiciona con el `ZStack`
                // y no con `UIScreen.main.bounds`: esa API está deprecada y
                // en iPad multitasking mide la pantalla, no la ventana.
                PinEnColocacion()
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(L.t("Mueve el mapa. Al parar 1 s, se calcula la ruta",
                                 "Move the map. Pause for 1 s to calculate the route"))
                            .font(.system(size: 12, weight: .semibold))
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
