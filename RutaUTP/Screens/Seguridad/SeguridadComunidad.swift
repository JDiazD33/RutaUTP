//
//  SeguridadComunidad.swift
//  RutaUTP
//
//  Comunidad de demostración: votos, tarjeta de publicación, detalle
//  y la vista de foto de referencia.
//  
//  Estaba dentro de `SeguridadView.swift`, que mezclaba la pantalla con
//  todo su contenido.

import SwiftUI
// MARK: - Votos de la comunidad (like / dislike)
/// Reacción del usuario por reporte. Vive en la sesión (demo; no persiste).
/// Tocar el mismo voto lo retira; votar el lado opuesto cambia el voto.
final class ComunidadReacciones: ObservableObject {
    enum Voto { case ninguno, util, noUtil }

    @Published private var votos: [UUID: Voto] = [:]

    func voto(para reporte: ReporteComunidad) -> Voto {
        votos[reporte.id] ?? .ninguno
    }

    func votar(_ reporte: ReporteComunidad, a nuevo: Voto) {
        votos[reporte.id] = (voto(para: reporte) == nuevo) ? .ninguno : nuevo
        AppHaptics.selection()
    }

    func utiles(_ reporte: ReporteComunidad) -> Int {
        reporte.utiles + (voto(para: reporte) == .util ? 1 : 0)
    }

    func noUtiles(_ reporte: ReporteComunidad) -> Int {
        reporte.dislikes + (voto(para: reporte) == .noUtil ? 1 : 0)
    }
}

// MARK: - Reporte card
struct ReporteCard: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(reporte.avatarColor).frame(width: 40, height: 40)
                    Text(reporte.iniciales)
                        .font(.labelCapsMd)
                        .foregroundStyle(reporte.avatarForeground)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reporte.nombre)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(reporte.tiempoLocalizado)
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
                Spacer()
                Text(reporte.tipo.titulo.uppercased())
                    .font(.labelCapsSm)
                    .foregroundStyle(reporte.tipo.foreground)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(reporte.tipo.background))
            }

            Text(reporte.cuerpoLocalizado)
                .font(.system(size: 15))
                .lineSpacing(3)
                .lineLimit(4)
                .foregroundStyle(.onSurface)

            if let foto = reporte.foto {
                FotoReporteView(foto: foto)
            }

            Divider().overlay(Color.outlineVariant.opacity(0.2))
            HStack(spacing: 8) {
                votoButton(.util)
                votoButton(.noUtil)

                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(reporte.comentarios)")
                        .font(.bodySm)
                }
                .foregroundStyle(.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L.t("\(reporte.comentarios) comentarios", "\(reporte.comentarios) comments"))

                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func votoButton(_ tipo: ComunidadReacciones.Voto) -> some View {
        let esUtil = tipo == .util
        let activo = reacciones.voto(para: reporte) == tipo
        let cantidad = esUtil ? reacciones.utiles(reporte) : reacciones.noUtiles(reporte)
        let color: Color = esUtil ? .appPrimary : .appError

        Button {
            reacciones.votar(reporte, a: tipo)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: esUtil
                      ? (activo ? "hand.thumbsup.fill" : "hand.thumbsup")
                      : (activo ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                    .font(.system(size: 13, weight: .semibold))
                if esUtil {
                    Text(L.t("Útil", "Useful") + " (\(cantidad))")
                        .font(.bodySm)
                } else {
                    Text("\(cantidad)")
                        .font(.bodySm)
                }
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(esUtil ? L.t("Me es útil", "Helpful") : L.t("No me es útil", "Not helpful"))
        .accessibilityValue(L.t("\(cantidad) votos", "\(cantidad) votes"))
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

// MARK: - Reporte Detail Sheet
struct ReporteDetailSheet: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones
    @Environment(\.dismiss) private var dismiss

    /// Comentarios de muestra, deterministas por reporte (misma semilla →
    /// mismos comentarios mientras la sesión esté viva).
    private var comentariosMuestra: [(nombre: String, iniciales: String, texto: String)] {
        let semilla = reporte.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let autores = [("Luisa P.", "LP"), ("Marco T.", "MT"), ("Diana R.", "DR"),
                       ("Sergio V.", "SV"), ("Pilar A.", "PA"), ("César H.", "CH")]
        let textos = [
            L.t("Totalmente de acuerdo.", "Totally agree."),
            L.t("Gracias por avisar a tiempo.", "Thanks for the heads-up."),
            L.t("Me pasó igual ayer por la mañana.", "Same thing happened to me yesterday morning."),
            L.t("Justo venía de ahí, horrible.", "I was just there, it was awful."),
            L.t("Buen dato, no lo sabía.", "Good to know, I had no idea."),
            L.t("Hay que tener cuidado ahí siempre.", "We always have to be careful there."),
            L.t("Confirmo, sigue igual.", "Confirmed, still the same.")
        ]
        return (0..<reporte.comentarios).map { k in
            let autor = autores[(semilla + k) % autores.count]
            let texto = textos[(semilla + k * 2) % textos.count]
            return (autor.0, autor.1, texto)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Autor
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(reporte.avatarColor).frame(width: 48, height: 48)
                            Text(reporte.iniciales)
                                .font(.headlineSm)
                                .foregroundStyle(reporte.avatarForeground)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reporte.nombre)
                                .font(.headlineSm)
                            Text(reporte.tiempoLocalizado)
                                .font(.labelCapsSm)
                                .foregroundStyle(.onSurfaceVariant)
                                .appTracking(AppTracking.wideLabel)
                        }
                        Spacer()
                        Text(reporte.tipo.titulo.uppercased())
                            .font(.labelCapsMd)
                            .foregroundStyle(reporte.tipo.foreground)
                            .appTracking(AppTracking.wideLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(reporte.tipo.background))
                    }

                    Text(reporte.cuerpoLocalizado)
                        .font(.bodyLg)
                        .foregroundStyle(.onSurface)

                    if let foto = reporte.foto {
                        FotoReporteView(foto: foto, detalle: true)
                    }

                    // Votos interactivos
                    HStack(spacing: 10) {
                        votoButton(.util)
                        votoButton(.noUtil)
                        Spacer()
                    }

                    Divider()

                    // Comentarios
                    Text(L.t("COMENTARIOS (\(reporte.comentarios))", "COMMENTS (\(reporte.comentarios))"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)

                    if reporte.comentarios == 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 18))
                                .foregroundStyle(.onSurfaceVariant.opacity(0.5))
                            Text(L.t("Aún no hay comentarios. Sé el primero en comentar.",
                                     "No comments yet. Be the first to comment."))
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(comentariosMuestra.enumerated()), id: \.offset) { _, c in
                                HStack(alignment: .top, spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color.surfaceContainerHigh).frame(width: 30, height: 30)
                                        Text(c.iniciales)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.onSurfaceVariant)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.nombre)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.onSurface)
                                        Text(c.texto)
                                            .font(.bodySm)
                                            .foregroundStyle(.onSurfaceVariant)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.surfaceContainerLow)
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }

            Button { dismiss() } label: {
                Text(L.t("Cerrar", "Close"))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                    .foregroundStyle(.white)
                    .font(.bodyMdMedium)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func votoButton(_ tipo: ComunidadReacciones.Voto) -> some View {
        let esUtil = tipo == .util
        let activo = reacciones.voto(para: reporte) == tipo
        let cantidad = esUtil ? reacciones.utiles(reporte) : reacciones.noUtiles(reporte)
        let color: Color = esUtil ? .appPrimary : .appError

        Button {
            reacciones.votar(reporte, a: tipo)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: esUtil
                      ? (activo ? "hand.thumbsup.fill" : "hand.thumbsup")
                      : (activo ? "hand.thumbsdown.fill" : "hand.thumbsdown"))
                    .font(.system(size: 14, weight: .semibold))
                Text(esUtil
                     ? L.t("Útil", "Useful") + " (\(cantidad))"
                     : L.t("No útil", "Not helpful") + " (\(cantidad))")
                    .font(.bodySmMedium)
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.outlineVariant.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}


// MARK: - Foto de referencia compartida entre publicación y detalle
struct FotoReporteView: View {
    let foto: FotoComunidad
    var detalle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if detalle {
                    Image(foto.asset).resizable().scaledToFit()
                } else {
                    GeometryReader { geo in
                        Image(foto.asset).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: 180)
                            .clipped()
                    }
                    .frame(height: 180)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(L.t("Foto de archivo: ", "Archive photo: ") + foto.lugar)
            Label(foto.lugar, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onSurface)
            Text(L.t("PUBLICACIÓN DEMO · FOTO DE REFERENCIA", "DEMO POST · REFERENCE PHOTO"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.onSurfaceVariant)
            Text("© " + foto.autor + " · " + foto.fecha + " · CC BY-SA " + foto.licencia)
                .font(.system(size: 10))
                .foregroundStyle(Color.onSurfaceVariant)
            if detalle {
                Text(L.t("Autor del post ficticio. La foto es de archivo y no documenta un incidente actual. Vista previa recortada; imagen completa arriba.",
                         "Fictional post author. This archive photo does not document a current incident. Cropped preview; full image above."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                HStack(spacing: 16) {
                    if let url = URL(string: foto.fuente) { Link(L.t("Ver fuente", "View source"), destination: url) }
                    if let url = URL(string: foto.licenciaURL) { Link(L.t("Licencia", "License"), destination: url) }
                }
                .font(.caption.weight(.medium))
            }
        }
    }
}

