//
//  VisorFotoCarnet.swift
//  RutaUTP
//
//  Visor ampliable de la foto del carné.
//

import SwiftUI
import UIKit

/// Visor de la foto del carné: la muestra **completa** dentro de la pantalla y
/// solo amplía si el usuario lo pide.
///
/// Antes la imagen se forzaba a un ancho mínimo de 900 pt dentro de un
/// `ScrollView` en dos ejes. En un iPhone (~390 pt de ancho) eso dibujaba el
/// carné al doble de tamaño, recortado por los cuatro lados y con scroll
/// horizontal para poder verlo entero. El visor arranca ahora con el tamaño que
/// hace entrar la tarjeta entera (`scaledToFit`) y el pellizco sirve solo para
/// leer el texto pequeño, sin cambiar el punto de partida.
///
/// La proporción de partida es la del documento (apaisado, como un DNI): en
/// vertical el ajuste queda limitado por el ancho, así que la tarjeta se ve
/// entera y centrada, sin recortes ni desplazamiento.
struct VisorFotoCarnet: View {
    let imagen: UIImage

    /// Ampliación elegida por el usuario. `1` = la tarjeta entera en pantalla.
    @State private var zoom: CGFloat = 1
    @State private var desplazamiento: CGSize = .zero
    @GestureState private var arrastre: CGSize = .zero
    @GestureState private var aumento: CGFloat = 1

    private static let zoomMaximo: CGFloat = 6
    /// Margen alrededor del marco, para que la tarjeta no toque los bordes.
    private static let margen: CGFloat = 16
    /// Ampliación del doble toque: suficiente para leer el texto pequeño.
    private static let zoomDobleToque: CGFloat = 2.5

    /// Zoom que se está dibujando ahora (incluye el pellizco en curso).
    private var zoomDibujado: CGFloat {
        min(Self.zoomMaximo, max(1, zoom * aumento))
    }

    /// Escala que hace entrar la imagen **completa** en el marco.
    ///
    /// El `min` es la corrección: con `max` (rellenar) la tarjeta apaisada se
    /// recortaba por los lados en una pantalla vertical.
    private func escalaQueEntra(marco: CGSize) -> CGFloat {
        guard imagen.size.width > 0, imagen.size.height > 0 else { return 1 }

        return min(marco.width / imagen.size.width,
                   marco.height / imagen.size.height)
    }

    private func tamanoDibujado(marco: CGSize, escala: CGFloat) -> CGSize {
        CGSize(width: imagen.size.width * escala,
               height: imagen.size.height * escala)
    }

    /// Limita el desplazamiento para que la imagen no se salga del marco.
    ///
    /// Con la tarjeta entera (sin ampliar) el tope es cero, así que queda
    /// siempre centrada; el desplazamiento solo existe al ampliar.
    private func limitar(_ offset: CGSize, marco: CGSize, tamano: CGSize) -> CGSize {
        let x = max(0, (tamano.width - marco.width) / 2)
        let y = max(0, (tamano.height - marco.height) / 2)

        return CGSize(width: min(x, max(-x, offset.width)),
                      height: min(y, max(-y, offset.height)))
    }

    private func reiniciar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoom = 1
            desplazamiento = .zero
        }
    }

    var body: some View {
        GeometryReader { geo in
            let marco = CGSize(width: max(1, geo.size.width - Self.margen * 2),
                               height: max(1, geo.size.height - Self.margen * 2))
            let escalaBase = escalaQueEntra(marco: marco)
            let escalaDibujada = escalaBase * zoomDibujado
            // Ojo: el nombre NO puede ser `tamanoDibujado`, o ensombrecería al
            // método homónimo y las llamadas de los gestos no compilarían.
            let tamano = tamanoDibujado(marco: marco, escala: escalaDibujada)
            // Tamaño con el zoom ya confirmado (sin el pellizco en curso), para
            // acotar el desplazamiento cuando termina el gesto.
            let tamanoConfirmado = tamanoDibujado(marco: marco, escala: escalaBase * zoom)
            let posicion = limitar(
                CGSize(width: desplazamiento.width + arrastre.width,
                       height: desplazamiento.height + arrastre.height),
                marco: marco,
                tamano: tamano
            )

            Image(uiImage: imagen)
                .resizable()
                .interpolation(.high)
                .frame(width: tamano.width, height: tamano.height)
                .offset(posicion)
                .frame(width: marco.width, height: marco.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($arrastre) { valor, estado, _ in
                            estado = valor.translation
                        }
                        .onEnded { valor in
                            desplazamiento = limitar(
                                CGSize(width: desplazamiento.width + valor.translation.width,
                                       height: desplazamiento.height + valor.translation.height),
                                marco: marco,
                                tamano: tamanoConfirmado
                            )
                        }
                        // MagnifyGesture sustituye a MagnificationGesture,
                        // obsoleta en iOS 17 (el mínimo del proyecto).
                        .simultaneously(with:
                            MagnifyGesture()
                                .updating($aumento) { valor, estado, _ in
                                    estado = valor.magnification
                                }
                                .onEnded { valor in
                                    zoom = min(Self.zoomMaximo,
                                               max(1, zoom * valor.magnification))
                                    desplazamiento = limitar(
                                        desplazamiento,
                                        marco: marco,
                                        tamano: tamanoDibujado(
                                            marco: marco,
                                            escala: escalaBase * zoom
                                        )
                                    )
                                }
                        )
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if zoom > 1.01 {
                            reiniciar()
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                zoom = Self.zoomDobleToque
                            }
                        }
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityLabel(L.t("Foto del carné", "Card photo"))
                .accessibilityValue(L.f("Ampliación {0} por ciento", "Zoom {0} percent", ["\(Int(zoom * 100))"]))
                .accessibilityHint(L.t("Usa Acciones para acercar, alejar o restablecer la foto", "Use Actions to zoom in, zoom out or reset the photo"))
                .accessibilityActions {
                    Button(L.t("Acercar", "Zoom in")) {
                        zoom = min(Self.zoomMaximo, zoom + 0.5)
                    }
                    Button(L.t("Alejar", "Zoom out")) {
                        zoom = max(1, zoom - 0.5)
                        desplazamiento = limitar(desplazamiento, marco: marco,
                            tamano: tamanoDibujado(marco: marco, escala: escalaBase * zoom))
                    }
                    Button(L.t("Ver foto completa", "Fit whole photo"), action: reiniciar)
                    Button(L.t("Mover foto arriba", "Move photo up")) {
                        desplazamiento = limitar(CGSize(width: desplazamiento.width, height: desplazamiento.height - 20), marco: marco, tamano: tamanoDibujado(marco: marco, escala: escalaBase * zoom))
                    }
                    Button(L.t("Mover foto abajo", "Move photo down")) {
                        desplazamiento = limitar(CGSize(width: desplazamiento.width, height: desplazamiento.height + 20), marco: marco, tamano: tamanoDibujado(marco: marco, escala: escalaBase * zoom))
                    }
                    Button(L.t("Mover foto a la izquierda", "Move photo left")) {
                        desplazamiento = limitar(CGSize(width: desplazamiento.width - 20, height: desplazamiento.height), marco: marco, tamano: tamanoDibujado(marco: marco, escala: escalaBase * zoom))
                    }
                    Button(L.t("Mover foto a la derecha", "Move photo right")) {
                        desplazamiento = limitar(CGSize(width: desplazamiento.width + 20, height: desplazamiento.height), marco: marco, tamano: tamanoDibujado(marco: marco, escala: escalaBase * zoom))
                    }
                }
                .overlay(alignment: .bottom) {
                    // El botón solo aparece ampliado: es la salida rápida a la
                    // vista completa, que es el estado por defecto.
                    if zoom > 1.01 {
                        Button(action: reiniciar) {
                            Label(L.t("Ver completo", "Fit whole card"),
                                  systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .accessibilityHint(L.t("Vuelve a mostrar el carné entero en pantalla",
                                               "Shows the whole card on screen again"))
                    }
                }
        }
    }
}
