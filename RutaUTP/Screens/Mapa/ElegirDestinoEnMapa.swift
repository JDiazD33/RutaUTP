import SwiftUI
import CoreLocation

// MARK: - Elegir destino tocando el mapa
/// Mapa a pantalla completa lanzado desde el buscador: el usuario toca el
/// punto exacto y se convierte en el destino (con dirección real vía
/// geocodificación inversa).
struct ElegirDestinoEnMapa: View {
    /// Destino ya elegido antes de abrir (si existe): centra el mapa ahí.
    let coordenadaInicial: CLLocationCoordinate2D?
    /// Devuelve (título, coordenada) del punto elegido.
    var onElegir: (String, CLLocationCoordinate2D) -> Void
    var onCerrar: () -> Void

    @State private var coordenada: CLLocationCoordinate2D? = nil
    @State private var resolviendoDireccion = false

    var body: some View {
        ZStack {
            MapaElegirLugar(
                colorPin: .appPrimary,
                coordenada: coordenada ?? coordenadaInicial,
                onTocar: { coord in
                    AppHaptics.impact(.light)
                    coordenada = coord
                }
            )
            .ignoresSafeArea()

            VStack {
                barraSuperior
                Spacer()
                pie
            }
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(L.t("¿A dónde vas hoy?", "Where to today?"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))

            Spacer()

            Button(action: onCerrar) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(
                        Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Abajo: instrucción mientras no haya pin; confirmar cuando sí.
    @ViewBuilder
    private var pie: some View {
        if coordenada != nil {
            Button(action: confirmar) {
                HStack(spacing: 8) {
                    if resolviendoDireccion {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(resolviendoDireccion
                         ? L.t("Buscando dirección…", "Looking up address…")
                         : L.t("Usar este destino", "Use this destination"))
                        .font(.headlineSm)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appPrimary)
                        .shadow(color: .appPrimary.opacity(0.35), radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(PressableCapsuleStyle())
            .disabled(resolviendoDireccion)
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(L.t("Toca el mapa donde quieres ir", "Tap the map where you want to go"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }

    /// Convierte el punto en el destino: resuelve su dirección real (con
    /// respaldo si el geocoder no responde) y lo entrega al Mapa.
    private func confirmar() {
        guard let coordenada, !resolviendoDireccion else { return }
        resolviendoDireccion = true
        Task { @MainActor in
            let titulo = await Self.nombreDelLugar(coordenada)
            resolviendoDireccion = false
            onElegir(titulo, coordenada)
        }
    }

    /// Delega en el helper compartido: la misma resolución la usan el guardado
    /// de lugares y el punto de subida.
    static func nombreDelLugar(_ coord: CLLocationCoordinate2D) async -> String {
        await Geocodificacion.nombreDelLugar(coord)
    }
}
