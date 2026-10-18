import SwiftUI

struct ModoBusesUTPSection: View {
    @AppStorage(PreferenciasApp.busesUTP) private var activado = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Transporte", "Transport"))
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { activado && TransporteApp.busesUTPDisponibles },
                    set: { activado = $0 && TransporteApp.busesUTPDisponibles }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "bus.fill")
                            .font(.body.weight(.regular))
                            .foregroundStyle(colorScheme == .dark ? Color.primaryFixed : Color.appPrimary)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.t("Buses UTP", "UTP buses"))
                                .font(.bodyMd)
                                .foregroundStyle(Color.onSurface)
                            Text(activado
                                 ? (TransporteApp.rutasUTPPendientes
                                    ? L.t("Rutas pendientes", "Routes pending")
                                    : L.t("Modo UTP activado", "UTP mode on"))
                                 : L.t("Transporte urbano", "City transport"))
                                .font(.footnote)
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
                    .padding(.leading, 40)

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
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
