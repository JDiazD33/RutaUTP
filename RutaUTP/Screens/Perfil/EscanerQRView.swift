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
import UIKit

// MARK: - Pantalla

struct EscanerQRView: View {

    /// Diagnóstico del monedero tras un rechazo. Mantenerlo antes de onPagar
    /// conserva la construcción con el único trailing closure de cobro.
    var errorPago: (@MainActor (Double) -> ErrorCobroPasaje?)? = nil

    /// Cobra el importe indicado con el monedero. Devuelve si se pudo.
    ///
    /// Marcado `@MainActor` porque toca `MonederoStore`, que también lo está:
    /// así la conversión del cierre no pierde el actor global por el camino.
    var onPagar: @MainActor (Double) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState(for: .voiceOver) private var enfocarResultado: Bool
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
        .onChange(of: modelo.resultado?.id) { _, id in
            enfocarResultado = id != nil
        }
        .onChange(of: mensajePago) { _, mensaje in
            guard voiceOverOn, scenePhase == .active, let mensaje else { return }
            AccesibilidadIdioma.anunciar(mensaje)
        }
        .accessibilityAction(.escape) { dismiss() }
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
                .accessibilityAddTraits(.isHeader)

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
                .foregroundStyle(encendido ? Color.appAccent : Color.white)
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
                                .foregroundStyle(.onPrimaryFill)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primaryFill))
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
                    .foregroundStyle(Color.appAccent)
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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Código leído", "Code read"))
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(subtituloResultado(resultado))
                        .font(.bodyXs)
                        .foregroundStyle(.onSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($enfocarResultado)

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
                    if let moneda = resultado.campos.monedaNormalizada {
                        fila(L.t("Moneda", "Currency"),
                             moneda.isEmpty ? L.t("Sin indicar", "Not specified") : moneda)
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

            if let importe = resultado.importeParaPagoDemo {
                Button {
                    // El modelo consume el éxito antes de permitir otra acción,
                    // incluyendo toques pendientes de una tarjeta anterior.
                    guard let pagado = modelo.pagar(resultado, onPagar: onPagar),
                          modelo.resultado?.id == resultado.id else { return }
                    if pagado {
                        AppHaptics.success()
                        mensajePago = L.t("Pasaje pagado (simulado).",
                                          "Fare paid (simulated).")
                    } else {
                        AppHaptics.warning()
                        mensajePago = errorPago?(importe)?.mensaje
                            ?? L.t("No se pudo completar el pago. Inténtalo de nuevo.",
                                   "The payment could not be completed. Try again.")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(modelo.pagoRealizado
                             ? L.t("Pasaje pagado (simulado)", "Fare paid (simulated)")
                             : L.f("Pagar {0} (simulado)", "Pay {0} (simulated)", ["\(FormatoNumero.soles(importe))"]))
                            .font(.bodySmMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.onPrimaryFill)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primaryContainer))
                }
                .buttonStyle(.plain)
                .disabled(!modelo.puedePagar(resultado))
            } else if resultado.campos.esPago, let error = resultado.errorParaPagoDemo {
                Text(error.mensaje)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }

            if let mensajePago {
                Text(L.aviso(mensajePago))
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
            return L.f("QR de pago · {0}", "Payment QR · {0}", ["\(billetera)"])
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta)
        .accessibilityValue(valor)
    }
}
