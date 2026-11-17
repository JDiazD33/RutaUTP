//
//  CambiosRutaMapa.swift
//  RutaUTP
//
//  Vistas de los cambios de ruta confirmados en el mapa principal: marcador,
//  fila de aviso en la guía de la ruta y hoja de detalle.
//

import SwiftUI

/// Marcador de un cambio confirmado. El icono identifica el motivo; el color
/// no es la única señal.
struct MarcadorCambioRuta: View {
    let motivo: MotivoCambioRuta

    var body: some View {
        Image(systemName: motivo.icono)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.appSurface)
            .frame(width: 32, height: 32)
            .background(motivo.tinta, in: Circle())
            .overlay { Circle().stroke(Color.appSurface, lineWidth: 2) }
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Marcador discreto del mapa libre: un punto del color del motivo. Conserva
/// un área táctil de 44 puntos; el icono aparece al acercar el mapa.
struct PuntoCambioRuta: View {
    let motivo: MotivoCambioRuta

    var body: some View {
        Circle()
            .fill(motivo.tinta)
            .frame(width: 12, height: 12)
            .overlay { Circle().stroke(Color.appSurface, lineWidth: 2) }
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Muestra de línea para la leyenda: continua o punteada, como en el mapa.
private struct MuestraLinea: View {
    let punteada: Bool

    var body: some View {
        Path { trazo in
            trazo.move(to: CGPoint(x: 2, y: 6))
            trazo.addLine(to: CGPoint(x: 26, y: 6))
        }
        .stroke(MotivoCambioRuta.desvio.tinta,
                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: punteada ? [2, 6] : []))
        .frame(width: 28, height: 12)
        .accessibilityHidden(true)
    }
}

/// Fila que avisa, en la guía de la ruta, de un cambio que la afecta.
struct AvisoCambioRutaFila: View {
    let avisos: [RouteChangeAlert]
    let accion: () -> Void

    var body: some View {
        if let aviso = avisos.first {
            Button(action: accion) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: aviso.motivo.icono)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(aviso.motivo.tinta)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(avisos.count == 1 ? aviso.motivo.tituloAviso
                             : L.f("{0} y {1} más", "{0} and {1} more",
                                   [aviso.motivo.tituloAviso, "\(avisos.count - 1)"]))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                        Text(aviso.textoVia ?? aviso.place)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(aviso.motivo.tinta.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(L.t("Muestra los cambios confirmados en esta ruta.",
                                   "Shows the confirmed changes on this route."))
        }
    }
}

/// Detalle de los cambios confirmados. Solo consulta: confirmar o corregir un
/// cambio se hace desde Reportar.
struct CambiosRutaDetalleSheet: View {
    let avisos: [RouteChangeAlert]
    let quorum: Int
    let nombreLinea: (RouteChangeAlert) -> String
    @Environment(\.dismiss) private var dismiss

    /// Avisos de una misma incidencia: mismo motivo, lugar, vía y vigencia. Un
    /// cierre deja un aviso por línea afectada; se leen juntos, en una sección.
    private var grupos: [[RouteChangeAlert]] {
        var claves: [String] = []
        var porClave: [String: [RouteChangeAlert]] = [:]
        for aviso in avisos {
            let clave = [aviso.reason, aviso.place, aviso.via ?? "", aviso.detalleVigencia]
                .joined(separator: "\u{1F}")
            if porClave[clave] == nil { claves.append(clave) }
            porClave[clave, default: []].append(aviso)
        }
        return claves.compactMap { porClave[$0] }
    }

    /// «C-03 «JJ», C-07 «Z1» y M-34 «A»», sin repetir variantes homónimas.
    private func lineas(de grupo: [RouteChangeAlert]) -> String {
        var nombres: [String] = []
        for nombre in grupo.map(nombreLinea) where !nombre.isEmpty && !nombres.contains(nombre) {
            nombres.append(nombre)
        }
        nombres.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        let formato = ListFormatter()
        formato.locale = FormatoFecha.localeActivo
        return formato.string(from: nombres) ?? nombres.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grupos, id: \.first?.id) { grupo in
                    let aviso = grupo[0]
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(aviso.motivo.tituloAviso, systemImage: aviso.motivo.icono)
                                .font(.headline)
                                .foregroundStyle(aviso.motivo.tinta)
                            let linea = lineas(de: grupo)
                            if !linea.isEmpty {
                                Text(aviso.motivo.cambiaRecorrido ? linea
                                     : L.f("Reportado desde {0}. Afecta a las líneas que pasan por aquí.",
                                           "Reported from {0}. Affects the lines that pass here.", [linea]))
                                    .font(.subheadline.weight(aviso.motivo.cambiaRecorrido ? .semibold : .regular))
                            }
                            Text(aviso.place)
                                .font(.body)
                            if let via = aviso.textoVia {
                                Label(via, systemImage: "arrow.triangle.turn.up.right.diamond")
                                    .font(.body.weight(.medium))
                            }
                            if grupo.contains(where: { !$0.calleNueva.isEmpty }) {
                                Text(L.t("La línea continua es la calle por la que va ahora; la punteada, el tramo que deja de recorrer.",
                                         "The solid line is the street it now takes; the dotted one, the stretch it no longer covers."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else if aviso.coordenadaFin != nil {
                                Text(L.t("El tramo punteado del mapa es el que la línea deja de recorrer.",
                                         "The dotted stretch on the map is the part the line no longer covers."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(aviso.detalleVigencia)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    DisclosureGroup {
                        ForEach(MotivoCambioRuta.allCases) { motivo in
                            Label {
                                Text(motivo.titulo)
                            } icon: {
                                Image(systemName: motivo.icono)
                                    .foregroundStyle(motivo.tinta)
                            }
                        }
                        Label {
                            Text(L.t("Calle por la que va ahora", "Street it now takes"))
                        } icon: {
                            MuestraLinea(punteada: false)
                        }
                        Label {
                            Text(L.t("Tramo que deja de recorrer", "Stretch it no longer covers"))
                        } icon: {
                            MuestraLinea(punteada: true)
                        }
                    } label: {
                        Label(L.t("Qué significa cada color", "What each color means"),
                              systemImage: "paintpalette")
                    }
                }
                Section {
                } footer: {
                    Text(L.f("Reportes de la comunidad. Un cambio se muestra cuando lo confirman {0} cuentas distintas. Para confirmarlo o corregirlo, usa Reportar.",
                             "Community reports. A change is shown once {0} different accounts confirm it. To confirm or correct it, use Report.",
                             ["\(quorum)"]))
                }
            }
            .navigationTitle(L.t("Cambios confirmados", "Confirmed changes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .seguirTemaForzado()
    }
}

/// Mantiene en el mapa los cambios confirmados mientras la pantalla está
/// visible y en primer plano. Fuera de eso no conserva la conexión abierta, y
/// al perderla retira los avisos en lugar de mostrarlos sin vigencia conocida.
struct CambiosRutaEnMapaModifier: ViewModifier {
    let vm: MapaViewModel
    let rutaViaje: DetectionRouteGeometry?
    let activo: Bool
    /// GPS compartido para el formulario del desvío grabado.
    let locationService: LocationServiceProtocol
    /// El servidor aceptó el reporte con el trazo grabado.
    var alEnviarDesvio: () -> Void = {}
    @StateObject private var servicio = RouteChangesService()

    func body(content: Content) -> some View {
        content
            .onChange(of: activo, initial: true) { _, activo in
                if activo { servicio.start() } else { servicio.stop() }
            }
            .onDisappear { servicio.stop() }
            .onChange(of: servicio.alerts, initial: true) { _, _ in sincronizar() }
            .onChange(of: vm.itinerario?.optionID) { _, _ in sincronizar() }
            .onChange(of: rutaViaje?.id) { _, _ in sincronizar() }
            .onChange(of: vm.rutasPorId.count) { _, _ in sincronizar() }
            // Al cerrarla, el aviso sigue dibujado un tiempo en el mapa.
            .sheet(item: Binding(get: { vm.cambiosSeleccionados },
                                 set: { vm.cambiosSeleccionados = $0 }),
                   onDismiss: { vm.mantenerCambiosDestacados() }) { seleccion in
                CambiosRutaDetalleSheet(avisos: seleccion.avisos, quorum: servicio.quorum,
                                        nombreLinea: { vm.nombreLinea(delCambio: $0) })
            }
            // Reutiliza la conexión del mapa: el formulario ya llega listo.
            .sheet(item: Binding(get: { vm.desvioPorReportar },
                                 set: { vm.desvioPorReportar = $0 })) { desvio in
                RouteChangesSheet(service: servicio, initialRouteID: desvio.routeID,
                                  locationService: locationService, desvioGrabado: desvio,
                                  alEnviarTrazo: alEnviarDesvio)
                    .seguirTemaForzado()
                    .presentationDetents([.large])
            }
    }

    @MainActor
    private func sincronizar() {
        vm.actualizarCambiosRuta(servicio.alerts, rutaViaje: rutaViaje)
    }
}

/// Propone reportar el desvío que grabó «Estoy en un micro». Aparece cuando el
/// micro retoma su recorrido; nada se envía sin que el usuario lo confirme.
struct AvisoDesvioDetectado: View {
    let desvio: TrazadorDesvio.Desvio
    let onReportar: () -> Void
    let onDescartar: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    private var largo: String {
        Measurement(value: desvio.longitud, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(FormatoFecha.localeActivo))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: MotivoCambioRuta.desvio.icono)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MotivoCambioRuta.desvio.tinta)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("¿El micro tomó otra calle?", "Did the bus take another street?"))
                        .font(.headline)
                        .foregroundStyle(Color.onSurface)
                    Text(L.f("Grabamos {0} fuera de su recorrido. Repórtalo para que otros vean la calle nueva.",
                             "We recorded {0} off its route. Report it so others can see the new street.",
                             [largo]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if textSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    botonReportar
                    botonDescartar
                }
            } else {
                HStack(spacing: 10) {
                    botonDescartar
                    botonReportar
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(
                L.t("Posible desvío grabado", "Possible detour recorded")).post()
        }
    }

    private var botonReportar: some View {
        Button(action: onReportar) {
            Text(L.t("Reportar desvío", "Report detour"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private var botonDescartar: some View {
        Button(action: onDescartar) {
            Text(L.t("Ahora no", "Not now"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}
