//
//  SeniasOverlay.swift
//  RutaUTP
//
//  Modo Señas: el texto señable se vuelve tocable y muestra la seña en LSP.
//
//  Tres piezas:
//   1. SeniasPlayerView  -> reproduce el clip en bucle (AVPlayerLooper).
//   2. SeniasOverlay     -> tarjeta del miniplayer.
//   3. .seniable(clave:) -> modificador que se aplica al texto.
//
//  La tarjeta vive en SU PROPIA UIWindow a nivel .alert (SeniasOverlayVentana),
//  así se ve por encima de TODO, incluidos sheets y fullScreenCovers — que de
//  otro modo tapan el miniplayer y las señas dentro de un sheet no se ven.
//
//  Si no hay clip, NO se inventa una seña: se muestra un estado honesto de
//  "pendiente de grabación". El contenido real se añade después en
//  senias/clips/<idioma>/ sin tocar una línea de este archivo.
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
        layer.cornerRadius = 16
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
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        )
        .overlay(alignment: .topTrailing) { botonCerrar }
        .accessibilityElement(children: .contain)
    }

    private func encabezado(clave: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.appPrimary)

            Text(servicio.texto(clave: clave))
                .font(.system(size: 14, weight: .semibold))
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
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if senia.esPlaceholder {
                    etiqueta(L.t("Clip de prueba", "Test clip"), sistema: "exclamationmark.triangle.fill", color: .orange)
                }
            }

        case .pendiente(let motivo):
            VStack(spacing: 8) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.onSurfaceVariant.opacity(0.5))

                Text(L.t("Seña pendiente de grabación", "Sign not recorded yet"))
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(motivo)
                    .font(.system(size: 10))
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(width: 156, height: 156)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.onSurfaceVariant)
                .background(Circle().fill(Color(.systemBackground)))
        }
        .padding(6)
        .accessibilityLabel(L.t("Cerrar", "Close"))
    }
}

// MARK: - 2b. Ventana propia (por encima de sheets y covers)

/// Muestra `SeniasOverlay` en una UIWindow dedicada a nivel `.alert + 1`.
///
/// Los sheets y fullScreenCovers se presentan por encima del contenido de la
/// ventana principal, así que el overlay raíz quedaba DEBAJO y las señas
/// dentro de un sheet (ej. "Guardar lugar") no se veían. Una ventana a nivel
/// alert flota sobre todo eso. Sólo hilo principal (se llama desde
/// SeniasPresenter, que siempre se toca desde la UI).
final class SeniasOverlayVentana {

    static let shared = SeniasOverlayVentana()

    private var ventana: VentanaSenias?

    private init() {}

    /// Sincroniza la ventana con el estado del presentador.
    func actualizar(hayClave: Bool) {
        if hayClave {
            mostrar()
        } else {
            ventana?.isHidden = true
        }
    }

    private func mostrar() {
        guard let escena = escenaActiva() else { return }

        if let ventana {
            // Reubica por si hubo rotación desde la última vez.
            ventana.frame = escena.coordinateSpace.bounds
            ventana.isHidden = false
            return
        }

        let ventana = VentanaSenias(frame: escena.coordinateSpace.bounds)
        ventana.windowScene = escena
        ventana.windowLevel = .alert + 1
        ventana.backgroundColor = .clear
        // La ventana se crea tarde (primer seña visible) y ya se perdió el
        // onChange del tema: aplica el mismo escritor que usa RootView.
        ventana.overrideUserInterfaceStyle =
            UserDefaults.standard.bool(forKey: "isDarkMode") ? .dark : .light

        let controlador = UIHostingController(rootView: SeniasOverlay().ignoresSafeArea())
        controlador.view.backgroundColor = .clear
        ventana.rootViewController = controlador

        self.ventana = ventana
        ventana.isHidden = false
    }

    private func escenaActiva() -> UIWindowScene? {
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return escenas.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        } ?? escenas.first
    }
}

/// UIWindow del miniplayer: transparente y con toque libre — los toques que
/// no caen sobre la tarjeta pasan a la app de debajo sin bloquear nada.
private final class VentanaSenias: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let vista = super.hitTest(point, with: event) else { return nil }
        // Si SwiftUI no reclama el toque, hitTest devuelve la vista raíz del
        // hosting controller (o nil): en ambos casos se deja pasar.
        return vista === rootViewController?.view ? nil : vista
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
