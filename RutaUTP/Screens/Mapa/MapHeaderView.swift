import SwiftUI
import MapKit

struct MapHeaderView: View {
    let vm: MapaViewModel
    @Binding var mostrarDrawer: Bool

    // MARK: - Header
    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { mostrarDrawer = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Abrir menú", "Open menu"))

            Text(L.t("Mapa", "Map"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)

            if vm.fuenteFlota == .real {
                // Tener credenciales no demuestra que hayan llegado posiciones.
                // El proveedor elimina los vehículos cuando sus datos caducan.
                let hayDatosRecientes = vm.hayPosicionesRealesRecientes
                Text(hayDatosRecientes
                     ? L.t("DATOS RECIENTES", "RECENT DATA")
                     : L.t("ESPERANDO DATOS", "WAITING FOR DATA"))
                    .font(.system(size: 9, weight: .bold))
                    .appTracking(AppTracking.wideLabel)
                    .foregroundStyle(hayDatosRecientes ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(
                        (hayDatosRecientes ? Color.green : Color.secondary).opacity(0.14)
                    ))
                    .accessibilityLabel(hayDatosRecientes
                        ? L.t("Posiciones recientes de vehículos", "Recent vehicle positions")
                        : L.t("Esperando posiciones de vehículos confirmados", "Waiting for confirmed vehicle positions"))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appSurface.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
