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

/// Cada categoria conserva el modelo original y ofrece una segunda carroceria.
enum VarianteTransporte3D: String, CaseIterable, Identifiable {
    case original, detallado
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .original: return L.t("Original", "Original")
        case .detallado: return L.t("Detallado", "Detailed")
        }
    }

    var subdirectorioRecurso: String {
        switch self {
        case .original: return "Transportes3D"
        case .detallado: return "Transportes3D/Detallado"
        }
    }
}

enum AccionTransporte3D: String {
    case izquierda, derecha, acercar, alejar, restablecer
    case moverIzquierda, moverDerecha, moverArriba, moverAbajo
}

struct OrdenTransporte3D {
    var id = UUID()
    let accion: AccionTransporte3D
}

enum EstadoTransporte3D: Equatable {
    case cargando
    case listo(TipoTransporte3D, VarianteTransporte3D)
    case fallo

    func corresponde(tipo: TipoTransporte3D, variante: VarianteTransporte3D) -> Bool {
        self == .listo(tipo, variante)
    }
}

struct Transportes3DView: View {
    var identificacion: IdentificacionRuta3D? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoTransporte3D = .micro

    private var tipoSeleccionado: TipoTransporte3D? {
        if let identificacion { return identificacion.tipoModelo }
        return tipo
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let identificacion {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(identificacion.codigo + " · " + identificacion.letra)
                                .font(.headlineSm)
                            Text(identificacion.empresa)
                                .font(.bodySm)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        ColoresReferenciaRutaView(referencia: identificacion.colores)
                    } else {
                        SelectorTransporte3D(titulo: L.t("Tipo de transporte", "Vehicle type"),
                                             opciones: TipoTransporte3D.allCases, seleccion: $tipo,
                                             nombre: \.nombre, identificador: "transportes3d.tipo")
                    }
                    if let tipoSeleccionado {
                        PanelTransporte3D(tipo: tipoSeleccionado, identificacion: identificacion)
                    } else {
                        Text(L.t("Modelo de esta categoría próximamente", "Model for this category coming soon"))
                            .font(.bodySm)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Transportes en 3D", "Transport in 3D"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .tint(Color.appAccent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }
}

/// El detalle y la galeria comparten el mismo visor y sus alternativas accesibles.
struct PanelTransporte3D: View {
    let tipo: TipoTransporte3D
    var identificacion: IdentificacionRuta3D? = nil
    var activo = true
    /// En el detalle de ruta el panel queda bajo el mapa, casi siempre fuera
    /// de la pantalla al entrar. Con `true`, el visor espera a que el panel se
    /// vea dentro del scroll y a que el desplazamiento se detenga antes de
    /// crear RealityKit.
    var esperarVisibilidad = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("transportes3d.variante") private var variante: VarianteTransporte3D = .original
    @State private var estado: EstadoTransporte3D = .cargando
    @State private var intento = 0
    @State private var orden: OrdenTransporte3D?
    /// RealityKit crea el `ARView` (y su sesión gráfica) dentro del `init` de
    /// la vista UIKit. Montarlo cuando la sección entra en pantalla durante la
    /// transición del detalle costaba fotogramas en las líneas con modelo y no
    /// en las que muestran «próximamente». Se espera a que la transición
    /// termine para que todas las rutas respondan igual.
    ///
    /// Aun diferido, crear el `ARView` sigue siendo la parte más cara de la
    /// primera entrada, y ocurría aunque el panel estuviera fuera de la
    /// pantalla. En el detalle se monta cuando el panel ya se ve y el scroll
    /// se detuvo un momento; una vez montado se conserva.
    ///
    /// La espera usaba `onScrollVisibilityChange`, que solo existe en iOS 18:
    /// en iOS 17 el visor se creaba 350 ms después de entrar, dentro de la
    /// animación de entrada. Ahora la visibilidad se mide igual en ambas
    /// versiones y el visor no se crea mientras el contenido se desplaza.
    @State private var visorListo = false
    @State private var visibleEnScroll = false
    @State private var seguimiento = SeguimientoScroll()

    private var puedeMontarVisor: Bool {
        esperarVisibilidad ? visibleEnScroll : true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            selectorModelo
            visor
            HStack(spacing: 6) {
                control("arrow.counterclockwise", L.t("Girar a la izquierda", "Rotate left"), .izquierda)
                control("arrow.clockwise", L.t("Girar a la derecha", "Rotate right"), .derecha)
                control("plus.magnifyingglass", L.t("Acercar", "Zoom in"), .acercar)
                control("minus.magnifyingglass", L.t("Alejar", "Zoom out"), .alejar)
                control("arrow.uturn.backward", L.t("Restablecer vista", "Reset view"), .restablecer)
            }
            .disabled(!modeloListo || !activo)
            Text(L.t("Un dedo para girar; dos para mover o ampliar.", "One finger to rotate; two to pan or zoom."))
                .font(.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
            Text(L.t("Modelos de referencia", "Reference models"))
                .font(.caption)
                .foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private var selectorModelo: some View {
        SelectorTransporte3D(titulo: L.t("Modelo del vehículo", "Vehicle model"),
                             opciones: VarianteTransporte3D.allCases, seleccion: $variante,
                             nombre: \.nombre, identificador: "transportes3d.variante")
            .disabled(!activo)
    }

    private var modeloListo: Bool {
        estado.corresponde(tipo: tipo, variante: variante)
    }

    private var descripcionModeloCargado: String {
        switch estado {
        case let .listo(tipoCargado, varianteCargada):
            return tipoCargado.nombre + ", " + varianteCargada.nombre
        case .cargando: return L.t("Cargando modelo…", "Loading model…")
        case .fallo: return L.t("No se pudo cargar el modelo.", "The model could not be loaded.")
        }
    }

    private var visor: some View {
        ZStack {
            Color.white
            // Solo el segundo plano libera RealityKit. `.inactive` también llega
            // con el Centro de control o un aviso: destruir y recrear el visor
            // en cada caso detenía la interfaz al volver.
            if scenePhase != .background && activo && visorListo {
                VisorTransporte3D(tipo: tipo, variante: variante, color: UIColor(PaletasEmpresa.actual.colorMarca),
                                 intento: intento, orden: orden, identificacion: identificacion, estado: $estado)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(identificacion.map {
                        L.f("Modelo 3D: {0}, letra {1}, {2}", "3D model: {0}, letter {1}, {2}", [$0.codigo, $0.letra, $0.empresa])
                    } ?? L.f("Modelo 3D de {0}", "3D model of {0}", [tipo.nombre]))
                    .accessibilityValue(descripcionModeloCargado)
                    .accessibilityAction(named: L.t("Mover a la izquierda", "Move left")) { enviar(.moverIzquierda) }
                    .accessibilityAction(named: L.t("Mover a la derecha", "Move right")) { enviar(.moverDerecha) }
                    .accessibilityAction(named: L.t("Mover arriba", "Move up")) { enviar(.moverArriba) }
                    .accessibilityAction(named: L.t("Mover abajo", "Move down")) { enviar(.moverAbajo) }
                    .accessibilityIdentifier("transportes3d.modelo")
            }
            if !modeloListo && estado != .fallo {
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
        .modifier(VisibilidadEnScroll(activa: esperarVisibilidad, visible: $visibleEnScroll,
                                      seguimiento: seguimiento))
        .task(id: puedeMontarVisor) {
            guard puedeMontarVisor, !visorListo else { return }
            if esperarVisibilidad {
                // Crear el visor detiene la interfaz un instante: se espera a
                // que termine la entrada de la pantalla y a que el contenido
                // lleve un momento quieto.
                while !Task.isCancelled, !seguimiento.enReposo {
                    try? await Task.sleep(for: .milliseconds(120))
                }
            } else {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled, puedeMontarVisor else { return }
            visorListo = true
        }
    }

    private func enviar(_ accion: AccionTransporte3D) {
        guard modeloListo && activo else { return }
        orden = OrdenTransporte3D(accion: accion)
    }

    private func control(_ simbolo: String, _ etiqueta: String, _ accion: AccionTransporte3D) -> some View {
        Button { enviar(accion) } label: {
            Image(systemName: simbolo)
                .font(.system(size: 18, weight: .medium))
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 48)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appAccent)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier("transportes3d.control." + accion.rawValue)
    }
}

/// Opciones directas: no dependen de presentar un menu mientras arranca RealityKit.
/// La fila completa recibe el toque, tambien durante la carga de otro modelo.
private struct SelectorTransporte3D<Opcion: Hashable & RawRepresentable>: View where Opcion.RawValue == String {
    let titulo: String
    let opciones: [Opcion]
    @Binding var seleccion: Opcion
    let nombre: KeyPath<Opcion, String>
    let identificador: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(.subheadline.weight(.semibold))
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(opciones, id: \.self) { opcion in
                    Button { seleccion = opcion } label: {
                        Text(opcion[keyPath: nombre])
                            .font(.bodySm.weight(.medium))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(seleccion == opcion ? Color.onPrimaryContainer : Color.onSurface)
                            .background(seleccion == opcion ? Color.primaryContainer : Color.surfaceContainerLow,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(seleccion == opcion ? .isSelected : [])
                    .accessibilityIdentifier(identificador + "." + opcion.rawValue)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titulo)
        .accessibilityIdentifier(identificador)
    }
}

/// Momento del último desplazamiento del panel. No es estado de la vista:
/// actualizarlo en cada fotograma del scroll no vuelve a evaluar ningún `body`.
private final class SeguimientoScroll {
    private let creado = Date()
    var ultimoMovimiento = Date.distantPast

    /// La pantalla ya terminó de entrar y el contenido lleva un momento quieto.
    var enReposo: Bool {
        let ahora = Date()
        return ahora.timeIntervalSince(creado) >= 0.7 && ahora.timeIntervalSince(ultimoMovimiento) >= 0.3
    }
}

/// Informa si el panel se ve dentro del scroll que lo contiene y anota cada
/// desplazamiento. Fuera de un scroll el panel cuenta como visible.
private struct VisibilidadEnScroll: ViewModifier {
    let activa: Bool
    @Binding var visible: Bool
    let seguimiento: SeguimientoScroll

    private struct Marco: Equatable {
        let visible: Bool
        /// Posición del panel en tramos de 24 puntos: basta para saber que se movió.
        let tramo: Int
    }

    func body(content: Content) -> some View {
        if activa {
            content.onGeometryChange(for: Marco.self) { proxy in
                let propio = CGRect(origin: .zero, size: proxy.size)
                guard propio.height > 0, let ventana = proxy.bounds(of: .scrollView) else {
                    return Marco(visible: true, tramo: 0)
                }
                let visto = propio.intersection(ventana)
                let fraccion = visto.isNull ? 0 : visto.height / propio.height
                return Marco(visible: fraccion >= 0.25, tramo: Int((ventana.minY / 24).rounded(.down)))
            } action: { marco in
                seguimiento.ultimoMovimiento = Date()
                if visible != marco.visible { visible = marco.visible }
            }
        } else {
            content
        }
    }
}
