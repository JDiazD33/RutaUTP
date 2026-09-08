//
//  RouteTrackingDemoView.swift
//  RutaUTP
//
//  Vista de PRUEBA aislada del módulo de tracking real.
//  NO está conectada al flujo principal (se abre desde el SideDrawer del
//  Mapa → AppRouter.navigate(to: .trackingDemo)).
//
//  Banco de pruebas del stack de tracking ACTUAL:
//   1. Pide permiso de ubicación y muestra tu posición real en el mapa.
//   2. Destinos = los mismos chips fijos del Mapa (UTP / Centro / Huanchaco).
//   3. Ruteo con el MISMO pipeline del Mapa: MKDirections transit →
//      automobile → trazo directo de respaldo.
//   4. Navegación estilo NavegacionRutaView (tema oscuro): estado,
//      barra de progreso, ETA/distancia restante, detección de desvío con
//      recálculo y alerta de llegada.
//   5. Modo DEMO: simula el avance a lo largo de la ruta calculada para
//      probar todo en el simulador sin caminar.
//   6. Vehículos en el mapa vía VehicleTrackingProviding con badge de
//      fuente (DEMO simulado / EN VIVO backend futuro).
//   7. Registra el viaje en un TripSession (puntos GPS) listo para backend.
//
//  Usa `Map(position:)` con `MapCameraPosition` (iOS 17+), igual que el
//  resto del módulo.
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct RouteTrackingDemoView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm: RouteTrackingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var seguir: Bool = true
    @State private var ultimoCentroCamara: CLLocationCoordinate2D?
    @State private var destinoElegido: RouteTrackingViewModel.DestinoDemo

    init(locationService: LocationServiceProtocol = LocationService()) {
        _vm = StateObject(wrappedValue: RouteTrackingViewModel(locationService: locationService))
        _destinoElegido = State(initialValue: RouteTrackingViewModel.destinos[0])
    }

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a").ignoresSafeArea()

            mapa

            VStack(spacing: 0) {
                topBar
                Spacer()
                panelInferior
            }

            if vm.estado == .finalizado {
                alertaLlegada
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.requestPermissionAndStart()
        }
        .onDisappear {
            vm.stop()
        }
        .onChange(of: vm.posicionTick) { _, _ in
            guard seguir, let nueva = vm.posicion else { return }
            // Recentrar solo si se alejó del último centro (evita pelear
            // con el gesto del usuario cada tick del modo demo).
            if let ultimo = ultimoCentroCamara,
               PolylineMatching.distanceMeters(ultimo, nueva) < 5 { return }
            moverCamara(a: nueva)
        }
    }

    // MARK: - Mapa (iOS 17+, mismo estilo del módulo)

    private var mapa: some View {
        Map(position: $cameraPosition) {
            // Destinos del demo = chips fijos del Mapa.
            ForEach(RouteTrackingViewModel.destinos) { destino in
                Annotation(destino.label, coordinate: destino.coordinate) {
                    if destino.label == "UTP" {
                        MarcadorUTP()
                    } else {
                        MarcadorDestinoBuscado(titulo: destino.label)
                    }
                }
            }

            // Posición actual (GPS real o simulada por el modo demo).
            if let pos = vm.posicion {
                Annotation("Mi posición", coordinate: pos) {
                    PulsingUserMarker()
                }
            }

            // Ruta calculada (pipeline real del Mapa).
            if let polyline = vm.routePolyline {
                MapPolyline(polyline)
                    .stroke(Color.primaryContainer,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            // Vehículos en tiempo real vía provider (badge DEMO/EN VIVO arriba).
            ForEach(vm.vehiculos.prefix(8)) { vehiculo in
                Annotation("Línea \(vehiculo.linea)", coordinate: vehiculo.coordinate) {
                    AnimatedBusMarker(
                        linea: vehiculo.linea,
                        color: colorDeLinea(vehiculo.linea),
                        heading: vehiculo.heading
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
    }

    private func moverCamara(a coord: CLLocationCoordinate2D) {
        ultimoCentroCamara = coord
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coord, distance: 700, heading: 0, pitch: 45)
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                vm.stop()
                router.navigate(to: .mapaPrincipal)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar demo")

            VStack(alignment: .leading, spacing: 2) {
                Text("TRACKING DEMO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .appTracking(AppTracking.wideLabel)
                Text("Módulo de tracking real")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            badgeFuente
            badgePermiso
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color(hex: "#0a0a0a").opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    /// Fuente de los vehículos del mapa (VehicleTrackingProviding.source).
    private var badgeFuente: some View {
        let enVivo = vm.fuenteVehiculos == .real
        return Text(enVivo ? "EN VIVO" : "DEMO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(enVivo ? .black : .white)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(enVivo ? Color(hex: "#8affc1") : Color.white.opacity(0.14)))
    }

    private var badgePermiso: some View {
        let status = vm.authStatus
        let (text, color): (String, Color) = {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: return ("GPS ON", Color(hex: "#8affc1"))
            case .denied, .restricted:                    return ("GPS OFF", .appError)
            case .notDetermined:                          return ("SIN GPS", .gray)
            @unknown default:                             return ("GPS", .gray)
            }
        }()
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(status.isAuthorized ? .black : .white)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
    }

    // MARK: - Panel inferior (mismo estilo de NavegacionRutaView)

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
                        .lineLimit(1)
                }
                Spacer()
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#ffd7d3"))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#5c2224")))
            }

            if vm.tripInProgress {
                barraProgreso
                statsRow
            } else {
                selectorDestino
            }

            controles
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

    // MARK: - Progreso + stats del viaje

    private var barraProgreso: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.primaryContainer)
                        .frame(width: max(8, geo.size.width * vm.progreso))
                }
            }
            .frame(height: 6)

            HStack {
                Text("Avance del recorrido")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(Int(vm.progreso * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primaryContainer)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(icono: "clock.fill", valor: "\(vm.minutosRestantes) min", etiqueta: "Restante")
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                 valor: vm.distanciaRestanteTexto, etiqueta: "Por recorrer")
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "record.circle",
                 valor: "\(vm.sesion?.puntosRecorridos.count ?? 0)", etiqueta: "Puntos GPS")
                .frame(maxWidth: .infinity)
        }
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
    }

    // MARK: - Selección de destino (chips = chips fijos del Mapa)

    private var selectorDestino: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINO")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)

            HStack(spacing: 8) {
                ForEach(RouteTrackingViewModel.destinos) { destino in
                    let seleccionado = destino.id == destinoElegido.id
                    Button {
                        destinoElegido = destino
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destino.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(destino.label)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(seleccionado ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(seleccionado ? Color(hex: "#8affc1")
                                                                : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await vm.iniciar(destino: destinoElegido) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Iniciar viaje a \(destinoElegido.label)")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vm.posicion == nil ? Color.white.opacity(0.25) : Color.primaryContainer))
            }
            .buttonStyle(.plain)
            .disabled(vm.posicion == nil)
            .accessibilityHint("Calcula la ruta real y activa el tracking")
        }
    }

    // MARK: - Controles (demo / detener / seguir / ajustes)

    private var controles: some View {
        VStack(spacing: 10) {
            if vm.tripInProgress {
                HStack(spacing: 10) {
                    // Modo demo: simula el avance por la ruta (prueba en simulador).
                    Button {
                        vm.modoDemo.toggle()
                    } label: {
                        Label(vm.modoDemo ? "Demo ON" : "Demo",
                              systemImage: vm.modoDemo ? "stop.fill" : "play.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(vm.modoDemo ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(vm.modoDemo ? Color(hex: "#8affc1")
                                                                   : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Simular avance por la ruta")

                    Button {
                        vm.cancelTrip()
                    } label: {
                        Label("Detener", systemImage: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if vm.estado == .sinPermiso {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Abrir Ajustes", systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: "#8affc1")))
                }
                .buttonStyle(.plain)
            }

            Button {
                seguir.toggle()
                if seguir, let pos = vm.posicion {
                    moverCamara(a: pos)
                }
            } label: {
                Label(seguir ? "Siguiendo tu ubicación" : "Centrar en mi ubicación",
                      systemImage: seguir ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Estado → UI

    private var iconoEstado: String {
        switch vm.estado {
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash.fill"
        case .listo:         return "location.fill"
        case .enRuta:        return "bus.fill"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    private var colorEstado: Color {
        switch vm.estado {
        case .esperandoGPS:  return .white
        case .sinPermiso:    return .red
        case .listo:         return Color(hex: "#8affc1")
        case .enRuta:        return Color.primaryContainer
        case .fueraDeRuta:   return .orange
        case .cercaDestino:  return .yellow
        case .finalizado:    return Color(hex: "#8affc1")
        }
    }

    private var instruccion: String {
        switch vm.estado {
        case .esperandoGPS:
            return "Buscando señal GPS…"
        case .sinPermiso:
            return "Activa la ubicación para navegar"
        case .listo:
            return "GPS listo · elige un destino"
        case .enRuta:
            return "Tracking activo"
        case .fueraDeRuta(let metros):
            return "Te alejaste de la ruta (\(Int(metros)) m)"
        case .cercaDestino:
            return "Prepárate para llegar"
        case .finalizado:
            return "¡Llegaste a tu destino!"
        }
    }

    private var subtitulo: String {
        switch vm.estado {
        case .esperandoGPS:  return "Esperando el primer fix del GPS"
        case .sinPermiso:    return "Ajustes → Privacidad → Ubicación"
        case .listo:         return "Inicia el viaje para probar el tracking"
        case .enRuta:        return "Hacia \(vm.destinoSeleccionado?.label ?? "…")"
        case .fueraDeRuta:   return "Recalculando automáticamente"
        case .cercaDestino:  return "Llegando a \(vm.destinoSeleccionado?.label ?? "…")"
        case .finalizado:    return vm.destinoSeleccionado?.label ?? "Destino"
        }
    }

    // MARK: - Alerta de llegada (igual a NavegacionRutaView)

    private var alertaLlegada: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "#8affc1"))
            Text("Fin del recorrido")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
            Text("Llegaste a \(vm.destinoSeleccionado?.label ?? "tu destino")")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                vm.cancelTrip()
            } label: {
                Text("Terminar")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color(hex: "#8affc1")))
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

    // MARK: - Helpers

    /// Color estable por línea para los vehículos del provider.
    private func colorDeLinea(_ linea: String) -> Color {
        let paleta: [Color] = [.primaryContainer, .secondary, .tertiaryContainer,
                               .secondaryContainer, .tertiary, .appError]
        let suma = linea.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paleta[suma % paleta.count]
    }
}

#Preview {
    RouteTrackingDemoView()
        .environmentObject(AppRouter())
}
