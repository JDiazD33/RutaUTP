import SwiftUI

/// Tipos de referencia, sin atribuir una carroceria a ninguna linea GTFS.
enum TipoTransporte3D: String, CaseIterable, Identifiable {
    case micro, combi, colectivo
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .micro: return L.t("Micro", "Bus")
        case .combi: return L.t("Combi", "Minibus")
        case .colectivo: return L.t("Colectivo", "Shared taxi")
        }
    }
}

enum AccionTransporte3D {
    case izquierda, derecha, acercar, alejar, restablecer
    case moverIzquierda, moverDerecha, moverArriba, moverAbajo
}

struct OrdenTransporte3D {
    var id = UUID()
    let accion: AccionTransporte3D
}

enum EstadoTransporte3D { case cargando, listo, fallo }

struct Transportes3DView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var tipo: TipoTransporte3D = .micro
    @State private var estado: EstadoTransporte3D = .cargando
    @State private var intento = 0
    @State private var orden: OrdenTransporte3D?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker(L.t("Tipo de transporte", "Vehicle type"), selection: $tipo) {
                        ForEach(TipoTransporte3D.allCases) { tipo in
                            Text(tipo.nombre).tag(tipo)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.appPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("transportes3d.tipo")

                    visor

                    HStack(spacing: 8) {
                        control("arrow.counterclockwise", L.t("Girar a la izquierda", "Rotate left"), .izquierda)
                        control("arrow.clockwise", L.t("Girar a la derecha", "Rotate right"), .derecha)
                        control("plus.magnifyingglass", L.t("Acercar", "Zoom in"), .acercar)
                        control("minus.magnifyingglass", L.t("Alejar", "Zoom out"), .alejar)
                        control("arrow.uturn.backward", L.t("Restablecer vista", "Reset view"), .restablecer)
                    }
                    .disabled(estado != .listo)

                    Text(L.t("Un dedo para girar; dos para mover o ampliar.", "One finger to rotate; two to pan or zoom."))
                        .font(.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                    Text(L.t("Modelos de referencia", "Reference models"))
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Transportes en 3D", "Transport in 3D"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .tint(Color.appPrimary)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    private var visor: some View {
        ZStack {
            Color.white
            if scenePhase == .active {
                VisorTransporte3D(tipo: tipo, color: UIColor(PaletasEmpresa.actual.colorMarca),
                                 intento: intento, orden: orden, estado: $estado)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.f("Modelo 3D de {0}", "3D model of {0}", [tipo.nombre]))
                    .accessibilityAction(named: L.t("Mover a la izquierda", "Move left")) { enviar(.moverIzquierda) }
                    .accessibilityAction(named: L.t("Mover a la derecha", "Move right")) { enviar(.moverDerecha) }
                    .accessibilityAction(named: L.t("Mover arriba", "Move up")) { enviar(.moverArriba) }
                    .accessibilityAction(named: L.t("Mover abajo", "Move down")) { enviar(.moverAbajo) }
                    .accessibilityIdentifier("transportes3d.modelo")
            }
            if estado == .cargando {
                ProgressView(L.t("Cargando modelo…", "Loading model…"))
                    .tint(Color(UIColor.darkGray))
                    .foregroundStyle(Color(UIColor.darkGray))
            } else if estado == .fallo {
                VStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .accessibilityHidden(true)
                    Text(L.t("No se pudo cargar el modelo.", "The model could not be loaded."))
                        .multilineTextAlignment(.center)
                    Button(L.t("Reintentar", "Try again")) { intento += 1 }
                        .buttonStyle(.bordered)
                        .tint(Color(UIColor.darkGray))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Color(UIColor.darkGray))
                .padding(20)
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func enviar(_ accion: AccionTransporte3D) {
        orden = OrdenTransporte3D(accion: accion)
    }

    private func control(_ simbolo: String, _ etiqueta: String, _ accion: AccionTransporte3D) -> some View {
        Button { enviar(accion) } label: {
            Image(systemName: simbolo)
                .font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appPrimary)
        .accessibilityLabel(etiqueta)
    }
}
