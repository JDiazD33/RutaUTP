import SwiftUI
import MapKit

struct RouteSummaryPanel: View {
    let vm: MapaViewModel
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    let onConfirmBoarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if vm.calculandoItinerario {
                    ProgressView().controlSize(.small)
                    Text(L.t("Buscando paradero y transporte…", "Finding stops and transit…"))
                } else {
                    Text(vm.busquedaResultado.map { L.t("Hacia ", "To ") + $0.titulo } ?? "")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { vm.limpiar() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Quitar ruta", "Clear route"))
            }
            .font(.system(size: 13, weight: .semibold))
            if let installed = vm.itinerarioInstalado {
                let plan = installed.plan
                let metrics = installed.metrics
                Label(L.t("Camina ", "Walk ") + "\(Int(ceil(metrics.walkToBoardMeters))) m · " + plan.board.nombre,
                      systemImage: "figure.walk")
                Label(L.t("Toma la línea ", "Take line ") + plan.route.lineaConLetra + " · " + plan.route.precioTexto,
                      systemImage: "bus.fill")
                    .fixedSize(horizontal: false, vertical: true)
                if let transfer = plan.transfer {
                    Text(L.t("1 transbordo", "1 transfer")).fontWeight(.bold)
                    Label(L.t("Baja en ", "Get off at ") + plan.firstAlight.nombre, systemImage: "mappin.and.ellipse")
                    Label(L.t("Camina ", "Walk ") + "\(Int(ceil(metrics.transferWalkMeters))) m · " + transfer.board.nombre,
                          systemImage: "figure.walk")
                    Label(L.t("Luego toma ", "Then take ") + transfer.route.lineaConLetra + " · " + transfer.route.precioTexto,
                          systemImage: "arrow.triangle.swap")
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L.t("El tiempo incluye una espera estimada para el segundo micro.",
                             "Time includes an estimated wait for the second bus."))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Label(L.t("Baja en ", "Get off at ") + plan.alight.nombre,
                      systemImage: "mappin.and.ellipse")
                Text(L.t("Luego camina \(Int(ceil(metrics.walkToDestinationMeters))) m hasta tu destino.",
                         "Then walk \(Int(ceil(metrics.walkToDestinationMeters))) m to your destination."))
                    .foregroundStyle(Color.onSurfaceVariant)
                Text(L.t("··· A pie   ━ En bus", "··· Walk   ━ Bus") + " · ~\(vm.etaMinutos ?? 0) min")
                    .foregroundStyle(Color.onSurfaceVariant)
                if plan.walkingApproximate {
                    AvisoRutaAproximada()
                }
                if trackingCoordinator.selectedTripRoute == nil {
                    invitacionConfirmarViaje
                }
            } else if let mensaje = vm.mensajeRuta {
                Text(mensaje).foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Guía de la ruta", "Route guide"))
    }

    /// Acceso voluntario que permanece disponible aunque se cierre el aviso.
    private var invitacionConfirmarViaje: some View {
        Button {
            onConfirmBoarding()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("¿Ya subiste?", "Already on board?"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Confirma tu línea", "Confirm your line"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(L.t("¿Ya subiste? Confirma tu línea", "Already on board? Confirm your line"))
    }
}
