import SwiftUI
import MapKit

struct NearbyTransportPanel<ReportButton: View>: View {
    let vm: MapaViewModel
    @Binding var panelColapsado: Bool
    let reportButton: ReportButton

    // MARK: - Bottom panel
    // CORREGIDO V3: frame explicito de 168pt para que las cards no se corten
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                reportButton

                Spacer()

                if !panelColapsado {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.busesUTPActivos ? L.t("Buses de la UTP", "UTP buses")
                             : L.signable("mapa.cercanos", "Transportes cercanos", "Nearby transport"))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.onSurface)
                            .seniable("mapa.cercanos")
                        Text(vm.textoEstadoLineas)
                            .font(.system(size: 11))
                            .foregroundStyle(.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    // Al colapsar el texto se desliza a la derecha, hacia el
                    // ícono de bus (su ancla fija), y se funde detrás de él.
                    // Al expandir aparece ya en su sitio, sin arrastre.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
                }

                // Ícono de bus: fijo en el borde derecho, centrado bajo el
                // botón de Mi Ubicación. Los 4pt extra de padding cuadran
                // centros (36 vs 44pt de ancho) con los 20pt del botón GPS.
                Button {
                    AppHaptics.impact(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panelColapsado.toggle()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primaryContainer)
                            .frame(width: 36, height: 36)
                        Image(systemName: "bus.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.onPrimaryContainer)
                    }
                }
                .buttonStyle(PressableCapsuleStyle())
                .padding(.trailing, 4)
                .accessibilityLabel(panelColapsado
                                    ? L.t("Mostrar transportes cercanos", "Show nearby transport")
                                    : L.t("Ocultar transportes cercanos", "Hide nearby transport"))
            }
            .padding(.horizontal, 20)

            // Cards de buses con altura suficiente (rutas reales del feed GTFS)
            ScrollView(.horizontal, showsIndicators: false) {
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
                        .frame(width: 256, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                    } else if vm.tarjetasDelPanel.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "bus")
                                .foregroundStyle(vm.busesUTPActivos ? Color.red : Color.onSurfaceVariant)
                                .accessibilityHidden(true)
                            Text(vm.mensajePanelSinBuses)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(width: 256, alignment: .leading)
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
            .frame(height: 112)
        }
        .frame(height: 168)
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
}
