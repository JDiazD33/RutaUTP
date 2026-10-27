//
//  SeniasPlayerView.swift
//  RutaUTP
//
//  Envoltorio SwiftUI del reproductor de señas: reproducción única al
//  activar el modo y bucle al consultar una seña.
//

import SwiftUI

struct SeniasPlayerView: UIViewRepresentable {
    let url: URL
    let id: UUID
    var repetir = true
    var encuadreCompleto = false
    var alFinalizar: (() -> Void)? = nil
    var alFallar: (() -> Void)? = nil

    func makeUIView(context: Context) -> SeniasPlayerUIView {
        let vista = SeniasPlayerUIView()
        vista.configurar(url: url, id: id, repetir: repetir, encuadreCompleto: encuadreCompleto,
                         alFinalizar: alFinalizar, alFallar: alFallar)
        return vista
    }

    func updateUIView(_ uiView: SeniasPlayerUIView, context: Context) {
        uiView.configurar(url: url, id: id, repetir: repetir, encuadreCompleto: encuadreCompleto,
                            alFinalizar: alFinalizar, alFallar: alFallar)
    }

    static func dismantleUIView(_ uiView: SeniasPlayerUIView, coordinator: ()) {
        uiView.limpiar()
    }
}
