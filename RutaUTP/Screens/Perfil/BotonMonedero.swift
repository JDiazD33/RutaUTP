//
//  BotonMonedero.swift
//  RutaUTP
//
//  Estilo compartido por las acciones de las hojas del monedero.
//

import SwiftUI

/// Mismo aspecto que los accesos de `MonederoCard`: el botón destacado usa el
/// color de etiqueta, negro o blanco según el tema, y el secundario el relleno
/// agrupado del sistema. Así Recargar y Pagar con QR continúan la tarjeta del
/// perfil sin introducir un color nuevo.
struct BotonMonederoStyle: ButtonStyle {
    var destacado = false

    func makeBody(configuration: Configuration) -> some View {
        Contenido(configuration: configuration, destacado: destacado)
    }

    private struct Contenido: View {
        let configuration: ButtonStyleConfiguration
        let destacado: Bool
        @Environment(\.isEnabled) private var habilitado

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(destacado ? Color(uiColor: .systemBackground) : Color.onSurface)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(destacado ? Color(uiColor: .label) : Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(habilitado ? (configuration.isPressed ? 0.7 : 1) : 0.4)
        }
    }
}
