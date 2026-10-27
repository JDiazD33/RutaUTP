//
//  VentanaEscanerQR.swift
//  RutaUTP
//
//  Piezas visuales de la ventana de lectura: las cuatro esquinas y la línea
//  de barrido que indica que el escáner está activo.
//

import SwiftUI

// MARK: - Piezas de la ventana

/// Las cuatro esquinas de la ventana, en un solo trazado.
struct EsquinasVentana: Shape {

    var largo: CGFloat = 30
    var radio: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var camino = Path()
        let r = min(radio, largo)

        // Superior izquierda
        camino.move(to: CGPoint(x: rect.minX, y: rect.minY + largo))
        camino.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        camino.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                            control: CGPoint(x: rect.minX, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.minX + largo, y: rect.minY))

        // Superior derecha
        camino.move(to: CGPoint(x: rect.maxX - largo, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        camino.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                            control: CGPoint(x: rect.maxX, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + largo))

        // Inferior derecha
        camino.move(to: CGPoint(x: rect.maxX, y: rect.maxY - largo))
        camino.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        camino.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                            control: CGPoint(x: rect.maxX, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.maxX - largo, y: rect.maxY))

        // Inferior izquierda
        camino.move(to: CGPoint(x: rect.minX + largo, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        camino.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                            control: CGPoint(x: rect.minX, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - largo))

        return camino
    }
}

/// Línea que recorre la ventana para indicar que está leyendo.
///
/// Con «reducir movimiento» activo se queda quieta en el borde superior: sigue
/// indicando que hay un área de lectura sin animar nada.
struct LineaBarrido: View {

    let lado: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var abajo = false

    var body: some View {
        LinearGradient(
            colors: [Color.appPrimary.opacity(0),
                     Color.appPrimary,
                     Color.appPrimary.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: max(1, lado - 32), height: 3)
        .clipShape(Capsule())
        .shadow(color: Color.appPrimary.opacity(0.8), radius: 6)
        .offset(y: abajo ? lado / 2 - 16 : -(lado / 2 - 16))
        .frame(width: lado, height: lado)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                abajo = true
            }
        }
    }
}
