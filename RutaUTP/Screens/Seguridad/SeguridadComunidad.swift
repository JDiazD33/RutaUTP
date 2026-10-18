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
@MainActor
final class ComunidadReacciones: ObservableObject {
    /// Mantiene votos y comentarios al cambiar de pestaña durante la sesión.
    static let compartida = ComunidadReacciones()
    enum Voto { case ninguno, util, noUtil }

    struct Comentario: Identifiable {
        let id = UUID()
        let texto: String
    }

    @Published private var votos: [UUID: Voto] = [:]
    @Published private var comentarios: [UUID: [Comentario]] = [:]

    func comentariosAgregados(_ reporte: ReporteComunidad) -> [Comentario] {
        comentarios[reporte.id] ?? []
    }

    func totalComentarios(_ reporte: ReporteComunidad) -> Int {
        reporte.comentarios + comentariosAgregados(reporte).count
    }

    @discardableResult
    func agregarComentario(_ texto: String, a reporte: ReporteComunidad) -> Bool {
        let limpio = String(texto.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !limpio.isEmpty else { return false }
        comentarios[reporte.id, default: []].append(Comentario(texto: limpio))
        AppHaptics.success()
        return true
    }

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
    var abrir: () -> Void = {}
    var comentar: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: abrir) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L.t("Ver publicación", "View post"))

            Divider().overlay(Color.outlineVariant.opacity(0.2))
            HStack(spacing: 8) {
                votoButton(.util)
                votoButton(.noUtil)

                Spacer(minLength: 0)
                Button(action: comentar) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(reacciones.totalComentarios(reporte))")
                            .font(.bodySm)
                    }
                    .foregroundStyle(.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.f("{0} comentarios", "{0} comments", ["\(reacciones.totalComentarios(reporte))"]))
                .accessibilityHint(L.t("Ver y añadir comentarios", "Read and add comments"))
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Publicación de ", "Post by ") + reporte.nombre)
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
                Text("\(cantidad)").font(.bodySm)
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(esUtil ? L.t("Me gusta", "Like") : L.t("No me gusta", "Dislike"))
        .accessibilityValue(L.f("{0} votos", "{0} votes", ["\(cantidad)"]))
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

// MARK: - Reporte Detail Sheet
struct ReporteDetailSheet: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones
    var comentarAlAbrir = false
    @Environment(\.dismiss) private var dismiss
    @State private var comentario = ""
    @FocusState private var comentarioEnfocado: Bool

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
            HStack {
                Text(L.t("Publicación", "Post")).font(.headlineSm)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .foregroundStyle(Color.onSurfaceVariant).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Cerrar", "Close"))
            }
            .padding(.horizontal, 20)
            ScrollViewReader { proxy in
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
                        Text(L.f("COMENTARIOS ({0})", "COMMENTS ({0})", ["\(reacciones.totalComentarios(reporte))"]))
                            .font(.labelCapsMd)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)

                        if reacciones.totalComentarios(reporte) == 0 {
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
                        ForEach(reacciones.comentariosAgregados(reporte)) { nuevo in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.t("Tú", "You")).font(.bodySmMedium)
                                Text(nuevo.texto).font(.bodySm).textSelection(.enabled)
                            }
                            .foregroundStyle(Color.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text(L.t("Los comentarios se conservan durante esta sesión de demostración.",
                                 "Comments are kept for this demo session."))
                            .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                        Color.clear.frame(height: 1).id("finComentarios")
                    }
                    .padding(20)
                }
                .onAppear {
                    if comentarAlAbrir { proxy.scrollTo("finComentarios", anchor: .bottom) }
                }
                .onChange(of: reacciones.totalComentarios(reporte)) { _, _ in
                    withAnimation { proxy.scrollTo("finComentarios", anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { campoComentario }
        .task {
            if comentarAlAbrir {
                await Task.yield()
                comentarioEnfocado = true
            }
        }
    }

    private var campoComentario: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L.t("Tu comentario…", "Your comment…"), text: $comentario, axis: .vertical)
                .font(.bodyMd).lineLimit(1...4)
                .focused($comentarioEnfocado)
                .padding(12)
                .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: comentario) { _, texto in
                    if texto.count > 300 { comentario = String(texto.prefix(300)) }
                }
                .submitLabel(.send)
                .onSubmit(enviarComentario)
            Button(action: enviarComentario) {
                Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.onPrimaryFill)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(comentario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L.t("Añadir comentario", "Add comment"))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.appSurface)
    }

    private func enviarComentario() {
        if reacciones.agregarComentario(comentario, a: reporte) { comentario = "" }
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
                Text("\(cantidad)").font(.bodySmMedium)
            }
            .foregroundStyle(activo ? color : Color.onSurfaceVariant)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(activo ? color.opacity(0.10) : Color.surfaceContainerLow)
            )
            .overlay(
                Capsule().stroke(activo ? color.opacity(0.35) : Color.outlineVariant.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(esUtil ? L.t("Me gusta", "Like") : L.t("No me gusta", "Dislike"))
        .accessibilityValue(L.f("{0} votos", "{0} votes", ["\(cantidad)"]))
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
                    Image(foto.asset).resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color.surfaceContainerLow)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(L.t("Foto de archivo: ", "Archive photo: ") + foto.lugar)
            .accessibilityValue(foto.descripcionLocalizada)
            Label(foto.lugar, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onSurface)
            Text(L.t("PUBLICACIÓN DEMO · FOTO DE REFERENCIA", "DEMO POST · REFERENCE PHOTO"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.onSurfaceVariant)
            Text(foto.atribucion)
                .font(.system(size: 10))
                .foregroundStyle(Color.onSurfaceVariant)
            if detalle {
                Text(L.t("Autor del post ficticio. La foto es de archivo y no documenta un incidente actual. Se conserva el encuadre; las nuevas fotos usan una copia de menor resolución.",
                         "Fictional post author. This archive photo does not document a current incident. Framing is preserved; new photos use a lower-resolution copy."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                HStack(spacing: 16) {
                    if let url = URL(string: foto.fuente) { Link(L.t("Ver fuente", "View source"), destination: url) }
                    if let licenciaURL = foto.licenciaURL, let url = URL(string: licenciaURL) {
                        Link(L.t("Licencia", "License"), destination: url)
                    }
                }
                .font(.caption.weight(.medium))
            }
        }
    }
}
