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
    @Published private var reportes: [UUID: ReportePublicacion] = [:]
    @Published private var ocultas: Set<UUID> = []

    // MARK: Reportes (misma vida que votos y comentarios: la sesión)

    func reporteEnviado(_ reporte: ReporteComunidad) -> ReportePublicacion? {
        reportes[reporte.id]
    }

    func estaOculta(_ reporte: ReporteComunidad) -> Bool {
        ocultas.contains(reporte.id)
    }

    func reportar(_ reporte: ReporteComunidad, _ nuevo: ReportePublicacion, ocultar: Bool) {
        reportes[reporte.id] = nuevo
        if ocultar { ocultas.insert(reporte.id) }
        AppHaptics.success()
    }

    func retirarReporte(_ reporte: ReporteComunidad) {
        reportes[reporte.id] = nil
        ocultas.remove(reporte.id)
        AppHaptics.selection()
    }

    /// Vuelve a mostrar en el feed una publicación reportada; el reporte sigue.
    func mostrar(_ reporte: ReporteComunidad) {
        ocultas.remove(reporte.id)
        AppHaptics.selection()
    }

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

    @State private var reportando = false
    @State private var confirmarRetiro = false
    @State private var verFoto = false

    var body: some View {
        Group {
            if reacciones.estaOculta(reporte) {
                tarjetaOculta
            } else {
                tarjeta
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
        // Mantener pulsada la tarjeta: la vista previa conserva su fondo.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu { menuContextual }
        .flujoReportePublicacion(reporte, reacciones: reacciones, presentado: $reportando)
        .confirmationDialog(L.t("Ya reportaste esta publicación", "You already reported this post"),
                            isPresented: $confirmarRetiro, titleVisibility: .visible) {
            Button(L.t("Retirar reporte", "Withdraw report"), role: .destructive) {
                reacciones.retirarReporte(reporte)
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var menuContextual: some View {
        if reacciones.estaOculta(reporte) {
            Button { reacciones.mostrar(reporte) } label: {
                Label(L.t("Mostrar", "Show"), systemImage: "eye")
            }
        } else {
            Button(action: abrir) {
                Label(L.t("Ver publicación", "View post"), systemImage: "text.bubble")
            }
            if reporte.foto != nil {
                Button { verFoto = true } label: {
                    Label(L.t("Ver foto", "View photo"), systemImage: "photo")
                }
            }
        }
        Divider()
        Button(role: reacciones.reporteEnviado(reporte) == nil ? .destructive : nil,
               action: alternarReporte) {
            Label(accionReporteTitulo,
                  systemImage: reacciones.reporteEnviado(reporte) == nil ? "flag" : "flag.slash")
        }
    }

    private var tarjeta: some View {
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

                    if reacciones.reporteEnviado(reporte) != nil {
                        EtiquetaReportada()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(L.t("Ver publicación", "View post"))
            // VoiceOver: las mismas acciones que la tarjeta ofrece al tacto,
            // sin recorrer cada botón por separado.
            .accessibilityActions {
                Button(L.t("Me gusta", "Like")) { reacciones.votar(reporte, a: .util) }
                Button(L.t("No me gusta", "Dislike")) { reacciones.votar(reporte, a: .noUtil) }
                Button(L.t("Comentar", "Comment"), action: comentar)
                if reporte.foto != nil {
                    Button(L.t("Ver foto", "View photo")) { verFoto = true }
                }
                Button(accionReporteTitulo, action: alternarReporte)
            }

            // Fuera del botón de la tarjeta: tocar la foto la abre ampliada.
            if let foto = reporte.foto {
                FotoReporteView(foto: foto, mostrarVisor: $verFoto)
            }

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Publicación de ", "Post by ") + reporte.nombre)
    }

    /// Sustituye a la publicación que el usuario reportó y decidió ocultar.
    private var tarjetaOculta: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                textoOculta
                Spacer(minLength: 0)
                botonMostrar
            }
            VStack(alignment: .leading, spacing: 8) {
                textoOculta
                botonMostrar
            }
        }
    }

    private var textoOculta: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Publicación oculta", "Hidden post"))
                    .font(.bodyMdMedium)
                    .foregroundStyle(Color.onSurface)
                Text(L.t("La reportaste y no se muestra en tu feed.", "You reported it and it's hidden from your feed."))
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "eye.slash")
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .accessibilityElement(children: .combine)
    }

    private var botonMostrar: some View {
        Button(L.t("Mostrar", "Show")) { reacciones.mostrar(reporte) }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityLabel(L.t("Mostrar publicación de ", "Show post by ") + reporte.nombre)
    }

    private var accionReporteTitulo: String {
        reacciones.reporteEnviado(reporte) == nil
            ? L.t("Reportar publicación", "Report post")
            : L.t("Retirar reporte", "Withdraw report")
    }

    private func alternarReporte() {
        if reacciones.reporteEnviado(reporte) == nil {
            reportando = true
        } else {
            confirmarRetiro = true
        }
    }

    @ViewBuilder
    private func votoButton(_ tipo: ComunidadReacciones.Voto) -> some View {
        let esUtil = tipo == .util
        let activo = reacciones.voto(para: reporte) == tipo
        let cantidad = esUtil ? reacciones.utiles(reporte) : reacciones.noUtiles(reporte)
        let color: Color = esUtil ? .appAccent : .appError

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

/// Indica en la tarjeta y en el detalle que el usuario ya reportó la publicación.
struct EtiquetaReportada: View {
    var body: some View {
        Label(L.t("Reportaste esta publicación", "You reported this post"), systemImage: "flag.fill")
            .font(.bodySmMedium)
            .foregroundStyle(Color.appError)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Reporte Detail Sheet
struct ReporteDetailSheet: View {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones
    var comentarAlAbrir = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var comentario = ""
    @FocusState private var comentarioEnfocado: Bool
    @State private var reportando = false
    @State private var confirmarRetiro = false
    @State private var verFoto = false

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
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        autor

                        if let enviado = reacciones.reporteEnviado(reporte) {
                            avisoReportada(enviado)
                        }

                        Text(reporte.cuerpoLocalizado)
                            .font(.bodyLg)
                            .foregroundStyle(.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if let foto = reporte.foto {
                            FotoReporteView(foto: foto, detalle: true, mostrarVisor: $verFoto)
                        }

                        // Votos interactivos y reporte
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                votoButton(.util)
                                votoButton(.noUtil)
                                Spacer(minLength: 8)
                                botonReportar
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    votoButton(.util)
                                    votoButton(.noUtil)
                                }
                                botonReportar
                            }
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
            .safeAreaInset(edge: .bottom, spacing: 0) { campoComentario }
            .background(Color.appSurface)
            // Barra nativa: el título ya no queda pegado al indicador de
            // arrastre ni se recorta con tamaños de texto grandes.
            .navigationTitle(L.t("Publicación", "Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .accessibilityLabel(L.t("Cerrar publicación", "Close post"))
                }
            }
        }
        .tint(Color.appAccent)
        .flujoReportePublicacion(reporte, reacciones: reacciones, presentado: $reportando) { oculta in
            // Una publicación oculta ya no está en el feed: se vuelve a él.
            if oculta { dismiss() }
        }
        .confirmationDialog(L.t("Ya reportaste esta publicación", "You already reported this post"),
                            isPresented: $confirmarRetiro, titleVisibility: .visible) {
            Button(L.t("Retirar reporte", "Withdraw report"), role: .destructive) {
                reacciones.retirarReporte(reporte)
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
        .accessibilityAction(.escape) { dismiss() }
        .task {
            if comentarAlAbrir {
                await Task.yield()
                comentarioEnfocado = true
            }
        }
    }

    // MARK: Autor

    /// Con tamaños de accesibilidad la etiqueta del tipo baja bajo el nombre
    /// en lugar de comprimirlo.
    private var autor: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(reporte.avatarColor).frame(width: 48, height: 48)
                    Text(reporte.iniciales)
                        .font(.headlineSm)
                        .foregroundStyle(reporte.avatarForeground)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reporte.nombre)
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(reporte.tiempoLocalizado)
                        .font(.labelCapsSm)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(reporte.tipo.titulo.uppercased())
                .font(.labelCapsMd)
                .foregroundStyle(reporte.tipo.foreground)
                .appTracking(AppTracking.wideLabel)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(reporte.tipo.background))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Reporte

    private func avisoReportada(_ enviado: ReportePublicacion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EtiquetaReportada()
            Text(L.f("Motivo: {0}", "Reason: {0}", [enviado.motivo.titulo]))
                .font(.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if !enviado.detalle.isEmpty {
                Text(enviado.detalle)
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appError.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var botonReportar: some View {
        let reportada = reacciones.reporteEnviado(reporte) != nil
        return Button {
            if reportada { confirmarRetiro = true } else { reportando = true }
        } label: {
            Label(reportada ? L.t("Reportada", "Reported") : L.t("Reportar", "Report"),
                  systemImage: reportada ? "flag.fill" : "flag")
                .font(.bodySmMedium)
                .foregroundStyle(reportada ? Color.appError : Color.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(reportada ? Color.appError.opacity(0.10) : Color.surfaceContainerLow)
                )
                .overlay(
                    Capsule().stroke(reportada ? Color.appError.opacity(0.35) : Color.outlineVariant.opacity(0.30),
                                     lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Reportar publicación", "Report post"))
        .accessibilityValue(reportada ? L.t("Reportada", "Reported") : "")
        .accessibilityHint(reportada
            ? L.t("Permite retirar tu reporte", "Lets you withdraw your report")
            : L.t("Indica si es falsa, infringe derechos u ofende", "Tell us if it's false, infringes rights or is offensive"))
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
        let color: Color = esUtil ? .appAccent : .appError

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
    /// Visor a pantalla completa; el contenedor lo enlaza para abrirlo también
    /// desde sus acciones de VoiceOver o su menú contextual.
    @Binding var mostrarVisor: Bool

    @Namespace private var transicion
    @ScaledMetric(relativeTo: .body) private var tamanoIconoAmpliar: CGFloat = 30

    init(foto: FotoComunidad, detalle: Bool = false, mostrarVisor: Binding<Bool>) {
        self.foto = foto
        self.detalle = detalle
        _mostrarVisor = mostrarVisor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                AppHaptics.impact(.light)
                mostrarVisor = true
            } label: {
                miniatura
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: tamanoIconoAmpliar, height: tamanoIconoAmpliar)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .modifier(OrigenZoomFoto(id: foto.asset, espacio: transicion))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Foto de archivo: ", "Archive photo: ") + foto.lugar)
            .accessibilityValue(foto.descripcionLocalizada)
            .accessibilityHint(L.t("Abre la foto a pantalla completa", "Opens the photo full screen"))
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
        .fullScreenCover(isPresented: $mostrarVisor) {
            VisorFotoComunidad(foto: foto)
                .modifier(DestinoZoomFoto(id: foto.asset, espacio: transicion))
        }
    }

    @ViewBuilder
    private var miniatura: some View {
        if detalle {
            Image(foto.asset).resizable().scaledToFit()
        } else {
            Image(foto.asset).resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color.surfaceContainerLow)
        }
    }
}
