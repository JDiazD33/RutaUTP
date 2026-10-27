//
//  SeniasOverlay.swift
//  RutaUTP
//
//  Modo Señas: el texto señable se vuelve tocable y muestra la seña en LSP.
//
//  Tres piezas, una por archivo:
//   1. SeniasPlayerView  -> SeniasPlayerView.swift (reproducción única al
//                           activar; bucle al consultar).
//   2. SeniasOverlay     -> este archivo (media pantalla al activar;
//                           miniplayer al consultar).
//   3. .seniable(clave:) -> SeniableModifier.swift.
//
//  La tarjeta vive en SU PROPIA UIWindow a nivel .alert (SeniasOverlayVentana,
//  en SeniasOverlayVentana.swift), así se ve por encima de TODO, incluidos
//  sheets y fullScreenCovers — que de otro modo tapan el miniplayer y las
//  señas dentro de un sheet no se ven.
//
//  Si no hay clip, NO se inventa una seña: se muestra un estado honesto de
//  "pendiente de grabación". El contenido real se añade después en
//  senias/clips/<idioma>/ sin tocar una línea de este archivo.
//

import SwiftUI

// MARK: - 2. Overlay

struct SeniasOverlay: View {

    @ObservedObject private var presenter = SeniasPresenter.shared
    @Environment(\.dynamicTypeSize) private var textSize

    private let servicio = SeniasService.shared

    var body: some View {
        GeometryReader { geometria in
            if let clave = presenter.claveVisible {
                let id = presenter.idPresentacion
                VStack {
                    Spacer(minLength: 0)
                    if presenter.esActivacionDelModo {
                        tarjetaActivacion(clave: clave, id: id)
                            .frame(height: geometria.size.height / 2)
                            .padding(.horizontal, 14)
                        Spacer(minLength: 0)
                    } else {
                        HStack {
                            Spacer()
                            tarjeta(clave: clave, id: id,
                                    ancho: textSize.isAccessibilitySize
                                        ? min(320, max(180, geometria.size.width - 28)) : 180)
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, 104)
                    }
                }
                .id(id)
                .onAppear { presenter.tarjetaPresentada(clave: clave, id: id) }
            }
        }
        .animation(.easeOut(duration: 0.22), value: presenter.claveVisible)
        .environment(\.locale, IdiomaManager.shared.idioma.locale)
        .onChange(of: IdiomaManager.shared.codigo) { _, _ in
            presenter.cancelarAccionPendiente()
            presenter.ocultar()
        }
    }

    private func tarjetaActivacion(clave: String, id: UUID) -> some View {
        VStack(spacing: 8) {
            HStack {
                encabezado(clave: clave)
                Spacer(minLength: 8)
                botonCerrar
            }
            contenido(clave: clave, id: id, activacion: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("senias.activacion")
    }

    private func tarjeta(clave: String, id: UUID, ancho: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                encabezado(clave: clave)
                Spacer(minLength: 0)
                botonCerrar
            }
            contenido(clave: clave, id: id, activacion: false)
                .frame(maxWidth: .infinity)
                .frame(height: 156)
        }
        .padding(12)
        .frame(width: ancho)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .accessibilityElement(children: .contain)
    }

    private func encabezado(clave: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.appAccent)
                .accessibilityHidden(true)

            Text(servicio.texto(clave: clave))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func contenido(clave: String, id: UUID, activacion: Bool) -> some View {
        switch servicio.estado(para: clave) {

        case .clip(let url, let senia):
            VStack(spacing: 6) {
                SeniasPlayerView(
                    url: url, id: id, repetir: !activacion,
                    encuadreCompleto: activacion || clave == "rutas.guia",
                    alFinalizar: { presenter.videoFinalizado(id: id) },
                    alFallar: { presenter.videoNoDisponible(id: id) }
                )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if senia.esPlaceholder {
                    etiqueta(L.t("Clip de prueba", "Test clip"), sistema: "exclamationmark.triangle.fill", color: .orange)
                }
            }

        case .pendiente(let motivo):
            // El vídeo mantiene su encuadre; los mensajes pueden desplazarse
            // dentro de ese espacio cuando crece el texto.
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.onSurfaceVariant.opacity(0.5))
                        .accessibilityHidden(true)

                    Text(L.t("Seña pendiente de grabación", "Sign not recorded yet"))
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L.aviso(motivo))
                        .font(.caption2)
                        .foregroundStyle(.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.surfaceContainerLow)
            )
            .onAppear {
                if activacion { presenter.videoNoDisponible(id: id) }
            }
        }
    }

    private func etiqueta(_ texto: String, sistema: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: sistema).font(.system(size: 8, weight: .semibold))
                .accessibilityHidden(true)
            Text(texto).font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var botonCerrar: some View {
        Button { presenter.ocultar() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.onSurfaceVariant)
                .background(Circle().fill(Color(.systemBackground)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Cerrar", "Close"))
        .accessibilityHint(L.t("Continúa con la acción pendiente, si la hay", "Continues the pending action, if any"))
    }
}
