//
//  TrackingDemoComponents.swift
//  RutaUTP
//
//  Componentes visuales exclusivos del Tracking Demo:
//   - UserNavMarker: marcador de usuario con cono de rumbo (estilo apps
//     de navegación) + halo pulsante.
//   - BotonFlotanteMapa: botón circular flotante (seguir / encuadrar ruta)
//     con anillo pulsante para invitar al tap.
//   - VehiclePopupCard: popup en vivo del vehículo tocado (línea, rumbo,
//     velocidad estimada, distancia y frescura de la señal).
//   - ResumenLlegadaCard: alerta de llegada con métricas del viaje
//     (duración, distancia, velocidad media y puntos GPS).
//

import SwiftUI
import CoreLocation

// MARK: - Marcador de usuario con rumbo

/// Punto de usuario estilo navegación: halo pulsante + cono semitransparente
/// que apunta al rumbo actual (GPS course o simulado por el modo demo).
struct UserNavMarker: View {
    /// Rumbo en grados; -1 = desconocido (sin cono).
    let heading: Double

    var body: some View {
        DecorativeAnimationScope { animar in
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: animar ? 38 : 26, height: animar ? 38 : 26)
                    .animation(animar ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil,
                               value: animar)

                if heading >= 0 {
                    ConoDireccion()
                        .fill(Color.secondary.opacity(0.40))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(heading))
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(Color.secondary)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 3)
            }
        }
    }
}

/// Abanico de ~75° apuntando hacia arriba; se rota con `.rotationEffect`
/// para orientarlo al rumbo (0° = norte).
struct ConoDireccion: Shape {
    func path(in rect: CGRect) -> Path {
        let centro = CGPoint(x: rect.midX, y: rect.midY)
        let radio = min(rect.width, rect.height) / 2
        let apertura: CGFloat = .pi * 75 / 180
        var path = Path()
        path.move(to: centro)
        path.addArc(center: centro, radius: radio,
                    startAngle: .radians(-Double.pi / 2 - Double(apertura) / 2),
                    endAngle: .radians(-Double.pi / 2 + Double(apertura) / 2),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Botón flotante del mapa

/// Botón circular oscuro para los controles de cámara (seguir ubicación,
/// encuadrar ruta). `pulsante` enciende un anillo que late para invitar
/// al tap (ej. seguimiento desactivado con viaje en curso).
struct BotonFlotanteMapa: View {
    let icono: String
    let etiqueta: String
    var destacado: Bool = false
    var pulsante: Bool = false
    let action: () -> Void


    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            ZStack {
                if pulsante {
                    DecorativeAnimationScope { animar in
                        Circle()
                            .stroke(Color.appPrimary.opacity(0.7), lineWidth: 2)
                            .frame(width: 52, height: 52)
                            .scaleEffect(animar ? 1.3 : 0.9)
                            .opacity(animar ? 0 : 1)
                            .animation(animar ? .easeInOut(duration: 1.3).repeatForever(autoreverses: false) : nil,
                                       value: animar)
                    }
                }

                Image(systemName: icono)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(destacado ? Color.onPrimaryFill : Color.onSurface)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(destacado ? Color.primaryFill
                                                        : Color.surfaceContainerLowest.opacity(0.92)))
                    .overlay(Circle().stroke(Color.onSurface.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
    }
}

// MARK: - Popup de vehículo (tap en un bus del mapa)

/// Ficha en vivo del vehículo seleccionado. Se alimenta del stream del
/// provider (4 Hz), así que velocidad y distancia se actualizan solas
/// mientras el bus se mueve.
struct VehiclePopupCard: View {
    let vehiculo: VehiclePosition
    /// Velocidad estimada en m/s (nil = aún sin muestras suficientes).
    let velocidadMs: Double?
    /// Distancia desde la posición del usuario (nil = sin GPS).
    let distanciaM: Double?
    let enVivo: Bool
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            if textSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        iconoLinea
                        Spacer()
                        botonCerrar
                    }
                    datosVehiculo
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    iconoLinea
                    datosVehiculo
                    botonCerrar
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest.opacity(0.96))
                .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.onSurface.opacity(0.1), lineWidth: 1)
        )
    }

    private var iconoLinea: some View {
        VStack(spacing: 4) {
            Image(systemName: "bus.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.onPrimaryFill)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.primaryContainer))
                .accessibilityHidden(true)
            Text("L-\(vehiculo.linea)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Línea ", "Line ") + vehiculo.linea)
    }

    private var datosVehiculo: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { tituloYEstado }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { tituloYEstado }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { metricas }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { metricas }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.onSurface.opacity(0.7))

            (Text(L.t("Actualizado ", "Updated "))
                .foregroundStyle(Color.onSurface.opacity(0.45))
             + Text(Date(timeIntervalSince1970: vehiculo.timestamp), style: .relative)
                .bold()
                .foregroundStyle(Color.onSurface.opacity(0.7)))
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tituloYEstado: some View {
        Text(L.f("Unidad {0}", "Unit {0}", ["\(vehiculo.id)"]))
            .font(.subheadline.bold())
            .foregroundStyle(Color.onSurface)
            .fixedSize(horizontal: false, vertical: true)
        Text(enVivo ? L.t("EN VIVO", "LIVE") : L.t("DEMO", "DEMO"))
            .font(.caption2.bold())
            .foregroundStyle(enVivo ? .black : Color.onSurface)
            .appTracking(AppTracking.wideLabel)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(enVivo ? Color(hex: "#8affc1")
                                               : Color.onSurface.opacity(0.14)))
    }

    @ViewBuilder private var metricas: some View {
        if vehiculo.heading >= 0 {
            Label(cardinal(vehiculo.heading), systemImage: "location.north.fill")
                .fixedSize(horizontal: false, vertical: true)
        }
        if let v = velocidadKmh {
            Label("\(v) km/h", systemImage: "speedometer")
                .fixedSize(horizontal: false, vertical: true)
        }
        if let d = distanciaM {
            Label(L.f("a {0} de ti", "{0} away", ["\(Self.formatoDistancia(d))"]), systemImage: "figure.walk")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var botonCerrar: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.onSurface.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Cerrar", "Close"))
    }

    private var velocidadKmh: Int? {
        guard let ms = velocidadMs, ms >= 0 else { return nil }
        return Int((ms * 3.6).rounded())
    }

    /// Rumbo en grados → punto cardinal (N, NE, E, …).
    private func cardinal(_ grados: Double) -> String {
        let direcciones = [L.t("N", "N"), L.t("NE", "NE"), L.t("E", "E"), L.t("SE", "SE"),
                           L.t("S", "S"), L.t("SO", "SW"), L.t("O", "W"), L.t("NO", "NW")]
        let normalizado = (grados.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45
        return direcciones[Int(normalizado) % direcciones.count]
    }

    static func formatoDistancia(_ metros: Double) -> String {
        metros >= 1000
            ? FormatoNumero.decimal(metros / 1000) + " km"
            : "\(Int(metros)) m"
    }
}

// MARK: - Resumen de llegada

/// Alerta de fin de viaje con las métricas de la sesión: duración,
/// distancia recorrida, velocidad media y puntos GPS registrados.
struct ResumenLlegadaCard: View {
    @Environment(\.dynamicTypeSize) private var textSize

    private var apilarContenido: Bool { textSize >= .xxxLarge }
    let resumen: RouteTrackingViewModel.ResumenViaje
    let destino: String
    let onCerrar: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color(light: "#087C55", dark: "#8affc1"))

            VStack(spacing: 4) {
                Text(L.t("¡Llegaste a tu destino!", "You arrived!"))
                    .font(.title3.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.onSurface)
                Text(destino)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.appPrimary)
            }

            (apilarContenido ? AnyLayout(VStackLayout(spacing: 8))
                              : AnyLayout(HStackLayout(spacing: 8))) {
                celda("clock.fill", formatoDuracion(resumen.duracionS),
                      L.t("Duración", "Duration"))
                celda("point.topleft.down.curvedto.point.bottomright.up",
                      VehiclePopupCard.formatoDistancia(resumen.distanciaM),
                      L.t("Recorrido", "Distance"))
            }
            (apilarContenido ? AnyLayout(VStackLayout(spacing: 8))
                              : AnyLayout(HStackLayout(spacing: 8))) {
                celda("speedometer", "\(Int(resumen.velocidadKmh)) km/h",
                      L.t("Vel. media", "Avg. speed"))
                celda("record.circle", "\(resumen.puntos)",
                      L.t("Puntos GPS", "GPS points"))
            }

            Button(action: onCerrar) {
                Text(L.t("Terminar", "Done"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.onPrimaryFill)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.primaryFill))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .shadow(color: .black.opacity(0.5), radius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.onSurface.opacity(0.1), lineWidth: 1)
        )
    }

    private func celda(_ icono: String, _ valor: String, _ etiqueta: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.onSurface.opacity(0.5))
            Text(valor)
                .font(.headline.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.onSurface)
            Text(etiqueta.uppercased())
                .font(.caption2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.onSurface.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta)
        .accessibilityValue(valor)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.onSurface.opacity(0.06)))
    }

    /// "12:45" o "1h 05m".
    private func formatoDuracion(_ segundos: TimeInterval) -> String {
        let total = Int(segundos)
        if total >= 3600 {
            return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Marcador + botones") {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VStack(spacing: 28) {
            UserNavMarker(heading: 45)
            HStack(spacing: 16) {
                BotonFlotanteMapa(icono: "location.fill", etiqueta: "Seguir", destacado: true) {}
                BotonFlotanteMapa(icono: "arrow.up.left.and.down.right.magnifyingglass",
                                  etiqueta: "Ruta", pulsante: true) {}
            }
        }
    }
}

#Preview("Popup vehículo") {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VehiclePopupCard(
            vehiculo: VehiclePosition(id: "SIM-3", linea: "B",
                                      lat: -8.11, lon: -79.03, heading: 130, speed: -1),
            velocidadMs: 8.4,
            distanciaM: 340,
            enVivo: false,
            onClose: {}
        )
        .padding(16)
    }
}

#Preview("Resumen llegada") {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        ResumenLlegadaCard(
            resumen: .init(duracionS: 1140, distanciaM: 3200, puntos: 87, velocidadKmh: 10.1),
            destino: "UTP",
            onCerrar: {}
        )
    }
}


struct TransitStopMarker: View {
    let number: String
    let title: String
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "bus.fill")
                Text(number.isEmpty ? title : number + " · " + title)
            }
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Capsule().fill(color))
            .overlay(Capsule().stroke(Color.appSurface, lineWidth: 2))
            Rectangle().fill(color).frame(width: 3, height: 10)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number.isEmpty ? title : number + ", " + title)
    }
}
