import SwiftUI
import MapKit

struct TrackingProgressPanel: View {
    let vm: RouteTrackingViewModel

    private var colorRuta: Color {
        vm.rutaGTFS?.color ?? Color.primaryContainer
    }

    var body: some View {
        Group {
            barraProgreso
            statsRow
        }
    }

    // MARK: - Progreso + stats del viaje

    private var barraProgreso: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.onSurface.opacity(0.15))
                    Capsule()
                        .fill(colorRuta)
                        .frame(width: max(8, geo.size.width * vm.progreso))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.3), value: vm.progreso)

            HStack {
                Text(L.t("Avance del recorrido", "Trip progress"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.onSurface.opacity(0.5))
                Spacer()
                Text("\(Int(vm.progreso * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colorRuta)
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
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "clock.fill",
                 valor: "\(vm.minutosRestantes) min",
                 etiqueta: L.t("Restante", "Remaining"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "point.topleft.down.curvedto.point.bottomright.up",
                 valor: vm.distanciaRestanteTexto,
                 etiqueta: L.t("Por recorrer", "To go"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Color.onSurface.opacity(0.12)).frame(width: 1, height: 34)
            stat(icono: "record.circle",
                 valor: "\(vm.puntosGPSRegistrados)",
                 etiqueta: L.t("Puntos GPS", "GPS points"))
                .frame(maxWidth: .infinity)
        }
    }

    /// Hora de llegada estimada al ritmo de la ruta calculada.
    private var horaLlegadaTexto: String {
        guard vm.etaTotalSeg != nil else { return "—" }
        let fecha = Date().addingTimeInterval(vm.remainingSeconds)
        return FormatoFecha.formateador(patron: "HH:mm", locale: .current)
            .string(from: fecha)
    }

    private func stat(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.onSurface.opacity(0.55))
            Text(valor)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.onSurface.opacity(0.5))
                .appTracking(AppTracking.wideLabel)
        }
    }
}
