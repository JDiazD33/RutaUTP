//
//  EncuadreFotoView.swift
//  RutaUTP
//
//  Editor de encuadre para la foto del carné y del perfil.
//

import SwiftUI
import UIKit

/// El mismo rectángulo y transformación se usan para la vista previa y el archivo.
struct EncuadreFotoView: View {
    let image: UIImage
    var esPerfil = false
    let onGuardar: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var desplazamiento: CGSize = .zero
    @GestureState private var arrastre: CGSize = .zero
    @GestureState private var aumento: CGFloat = 1

    private var proporcion: CGFloat { esPerfil ? 1 : 1.586 }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let ancho = max(1, min(geo.size.width - 32, 600))
                let marco = CGSize(width: ancho, height: ancho / proporcion)
                let escala = escalaBase(marco) * min(6, max(1, zoom * aumento))
                let posicion = limitar(CGSize(width: desplazamiento.width + arrastre.width,
                                               height: desplazamiento.height + arrastre.height), marco: marco, escala: escala)
                ScrollView {
                    VStack(spacing: 24) {
                        Text(esPerfil ? L.t("Mueve la foto y ajusta el zoom para centrar tu rostro en el círculo.", "Drag and zoom to center your face in the circle.") : L.t("Mueve la foto y pellizca para acercarla. Deja el carné completo dentro del marco.", "Drag and pinch to zoom. Keep the entire card inside the frame."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: image.size.width * escala, height: image.size.height * escala)
                                .offset(posicion)
                        }
                        .frame(width: marco.width, height: marco.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: esPerfil ? marco.width / 2 : 0))
                        .overlay(RoundedRectangle(cornerRadius: esPerfil ? marco.width / 2 : 0).stroke(Color.appPrimary, lineWidth: 2).allowsHitTesting(false))
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .updating($arrastre) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                desplazamiento = limitar(CGSize(width: desplazamiento.width + value.translation.width,
                                                                height: desplazamiento.height + value.translation.height),
                                                         marco: marco, escala: escalaBase(marco) * zoom)
                            }
                            // MagnifyGesture sustituye a MagnificationGesture,
                            // obsoleta en iOS 17 (el mínimo del proyecto).
                            .simultaneously(with: MagnifyGesture()
                                .updating($aumento) { value, state, _ in
                                    state = value.magnification
                                }
                                .onEnded { value in
                                    zoom = min(6, max(1, zoom * value.magnification))
                                    desplazamiento = limitar(desplazamiento, marco: marco, escala: escalaBase(marco) * zoom)
                                }))
                        .accessibilityLabel(L.t("Vista previa del recorte", "Crop preview"))
                        .accessibilityValue(L.f("Ampliación {0} por ciento", "Zoom {0} percent", ["\(Int(zoom * 100))"]))
                        .accessibilityActions {
                            Button(L.t("Mover foto arriba", "Move photo up")) {
                                desplazamiento = limitar(CGSize(width: desplazamiento.width, height: desplazamiento.height - 20), marco: marco, escala: escalaBase(marco) * zoom)
                            }
                            Button(L.t("Mover foto abajo", "Move photo down")) {
                                desplazamiento = limitar(CGSize(width: desplazamiento.width, height: desplazamiento.height + 20), marco: marco, escala: escalaBase(marco) * zoom)
                            }
                            Button(L.t("Mover foto a la izquierda", "Move photo left")) {
                                desplazamiento = limitar(CGSize(width: desplazamiento.width - 20, height: desplazamiento.height), marco: marco, escala: escalaBase(marco) * zoom)
                            }
                            Button(L.t("Mover foto a la derecha", "Move photo right")) {
                                desplazamiento = limitar(CGSize(width: desplazamiento.width + 20, height: desplazamiento.height), marco: marco, escala: escalaBase(marco) * zoom)
                            }
                        }
                        VStack {
                            Label(L.t("Ampliación", "Zoom"), systemImage: "plus.magnifyingglass")
                            Slider(value: $zoom, in: 1...6)
                                .accessibilityLabel(L.t("Ampliación", "Zoom"))
                                .accessibilityValue(L.f("{0} por ciento", "{0} percent", ["\(Int(zoom * 100))"]))
                        }
                        Button(L.t("Restablecer encuadre", "Reset framing")) {
                            zoom = 1
                            desplazamiento = .zero
                        }
                        Button {
                            let escalaFinal = escalaBase(marco) * zoom
                            let offset = limitar(desplazamiento, marco: marco, escala: escalaFinal)
                            let factor = min(2400 / marco.width, 1 / escalaFinal)
                            let salida = CGSize(width: marco.width * factor, height: marco.height * factor)
                            let formato = UIGraphicsImageRendererFormat()
                            formato.scale = 1
                            formato.opaque = true
                            let recorte = UIGraphicsImageRenderer(size: salida, format: formato).image { _ in
                                image.draw(in: CGRect(
                                    x: ((marco.width - image.size.width * escalaFinal) / 2 + offset.width) * factor,
                                    y: ((marco.height - image.size.height * escalaFinal) / 2 + offset.height) * factor,
                                    width: image.size.width * escalaFinal * factor,
                                    height: image.size.height * escalaFinal * factor))
                            }
                            onGuardar(recorte)
                        } label: {
                            Text(L.t("Guardar encuadre", "Save framing"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.primaryFill)
                        .foregroundStyle(Color.onPrimaryFill)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(esPerfil ? L.t("Encuadrar foto de perfil", "Frame profile photo") : L.t("Encuadrar carné", "Frame card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
    }

    private func escalaBase(_ marco: CGSize) -> CGFloat {
        max(marco.width / image.size.width, marco.height / image.size.height)
    }

    private func limitar(_ offset: CGSize, marco: CGSize, escala: CGFloat) -> CGSize {
        let x = max(0, (image.size.width * escala - marco.width) / 2)
        let y = max(0, (image.size.height * escala - marco.height) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
}
