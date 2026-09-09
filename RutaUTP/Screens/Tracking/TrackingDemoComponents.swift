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
    @State private var pulsando = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#8affc1").opacity(0.28))
                .frame(width: pulsando ? 38 : 26, height: pulsando ? 38 : 26)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: pulsando)

            if heading >= 0 {
                ConoDireccion()
                    .fill(Color(hex: "#8affc1").opacity(0.40))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(heading))
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(Color(hex: "#8affc1"))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.35), radius: 3)
        }
        .onAppear { pulsando = true }
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

    @State private var latiendo = false

    var body: some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            ZStack {
                if pulsante {
                    Circle()
                        .stroke(Color(hex: "#8affc1").opacity(0.7), lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .scaleEffect(latiendo ? 1.3 : 0.9)
                        .opacity(latiendo ? 0 : 1)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false),
                                   value: latiendo)
                }

                Image(systemName: icono)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(destacado ? Color(hex: "#0a0a0a") : .white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(destacado ? Color(hex: "#8affc1")
                                                        : Color(hex: "#141414").opacity(0.92)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
        .onAppear {
            if pulsante { latiendo = true }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryContainer)
                    .frame(width: 42, height: 42)
                Image(systemName: "bus.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .top) {
                Text("L-\(vehiculo.linea)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primaryContainer))
                    .offset(y: -10)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L.t("Unidad \(vehiculo.id)", "Unit \(vehiculo.id)"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(enVivo ? L.t("EN VIVO", "LIVE") : "DEMO")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(enVivo ? .black : .white)
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(enVivo ? Color(hex: "#8affc1")
                                                           : Color.white.opacity(0.14)))
                }

                HStack(spacing: 10) {
                    if vehiculo.heading >= 0 {
                        Label(cardinal(vehiculo.heading), systemImage: "location.north.fill")
                    }
                    if let v = velocidadKmh {
                        Label("\(v) km/h", systemImage: "speedometer")
                    }
                    if let d = distanciaM {
                        Label(L.t("a \(Self.formatoDistancia(d)) de ti",
                                  "\(Self.formatoDistancia(d)) away"), systemImage: "figure.walk")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

                (Text(L.t("Actualizado ", "Updated "))
                    .foregroundStyle(.white.opacity(0.45))
                 + Text(Date(timeIntervalSince1970: vehiculo.timestamp), style: .relative)
                    .bold()
                    .foregroundStyle(.white.opacity(0.7)))
                    .font(.system(size: 10))
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#141414").opacity(0.96))
                .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var velocidadKmh: Int? {
        guard let ms = velocidadMs, ms >= 0 else { return nil }
        return Int((ms * 3.6).rounded())
    }

    /// Rumbo en grados → punto cardinal (N, NE, E, …).
    private func cardinal(_ grados: Double) -> String {
        let direcciones = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let normalizado = (grados.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45
        return direcciones[Int(normalizado) % direcciones.count]
    }

    static func formatoDistancia(_ metros: Double) -> String {
        metros >= 1000
            ? String(format: "%.1f km", metros / 1000)
            : "\(Int(metros)) m"
    }
}

// MARK: - Resumen de llegada

/// Alerta de fin de viaje con las métricas de la sesión: duración,
/// distancia recorrida, velocidad media y puntos GPS registrados.
struct ResumenLlegadaCard: View {
    let resumen: RouteTrackingViewModel.ResumenViaje
    let destino: String
    let onCerrar: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color(hex: "#8affc1"))

            VStack(spacing: 4) {
                Text(L.t("¡Llegaste a tu destino!", "You arrived!"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                Text(destino)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8affc1"))
            }

            HStack(spacing: 8) {
                celda("clock.fill", formatoDuracion(resumen.duracionS),
                      L.t("Duración", "Duration"))
                celda("point.topleft.down.curvedto.point.bottomright.up",
                      VehiclePopupCard.formatoDistancia(resumen.distanciaM),
                      L.t("Recorrido", "Distance"))
            }
            HStack(spacing: 8) {
                celda("speedometer", "\(Int(resumen.velocidadKmh)) km/h",
                      L.t("Vel. media", "Avg. speed"))
                celda("record.circle", "\(resumen.puntos)",
                      L.t("Puntos GPS", "GPS points"))
            }

            Button(action: onCerrar) {
                Text(L.t("Terminar", "Done"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color(hex: "#8affc1")))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
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

    private func celda(_ icono: String, _ valor: String, _ etiqueta: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
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
        Color(hex: "#0a0a0a").ignoresSafeArea()
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
        Color(hex: "#0a0a0a").ignoresSafeArea()
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
        Color(hex: "#0a0a0a").ignoresSafeArea()
        ResumenLlegadaCard(
            resumen: .init(duracionS: 1140, distanciaM: 3200, puntos: 87, velocidadKmh: 10.1),
            destino: "UTP",
            onCerrar: {}
        )
    }
}
