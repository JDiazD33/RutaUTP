import SwiftUI

// MARK: - Popup de Detalle de Bus Animado
struct BusDetailPopup: View {
    let bus: BusAnimado
    let onClose: () -> Void
    let onVerRuta: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bus.color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(bus.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L.t("LÍNEA", "LINE") + " \(bus.linea)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.onSurface)
                        Text(bus.etiquetaLlegada)
                            .font(.labelCapsSm)
                            .foregroundStyle(.white)
                            .appTracking(AppTracking.wideLabel)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(bus.color))
                    }
                    Text("\(bus.empresa) • \(bus.tipo) (\(bus.ramalTexto))")
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(L.t("Cerrar detalle del micro", "Close bus details"))
            }

            if bus.fuente == .real {
                Text(bus.minutosLlegada == nil
                     ? L.t("Llegada no disponible: faltan datos suficientes para estimarla.",
                           "Arrival unavailable: not enough data to estimate it.")
                     : L.t("Llegada aproximada al punto consultado de la ruta. Puede variar por tráfico y paradas.",
                           "Approximate arrival at the queried point on the route. Traffic and stops may change it."))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            BusOccupancyPanel(vehicleID: bus.fuente == .real && bus.id.hasPrefix("real-")
                              ? String(bus.id.dropFirst(5)) : nil)
                .id(bus.id)

            Button(action: onVerRuta) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(L.t("Ver Ruta Completa", "View full route"))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bus.color)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(bus.color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Detalle de la línea ", "Details for line ") + bus.linea)
        .accessibilityAction(.escape, onClose)
    }
}
