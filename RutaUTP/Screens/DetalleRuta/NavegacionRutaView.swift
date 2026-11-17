//
//  NavegacionRutaView.swift
//  RutaUTP
//
//  Navegación ACTIVA sobre el recorrido real de la ruta (shape GTFS):
//   - GPS real del usuario proyectado sobre la polyline (PolylineMatching)
//   - Progreso del viaje (0...1), próximo paradero y paraderos restantes
//   - Paradero de bajada a elección; por defecto, el final de la línea
//   - Minutos y metros restantes hasta ese paradero, proporcionales al avance
//   - Aviso "prepárate para bajar" al acercarse y aviso de llegada
//   - Cambios de ruta confirmados por la comunidad que afectan a la línea
//   - Modo demo: simula el viaje completo a lo largo del shape (para
//     probar en simulador o sin moverse del sitio)
//
//  La guía sigue el GPS del usuario sobre el shape GTFS. Las estimaciones
//  comunitarias de vehículos pertenecen al flujo de tracking independiente.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Vista
struct NavegacionRutaView: View {
    let ruta: RutaOpcion
    let onFinish: () -> Void

    @StateObject private var viewModel: NavegacionRutaViewModel
    /// Avisos confirmados de cambios de ruta; solo conecta con la pantalla visible.
    @StateObject private var cambiosRuta = RouteChangesService()
    @State private var seguir: Bool = true
    @State private var ajustarTrigger = 0
    @State private var pantallaVisible = false
    @State private var alturaCabecera: CGFloat = 60
    @State private var alturaContenido: CGFloat = 260
    @State private var eligiendoParadero = false
    @State private var confirmandoFinalizar = false
    @State private var mostrarCambios = false
    @State private var avisos: [RouteChangeAlert] = []
    @State private var cambiosEnMapa: [CambioRutaEnMapa] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @AccessibilityFocusState(for: .voiceOver) private var enfocarLlegada: Bool

    init(ruta: RutaOpcion, locationService: LocationServiceProtocol, onFinish: @escaping () -> Void) {
        self.ruta = ruta
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: NavegacionRutaViewModel(ruta: ruta, locationService: locationService))
    }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var llego: Bool { viewModel.estado == .finalizado }
    private var identificacion: (codigo: String, letra: String) {
        GTFSNombreParser.identificacionTransporte(linea: ruta.linea, variante: ruta.variante)
    }

    var body: some View {
        GeometryReader { geometria in
            let alturaPanel = min(alturaContenido, geometria.size.height * 0.56)
            ZStack {
                MapaNavegacionRepresentable(
                    shape: viewModel.shape,
                    paraderos: ruta.paraderos,
                    colorLinea: UIColor(ruta.colorLinea),
                    colorPosicion: UIColor(Color.appPrimary),
                    posicion: viewModel.posicion,
                    destino: viewModel.coordenadaDestino,
                    nombreDestino: viewModel.nombreDestino,
                    cambios: cambiosEnMapa,
                    seguir: $seguir,
                    modoDemo: viewModel.modoDemo,
                    ajustarTrigger: ajustarTrigger,
                    margenes: UIEdgeInsets(
                        top: geometria.safeAreaInsets.top + alturaCabecera + 32,
                        left: 32,
                        bottom: geometria.safeAreaInsets.bottom + alturaPanel + 100,
                        right: 72
                    ),
                    reducirMovimiento: reducirMovimiento,
                    alTocarCambio: { mostrarCambios = true }
                )
                .ignoresSafeArea()
                .accessibilityHidden(llego)

                VStack(spacing: 12) {
                    cabecera
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { alturaCabecera = $0 }
                    Spacer(minLength: 0)
                    controlesMapa
                    ScrollView {
                        contenidoPanel
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { alturaContenido = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: alturaPanel)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // Deja libre el pie nativo de Apple Maps y su aviso legal.
                .padding(.bottom, 32)
                .accessibilityHidden(llego)

                if llego {
                    alertaLlegada
                        .transition(.opacity)
                }
            }
            .animation(reducirMovimiento ? nil : .easeInOut(duration: 0.25), value: llego)
        }
        .onAppear {
            NotificacionesService.shared.navegacionAbierta = true
            pantallaVisible = true
            viewModel.actualizarActividadVisual(scenePhase == .active)
            viewModel.iniciar()
            actualizarServicios()
        }
        .onDisappear {
            NotificacionesService.shared.navegacionAbierta = false
            pantallaVisible = false
            viewModel.actualizarActividadVisual(false)
            viewModel.terminar()
            actualizarServicios()
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.actualizarActividadVisual(pantallaVisible && phase == .active)
            if pantallaVisible && phase == .active && !viewModel.modoDemo && viewModel.estado != .finalizado {
                viewModel.iniciar()
            }
            actualizarServicios()
        }
        .onChange(of: cambiosRuta.alerts, initial: true) { _, alertas in
            actualizarCambios(alertas)
        }
        .onChange(of: faseAccesible) { _, fase in
            switch fase {
            case "cerca", "pasado": AppHaptics.warning()
            case "final": AppHaptics.success()
            default: break
            }
            guard voiceOverOn, scenePhase == .active, pantallaVisible else { return }
            enfocarLlegada = viewModel.estado == .finalizado
            if !enfocarLlegada {
                AccesibilidadIdioma.anunciar(instruccion + ". " + subtitulo)
            }
        }
        .sheet(isPresented: $eligiendoParadero) {
            SelectorParaderoBajada(viewModel: viewModel, linea: ruta.linea, finalDeLinea: ruta.paradaFinVisible)
        }
        .sheet(isPresented: $mostrarCambios) {
            CambiosRutaDetalleSheet(avisos: avisos, quorum: cambiosRuta.quorum,
                                    nombreLinea: { $0.routeId == ruta.id ? ruta.lineaConLetra : "" })
        }
        .accessibilityAction(.escape) { finalizar() }
    }

    /// La pantalla sigue el avance con el teléfono a la vista: se mantiene
    /// encendida mientras está visible y en primer plano, y los avisos de
    /// cambios de ruta solo conservan su conexión en ese mismo caso.
    private func actualizarServicios() {
        let activa = pantallaVisible && scenePhase == .active
        UIApplication.shared.isIdleTimerDisabled = activa
        if activa { cambiosRuta.start() } else { cambiosRuta.stop() }
    }

    /// Avisos que tocan el recorrido de esta línea. Se calculan al cambiar los
    /// avisos, no en cada lectura del GPS.
    private func actualizarCambios(_ alertas: [RouteChangeAlert]) {
        let recorrido = viewModel.shape
        var afectan: [RouteChangeAlert] = []
        var enMapa: [CambioRutaEnMapa] = []
        for aviso in alertas {
            let misma = aviso.routeId == ruta.id
            let tramo = misma ? TramoCambioRuta.coordenadas(de: aviso, en: recorrido) : nil
            guard TramoCambioRuta.afecta(aviso, tramo: tramo, recorrido: recorrido, mismaRuta: misma) else { continue }
            afectan.append(aviso)
            enMapa.append(CambioRutaEnMapa(aviso: aviso, tramo: tramo ?? [], calleNueva: aviso.calleNueva))
        }
        if afectan.isEmpty { mostrarCambios = false }
        avisos = afectan
        cambiosEnMapa = enMapa
    }

    private func finalizar() {
        if viewModel.viajeEnCurso {
            confirmandoFinalizar = true
        } else {
            onFinish()
        }
    }

    // MARK: - Cabecera
    private var cabecera: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                tarjetaLinea
                Spacer(minLength: 0)
                menuOpciones
                botonFinalizar
            }
            VStack(alignment: .leading, spacing: 10) {
                tarjetaLinea
                HStack(spacing: 10) {
                    menuOpciones
                    botonFinalizar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tarjetaLinea: some View {
        HStack(spacing: 10) {
            Group {
                if identificacion.letra.isEmpty {
                    Image(systemName: "bus.fill")
                        .font(.headline)
                } else {
                    Text(identificacion.letra)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }
            }
            .foregroundStyle(ruta.colorLinea.textoContrastante(esquema: colorScheme))
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 36)
            .background(ruta.colorLinea, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Línea ", "Line ") + identificacion.codigo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                Text(viewModel.modoDemo ? L.t("Simulación", "Simulation") : L.t("Tu viaje", "Your trip"))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Línea ", "Line ") + ruta.lineaConLetra + ". " + ruta.empresa)
        .accessibilityValue(viewModel.modoDemo ? L.t("Simulación", "Simulation") : L.t("Tu viaje", "Your trip"))
        .accessibilityAddTraits(.isHeader)
    }

    private var menuOpciones: some View {
        Menu {
            Button {
                eligiendoParadero = true
            } label: {
                Label(L.t("Elegir dónde bajar", "Choose where to get off"), systemImage: "flag")
            }
            if !avisos.isEmpty {
                Button {
                    mostrarCambios = true
                } label: {
                    Label(L.t("Cambios confirmados", "Confirmed changes"), systemImage: "exclamationmark.triangle")
                }
            }
            Toggle(isOn: $viewModel.modoDemo) {
                Label(L.t("Simular recorrido", "Simulate route"), systemImage: "play.circle")
            }
            .disabled(viewModel.shape.count < 2)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(L.t("Más opciones", "More options"))
    }

    private var botonFinalizar: some View {
        Button(role: .destructive) {
            finalizar()
        } label: {
            Text(L.t("Finalizar", "End"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(light: "#FFFFFF", dark: "#3B0007"))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color.appError, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .confirmationDialog(L.t("¿Finalizar la navegación?", "End navigation?"),
                            isPresented: $confirmandoFinalizar, titleVisibility: .visible) {
            Button(L.t("Finalizar", "End"), role: .destructive) { onFinish() }
            Button(L.t("Seguir navegando", "Keep navigating"), role: .cancel) {}
        } message: {
            Text(L.t("Dejaremos de seguir tu avance en esta línea.",
                     "We'll stop following your progress on this line."))
        }
    }

    // MARK: - Controles del mapa
    private var controlesMapa: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                Button {
                    seguir = true
                } label: {
                    Image(systemName: seguir ? "location.fill" : "location")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(seguir ? acento : Color.onSurface)
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L.t("Seguir mi ubicación", "Follow my location"))
                .accessibilityAddTraits(seguir ? .isSelected : [])

                Divider().frame(width: 28)

                Button {
                    seguir = false
                    ajustarTrigger += 1
                } label: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .symbolEffect(.bounce, value: reducirMovimiento ? 0 : ajustarTrigger)
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L.t("Ver recorrido completo", "Show entire route"))
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Panel inferior
    private var contenidoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Instrucción principal según estado
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconoEstado)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colorEstado)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(colorEstado.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(instruccion)
                        .font(.headline)
                        .foregroundStyle(Color.onSurface)
                    Text(subtitulo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(instruccion)
            .accessibilityValue(subtitulo)

            if viewModel.estado == .sinPermiso {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(L.t("Abrir Ajustes", "Open Settings"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryFill)
                .foregroundStyle(Color.onPrimaryFill)
            }

            if !avisos.isEmpty {
                AvisoCambioRutaFila(avisos: avisos) { mostrarCambios = true }
            }

            if viewModel.estado != .sinRecorrido {
                filaDestino
                avance
                datos
            }
        }
        .padding(16)
    }

    /// Paradero donde la persona baja; tocarlo permite elegir otro.
    private var filaDestino: some View {
        Button {
            eligiendoParadero = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(acento)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Bajas en", "You get off at"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.nombreDestino)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ruta.costo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .background(Color(uiColor: .quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Bajas en", "You get off at") + " " + viewModel.nombreDestino)
        .accessibilityValue(L.t("Pasaje ", "Fare ") + ruta.costo)
        .accessibilityHint(L.t("Abre la lista de paraderos para elegir dónde bajar.",
                               "Opens the stop list to choose where to get off."))
    }

    private var avance: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: viewModel.progresoViaje)
                .tint(acento)
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("Avance de tu viaje · tiempos estimados", "Trip progress · estimated times"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(Double(porcentaje) / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.onSurface)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Avance de tu viaje, tiempos estimados", "Trip progress, estimated times"))
        .accessibilityValue(L.f("{0} por ciento", "{0} percent", ["\(porcentaje)"]))
    }

    private var porcentaje: Int { Int((viewModel.progresoViaje * 100).rounded(.down)) }

    private var datos: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 3),
                  alignment: .leading, spacing: 12) {
            dato(icono: "clock",
                 valor: viewModel.posicion == nil || ruta.duracionMin <= 0
                    ? "—" : "~" + L.f("{0} min", "{0} min", ["\(viewModel.minutosRestantes)"]),
                 etiqueta: L.t("Restante", "Remaining"))
            dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
                 valor: viewModel.distanciaRestanteTexto, etiqueta: L.t("Por recorrer", "To go"))
            dato(icono: "mappin.and.ellipse",
                 valor: "\(viewModel.paraderosRestantes)", etiqueta: L.t("Paraderos", "Stops"))
        }
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(valor)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.onSurface)
            Label(etiqueta, systemImage: icono)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta)
        .accessibilityValue(valor == "—" ? L.t("No disponible", "Unavailable") : valor)
    }

    // MARK: - Estado → UI
    /// Excluye metros variables para no interrumpir la lectura en cada actualización GPS.
    private var faseAccesible: String {
        switch viewModel.estado {
        case .esperandoGPS: return "gps"
        case .sinRecorrido: return "sinRecorrido"
        case .sinPermiso: return "permiso"
        case .enRuta: return "ruta"
        case .fueraDeRuta: return "fuera"
        case .cercaDestino: return "cerca"
        case .destinoPasado: return "pasado"
        case .finalizado: return "final"
        }
    }
    private var iconoEstado: String {
        switch viewModel.estado {
        case .sinRecorrido: return "map"
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash"
        case .enRuta:        return "bus.fill"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .destinoPasado: return "arrow.uturn.backward"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    /// Tonos con contraste suficiente en claro y oscuro; el icono acompaña al color.
    private var colorEstado: Color {
        switch viewModel.estado {
        case .esperandoGPS:  return Color(uiColor: .secondaryLabel)
        case .sinPermiso:    return .appError
        case .enRuta:        return acento
        case .sinRecorrido, .fueraDeRuta, .destinoPasado:
            return Color(light: "#B4470B", dark: "#FFA466")
        case .cercaDestino:  return Color(light: "#7A5C00", dark: "#FFD54F")
        case .finalizado:    return Color(light: "#1F6F45", dark: "#81DCA6")
        }
    }

    private var instruccion: String {
        switch viewModel.estado {
        case .sinRecorrido:
            return L.t("Recorrido no disponible", "Route unavailable")
        case .esperandoGPS:
            return L.t("Buscando señal GPS…", "Finding GPS signal…")
        case .sinPermiso:
            return L.t("Activa la ubicación para navegar", "Enable location to navigate")
        case .enRuta:
            return viewModel.paraderoSiguiente != nil
                ? L.t("Próximo paradero", "Next stop")
                : L.t("Continúa por el recorrido", "Continue along the route")
        case .fueraDeRuta(let metros):
            return viewModel.haEntradoEnRuta
                ? L.f("Fuera del recorrido · {0} m", "Off route · {0} m", ["\(Int(metros))"])
                : L.t("Acércate a un paradero", "Head to a stop")
        case .cercaDestino:
            return L.t("Prepárate para bajar", "Get ready to get off")
        case .destinoPasado:
            return L.t("Ya pasaste tu paradero", "You passed your stop")
        case .finalizado:
            return viewModel.destino == nil
                ? L.t("Llegaste al final de la línea", "You reached the end of the line")
                : L.t("Llegaste a tu paradero", "You reached your stop")
        }
    }

    private var subtitulo: String {
        switch viewModel.estado {
        case .sinRecorrido:
            return L.t("Esta línea no tiene un trazado válido para navegar.", "This line has no valid route geometry.")
        case .esperandoGPS:
            return L.t("Usaremos tu ubicación para mostrar tu avance.", "Your location will show your progress.")
        case .sinPermiso:
            return L.t("Permite el acceso a tu ubicación en Ajustes.", "Allow location access in Settings.")
        case .enRuta:
            let nombre = viewModel.paraderoSiguiente?.nombreVisible ?? viewModel.nombreDestino
            return nombre + (viewModel.distanciaProximoParaderoTexto.map { " · " + $0 } ?? "")
        case .fueraDeRuta:
            guard let paradero = viewModel.paraderoCercano, let metros = viewModel.distanciaParaderoM else {
                return L.t("Busca un paradero de la línea ", "Look for a stop on line ") + ruta.linea
            }
            let distancia = metros >= 1000 ? FormatoNumero.decimal(metros / 1000) + " km" : "\(Int(metros)) m"
            return paradero.nombreVisible + " · " + distancia + L.t(" en línea recta", " straight-line distance")
        case .cercaDestino:
            return viewModel.nombreDestino + " · " + viewModel.distanciaRestanteTexto
        case .destinoPasado:
            return L.t("Baja en el siguiente o elige otro paradero.", "Get off at the next one or choose another stop.")
        case .finalizado:
            return viewModel.nombreDestino
        }
    }

    // MARK: - Alerta de llegada
    private var alertaLlegada: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color(light: "#1F6F45", dark: "#81DCA6"))
                    .symbolEffect(.bounce, value: reducirMovimiento ? false : llego)
                    .accessibilityHidden(true)
                Text(viewModel.destino == nil
                     ? L.t("Fin del recorrido", "End of the route")
                     : L.t("Llegaste a tu paradero", "You reached your stop"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("Llegaste a ", "You arrived at ") + viewModel.nombreDestino)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($enfocarLlegada)

                Button {
                    onFinish()
                } label: {
                    Text(L.t("Terminar", "Done"))
                        .font(.headline)
                        .foregroundStyle(Color.onPrimaryFill)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                if viewModel.destino != nil {
                    Button {
                        viewModel.elegirDestino(nil)
                    } label: {
                        Text(L.t("Seguir en esta línea", "Stay on this line"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(acento)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Paradero de bajada
/// Lista de paraderos en orden de viaje para elegir dónde bajar.
private struct SelectorParaderoBajada: View {
    @ObservedObject var viewModel: NavegacionRutaViewModel
    let linea: String
    let finalDeLinea: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var busqueda = ""

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    private var resultados: [NavegacionRutaViewModel.ParadaEnRuta] {
        let texto = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return viewModel.paradas }
        return viewModel.paradas.filter { $0.paradero.nombreVisible.localizedStandardContains(texto) }
    }

    var body: some View {
        NavigationStack {
            List {
                if busqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        fila(titulo: finalDeLinea, detalle: L.t("Final de la línea", "End of the line"),
                             elegida: viewModel.destino == nil, pasada: false) {
                            viewModel.elegirDestino(nil)
                        }
                    }
                }
                Section {
                    if viewModel.paradas.isEmpty {
                        Text(viewModel.estado == .esperandoGPS
                             ? L.t("Cargando paraderos…", "Loading stops…")
                             : L.t("Esta línea no tiene paraderos sobre su recorrido.",
                                   "This line has no stops along its route."))
                            .foregroundStyle(.secondary)
                    } else if resultados.isEmpty {
                        Text(L.t("Ningún paradero coincide con la búsqueda.", "No stops match your search."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(resultados) { parada in
                        let pasada = viewModel.yaPaso(parada)
                        fila(titulo: parada.paradero.nombreVisible,
                             detalle: pasada ? L.t("Ya pasaste este paradero", "You already passed this stop") : nil,
                             elegida: viewModel.destino?.id == parada.id, pasada: pasada) {
                            viewModel.elegirDestino(parada)
                        }
                    }
                } header: {
                    Text(L.t("En orden de viaje", "In travel order"))
                }
            }
            .searchable(text: $busqueda, prompt: L.t("Buscar paradero", "Search stops"))
            .navigationTitle(L.t("¿Dónde bajas?", "Where do you get off?"))
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

    private func fila(titulo: String, detalle: String?, elegida: Bool, pasada: Bool,
                      accion: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            accion()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .foregroundStyle(pasada ? Color(uiColor: .secondaryLabel) : Color.onSurface)
                    if let detalle {
                        Text(detalle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if elegida {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(acento)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pasada)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}


#Preview {
    NavegacionRutaView(
        ruta: RutaOpcion(
            id: "17350695", linea: "C-01", empresa: "Nuevos Girasoles",
            recorrido: "Av. Miguel Grau (ramal circular)",
            frecuenciaMin: 4, duracionMin: 77, costo: "S/ 2.50",
            numParaderos: 247, distanciaKm: 21.3, colorLinea: Color(hex: "#00CC00"),
            shape: [], paraderos: [],
            paradaInicio: "Av. Miguel Grau", paradaFin: "Av. Miguel Grau"
        ),
        locationService: LocationService(),
        onFinish: {}
    )
}
