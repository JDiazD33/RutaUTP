import SwiftUI

// MARK: - Ruta Opcion Card
struct RutaOpcionCard: View {
    let ruta: RutaOpcion
    var distanciaLugar: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(ruta.colorLinea)
                .frame(width: 4, height: 56)

            ZStack {
                Circle()
                    .fill(ruta.colorLinea.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(ruta.linea)
                    .font(.system(size: 14, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(ruta.colorLinea)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ruta.empresa)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                    .lineLimit(1)
                if !ruta.variante.isEmpty {
                    Text(L.t("Variante ", "Variant ") + ruta.variante)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.surfaceContainerLow, in: Capsule())
                }
                Text(ruta.recorrido)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
                if let distanciaLugar {
                    Text(distanciaLugar)
                        .font(.labelCapsSm)
                        .foregroundStyle(ruta.colorLinea)
                        .lineLimit(1)
                        .appTracking(AppTracking.wideLabel)
                } else {
                    Text(L.t("\(ruta.numParaderos) paraderos", "\(ruta.numParaderos) stops") + " · \(String(format: "%.1f", ruta.distanciaKm)) km")
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant.opacity(0.8))
                        .lineLimit(1)
                        .appTracking(AppTracking.wideLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ruta.frecuenciaTexto)
                    .font(.bodyMdMedium)
                    .foregroundStyle(ruta.colorLinea)
                Text(L.t("frecuencia", "frequency"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceContainerLowest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.40), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

