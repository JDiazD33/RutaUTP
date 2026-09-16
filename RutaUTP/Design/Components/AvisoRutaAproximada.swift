//
//  AvisoRutaAproximada.swift
//  RutaUTP
//
//  Aviso de «esto es una estimación» con salida a lo que sí funciona.
//
//  Había tres mensajes distintos para el mismo problema (uno en Mapa y dos en
//  Tracking) y ninguno decía lo importante: que el recorrido del BUS sigue
//  siendo el oficial aunque fallen las indicaciones a pie. El feed GTFS viaja
//  dentro de la app y no necesita conexión; lo que depende de Apple Maps es la
//  búsqueda de direcciones y el trazado peatonal.
//
//  Un aviso rojo sin salida deja al usuario sin saber si puede fiarse del
//  resto del viaje. Este lo dice y ofrece el detalle.
//

import SwiftUI

struct AvisoRutaAproximada: View {

    /// Qué falló. Cambia el texto, no el tratamiento.
    enum Motivo {
        /// Apple Directions no dio indicaciones peatonales.
        case caminataEstimada
        /// No hay datos de Apple Maps para el trazado.
        case rutaSinDatos

        var titulo: String {
            switch self {
            case .caminataEstimada:
                return L.t("Caminata estimada en línea recta", "Walk estimated in a straight line")
            case .rutaSinDatos:
                return L.t("Trazado estimado, sin datos de Apple Maps",
                           "Estimated trace, no Apple Maps data")
            }
        }
    }

    var motivo: Motivo = .caminataEstimada

    @State private var mostrarDetalle = false

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            mostrarDetalle = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.appError)

                VStack(alignment: .leading, spacing: 2) {
                    Text(motivo.titulo)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("El recorrido del bus sí es el oficial: va dentro de la app. Toca para ver qué funciona sin conexión.",
                             "The bus route is the official one: it ships with the app. Tap to see what works offline."))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.surfaceContainerHigh.opacity(0.55))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(motivo.titulo)
        .accessibilityHint(L.t("Muestra qué funciona sin conexión", "Shows what works offline"))
        .sheet(isPresented: $mostrarDetalle) {
            OfflineMapSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
    }
}
