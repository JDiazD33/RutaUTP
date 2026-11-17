import SwiftUI

// MARK: - Ficha del micro seleccionado en el Mapa
/// Ficha del micro tocado en el Mapa.
///
/// La insignia lleva el código y el color de la línea, igual que la etiqueta del
/// micro sobre el mapa, así que el título queda libre para la empresa. Llegada y
/// ocupación van como filas de etiqueta y valor dentro de un grupo, al modo de
/// un formulario de iOS, y al pie quedan las dos acciones: centrar el micro o
/// abrir su recorrido completo en Rutas.
struct BusDetailPopup: View {
    let bus: BusAnimado
    let onClose: () -> Void
    let onVerMicro: () -> Void
    let onVerRuta: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// El círculo de cierre crece con su símbolo cuando la letra es grande.
    @ScaledMetric(relativeTo: .footnote) private var ladoCierre: CGFloat = 30

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado
            datos
            acciones
        }
        .padding(14)
        // Material más denso que el del buscador: la ficha lleva texto sobre la
        // zona del mapa con más micros y debe leerse sin que estos la tiñan.
        .background {
            forma
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .overlay {
            forma
                .strokeBorder(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Detalle de la línea ", "Details for line ") + bus.linea)
        .accessibilityAction(.escape, onClose)
    }

    // MARK: Encabezado

    private var encabezado: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                insignia
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.headline)
                        .foregroundStyle(.onSurface)
                    Text(detalleVehiculo)
                        .font(.subheadline)
                        .foregroundStyle(.onSurfaceVariant)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([L.t("Línea ", "Line ") + bus.linea, bus.empresa, detalleVehiculo]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityAddTraits(.isHeader)

            botonCerrar
        }
    }

    /// Código de la línea sobre su color. El texto pasa a negro o blanco según
    /// el color, porque el feed trae líneas claras (amarillo) y oscuras.
    private var insignia: some View {
        Text(bus.linea)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(bus.color.textoContrastante(esquema: colorScheme))
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(bus.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// La empresa titula la ficha; si el feed no la trae, lo hace la línea.
    private var titulo: String {
        bus.empresa.isEmpty ? L.t("Línea ", "Line ") + bus.linea : bus.empresa
    }

    /// «Micro · Ramal A»; sin ramal conocido queda solo el tipo de vehículo.
    private var detalleVehiculo: String {
        let tipo = L.tipoVehiculo(bus.tipo)
        return bus.variante.isEmpty ? tipo : tipo + " · " + bus.ramalTexto
    }

    private var botonCerrar: some View {
        // El área táctil mide 44 pt; el margen negativo deja el círculo visible
        // alineado con el borde del contenido en vez de hundido en la ficha.
        let margen = max(0, (44 - ladoCierre) / 2)
        return Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.onSurfaceVariant)
                .frame(width: ladoCierre, height: ladoCierre)
                .background(Color.surfaceContainerHighest, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding([.top, .trailing], -margen)
        .accessibilityLabel(L.t("Cerrar detalle del micro", "Close bus details"))
    }

    // MARK: Datos

    private var datos: some View {
        VStack(spacing: 0) {
            filaLlegada
            filaOcupacion
        }
        .background(Color.surfaceContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Las posiciones reales llevan `~` y una nota: su llegada es una estimación.
    /// Sin datos fiables se dice que no hay estimación en lugar de inventarla.
    @ViewBuilder
    private var filaLlegada: some View {
        let llegada = L.t("Llegada", "Arrival")
        if let minutos = bus.minutosLlegada {
            let tiempo = L.f("{0} min", "{0} min", ["\(minutos)"])
            BusDetailRow(
                titulo: llegada, simbolo: "clock",
                valor: bus.fuente == .real ? "~" + tiempo : tiempo,
                valorAccesible: tiempo,
                notas: bus.fuente == .real
                    ? [L.t("Llegada aproximada al punto consultado de la ruta. Puede variar por tráfico y paradas.",
                           "Approximate arrival at the queried point on the route. Traffic and stops may change it.")]
                    : [],
                conSeparador: true
            )
        } else {
            BusDetailRow(
                titulo: llegada, simbolo: "clock",
                valor: L.t("Sin estimación", "No estimate"), tinte: .onSurfaceVariant,
                etiquetaAccesible: L.t("Llegada no disponible: faltan datos suficientes para estimarla.",
                                       "Arrival unavailable: not enough data to estimate it."),
                conSeparador: true
            )
        }
    }

    @ViewBuilder
    private var filaOcupacion: some View {
        if let ocupacion = bus.displayedScenarioOccupancy {
            BusDetailRow(
                titulo: L.t("Ocupación", "Occupancy"), simbolo: "person.2.fill",
                valor: ocupacion.title, tinte: ocupacion == .full ? .appError : .onSurface
            )
        } else if let vehicleID = bus.occupancyVehicleID {
            BusOccupancyPanel(vehicleID: vehicleID)
                .id(bus.presentationIdentity)
        } else {
            BusDetailRow(
                titulo: L.t("Ocupación", "Occupancy"), simbolo: "person.2.fill",
                valor: L.t("Sin datos", "No data"), tinte: .onSurfaceVariant,
                etiquetaAccesible: L.t("Ocupación no disponible", "Occupancy unavailable")
            )
        }
    }

    // MARK: Acciones

    /// Dos acciones en fila, con la principal al final como en los diálogos de
    /// iOS. Con letra grande pasan a columna, la principal arriba, sin recortarse.
    private var acciones: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { botonVerMicro; botonVerRuta }
            VStack(spacing: 10) { botonVerRuta; botonVerMicro }
        }
    }

    private var botonVerMicro: some View {
        Button(action: onVerMicro) {
            Label(L.t("Ver micro", "View bus"), systemImage: "scope")
        }
        .buttonStyle(EstiloAccionFicha(principal: false))
        .accessibilityHint(L.t("Centra el mapa en este micro", "Centers the map on this bus"))
    }

    private var botonVerRuta: some View {
        Button(action: onVerRuta) {
            Label(L.t("Ver ruta", "View route"),
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .buttonStyle(EstiloAccionFicha(principal: true))
        .accessibilityHint(L.t("Abre el recorrido completo de esta línea en Rutas",
                               "Opens this line's full route in Routes"))
    }
}

// MARK: - Fila de dato de la ficha
/// Fila de etiqueta y valor de la ficha del micro, al modo de un formulario de
/// iOS: símbolo y etiqueta a la izquierda, valor a la derecha.
///
/// Con letra grande o textos largos el valor pasa debajo de la etiqueta en lugar
/// de recortarse. Las notas aclaran el dato en letra pequeña, bajo la fila.
struct BusDetailRow: View {
    let titulo: String
    let simbolo: String
    let valor: String
    var tinte: Color = .onSurface
    /// Lectura del valor para VoiceOver cuando el texto visible lleva signos.
    var valorAccesible: String? = nil
    /// Frase completa para VoiceOver cuando el valor abreviado no basta.
    var etiquetaAccesible: String? = nil
    var notas: [String] = []
    /// Línea fina bajo la fila, alineada con el texto como en una lista de iOS.
    var conSeparador = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Columna fija para el símbolo: las etiquetas de todas las filas se alinean.
    @ScaledMetric(relativeTo: .subheadline) private var anchoSimbolo: CGFloat = 26

    private var sangriaTexto: CGFloat { anchoSimbolo + 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    etiqueta
                    Spacer(minLength: 12)
                    textoValor
                }
                VStack(alignment: .leading, spacing: 2) {
                    etiqueta
                    textoValor.padding(.leading, sangriaTexto)
                }
            }
            ForEach(notas, id: \.self) { nota in
                Text(nota)
                    .font(.caption)
                    .foregroundStyle(.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, sangriaTexto)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if conSeparador {
                Divider().padding(.leading, 12 + sangriaTexto)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiquetaAccesible ?? titulo)
        .accessibilityValue(valorParaVoiceOver)
    }

    private var etiqueta: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: simbolo)
                .frame(width: anchoSimbolo)
            Text(titulo)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.onSurfaceVariant)
    }

    private var textoValor: some View {
        Text(valor)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tinte)
            .fixedSize(horizontal: false, vertical: true)
            // Los minutos cambian con el micro en marcha: el cambio se anima
            // como un contador, salvo con Reducir movimiento.
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy, value: valor)
    }

    /// La frase completa ya incluye el dato; en otro caso se lee valor y notas.
    private var valorParaVoiceOver: String {
        let partes = etiquetaAccesible == nil ? [valorAccesible ?? valor] + notas : notas
        return partes.joined(separator: ". ")
    }
}

// MARK: - Estilo de las acciones de la ficha
/// Botón de la ficha con el mismo alto, radio y tinta que las acciones de la
/// guía de ruta: relleno de la temática para la acción principal y superficie
/// neutra para la secundaria.
private struct EstiloAccionFicha: ButtonStyle {
    let principal: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(principal ? Color.onPrimaryFill : Color.onSurface)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(principal ? Color.primaryFill : Color.surfaceContainerHighest,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
