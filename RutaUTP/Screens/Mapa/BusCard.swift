import SwiftUI

// MARK: - Bus card
struct BusCard: View {
    let linea: String
    let empresa: String
    let minutos: String
    let tipo: String
    let placa: String
    let colorLinea: Color
    var occupancy: BusOccupancyState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(linea)
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Spacer(minLength: 0)
                if let occupancy {
                    Label(occupancy.title, systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(occupancy == .full ? Color.red : Color.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Text(empresa)
                .font(.headlineSm)
                .foregroundStyle(.onSurface)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(minutos)
                    .font(.labelCapsMd)
                    .foregroundStyle(colorLinea == .appPrimary ? Color.onPrimaryContainer : Color.onSecondaryContainer)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorLinea == .appPrimary ? Color.primaryContainer : Color.secondaryContainer)
                    )
                Text("\(L.tipoVehiculo(tipo)) • \(placa)")
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 256, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.appSurface.opacity(0.55))
                )
        )
        .overlay(
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorLinea)
                    .frame(width: 4, height: 56)
                Spacer()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(linea + ", " + empresa)
        .accessibilityValue([minutos, L.tipoVehiculo(tipo), placa, occupancy?.title ?? ""].filter { !$0.isEmpty }.joined(separator: ". "))
    }
}
