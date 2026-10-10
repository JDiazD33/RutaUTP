import SwiftUI

struct RutaOpcionCard: View {
    @Environment(\.self) private var entorno
    let ruta: RutaOpcion
    var distanciaLugar: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 2) {
                    if ruta.letraTransporte.isEmpty {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 24, weight: .bold))
                    } else {
                        Text(L.t("LETRA", "LETTER"))
                            .font(.system(size: 9, weight: .bold))
                        Text(ruta.letraTransporte)
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(colorTextoLetra)
                .frame(width: 58, height: 58)
                .background(ruta.colorLinea, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("Línea ", "Line ") + ruta.linea)
                        .font(.bodyMdMedium.weight(.bold))
                        .foregroundStyle(Color.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ruta.empresa)
                        .font(.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 8) {
                extremo(ruta.paradaInicio, destino: false)
                extremo(ruta.paradaFin, destino: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { datosRuta }
                VStack(alignment: .leading, spacing: 8) { datosRuta }
            }
            .font(.caption)
            .foregroundStyle(Color.onSurfaceVariant)

            if let distanciaLugar {
                Label(distanciaLugar, systemImage: "figure.walk")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.onSurface)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Línea ", "Line ") + ruta.lineaConLetra + ", " + ruta.empresa)
        .accessibilityValue([ruta.recorrido, distanciaLugar, L.t("Pasaje ", "Fare ") + ruta.costo,
                             L.t("\(ruta.numParaderos) paraderos", "\(ruta.numParaderos) stops"),
                             ruta.frecuenciaMin > 0 ? ruta.frecuenciaTexto : nil]
            .compactMap { $0 }.joined(separator: ". "))
    }

    /// Conserva el color de la ruta y elige texto legible en colores claros u oscuros.
    private var colorTextoLetra: Color {
        let color = ruta.colorLinea.resolve(in: entorno)
        let luminancia = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        let contrasteNegro = (luminancia + 0.05) / 0.05
        let contrasteBlanco = 1.05 / (luminancia + 0.05)
        return contrasteNegro >= contrasteBlanco ? .black : .white
    }

    @ViewBuilder private var datosRuta: some View {
        Label(ruta.costo, systemImage: "banknote")
            .fontWeight(.semibold)
            .foregroundStyle(Color.onSurface)
        Label(L.t("\(ruta.numParaderos) paraderos", "\(ruta.numParaderos) stops"), systemImage: "mappin")
        if ruta.frecuenciaMin > 0 {
            Label(ruta.frecuenciaTexto, systemImage: "clock")
        }
    }

    private func extremo(_ nombre: String, destino: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: destino ? "mappin.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 16, height: 18)
                .accessibilityHidden(true)
            Text(nombre)
                .font(.bodySm)
                .foregroundStyle(Color.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
