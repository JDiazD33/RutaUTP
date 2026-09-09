//
//  RouteTrackingDemoView.swift
//  RutaUTP
//
//  Vista de PRUEBA aislada del módulo de tracking real.
//  NO está conectada al flujo principal (se abre desde el SideDrawer del
//  Mapa → AppRouter.navigate(to: .trackingDemo)).
//
//  Banco de pruebas del stack de tracking ACTUAL:
//   1. Pide permiso de ubicación y muestra tu posición real en el mapa
//      (marcador con cono de rumbo cuando hay course del GPS).
//   2. Destinos = los mismos chips fijos del Mapa (UTP / Centro / Huanchaco).
//   3. Ruteo con el MISMO pipeline del Mapa: MKDirections transit →
//      automobile → trazo directo de respaldo (avisa "ruta aproximada").
//   4. Navegación estilo apps de navegación: al iniciar el viaje se encuadra
//      toda la ruta; la cámara persigue la posición rotando con el rumbo
//      (3D en ruta, norte arriba en reposo) sin pelear con los gestos.
//   5. Ruta dibujada con casing blanco + tramo recorrido (tenue) y
//      restante (vivo), barra de progreso, ETA + hora de llegada estimada,
//      banner de recálculo en desvíos y alerta de llegada con resumen
//      (duración, distancia, velocidad media, puntos GPS).
//   6. Modo DEMO interactivo: simula el avance por la ruta a 1× / 2× / 4×.
//   7. Vehículos en el mapa vía VehicleTrackingProviding: tap en un bus →
//      popup en vivo (línea, rumbo, velocidad, distancia, frescura) con
//      badge de fuente (DEMO simulado / EN VIVO backend futuro).
//   8. Registra el viaje en un TripSession (puntos GPS) listo para backend.
//   9. Negocios en ruta (fase 1): burbujas de locales promocionados cerca
//      de la posición; tap → card con promo y cupón (JSON local).
//
//  Usa `Map(position:)` con `MapCameraPosition` (iOS 17+).
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
    @State private var rumboCamara: Double?
    @State private var ultimaActualizacionCamara: Date = .distantPast
    /// Chip tocado; nil = el primero del selector (UTP).
    @State private var destinoElegido: RouteTrackingViewModel.DestinoDemo?

    /// Tema elegido en Ajustes. La pantalla de tracking está estilizada en
    /// oscuro (navegación), pero la card de negocio es contenido flotante y
    /// debe seguir el tema del usuario como el resto del app.
    @AppStorage("isDarkMode") private var isDarkMode = false

    // ── Negocios en ruta (fase 1) ──
    /// Burbujas visibles: los 4 negocios más cercanos a la posición actual,
    /// refrescados cada ~120 m para que "vayan apareciendo" en el micro.
    @State private var negociosCerca: [Negocio] = []
    @State private var negocioSeleccionado: Negocio?
    @State private var ultimoRefreshNegocios: CLLocationCoordinate2D?

    // ── Interacción con vehículos ──
    /// ID del bus tocado en el mapa (la card se alimenta del stream en vivo).
    @State private var vehiculoSeleccionadoID: String?

    /// Confirmación antes de cortar un viaje en curso.
    @State private var confirmarDetener: Bool = false

    init(locationService: LocationServiceProtocol = LocationService()) {
        _vm = StateObject(wrappedValue: RouteTrackingViewModel(locationService: locationService))
    }

    /// Destino activo: el chip tocado o el primero por defecto.
    private var destinoActual: RouteTrackingViewModel.DestinoDemo {
        destinoElegido ?? vm.destinos[0]
    }

    /// Datos del vehículo tocado, siempre frescos (el stream actualiza 4 Hz).
    private var vehiculoSeleccionado: VehiclePosition? {
        guard let id = vehiculoSeleccionadoID else { return nil }
        return vm.vehiculos.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a").ignoresSafeArea()

            mapa

            VStack(spacing: 0) {
                topBar
                Spacer()

                // Controles flotantes de cámara (seguir / encuadrar ruta).
                HStack {
                    Spacer()
                    controlesMapa
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                // Card del negocio o del vehículo tocado: directamente sobre
                // el panel inferior, sin taparlo nunca. La de negocio sigue el
                // tema elegido en Ajustes (la pantalla fuerza oscuro; esa no).
                if let negocio = negocioSeleccionado {
                    NegocioDetailCard(
                        negocio: negocio,
                        ubicacion: vm.posicion,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                negocioSeleccionado = nil
                            }
                        }
                    )
                    .environment(\.colorScheme, isDarkMode ? .dark : .light)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let vehiculo = vehiculoSeleccionado {
                    VehiclePopupCard(
                        vehiculo: vehiculo,
                        velocidadMs: vm.velocidadesVehiculos[vehiculo.id],
                        distanciaM: vm.posicion.map {
                            PolylineMatching.distanceMeters($0, vehiculo.coordinate)
                        },
                        enVivo: vm.fuenteVehiculos == .real,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vehiculoSeleccionadoID = nil
                            }
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                panelInferior
            }

            // Resumen de llegada con dim que enfoca la card.
            if vm.estado == .finalizado, let resumen = vm.resumen {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ResumenLlegadaCard(
                        resumen: resumen,
                        destino: vm.destinoSeleccionado?.label ?? L.t("tu destino", "your destination"),
                        onCerrar: { vm.cancelTrip() }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
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
            refrescarNegocios()
            seguirPosicion()
        }
        // Al arrancar el viaje: encuadre de toda la ruta (el usuario decide
        // cuándo pasar a seguimiento con el botón flotante).
        .onChange(of: vm.tripInProgress) { _, activo in
            if activo { encuadrarRuta() }
        }
        // Activar el demo implica querer VER el avance: seguimiento automático.
        .onChange(of: vm.modoDemo) { _, activo in
            if activo {
                seguir = true
                if let pos = vm.posicion { moverCamara(a: pos) }
            }
        }
        // Feedback háptico en los cambios de estado clave.
        .onChange(of: vm.estado) { _, nuevo in
            switch nuevo {
            case .fueraDeRuta:  AppHaptics.warning()
            case .cercaDestino: AppHaptics.impact(.medium)
            case .finalizado:   AppHaptics.success()
            default: break
            }
        }
        .confirmationDialog(L.t("¿Finalizar el viaje?", "End the trip?"),
                            isPresented: $confirmarDetener,
                            titleVisibility: .visible) {
            Button(L.t("Sí, finalizar", "Yes, end it"), role: .destructive) {
                vm.cancelTrip()
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Mapa (iOS 17+)

    private var mapa: some View {
        Map(position: $cameraPosition) {
            // Destinos del demo = chips fijos del Mapa.
            ForEach(vm.destinos) { destino in
                Annotation(destino.label, coordinate: destino.coordinate) {
                    if destino.label == "UTP" {
                        MarcadorUTP()
                    } else {
                        MarcadorDestinoBuscado(titulo: destino.label)
                    }
                }
            }

            // Posición actual (GPS real o simulada por el modo demo) con
            // cono de rumbo estilo navegación.
            if let pos = vm.posicion {
                Annotation(L.t("Mi posición", "My position"), coordinate: pos) {
                    UserNavMarker(heading: vm.rumbo)
                }
            }

            // Ruta dividida por el avance: casing blanco + tramo restante
            // vivo y tramo recorrido tenue (estilo apps de navegación).
            if let restante = vm.rutaRestante {
                MapPolyline(restante)
                    .stroke(.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(restante)
                    .stroke(Color.primaryContainer,
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
            }
            if let recorrida = vm.rutaRecorrida {
                MapPolyline(recorrida)
                    .stroke(Color.primaryContainer.opacity(0.35),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            // Vehículos en tiempo real vía provider: tap → popup en vivo.
            ForEach(vm.vehiculos.prefix(8)) { vehiculo in
                Annotation(L.t("Línea", "Line") + " \(vehiculo.linea)", coordinate: vehiculo.coordinate) {
                    AnimatedBusMarker(
                        linea: vehiculo.linea,
                        color: colorDeLinea(vehiculo.linea),
                        heading: vehiculo.heading
                    )
                    .scaleEffect(vehiculoSeleccionadoID == vehiculo.id ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7),
                               value: vehiculoSeleccionadoID)
                    .onTapGesture {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            // Toggle: segundo tap sobre el mismo bus cierra.
                            vehiculoSeleccionadoID = (vehiculoSeleccionadoID == vehiculo.id)
                                ? nil : vehiculo.id
                            negocioSeleccionado = nil
                        }
                    }
                }
            }

            // Negocios en ruta: burbujas de locales promocionados cerca de
            // la posición. Tap → card con promo y cupón.
            ForEach(negociosCerca) { negocio in
                Annotation(negocio.nombre, coordinate: negocio.coordinate) {
                    NegocioBubbleMarker(
                        negocio: negocio,
                        seleccionado: negocioSeleccionado?.id == negocio.id
                    )
                    .onTapGesture {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            negocioSeleccionado = negocio
                            vehiculoSeleccionadoID = nil
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .ignoresSafeArea()
        // SIN .onTapGesture aquí: un gesto de tap sobre el Map entero compite
        // con los taps de las Annotations y las burbujas dejaban de responder.
        // Las cards se cierran con su botón X o tocando otra burbuja.
    }

    // MARK: - Cámara: seguimiento suave con rumbo

    /// Persigue la posición sin pelear con el usuario: solo recentra si se
    /// alejó ≥ 18 m del centro o giró ≥ 30°, con un mínimo de 0.35 s entre
    /// movimientos para no apilar animaciones en el modo demo.
    private func seguirPosicion() {
        guard seguir, let nueva = vm.posicion else { return }

        let movido = ultimoCentroCamara.map { PolylineMatching.distanceMeters($0, nueva) }
            ?? .greatestFiniteMagnitude
        let giro: Double = {
            guard let rumboCamara, vm.rumbo >= 0 else { return 0 }
            let delta = abs(rumboCamara - vm.rumbo).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta)
        }()
        guard movido >= 18 || giro >= 30 else { return }
        guard Date().timeIntervalSince(ultimaActualizacionCamara) >= 0.35 else { return }

        moverCamara(a: nueva)
    }

    /// Recentra la cámara. En viaje: vista 3D (pitch 55) rotando con el
    /// rumbo; en reposo: norte arriba, plano y más abierto.
    private func moverCamara(a coord: CLLocationCoordinate2D) {
        ultimoCentroCamara = coord
        let enViaje = vm.tripInProgress
        let heading = (enViaje && vm.rumbo >= 0) ? vm.rumbo : 0
        rumboCamara = heading
        ultimaActualizacionCamara = Date()
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coord,
                          distance: enViaje ? 550 : 1100,
                          heading: heading,
                          pitch: enViaje ? 55 : 0)
            )
        }
    }

    /// Encuadra toda la ruta calculada (vista general antes de arrancar el
    /// seguimiento). Desactiva `seguir` para no saltar de inmediato a la
    /// cámara de persecución: el botón late invitando al tap.
    private func encuadrarRuta() {
        guard let polyline = vm.routePolyline else { return }
        seguir = false
        var rect = polyline.boundingMapRect
        let margen = max(rect.width, rect.height) * 0.22
        rect = MKMapRect(x: rect.minX - margen, y: rect.minY - margen,
                         width: rect.width + margen * 2, height: rect.height + margen * 2)
        withAnimation(.easeInOut(duration: 0.7)) {
            cameraPosition = .region(MKCoordinateRegion(rect))
        }
    }

    // MARK: - Controles flotantes del mapa

    private var controlesMapa: some View {
        VStack(spacing: 10) {
            if vm.tripInProgress, vm.routePolyline != nil {
                BotonFlotanteMapa(
                    icono: "arrow.up.left.and.down.right.magnifyingglass",
                    etiqueta: L.t("Ver toda la ruta", "See the full route")
                ) {
                    encuadrarRuta()
                }
            }

            BotonFlotanteMapa(
                icono: seguir ? "location.fill" : "location",
                etiqueta: seguir ? L.t("Siguiendo tu ubicación", "Following your location")
                                 : L.t("Centrar en mi ubicación", "Center on my location"),
                destacado: seguir,
                pulsante: vm.tripInProgress && !seguir
            ) {
                seguir = true
                if let pos = vm.posicion { moverCamara(a: pos) }
            }
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
            .accessibilityLabel(L.t("Cerrar demo", "Close demo"))

            VStack(alignment: .leading, spacing: 2) {
                Text("TRACKING DEMO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .appTracking(AppTracking.wideLabel)
                Text(L.t("Módulo de tracking real", "Real tracking module"))
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
        return Text(enVivo ? L.t("EN VIVO", "LIVE") : "DEMO")
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
            case .notDetermined:                          return (L.t("SIN GPS", "NO GPS"), .gray)
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

    // MARK: - Panel inferior

    private var panelInferior: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .foregroundStyle(.onErrorContainer)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.errorContainer))
            }

            // Banner de recálculo (desvío sostenido detectado).
            if vm.recalculando {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.orange)
                        .controlSize(.small)
                    Text(L.t("Recalculando ruta…", "Recalculating route…"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if vm.tripInProgress {
                // Aviso cuando la ruta es el trazo directo de respaldo.
                if vm.rutaAproximada {
                    Label(L.t("Ruta aproximada · sin datos de MapKit",
                              "Approximate route · no MapKit data"),
                          systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.9))
                }

                barraProgreso
                statsRow
                controlesViaje
            } else {
                selectorDestino
            }

            if vm.estado == .sinPermiso {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(L.t("Abrir Ajustes", "Open Settings"), systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: "#8affc1")))
                }
                .buttonStyle(.plain)
            }
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
            .animation(.linear(duration: 0.3), value: vm.progreso)

            HStack {
                Text(L.t("Avance del recorrido", "Trip progress"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(Int(vm.progreso * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primaryContainer)
                    .monospacedDigit()
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(icono: "clock.badge.checkmark",
                 valor: horaLlegadaTexto,
                 etiqueta: L.t("Llegada", "Arrival"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "clock.fill",
                 valor: "\(vm.minutosRestantes) min",
                 etiqueta: L.t("Restante", "Remaining"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                 valor: vm.distanciaRestanteTexto,
                 etiqueta: L.t("Por recorrer", "To go"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "record.circle",
                 valor: "\(vm.sesion?.puntosRecorridos.count ?? 0)",
                 etiqueta: L.t("Puntos GPS", "GPS points"))
                .frame(maxWidth: .infinity)
        }
    }

    /// Hora de llegada estimada al ritmo de la ruta calculada.
    private var horaLlegadaTexto: String {
        guard let eta = vm.etaTotalSeg else { return "—" }
        let fecha = Date().addingTimeInterval(eta * (1 - vm.progreso))
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        return formato.string(from: fecha)
    }

    private func stat(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
    }

    // MARK: - Selección de destino (chips = chips fijos del Mapa)

    private var selectorDestino: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("DESTINO", "DESTINATION"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)

            HStack(spacing: 8) {
                ForEach(vm.destinos) { destino in
                    let seleccionado = destino.id == destinoActual.id
                    Button {
                        AppHaptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            destinoElegido = destino
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destino.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(destino.label)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
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
                Task { await vm.iniciar(destino: destinoActual) }
            } label: {
                HStack(spacing: 8) {
                    if vm.calculandoRuta {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                        Text(L.t("Calculando ruta…", "Calculating route…"))
                            .font(.system(size: 15, weight: .heavy))
                    } else {
                        Image(systemName: "play.fill")
                        Text(L.t("Iniciar viaje a \(destinoActual.label)",
                                 "Start trip to \(destinoActual.label)"))
                            .font(.system(size: 15, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vm.posicion == nil ? Color.white.opacity(0.25) : Color.primaryContainer))
            }
            .buttonStyle(.plain)
            .disabled(vm.posicion == nil || vm.calculandoRuta)
            .accessibilityHint(L.t("Calcula la ruta real y activa el tracking",
                                   "Calculates the real route and starts tracking"))
        }
    }

    // MARK: - Controles del viaje (demo / velocidad / detener)

    private var controlesViaje: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Modo demo: simula el avance por la ruta (prueba en simulador).
                Button {
                    AppHaptics.impact(.light)
                    vm.modoDemo.toggle()
                } label: {
                    Label(vm.modoDemo ? L.t("Pausar demo", "Pause demo")
                                      : L.t("Simular avance", "Simulate progress"),
                          systemImage: vm.modoDemo ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(vm.modoDemo ? .black : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(vm.modoDemo ? Color(hex: "#8affc1")
                                                               : Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Simular avance por la ruta", "Simulate progress along the route"))

                Button {
                    confirmarDetener = true
                } label: {
                    Label(L.t("Detener", "Stop"), systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.appError.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }

            // Velocidad de la simulación (visible solo con el demo corriendo).
            if vm.modoDemo {
                HStack(spacing: 0) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { factor in
                        let activo = vm.velocidadDemo == factor
                        Button {
                            AppHaptics.selection()
                            vm.velocidadDemo = factor
                        } label: {
                            Text("\(Int(factor))×")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(activo ? .black : .white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(activo ? Color(hex: "#8affc1") : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .accessibilityLabel(L.t("Velocidad de la simulación", "Simulation speed"))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            return L.t("Buscando señal GPS…", "Looking for GPS signal…")
        case .sinPermiso:
            return L.t("Activa la ubicación para navegar", "Enable location to navigate")
        case .listo:
            return L.t("GPS listo · elige un destino", "GPS ready · pick a destination")
        case .enRuta:
            return L.t("Tracking activo", "Tracking active")
        case .fueraDeRuta(let metros):
            return L.t("Te alejaste de la ruta (\(Int(metros)) m)",
                       "You went off route (\(Int(metros)) m)")
        case .cercaDestino:
            return L.t("Prepárate para llegar", "Get ready to arrive")
        case .finalizado:
            return L.t("¡Llegaste a tu destino!", "You arrived at your destination!")
        }
    }

    private var subtitulo: String {
        switch vm.estado {
        case .esperandoGPS:
            return L.t("Esperando el primer fix del GPS", "Waiting for the first GPS fix")
        case .sinPermiso:
            return L.t("Ajustes → Privacidad → Ubicación", "Settings → Privacy → Location")
        case .listo:
            return L.t("Inicia el viaje para probar el tracking", "Start the trip to test tracking")
        case .enRuta:
            return L.t("Hacia \(vm.destinoSeleccionado?.label ?? "…")",
                       "To \(vm.destinoSeleccionado?.label ?? "…")")
        case .fueraDeRuta:
            return L.t("Recalculando automáticamente", "Recalculating automatically")
        case .cercaDestino:
            return L.t("Llegando a \(vm.destinoSeleccionado?.label ?? "…")",
                       "Arriving at \(vm.destinoSeleccionado?.label ?? "…")")
        case .finalizado:
            return vm.destinoSeleccionado?.label ?? L.t("Destino", "Destination")
        }
    }

    // MARK: Helpers

    // MARK: Negocios en ruta

    /// Recarga las burbujas cada 120 m de avance (o la primera vez). En un
    /// micro a 30 km/h es ~1 refresh cada 14 s: las burbujas van apareciendo
    /// durante el viaje sin parpadear.
    private func refrescarNegocios() {
        guard let pos = vm.posicion else { return }
        if let ultimo = ultimoRefreshNegocios,
           NegociosService.distanciaMetros(ultimo, pos) < 120 { return }
        ultimoRefreshNegocios = pos
        negociosCerca = NegociosService.shared.cerca(de: pos, radioMetros: 900, limite: 4)
        // El negocio abierto se mantiene aunque salga del top cercano: el
        // usuario ya mostró interés; se cierra solo con el botón.
    }

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
