// CamaraQR.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import Foundation
import AVFoundation

/// Estado del permiso y de la cámara.
enum EstadoCamaraQR: Equatable {
    case comprobando
    case listo
    case denegado
    case sinCamara
}

// MARK: - Control de la cámara

/// Puente entre AVFoundation, que entrega en su propia cola, y el modelo.
///
/// Está aparte para no tener que renunciar al actor principal en el modelo solo
/// por cumplir un protocolo de Objective-C.
private final class DelegadoQR: NSObject, AVCaptureMetadataOutputObjectsDelegate {

    private let alLeer: @Sendable (String) -> Void

    init(alLeer: @escaping @Sendable (String) -> Void) {
        self.alLeer = alLeer
    }

    func metadataOutput(
        _ salida: AVCaptureMetadataOutput,
        didOutput objetos: [AVMetadataObject],
        from conexion: AVCaptureConnection
    ) {
        guard
            let codigo = objetos.first as? AVMetadataMachineReadableCodeObject,
            codigo.type == .qr,
            let texto = codigo.stringValue,
            !texto.isEmpty
        else {
            return
        }

        alLeer(texto)
    }
}

/// Envoltorio de la sesión de captura.
///
/// No está aislado al actor principal a propósito: `startRunning()` bloquea y
/// tiene que ejecutarse en su propia cola, así que la cámara se queda aquí y el
/// modelo de la interfaz solo recibe avisos.
///
/// `@unchecked Sendable`: `dispositivo` y `configurada` se tocan únicamente
/// desde `cola`, que es serie; la identidad de captura se protege con candado.
/// La identidad y el callback de lectura se capturan juntos bajo el candado. La
/// sesión se comparte con la capa de previsualización, que es justo lo que
/// Apple documenta para `AVCaptureVideoPreviewLayer.session`.
final class CamaraQR: NSObject, @unchecked Sendable {

    /// Sesión para la capa de previsualización.
    let sesion = AVCaptureSession()

    /// Lectura de un QR. Se llama en la cola de la cámara.
    var alLeer: (@Sendable (String, UUID) -> Void)? {
        get {
            capturaLock.lock()
            defer { capturaLock.unlock() }
            return lector
        }
        set {
            capturaLock.lock()
            lector = newValue
            capturaLock.unlock()
        }
    }

    private let cola = DispatchQueue(label: "rutautp.escaner-qr")
    private var dispositivo: AVCaptureDevice?
    private var configurada = false
    private let capturaLock = NSLock()
    private var capturaVigente: UUID?
    private var lector: (@Sendable (String, UUID) -> Void)?

    var identidadDeCaptura: UUID? {
        capturaLock.lock()
        defer { capturaLock.unlock() }
        return capturaVigente
    }

    private lazy var delegado = DelegadoQR { [weak self] texto in
        guard let self else { return }
        self.capturaLock.lock()
        let captura = self.capturaVigente
        let alLeer = self.lector
        self.capturaLock.unlock()
        guard let captura else { return }
        alLeer?(texto, captura)
    }

    /// Configura entrada y salida.
    ///
    /// Llama a `listo` o a `fallo`, nunca a los dos. `listo` recibe si el
    /// dispositivo tiene linterna, para no tener que consultarlo después desde
    /// otro hilo.
    func preparar(
        listo: @escaping @Sendable (Bool) -> Void,
        fallo: @escaping @Sendable () -> Void
    ) {
        cola.async { [weak self] in
            guard let self else { return }

            if self.configurada {
                listo(self.dispositivo?.hasTorch ?? false)
                return
            }

            guard let dispositivo = AVCaptureDevice.default(for: .video) else {
                fallo()
                return
            }

            self.dispositivo = dispositivo

            self.sesion.beginConfiguration()
            defer { self.sesion.commitConfiguration() }

            guard
                let entrada = try? AVCaptureDeviceInput(device: dispositivo),
                self.sesion.canAddInput(entrada)
            else {
                fallo()
                return
            }

            self.sesion.addInput(entrada)

            // El orden importa: los tipos de metadato solo se pueden fijar
            // cuando la salida ya pertenece a la sesión. Al revés lanza una
            // excepción de Objective-C, que no se puede atrapar en Swift.
            let salida = AVCaptureMetadataOutput()

            guard self.sesion.canAddOutput(salida) else {
                fallo()
                return
            }

            self.sesion.addOutput(salida)
            salida.setMetadataObjectsDelegate(self.delegado, queue: self.cola)
            salida.metadataObjectTypes = [.qr]

            self.configurada = true
            listo(dispositivo.hasTorch)
        }
    }

    func arrancar() {
        let captura = UUID()
        capturaLock.lock()
        capturaVigente = captura
        capturaLock.unlock()
        cola.async { [weak self] in
            guard let self, self.identidadDeCaptura == captura,
                  self.configurada, !self.sesion.isRunning else { return }
            self.sesion.startRunning()
        }
    }

    func detener() {
        // Invalidar inmediatamente, antes de que la cola procese un arranque pendiente.
        capturaLock.lock()
        capturaVigente = nil
        capturaLock.unlock()
        cola.async { [weak self] in
            guard let sesion = self?.sesion, sesion.isRunning else { return }
            sesion.stopRunning()
        }
    }

    /// Enciende la linterna si estaba apagada y viceversa.
    func alternarLinterna(alCambiar: @escaping @Sendable (Bool) -> Void) {
        cola.async { [weak self] in
            guard let self, let dispositivo = self.dispositivo, dispositivo.hasTorch else {
                return
            }

            do {
                try dispositivo.lockForConfiguration()
                let encender = dispositivo.torchMode != .on
                dispositivo.torchMode = encender ? .on : .off
                dispositivo.unlockForConfiguration()
                alCambiar(encender)
            } catch {
                // Quedarse sin linterna no impide escanear: no se interrumpe
                // nada por esto.
            }
        }
    }

    func apagarLinterna() {
        cola.async { [weak self] in
            guard
                let self,
                let dispositivo = self.dispositivo,
                dispositivo.hasTorch,
                dispositivo.torchMode == .on
            else {
                return
            }

            do {
                try dispositivo.lockForConfiguration()
                dispositivo.torchMode = .off
                dispositivo.unlockForConfiguration()
            } catch { return }
        }
    }
}
