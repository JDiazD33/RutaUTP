import SwiftUI

struct ModoBusesUTPSection: View {
    @AppStorage(PreferenciasApp.busesUTP) private var activado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("TRANSPORTE", "TRANSPORT"))
                .font(.labelCapsLg)
                .foregroundStyle(.onSurfaceVariant)
                .accessibilityAddTraits(.isHeader)

            Toggle(isOn: Binding(
                get: { activado && TransporteApp.busesUTPDisponibles },
                set: { activado = $0 && TransporteApp.busesUTPDisponibles }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Color.red)
                        .frame(width: 40, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Buses de la UTP", "UTP buses"))
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurface)
                        Text(activado ? L.t("Modo UTP activado", "UTP mode on")
                                      : L.t("Usar transporte universitario", "Use university transport"))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                }
            }
            .tint(.appPrimary)
            .accessibilityLabel(L.t("Buses de la UTP", "UTP buses"))
            .accessibilityHint(activado
                ? L.t("Vuelve al transporte urbano y termina el viaje en curso", "Returns to city transport and ends the current trip")
                : L.t("Cambia el mapa y las rutas al transporte de la UTP y termina el viaje en curso", "Switches the map and routes to UTP transport and ends the current trip"))
            .padding(16)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))

            Text(TransporteApp.rutasUTPPendientes
                 ? TransporteApp.mensajePendiente
                 : L.t("Al activarlo, el mapa y las rutas usarán los buses de la UTP. Al desactivarlo, volverás al transporte urbano.",
                       "When enabled, the map and routes use UTP buses. When disabled, you return to city transport."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Text(L.t("Los viajes en curso terminan al cambiar de modo.", "Current trips end when you switch modes."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
