//
//  SeniasOverlay.swift
//  RutaUTP
//
//  Modo Señas: el texto señable se vuelve tocable y muestra la seña en LSP.
//
//  Tres piezas:
//   1. SeniasPlayerView  -> reproduce el clip en bucle (AVPlayerLooper).
//   2. SeniasOverlay     -> tarjeta que se muestra sobre toda la app.
//   3. .seniable(clave:) -> modificador que se aplica al texto.
//
//  Si no hay clip, NO se inventa una seña: se muestra un estado honesto de
//  "pendiente de grabación". El contenido real se añade después en senias/clips
//  sin tocar una línea de este archivo.
//

import SwiftUI
import AVFoundation

// MARK: - 1. Reproductor en bucle

/// UIView que mantiene un clip en bucle continuo.
final class SeniasPlayerUIView: UIView {

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var urlActual: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("no usado") }

    func configurar(url: URL) {
        // Evita reiniciar el bucle en cada updateUIView.
        guard url != urlActual else { return }
        urlActual = url
        limpiar()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true                 // las señas son mudas por definición

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.cornerRadius = 14
        layer.masksToBounds = true
        self.layer.addSublayer(layer)

        looper = AVPlayerLooper(player: queue, templateItem: item)
        queuePlayer = queue
        queue.play()
    }

    func limpiar() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        urlActual = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer.sublayers?.first as? AVPlayerLayer)?.frame = bounds
    }
}

struct SeniasPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SeniasPlayerUIView {
        let vista = SeniasPlayerUIView()
        vista.configurar(url: url)
        return vista
    }

    func updateUIView(_ uiView: SeniasPlayerUIView, context: Context) {
        uiView.configurar(url: url)
    }

    static func dismantleUIView(_ uiView: SeniasPlayerUIView, coordinator: ()) {
        uiView.limpiar()
    }
}

// MARK: - 2. Overlay

struct SeniasOverlay: View {

    @ObservedObject private var presenter = SeniasPresenter.shared
    @State private var aparecio = false

    private let servicio = SeniasService.shared

    // Mini-player flotante: esquina inferior derecha, por encima del
    // BottomNavBar, sin tapar el contenido. Al tocar otro texto señable,
    // el clip se reemplaza en el sitio.
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let clave = presenter.claveVisible {
                    tarjeta(clave: clave)
                        .scaleEffect(aparecio ? 1 : 0.9)
                        .opacity(aparecio ? 1 : 0)
                }
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 104) // justo encima del BottomNavBar flotante
        .animation(.easeOut(duration: 0.22), value: presenter.claveVisible)
        .onChange(of: presenter.claveVisible) { _, nuevo in
            if nuevo != nil {
                aparecio = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { aparecio = true }
            } else {
                aparecio = false
            }
        }
    }

    private func tarjeta(clave: String) -> some View {
        VStack(spacing: 8) {
            encabezado(clave: clave)
            contenido(clave: clave)
        }
        .padding(10)
        .frame(width: 152)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .overlay(alignment: .topTrailing) { botonCerrar }
        .accessibilityElement(children: .contain)
    }

    private func encabezado(clave: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.appPrimary)

            Text(servicio.texto(clave: clave))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func contenido(clave: String) -> some View {
        switch servicio.estado(para: clave) {

        case .clip(let url, let senia):
            VStack(spacing: 6) {
                SeniasPlayerView(url: url)
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if senia.esPlaceholder {
                    etiqueta(L.t("Clip de prueba", "Test clip"), sistema: "exclamationmark.triangle.fill", color: .orange)
                }
            }

        case .pendiente(let motivo):
            VStack(spacing: 8) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.onSurfaceVariant.opacity(0.5))

                Text(L.t("Seña pendiente de grabación", "Sign not recorded yet"))
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(motivo)
                    .font(.system(size: 9))
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(width: 128, height: 128)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLow)
            )
        }
    }

    private func etiqueta(_ texto: String, sistema: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: sistema).font(.system(size: 8, weight: .semibold))
            Text(texto).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var botonCerrar: some View {
        Button { presenter.ocultar() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.onSurfaceVariant)
                .background(Circle().fill(Color(.systemBackground)))
        }
        .padding(6)
        .accessibilityLabel(L.t("Cerrar", "Close"))
    }
}

// MARK: - 3. Modificador

/// Vuelve un texto tocable cuando el Modo Señas está activado.
///
/// Con el modo apagado no añade NADA: ni gesto ni trait de accesibilidad.
struct SeniableModifier: ViewModifier {

    let clave: String
    @AppStorage(SeniasService.llaveModo) private var modoActivo = false
    @ObservedObject private var presenter = SeniasPresenter.shared

    func body(content: Content) -> some View {
        if modoActivo {
            content
                // simultaneousGesture: funciona también sobre textos que están
                // DENTRO de un Button (chips, CTAs). El tap muestra la seña y
                // el botón sigue ejecutando su acción normal.
                .simultaneousGesture(
                    TapGesture().onEnded { presenter.mostrar(clave: clave) }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(L.t("Toca para ver la seña en lengua de señas", "Tap to see the sign language translation"))
        } else {
            content
        }
    }
}

extension View {
    /// Marca un texto como señable. Requiere que el texto use `L.signable`.
    func seniable(_ clave: String) -> some View {
        modifier(SeniableModifier(clave: clave))
    }

    /// Variante para modelos donde la clave puede no existir (nil = no señable).
    @ViewBuilder
    func seniable(_ clave: String?) -> some View {
        if let clave {
            modifier(SeniableModifier(clave: clave))
        } else {
            self
        }
    }
}
