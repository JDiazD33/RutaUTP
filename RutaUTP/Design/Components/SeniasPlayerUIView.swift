//
//  SeniasPlayerUIView.swift
//  RutaUTP
//
//  Reproductor de un clip de seña (Modo Señas): conserva el AVQueuePlayer
//  entre actualizaciones y descarta los callbacks de una carga anterior.
//

import UIKit
import AVFoundation

// MARK: - 1. Reproductor

/// Conserva el reproductor entre actualizaciones y descarta callbacks antiguos.
final class SeniasPlayerUIView: UIView {

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var urlActual: URL?
    private var idActual: UUID?
    private var repiteActual = true
    private var encuadreCompletoActual = false
    private var generacion = UUID()
    private var observadorFin: NSObjectProtocol?
    private var observadorError: NSObjectProtocol?
    private var observadorEstado: NSKeyValueObservation?
    private var resultadoEntregado = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("no usado") }

    func configurar(
        url: URL, id: UUID, repetir: Bool, encuadreCompleto: Bool = false,
        alFinalizar: (() -> Void)? = nil, alFallar: (() -> Void)? = nil
    ) {
        guard url != urlActual || id != idActual || repetir != repiteActual
                || encuadreCompleto != encuadreCompletoActual else { return }
        limpiar()
        urlActual = url
        idActual = id
        repiteActual = repetir
        encuadreCompletoActual = encuadreCompleto
        let carga = generacion

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true

        let layer = AVPlayerLayer(player: queue)
        // La guía vertical debe caber completa en la tarjeta cuadrada.
        // El encuadre es independiente del bucle o del cierre al terminar.
        layer.videoGravity = encuadreCompleto || !repetir ? .resizeAspect : .resizeAspectFill
        layer.frame = bounds
        layer.cornerRadius = 16
        layer.masksToBounds = true
        self.layer.addSublayer(layer)

        if repetir {
            looper = AVPlayerLooper(player: queue, templateItem: item)
        } else {
            queue.insert(item, after: nil)
            observadorFin = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.entregarResultado(carga: carga, accion: alFinalizar)
            }
            observadorError = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.entregarResultado(carga: carga, accion: alFallar)
            }
            observadorEstado = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.entregarResultado(carga: carga, accion: alFallar)
                }
            }
        }
        queuePlayer = queue
        queue.play()
    }

    func limpiar() {
        // Un fin ya encolado no puede cerrar otro idioma ni otra activación.
        generacion = UUID()
        resultadoEntregado = false
        if let observadorFin { NotificationCenter.default.removeObserver(observadorFin) }
        if let observadorError { NotificationCenter.default.removeObserver(observadorError) }
        observadorFin = nil
        observadorError = nil
        observadorEstado?.invalidate()
        observadorEstado = nil
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        urlActual = nil
        idActual = nil
    }

    private func entregarResultado(carga: UUID, accion: (() -> Void)?) {
        guard carga == generacion, !resultadoEntregado else { return }
        resultadoEntregado = true
        accion?()
    }

    deinit {
        if let observadorFin { NotificationCenter.default.removeObserver(observadorFin) }
        if let observadorError { NotificationCenter.default.removeObserver(observadorError) }
        observadorEstado?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer.sublayers?.first as? AVPlayerLayer)?.frame = bounds
    }
}
