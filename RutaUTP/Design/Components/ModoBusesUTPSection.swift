import SwiftUI

struct ModoBusesUTPSection: View {
    @AppStorage(PreferenciasApp.busesUTP) private var activado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Transporte", "Transport"))
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.onSurface)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { activado && TransporteApp.busesUTPDisponibles },
                    set: { activado = $0 && TransporteApp.busesUTPDisponibles }
                )) {
                    HStack(spacing: 14) {
                        Image(systemName: "bus.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onPrimaryContainer)
                            .frame(width: 38, height: 38)
                            .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.t("Buses UTP", "UTP buses"))
                                .font(.bodyMdMedium)
                                .foregroundStyle(Color.onSurface)
                            Text(activado
                                 ? (TransporteApp.rutasUTPPendientes
                                    ? L.t("Rutas pendientes", "Routes pending")
                                    : L.t("Modo UTP activado", "UTP mode on"))
                                 : L.t("Transporte urbano", "City transport"))
                                .font(.caption)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.appPrimary)
                .accessibilityLabel(L.t("Buses de la UTP", "UTP buses"))
                .accessibilityHint(activado
                    ? L.t("Vuelve al transporte urbano y termina el viaje en curso", "Returns to city transport and ends the current trip")
                    : L.t("Cambia el mapa y las rutas al transporte de la UTP y termina el viaje en curso", "Switches the map and routes to UTP transport and ends the current trip"))

                Text(L.t("Cambiar de modo termina tu viaje actual.", "Switching modes ends your current trip."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(L.t("Más información", "More information")) {
                    Text(TransporteApp.rutasUTPPendientes
                         ? TransporteApp.mensajePendiente
                         : L.t("Al activarlo, el mapa y las rutas usarán los buses de la UTP. Al desactivarlo, volverás al transporte urbano.",
                               "When enabled, the map and routes use UTP buses. When disabled, you return to city transport."))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.footnote)
                .foregroundStyle(Color.onSurfaceVariant)
                .tint(.appPrimary)
            }
            .padding(16)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.outlineVariant.opacity(0.18), lineWidth: 0.5)
            }
        }
    }
}
