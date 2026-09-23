//
//  EscanerQRView.swift
//  RutaUTP
//
//  Lector de QR para pagar desde el monedero.
//
//  Por qué AVFoundation y no VisionKit: `DataScannerViewController` trae su
//  propia interfaz y no se puede vestir; aquí hacen falta la ventana con
//  esquinas, la línea de barrido y el control de la linterna.
//
//  La captura se detiene en cuanto hay lectura: no tiene sentido seguir
//  gastando cámara y batería con el resultado ya en pantalla. Por eso mismo,
//  donde no hay cámara (el simulador) o el permiso está denegado, se ofrece
//  leer un código de ejemplo, para que el flujo de pago se pueda probar igual.
//

import SwiftUI
import AVFoundation
import UIKit

/// Resultado de una lectura.
struct ResultadoQR: Equatable {
    let texto: String
    let campos: PagoQR.CamposQR
}

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
/// `@unchecked Sendable`: todo el estado mutable (`dispositivo`, `configurada`)
/// se toca únicamente desde `cola`, que es una cola serie. `alLeer` se escribe
/// una sola vez, antes de arrancar la sesión, y a partir de ahí solo se lee. La
/// sesión se comparte con la capa de previsualización, que es justo lo que
/// Apple documenta para `AVCaptureVideoPreviewLayer.session`.
final class CamaraQR: NSObject, @unchecked Sendable {

    /// Sesión para la capa de previsualización.
    let sesion = AVCaptureSession()

    /// Lectura de un QR. Se llama en la cola de la cámara.
    var alLeer: (@Sendable (String) -> Void)?

    private let cola = DispatchQueue(label: "rutautp.escaner-qr")
    private var dispositivo: AVCaptureDevice?
    private var configurada = false

    private lazy var delegado = DelegadoQR { [weak self] texto in
        self?.alLeer?(texto)
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
        cola.async { [weak self] in
            guard let sesion = self?.sesion, !sesion.isRunning else { return }
            sesion.startRunning()
        }
    }

    func detener() {
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

            try? dispositivo.lockForConfiguration()
            dispositivo.torchMode = .off
            dispositivo.unlockForConfiguration()
        }
    }
}

// MARK: - Modelo

@MainActor
final class EscanerQRModel: ObservableObject {

    @Published private(set) var estado: EstadoCamaraQR = .comprobando
    @Published private(set) var resultado: ResultadoQR?
    @Published private(set) var linternaEncendida = false
    /// `true` si el dispositivo tiene linterna. Lo informa la propia cámara al
    /// configurarse, para no consultarlo después desde otro hilo.
    @Published private(set) var linternaDisponible = false

    let camara = CamaraQR()

    init() {
        camara.alLeer = { [weak self] texto in
            Task { @MainActor in self?.recibir(texto) }
        }
    }

    func comenzar() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break

        case .notDetermined:
            let concedido = await AVCaptureDevice.requestAccess(for: .video)

            guard concedido else {
                estado = .denegado
                return
            }

        default:
            estado = .denegado
            return
        }

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

        estado = arranque.0 ? .listo : .sinCamara
        linternaDisponible = arranque.1

        if arranque.0 { camara.arrancar() }
    }

    func detener() {
        camara.apagarLinterna()
        camara.detener()
        linternaEncendida = false
    }

    /// Deja el lector listo para otra lectura.
    func reanudar() {
        resultado = nil
        camara.arrancar()
    }

    func alternarLinterna() {
        camara.alternarLinterna { [weak self] encendida in
            Task { @MainActor in
                self?.linternaEncendida = encendida
                AppHaptics.selection()
            }
        }
    }

    /// Lectura de ejemplo, para poder probar el pago donde no hay cámara
    /// (el simulador) o cuando el permiso está denegado.
    func simularLectura() {
        recibir(PagoQR.cargaUtil(importe: nil))
    }

    private func recibir(_ texto: String) {
        guard resultado == nil else { return }

        resultado = ResultadoQR(texto: texto, campos: PagoQR.leer(texto))
        AppHaptics.success()

        camara.detener()
    }
}

// MARK: - Previsualización

/// Capa de vídeo de la cámara.
///
/// `layerClass` es la propia capa de vídeo, así que se redimensiona sola con la
/// vista y no hay que recalcular el frame en cada cambio de tamaño.
struct VistaPreviaQR: UIViewRepresentable {

    let sesion: AVCaptureSession

    func makeUIView(context: Context) -> VistaPreviaQRUIView {
        let vista = VistaPreviaQRUIView()
        vista.backgroundColor = .black
        vista.capa?.videoGravity = .resizeAspectFill
        vista.capa?.session = sesion
        return vista
    }

    func updateUIView(_ vista: VistaPreviaQRUIView, context: Context) {
        vista.capa?.session = sesion
    }

    final class VistaPreviaQRUIView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        /// Sin force-cast: `layerClass` lo garantiza, pero devolverlo opcional
        /// evita una conversión forzada que el compilador no puede comprobar.
        var capa: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Pantalla

struct EscanerQRView: View {

    /// Cobra el importe indicado con el monedero. Devuelve si se pudo.
    ///
    /// Marcado `@MainActor` porque toca `MonederoStore`, que también lo está:
    /// así la conversión del cierre no pierde el actor global por el camino.
    var onPagar: @MainActor (Double) -> Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelo = EscanerQRModel()
    @State private var mensajePago: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if modelo.estado == .listo {
                VistaPreviaQR(sesion: modelo.camara.sesion)
                    .ignoresSafeArea()

                ventanaDeEscaneo
            }

            VStack(spacing: 0) {
                barraSuperior
                Spacer(minLength: 0)
                panelInferior
            }
        }
        .task { await modelo.comenzar() }
        .onDisappear { modelo.detener() }
    }

    // MARK: - Ventana de escaneo

    /// Oscurecido con un hueco cuadrado, esquinas de marca y línea de barrido.
    private var ventanaDeEscaneo: some View {
        GeometryReader { geo in
            let lado = min(geo.size.width * 0.74, 300)
            let x0 = (geo.size.width - lado) / 2
            let y0 = (geo.size.height - lado) / 2
            let vela = Color.black.opacity(0.6)

            ZStack(alignment: .topLeading) {
                // Cuatro rectángulos en vez de recortar un agujero con modos de
                // fusión: es más fácil de leer y se comporta igual en cualquier
                // tamaño.
                vela.frame(width: geo.size.width, height: max(0, y0))
                vela.frame(width: geo.size.width, height: max(0, y0))
                    .offset(y: y0 + lado)
                vela.frame(width: max(0, x0), height: lado)
                    .offset(y: y0)
                vela.frame(width: max(0, x0), height: lado)
                    .offset(x: x0 + lado, y: y0)

                EsquinasVentana(largo: 30, radio: 12)
                    .stroke(Color.white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: lado, height: lado)
                    .offset(x: x0, y: y0)

                if modelo.resultado == nil {
                    LineaBarrido(lado: lado)
                        .frame(width: lado, height: lado)
                        .offset(x: x0, y: y0)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: modelo.resultado == nil)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Barra superior

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            botonRedondo(icono: "xmark", etiqueta: L.t("Cerrar", "Close")) {
                dismiss()
            }

            Spacer(minLength: 0)

            Text(L.t("Escanear QR", "Scan QR"))
                .font(.headlineSm)
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if modelo.linternaDisponible {
                botonRedondo(
                    icono: modelo.linternaEncendida ? "bolt.fill" : "bolt.slash.fill",
                    etiqueta: modelo.linternaEncendida
                        ? L.t("Apagar linterna", "Turn off flashlight")
                        : L.t("Encender linterna", "Turn on flashlight"),
                    encendido: modelo.linternaEncendida
                ) {
                    modelo.alternarLinterna()
                }
            } else {
                // Hueco del mismo tamaño que el botón de linterna, para que el
                // título quede centrado de verdad.
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func botonRedondo(
        icono: String,
        etiqueta: String,
        encendido: Bool = false,
        accion: @escaping () -> Void
    ) -> some View {
        Button {
            AppHaptics.impact(.light)
            accion()
        } label: {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(encendido ? Color.appPrimary : Color.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
    }

    // MARK: - Panel inferior

    @ViewBuilder
    private var panelInferior: some View {
        VStack(spacing: 14) {
            switch modelo.estado {
            case .comprobando:
                ProgressView()
                    .tint(.white)
                texto(L.t("Preparando la cámara…", "Preparing the camera…"))

            case .denegado:
                tarjetaAviso(
                    icono: "camera.fill",
                    titulo: L.t("Sin permiso de cámara", "No camera permission"),
                    detalle: L.t("Activa el acceso a la cámara en Ajustes para escanear un QR.",
                                 "Turn on camera access in Settings to scan a QR.")
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: url) {
                            Text(L.t("Abrir Ajustes", "Open Settings"))
                                .font(.bodySmMedium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.appPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .sinCamara:
                tarjetaAviso(
                    icono: "camera.metering.unknown",
                    titulo: L.t("Cámara no disponible", "Camera unavailable"),
                    detalle: L.t("Este dispositivo no puede escanear. En el simulador no hay cámara; puedes probar con un código de ejemplo.",
                                 "This device can't scan. The simulator has no camera; you can try with a sample code.")
                ) {
                    EmptyView()
                }

            case .listo:
                if let resultado = modelo.resultado {
                    tarjetaResultado(resultado)
                } else {
                    texto(L.t("Apunta al QR del cobrador", "Point at the collector's QR"))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.25), value: modelo.estado)
        .animation(.easeInOut(duration: 0.25), value: modelo.resultado)
    }

    private func texto(_ contenido: String) -> some View {
        Text(contenido)
            .font(.bodySm)
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
    }

    /// Aviso con acción opcional. Se usa cuando no se puede escanear.
    private func tarjetaAviso<Accion: View>(
        icono: String,
        titulo: String,
        detalle: String,
        @ViewBuilder accion: () -> Accion
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icono)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.appPrimary)
                Text(titulo)
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
                Spacer(minLength: 0)
            }

            Text(detalle)
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            accion()

            // Salida para probar el flujo sin cámara: es el caso del simulador
            // y el de un permiso denegado.
            Button {
                AppHaptics.impact(.medium)
                modelo.simularLectura()
            } label: {
                Text(L.t("Probar con un código de ejemplo", "Try a sample code"))
                    .font(.bodySmMedium)
                    .foregroundStyle(.onSurface)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLow))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.outline.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.appSurface))
    }

    /// Lo leído, con lo que se pudo entender y el pago simulado.
    private func tarjetaResultado(_ resultado: ResultadoQR) -> some View {
        // Si el QR trae importe se respeta; si es estático (el caso normal de
        // un QR de cuenta) se cobra la tarifa de referencia.
        let importe = resultado.campos.importe ?? MonederoStore.tarifaReferencia

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.appPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Código leído", "Code read"))
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(subtituloResultado(resultado))
                        .font(.bodyXs)
                        .foregroundStyle(.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }

            if resultado.campos.esPago {
                VStack(spacing: 0) {
                    if let billetera = resultado.campos.billetera {
                        fila(L.t("Billetera", "Wallet"), billetera)
                    }
                    if let titular = resultado.campos.titular {
                        fila(L.t("Cobra", "Payee"), titular)
                    }
                    if let celular = resultado.campos.celular {
                        fila(L.t("Celular", "Phone"), celular)
                    }
                    if let importeTexto = resultado.campos.importeTexto {
                        fila(L.t("Importe", "Amount"), importeTexto)
                    }
                    if let ciudad = resultado.campos.ciudad {
                        fila(L.t("Ciudad", "City"), ciudad)
                    }
                }
            } else {
                Text(resultado.texto)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if onPagar(importe) {
                    AppHaptics.success()
                    mensajePago = L.t("Pasaje pagado (simulado).",
                                      "Fare paid (simulated).")
                } else {
                    AppHaptics.warning()
                    mensajePago = L.t("Saldo insuficiente. Recarga para continuar.",
                                      "Not enough balance. Top up to continue.")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(L.t("Pagar \(String(format: "S/ %.2f", importe)) (simulado)",
                             "Pay \(String(format: "S/ %.2f", importe)) (simulated)"))
                        .font(.bodySmMedium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primaryContainer))
            }
            .buttonStyle(.plain)

            if let mensajePago {
                Text(mensajePago)
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
            }

            Button {
                AppHaptics.impact(.light)
                mensajePago = nil
                modelo.reanudar()
            } label: {
                Text(L.t("Escanear otro", "Scan another"))
                    .font(.bodySmMedium)
                    .foregroundStyle(.onSurface)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.appSurface))
    }

    /// Segunda línea de la tarjeta: de dónde salió el código.
    private func subtituloResultado(_ resultado: ResultadoQR) -> String {
        guard resultado.campos.esPago else {
            return L.t("Código sin formato de pago", "Code without payment format")
        }

        if let billetera = resultado.campos.billetera {
            return L.t("QR de pago · \(billetera)", "Payment QR · \(billetera)")
        }

        return L.t("QR de pago", "Payment QR")
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack(spacing: 12) {
            Text(etiqueta)
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
            Spacer(minLength: 8)
            Text(valor)
                .font(.bodySmMedium)
                .foregroundStyle(.onSurface)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Piezas de la ventana

/// Las cuatro esquinas de la ventana, en un solo trazado.
private struct EsquinasVentana: Shape {

    var largo: CGFloat = 30
    var radio: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var camino = Path()
        let r = min(radio, largo)

        // Superior izquierda
        camino.move(to: CGPoint(x: rect.minX, y: rect.minY + largo))
        camino.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        camino.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                            control: CGPoint(x: rect.minX, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.minX + largo, y: rect.minY))

        // Superior derecha
        camino.move(to: CGPoint(x: rect.maxX - largo, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        camino.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                            control: CGPoint(x: rect.maxX, y: rect.minY))
        camino.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + largo))

        // Inferior derecha
        camino.move(to: CGPoint(x: rect.maxX, y: rect.maxY - largo))
        camino.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        camino.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                            control: CGPoint(x: rect.maxX, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.maxX - largo, y: rect.maxY))

        // Inferior izquierda
        camino.move(to: CGPoint(x: rect.minX + largo, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        camino.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                            control: CGPoint(x: rect.minX, y: rect.maxY))
        camino.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - largo))

        return camino
    }
}

/// Línea que recorre la ventana para indicar que está leyendo.
///
/// Con «reducir movimiento» activo se queda quieta en el borde superior: sigue
/// indicando que hay un área de lectura sin animar nada.
private struct LineaBarrido: View {

    let lado: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var abajo = false

    var body: some View {
        LinearGradient(
            colors: [Color.appPrimary.opacity(0),
                     Color.appPrimary,
                     Color.appPrimary.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: max(1, lado - 32), height: 3)
        .clipShape(Capsule())
        .shadow(color: Color.appPrimary.opacity(0.8), radius: 6)
        .offset(y: abajo ? lado / 2 - 16 : -(lado / 2 - 16))
        .frame(width: lado, height: lado)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                abajo = true
            }
        }
    }
}
