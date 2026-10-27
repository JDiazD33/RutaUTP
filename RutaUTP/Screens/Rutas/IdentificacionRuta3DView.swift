//
//  IdentificacionRuta3DView.swift
//  RutaUTP
//
//  Vista de identificación del transporte en el detalle de ruta.
//

import SwiftUI

/// Micros, combis y colectivos comparten controles, con su propia geometria.
struct IdentificacionRuta3DView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let identificacion: IdentificacionRuta3D
    var activo = true
    @State private var ampliar = false

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L.t("Reconoce tu transporte", "Recognize your vehicle"))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if identificacion.tipoModelo != nil {
                    Button { ampliar = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.surfaceContainerLow, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(acento)
                    .accessibilityLabel(L.t("Ampliar modelo 3D", "Expand 3D model"))
                }
            }
            datos
            if let tipo = identificacion.tipoModelo {
                PanelTransporte3D(tipo: tipo, identificacion: identificacion, activo: activo && !ampliar)
                    .id(identificacion.claveModelo)
            } else {
                Label(L.t("Modelo de esta categoría próximamente", "Model for this category coming soon"), systemImage: "cube.transparent")
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.vertical, 12)
            }
        }
        .foregroundStyle(Color.onSurface)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("ruta.identificacion3d")
        .sheet(isPresented: $ampliar) {
            Transportes3DView(identificacion: identificacion)
        }
    }

    private var datos: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            layout {
                VStack(spacing: 2) {
                    Text(L.t("Letra", "Letter"))
                        .font(.caption2)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(identificacion.letraPrincipal.isEmpty ? "—" : identificacion.letraPrincipal)
                        if let distintivo = identificacion.distintivoLetra {
                            Text(distintivo)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(identificacion.letra.isEmpty ? "—" : identificacion.letra))
                }
                .foregroundStyle(Color.onSurface)
                .padding(.horizontal, 12)
                .frame(minWidth: 88, minHeight: 78)
                .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(identificacion.codigo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(identificacion.empresa)
                        .font(.body.weight(.medium))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            ColoresReferenciaRutaView(referencia: identificacion.colores)
        }
    }
}
