//
//  MarcaBilletera.swift
//  RutaUTP
//
//  Logo de una billetera, con respaldo textual si falta el recurso.
//

import SwiftUI
import UIKit

/// Logo de una billetera, con respaldo si el recurso todavía no está en el
/// catálogo de recursos.
///
/// Los recursos (`yape-logo`, `plin-logo`, en `Assets.xcassets/Marcas`) tienen
/// el lienzo recortado al dibujo. Se muestran siempre en una caja cuadrada para
/// que no vuelvan a encogerse por el espacio transparente del SVG.
struct MarcaBilletera: View {

    let billetera: BilleteraPago
    var altura: CGFloat = 30

    var body: some View {
        Group {
            if let logo = UIImage(named: billetera.assetLogo) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                // Sin archivo no se deja un hueco ni se inventa un logo: se
                // escribe el nombre sobre el color de marca, y el día que se
                // añada la imagen entra sola.
                Text(billetera.nombre)
                    .font(.system(size: max(11, altura * 0.45), weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(billetera.colorMarca))
            }
        }
        .frame(width: altura, height: altura)
        .accessibilityHidden(true)
    }
}
