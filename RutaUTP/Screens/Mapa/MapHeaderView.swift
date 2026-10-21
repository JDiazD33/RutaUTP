import SwiftUI
import MapKit

struct MapHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let vm: MapaViewModel
    @Binding var mostrarDrawer: Bool
    @AccessibilityFocusState(for: .voiceOver) private var enfocarMenu: Bool

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    // MARK: - Header
    var body: some View {
        HStack(spacing: 12) {
            BotonMenuMapa {
                AppHaptics.impact(.light)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                    mostrarDrawer = true
                }
            }
            .accessibilityFocused($enfocarMenu)

            VStack(alignment: .leading, spacing: 3) {
                Text(vm.busesUTPActivos ? L.t("Buses UTP", "UTP buses") : L.t("Mapa", "Map"))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if vm.fuenteFlota == .real {
                    // Tener credenciales no demuestra que hayan llegado posiciones.
                    // El proveedor elimina los vehículos cuando sus datos caducan.
                    let hayDatosRecientes = vm.hayPosicionesRealesRecientes
                    Text(hayDatosRecientes
                         ? L.t("DATOS RECIENTES", "RECENT DATA")
                         : L.t("ESPERANDO DATOS", "WAITING FOR DATA"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hayDatosRecientes ? Color.green : Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(hayDatosRecientes
                            ? L.t("Posiciones recientes de vehículos", "Recent vehicle positions")
                            : L.t("Esperando posiciones de vehículos confirmados", "Waiting for confirmed vehicle positions"))
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "map")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .onChange(of: mostrarDrawer) { _, abierto in
            if !abierto { enfocarMenu = true }
        }
    }
}

/// Mismo acceso al menú en la vista inicial y durante un viaje.
struct BotonMenuMapa: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(acento)
                .frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Abrir menú", "Open menu"))
    }
}
