// EscanerQRModel.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import Foundation
import Combine
import AVFoundation

// MARK: - Modelo

@MainActor
final class EscanerQRModel: ObservableObject {

    @Published private(set) var estado: EstadoCamaraQR = .comprobando
    @Published private(set) var resultado: ResultadoQR?
    @Published private(set) var pagoRealizado = false
    @Published private(set) var linternaEncendida = false
    /// `true` si el dispositivo tiene linterna. Lo informa la propia cámara al
    /// configurarse, para no consultarlo después desde otro hilo.
    @Published private(set) var linternaDisponible = false

    let camara = CamaraQR()

    // El callback y los observadores de @Published pueden reentrar de forma
    // síncrona. La guarda se activa antes de cualquier publicación del pago.
    private var pagoEnCurso = false
    private var arranqueGuard = StartGuard()
    private var lecturasActivas = true

    init() {
        let camara = camara
        camara.alLeer = { [weak self, weak camara] texto, captura in
            Task { @MainActor [weak self, weak camara] in
                guard let self, let camara, self.lecturasActivas,
                      camara.identidadDeCaptura == captura else { return }
                self.recibir(texto)
            }
        }
    }

    func comenzar() async {
        guard !Task.isCancelled else { return }
        let token = arranqueGuard.begin()
        lecturasActivas = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break

        case .notDetermined:
            let concedido = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled, arranqueGuard.isCurrent(token) else { return }

            guard concedido else {
                estado = .denegado
                return
            }

        default:
            estado = .denegado
            return
        }

        guard !Task.isCancelled, arranqueGuard.isCurrent(token) else { return }

        // (se pudo configurar, tiene linterna). El nombre no puede ser
        // `resultado`: ensombrecería la propiedad publicada del mismo nombre.
        let arranque = await withCheckedContinuation {
            (continuacion: CheckedContinuation<(Bool, Bool), Never>) in
            camara.preparar { hayLinterna in
                continuacion.resume(returning: (true, hayLinterna))
            } fallo: {
                continuacion.resume(returning: (false, false))
            }
        }

        guard !Task.isCancelled, arranqueGuard.isCurrent(token) else { return }
        estado = arranque.0 ? .listo : .sinCamara
        linternaDisponible = arranque.1

        if arranque.0, resultado == nil, lecturasActivas,
           !Task.isCancelled, arranqueGuard.isCurrent(token) { camara.arrancar() }
    }

    func detener() {
        arranqueGuard.invalidate()
        lecturasActivas = false
        camara.apagarLinterna()
        camara.detener()
        linternaEncendida = false
    }

    /// Deja el lector listo para otra lectura.
    func reanudar() {
        // No reemplazar una lectura mientras su callback está debitando.
        guard !pagoEnCurso else { return }
        // También proteger las publicaciones del reinicio: sus observadores
        // no deben cobrar una tarjeta que está siendo retirada.
        pagoEnCurso = true
        defer { pagoEnCurso = false }
        resultado = nil
        pagoRealizado = false
        // Una lectura de ejemplo no configura ni autoriza la cámara.
        if estado == .listo, lecturasActivas { camara.arrancar() }
    }

    func puedePagar(_ lectura: ResultadoQR) -> Bool {
        resultado?.id == lectura.id && !pagoRealizado && !pagoEnCurso
            && lectura.importeParaPagoDemo != nil
    }

    /// nil no invoca el monedero. Un fallo conserva la lectura para reintento;
    /// solo un éxito la consume, sin deduplicar futuros viajes con el mismo QR.
    func pagar(_ lectura: ResultadoQR, onPagar: @MainActor (Double) -> Bool) -> Bool? {
        guard puedePagar(lectura) else { return nil }
        pagoEnCurso = true
        defer { pagoEnCurso = false }

        guard let pagado = lectura.pagarDemo(onPagar: onPagar) else { return nil }
        if pagado, resultado?.id == lectura.id { pagoRealizado = true }
        return pagado
    }

    func alternarLinterna() {
        guard lecturasActivas, estado == .listo else { return }
        let token = arranqueGuard.generation
        camara.alternarLinterna { [weak self] encendida in
            Task { @MainActor in
                guard let self, self.lecturasActivas,
                      self.arranqueGuard.isCurrent(token) else { return }
                self.linternaEncendida = encendida
                AppHaptics.selection()
            }
        }
    }

    /// Lectura de ejemplo, para poder probar el pago donde no hay cámara
    /// (el simulador) o cuando el permiso está denegado.
    func simularLectura(texto: String? = nil) {
        recibir(texto ?? PagoQR.cargaUtil(importe: nil))
    }

    private func recibir(_ texto: String) {
        guard !pagoEnCurso, resultado == nil else { return }
        pagoEnCurso = true
        defer { pagoEnCurso = false }

        resultado = ResultadoQR(texto: texto, campos: PagoQR.leer(texto))
        AppHaptics.success()

        camara.detener()
    }
}
