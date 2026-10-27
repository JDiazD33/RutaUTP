//
//  ColoresReferenciaRutaView.swift
//  RutaUTP
//
//  Lista de colores de referencia de una ruta.
//

import SwiftUI

struct ColoresReferenciaRutaView: View {
    let referencia: ColoresTransporteReferencia?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let referencia {
                Text(L.t("Colores de referencia", "Reference colors"))
                    .font(.bodySm.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { muestras(referencia) }
                    VStack(alignment: .leading, spacing: 8) { muestras(referencia) }
                }
                Text(referencia.esOrientativa
                     ? L.t("Colores orientativos, pendientes de confirmar.", "Indicative colors, awaiting confirmation.")
                     : L.t("Los colores pueden variar entre unidades.", "Colors may vary between vehicles."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                if let fuente = referencia.fuente {
                    Link(L.t("Ver fuente", "View source"), destination: fuente)
                        .font(.bodySm)
                        .foregroundStyle(Color.appAccent)
                        .frame(minHeight: 44)
                }
            } else {
                Label(L.t("Color por confirmar", "Color to be confirmed"), systemImage: "paintpalette")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }

    @ViewBuilder
    private func muestras(_ referencia: ColoresTransporteReferencia) -> some View {
        ForEach(referencia.colores, id: \.rawValue) { color in
            HStack(spacing: 6) {
                Circle()
                    .fill(color.color)
                    .overlay(Circle().stroke(Color.outline, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(color.nombre).font(.bodySm)
            }
        }
    }
}
