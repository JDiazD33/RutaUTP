//
//  NavegacionRutaView.swift
//  RutaUTP
//
//  Navegación ACTIVA sobre el recorrido real de la ruta (shape GTFS):
//   - GPS real del usuario proyectado sobre la polyline (PolylineMatching)
//   - Progreso del viaje (0...1), próximo paradero y paraderos restantes
//   - Minutos y metros restantes proporcionales al avance
//   - Aviso "baja aquí" al acercarse al final del recorrido
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
    @State private var seguir: Bool = true
    @State private var pantallaVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @AccessibilityFocusState(for: .voiceOver) private var enfocarLlegada: Bool

    init(ruta: RutaOpcion, locationService: LocationServiceProtocol, onFinish: @escaping () -> Void) {
        self.ruta = ruta
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: NavegacionRutaViewModel(ruta: ruta, locationService: locationService))
    }

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a").ignoresSafeArea()

            MapaNavegacionRepresentable(
                shape: viewModel.shape,
                paraderos: ruta.paraderos,
                colorLinea: UIColor(ruta.colorLinea),
                colorPosicion: UIColor(Color.appPrimary),
                posicion: viewModel.posicion,
                seguir: $seguir,
                modoDemo: viewModel.modoDemo
            )
            .ignoresSafeArea()
            .accessibilityHidden(viewModel.estado == .finalizado)

            VStack(spacing: 0) {
                topBar
                Spacer()
                panelInferior
            }
            .accessibilityHidden(viewModel.estado == .finalizado)

            if viewModel.estado == .finalizado {
                alertaLlegada
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            NotificacionesService.shared.navegacionAbierta = true
            pantallaVisible = true
            viewModel.actualizarActividadVisual(scenePhase == .active)
            viewModel.iniciar()
        }
        .onDisappear {
            NotificacionesService.shared.navegacionAbierta = false
            pantallaVisible = false
            viewModel.actualizarActividadVisual(false)
            viewModel.terminar()
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.actualizarActividadVisual(pantallaVisible && phase == .active)
            if pantallaVisible && phase == .active && !viewModel.modoDemo && viewModel.estado != .finalizado {
                viewModel.iniciar()
            }
        }
        .onChange(of: faseAccesible) { _, _ in
            guard voiceOverOn, scenePhase == .active, pantallaVisible else { return }
            enfocarLlegada = viewModel.estado == .finalizado
            if !enfocarLlegada {
                AccesibilidadIdioma.anunciar(instruccion + ". " + subtitulo)
            }
        }
        .accessibilityAction(.escape) { onFinish() }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.modoDemo ? L.t("SIMULACIÓN", "SIMULATION") : L.t("TU VIAJE", "YOUR TRIP"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .appTracking(AppTracking.wideLabel)
                Text(L.t("Línea ", "Line ") + "\(ruta.linea) · \(ruta.empresa)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()

            Button {
                viewModel.modoDemo.toggle()
            } label: {
                Label(viewModel.modoDemo ? "Demo ON" : "Demo",
                      systemImage: viewModel.modoDemo ? "stop.fill" : "play.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(viewModel.modoDemo ? Color.onPrimaryFill : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(viewModel.modoDemo ? Color.primaryFill : Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Simular recorrido", "Simulate route"))
            .accessibilityValue(viewModel.modoDemo ? L.t("Activado", "On") : L.t("Desactivado", "Off"))
            .disabled(viewModel.shape.count < 2)

            Button {
                onFinish()
            } label: {
                Text(L.t("Finalizar", "End"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color(hex: "#0a0a0a").opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Panel inferior
    private var panelInferior: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Instrucción principal según estado
            HStack(spacing: 12) {
                Image(systemName: iconoEstado)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colorEstado)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(colorEstado.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(instruccion)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitulo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(instruccion)
            .accessibilityValue(subtitulo)

            if viewModel.estado == .sinPermiso {
                Button(L.t("Abrir Ajustes", "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.appPrimary)
            }

            HStack(spacing: 8) {
                Image(systemName: "flag.fill").foregroundStyle(ruta.colorLinea)
                Text(L.t("Hasta ", "To ") + ruta.paradaFin)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(ruta.costo).fontWeight(.semibold)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))

            // Barra de progreso del recorrido
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(ruta.colorLinea)
                            .frame(width: max(8, geo.size.width * viewModel.progreso))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(L.t("Avance de la línea · tiempos estimados", "Route progress · estimated times"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("\(Int(viewModel.progreso * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ruta.colorLinea)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Avance de la línea, tiempos estimados", "Route progress, estimated times"))
            .accessibilityValue(L.f("{0} por ciento", "{0} percent", ["\(Int(viewModel.progreso * 100))"]))

            // Stats
            HStack(spacing: 0) {
                stat(icono: "clock.fill", valor: viewModel.posicion == nil || ruta.duracionMin <= 0 ? "—" : "~" + L.f("{0} min", "{0} min", ["\(viewModel.minutosRestantes)"]), etiqueta: L.t("Restante", "Remaining"))
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
                stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                     valor: viewModel.distanciaRestanteTexto, etiqueta: L.t("Por recorrer", "To go"))
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
                stat(icono: "mappin.and.ellipse",
                     valor: "\(viewModel.paraderosRestantes)", etiqueta: L.t("Paraderos", "Stops"))
                    .frame(maxWidth: .infinity)
            }

            // Botón seguir/no seguir
            Button {
                seguir.toggle()
            } label: {
                Label(seguir ? L.t("Ver toda la ruta", "Show full route") : L.t("Seguir mi ubicación", "Follow my location"),
                      systemImage: seguir ? "arrow.up.left.and.arrow.down.right" : "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#141414").opacity(0.96))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func stat(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
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
        case .finalizado: return "final"
        }
    }
    private var iconoEstado: String {
        switch viewModel.estado {
        case .sinRecorrido: return "map.fill"
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash.fill"
        case .enRuta:        return "bus.fill"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    private var colorEstado: Color {
        switch viewModel.estado {
        case .sinRecorrido: return .orange
        case .esperandoGPS:  return .white
        case .sinPermiso:    return .red
        case .enRuta:        return ruta.colorLinea
        case .fueraDeRuta:   return .orange
        case .cercaDestino:  return .yellow
        case .finalizado:    return .green
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
        case .finalizado:
            return L.t("Llegaste al final de la línea", "You reached the end of the line")
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
            let nombre = viewModel.paraderoSiguiente?.nombre ?? ruta.paradaFin
            return nombre + (viewModel.distanciaProximoParaderoTexto.map { " · " + $0 } ?? "")
        case .fueraDeRuta:
            guard let paradero = viewModel.paraderoCercano, let metros = viewModel.distanciaParaderoM else {
                return L.t("Busca un paradero de la línea ", "Look for a stop on line ") + ruta.linea
            }
            let distancia = metros >= 1000 ? FormatoNumero.decimal(metros / 1000) + " km" : "\(Int(metros)) m"
            return paradero.nombre + " · " + distancia + L.t(" en línea recta", " straight-line distance")
        case .cercaDestino, .finalizado:
            return ruta.paradaFin
        }
    }

    // MARK: - Alerta de llegada
    private var alertaLlegada: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(L.t("Fin del recorrido", "End of the route"))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(L.t("Llegaste a ", "You arrived at ") + ruta.paradaFin)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .accessibilityFocused($enfocarLlegada)

            Button {
                onFinish()
            } label: {
                Text(L.t("Terminar", "Done"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onPrimaryFill)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.primaryFill))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "#141414"))
                .shadow(color: .black.opacity(0.5), radius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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
