//
//  SeleccionDiasNotificaciones.swift
//  RutaUTP
//
//  Selector multiple de dias de la semana.
//

import SwiftUI

struct SeleccionDiasNotificaciones: View {
    let seleccionados: Set<Int>
    let onToggle: (Int) -> Void

    var body: some View {
        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { dia in
            let seleccionado = seleccionados.contains(dia)
            Button { onToggle(dia) } label: {
                HStack(spacing: 12) {
                    Text(DiasNotificaciones.nombre(dia, corto: false))
                        .font(.body)
                        .foregroundStyle(EstiloPreferencias.texto)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if seleccionado {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DiasNotificaciones.nombre(dia, corto: false))
            .accessibilityAddTraits(seleccionado ? .isSelected : [])
        }
    }
}
