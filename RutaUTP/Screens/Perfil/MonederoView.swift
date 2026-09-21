// Monedero y QR de demostración local, sin pagos ni validación de viajes.
//
// El QR que se enseña para cobrar y el lector para pagar viven en
// `Services/Monedero/PagoQR.swift` (carga útil y dibujo) y en
// `Screens/Perfil/EscanerQRView.swift` (cámara). Aquí solo está la interfaz.

import SwiftUI
import UIKit

// MARK: - Tarjeta del monedero (va en la billetera del Perfil)

struct MonederoCard: View {
    @Environment(\.dynamicTypeSize) private var textSize

    @ObservedObject var store: MonederoStore
    let onRecargar: () -> Void
    let onMostrarQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 14))
                    .accessibilityHidden(true)
                Text(L.t("Saldo de demostración", "Demo balance"))
                    .font(.footnote.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)

            Text(store.saldoTexto)
                .font(.system(.title, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(L.t("≈ \(store.pasajesDisponibles) pasajes a \(store.tarifaTexto)",
                     "≈ \(store.pasajesDisponibles) fares at \(store.tarifaTexto)"))
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white.opacity(0.8))

            (textSize >= .xxxLarge ? AnyLayout(VStackLayout(spacing: 8))
                                    : AnyLayout(HStackLayout(spacing: 8))) {
                boton(L.t("Recargar", "Top up"), icono: "plus.circle.fill", accion: onRecargar)
                boton(L.t("Pagar con QR", "Pay with QR"),
                      icono: "qrcode.viewfinder",
                      accion: onMostrarQR)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Monedero UTP", "UTP Wallet"))
        .accessibilityValue(L.t("Saldo de demostración \(store.saldoTexto), aproximadamente \(store.pasajesDisponibles) pasajes a \(store.tarifaTexto)",
                                "Demo balance \(store.saldoTexto), approximately \(store.pasajesDisponibles) fares at \(store.tarifaTexto)"))
    }

    private func boton(_ titulo: String, icono: String, accion: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            accion()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icono)
                    .font(.system(size: 11, weight: .bold))
                Text(titulo)
                    .font(.caption2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(.white.opacity(0.22)))
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recarga (simulada)

struct RecargarSaldoSheet: View {
    @Environment(\.dynamicTypeSize) private var textSize

    private var apilarContenido: Bool { textSize >= .xxxLarge }

    @ObservedObject var store: MonederoStore
    @Environment(\.dismiss) private var dismiss
    @State private var elegido: Double = 10
    @State private var errorRecarga = false
    /// Billetera con la que se pagaría la recarga.
    ///
    /// Solo cambia la presentación: la demostración no abre ninguna app de
    /// pagos ni mueve dinero. Se deja elegida para que la pantalla muestre el
    /// flujo completo (elegir monto → elegir billetera → confirmar).
    @State private var billetera: BilleteraPago = .yape

    private let importes: [Double] = [5, 10, 20, 50]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    saldoActual
                    aviso
                    if store.datosLocalesInvalidos {
                        Text(L.t("No se pudieron recuperar los datos del monedero. Las operaciones están bloqueadas y los datos originales se conservan.",
                                 "Wallet data could not be recovered. Operations are blocked and the original data has been preserved."))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    selectorImporte
                    metodosDePago
                    if !store.movimientos.isEmpty { movimientos }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { botonRecargar }
            .navigationTitle(L.t("Recargar saldo", "Top up balance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .seguirTemaForzado()
        .alert(L.t("No se pudo recargar", "Unable to top up"), isPresented: $errorRecarga) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("El importe debe ser válido y el saldo no puede superar S/ 1 000 000. No se hicieron cambios.",
                     "The amount must be valid and the balance cannot exceed S/ 1,000,000. No changes were made."))
        }
    }

    private var saldoActual: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("SALDO DE DEMOSTRACIÓN", "DEMO BALANCE"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Text(store.saldoTexto)
                .font(.displayNumberMd)
                .monospacedDigit()
                .foregroundStyle(.onSurface)
        }
    }

    /// El aviso va arriba y no escondido: la recarga no mueve dinero.
    private var aviso: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appPrimary)
            Text(L.t("Recarga de demostración: no se procesa ningún pago real ni se abre ninguna app de pagos. El saldo se guarda solo en este dispositivo.",
                     "Demo top-up: no real payment is processed and no payment app is opened. The balance is stored only on this device."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appPrimary.opacity(0.09))
        )
    }

    private var selectorImporte: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("¿CUÁNTO QUIERES RECARGAR?", "HOW MUCH DO YOU WANT TO TOP UP?"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                     count: apilarContenido ? 1 : 2), spacing: 12) {
                ForEach(importes, id: \.self) { importe in
                    let seleccionado = elegido == importe
                    Button {
                        AppHaptics.selection()
                        withAnimation(.easeInOut(duration: 0.18)) { elegido = importe }
                    } label: {
                        Text(String(format: "S/ %.0f", importe))
                            .font(.system(.headline, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 10)
                            .monospacedDigit()
                            .foregroundStyle(seleccionado ? Color.onPrimaryContainer : Color.onSurface)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(seleccionado ? Color.primaryContainer : Color.surfaceContainerLow)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(seleccionado ? Color.primaryContainer : Color.outlineVariant.opacity(0.35),
                                            lineWidth: seleccionado ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(seleccionado ? .isSelected : [])
                }
            }
        }
    }

    /// Billeteras con las que se puede pagar la recarga.
    ///
    /// Es lo que se hace en Perú: se paga escaneando un QR. En la vida real eso
    /// es Yape o Plin; aquí se usan marcas propias («Yapo» y «Plun») para no
    /// apoyarse en marcas registradas ajenas. La demostración no abre ninguna
    /// app de pagos, así que la selección solo decide el aspecto (borde, fondo
    /// y el texto del botón).
    private var metodosDePago: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("PAGA CON", "PAY WITH"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            VStack(spacing: 12) {
                ForEach(BilleteraPago.allCases) { opcion in
                    tarjetaBilletera(opcion)
                }
            }

            Text(L.t("Demostración: no se abre ninguna app de pagos ni se mueve dinero real.",
                     "Demo: no payment app is opened and no real money moves."))
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tarjetaBilletera(_ opcion: BilleteraPago) -> some View {
        let seleccionada = billetera == opcion

        return Button {
            AppHaptics.selection()
            withAnimation(.easeInOut(duration: 0.18)) { billetera = opcion }
        } label: {
            HStack(spacing: 12) {
                MarcaBilletera(billetera: opcion, altura: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(opcion.nombre)
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(L.t("Billetera digital", "Digital wallet"))
                        .font(.bodyXs)
                        .foregroundStyle(.onSurfaceVariant)
                }

                Spacer(minLength: 0)

                Image(systemName: seleccionada ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(seleccionada ? opcion.colorMarca : Color.outlineVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(seleccionada
                          ? opcion.colorMarca.opacity(0.10)
                          : Color.surfaceContainerLowest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(seleccionada ? opcion.colorMarca : Color.outlineVariant.opacity(0.35),
                            lineWidth: seleccionada ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Pagar con \(opcion.nombre)", "Pay with \(opcion.nombre)"))
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
    }

    private var movimientos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("MOVIMIENTOS RECIENTES", "RECENT ACTIVITY"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            VStack(spacing: 0) {
                ForEach(store.movimientos.prefix(5)) { movimiento in
                    (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                      : AnyLayout(HStackLayout(spacing: 10))) {
                        Image(systemName: movimiento.esRecarga ? "arrow.down.circle.fill" : "bus.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(movimiento.esRecarga ? Color.appPrimary : Color.onSurfaceVariant)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(movimiento.descripcion)
                                .font(.bodySm)
                                .foregroundStyle(.onSurface)
                            Text(FormatoFecha
                                    .formateador(patron: "d MMM, HH:mm",
                                                 locale: FormatoFecha.localeActivo)
                                    .string(from: movimiento.fecha))
                                .font(.bodyXs)
                                .foregroundStyle(.onSurfaceVariant)
                        }
                        if !apilarContenido { Spacer() }
                        Text(String(format: "%@S/ %.2f",
                                    movimiento.importe > 0 ? "+" : "−",
                                    abs(movimiento.importe)))
                            .font(.bodySmMedium)
                            .monospacedDigit()
                            .foregroundStyle(movimiento.esRecarga ? Color.appPrimary : Color.onSurface)
                    }
                    .padding(.vertical, 9)
                    if movimiento.id != store.movimientos.prefix(5).last?.id {
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
            )
        }
    }

    private var botonRecargar: some View {
        Button {
            if store.recargar(elegido) {
                AppHaptics.success()
                dismiss()
            } else {
                AppHaptics.warning()
                errorRecarga = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(L.t("Recargar \(String(format: "S/ %.0f", elegido)) con \(billetera.nombre)",
                         "Top up \(String(format: "S/ %.0f", elegido)) with \(billetera.nombre)"))
                    .font(.headlineSm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primaryContainer)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .disabled(store.datosLocalesInvalidos)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - QR del monedero (cobrar y pagar)

/// La hoja tiene dos mitades y conviene no mezclarlas:
///
/// - **Cobrar**: el QR de la cuenta propia, para que quien quiera transferir
///   solo tenga que escanearlo. Es la mitad que se enseña.
/// - **Pagar**: el lector, para escanear el QR del cobrador.
struct QRPasajeSheet: View {

    @ObservedObject var store: MonederoStore
    @Environment(\.dismiss) private var dismiss

    @State private var billeteraCobro: BilleteraPago = .yape
    @State private var qr: UIImage?
    @State private var escanear = false

    /// Misma cuenta de demostración, presentada con la billetera elegida.
    private var cuenta: CuentaCobro {
        var cuenta = PagoQR.cuentaDemo
        cuenta.billetera = billeteraCobro
        return cuenta
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    tarjetaDeCobro
                    aviso
                    if store.datosLocalesInvalidos {
                        Text(L.t("No se pudieron recuperar los datos del monedero. Las operaciones están bloqueadas y los datos originales se conservan.",
                                 "Wallet data could not be recovered. Operations are blocked and the original data has been preserved."))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    seccionPagar
                }
                .padding(20)
            }
            .navigationTitle(L.t("Pagar con QR", "Pay with QR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
            .onAppear {
                // QR estático (sin importe): quien paga escribe cuánto envía,
                // que es lo que se espera de un QR de cuenta personal.
                if qr == nil {
                    actualizarQR()
                }
            }
        }
        .seguirTemaForzado()
        .fullScreenCover(isPresented: $escanear) {
            EscanerQRView { importe in store.cobrarPasaje(importe) }
        }
    }

    /// Une marca, cuenta y QR en una sola tarjeta. El logo abre la jerarquía
    /// visual y el código queda deliberadamente más pequeño para no dominar la
    /// pantalla.
    private var tarjetaDeCobro: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Mi QR para recibir", "My QR to receive"))
                    .font(.headlineSm)
                    .foregroundStyle(.onSurface)
                Text(L.t("Elige la billetera que quieres mostrar.",
                         "Choose the wallet you want to show."))
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                ForEach(BilleteraPago.allCases) { opcion in
                    selectorBilletera(opcion)
                }
            }

            Divider()

            if let qr {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    )
                    .accessibilityLabel(L.t("QR de cobro de demostración",
                                            "Demo payment QR"))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surfaceContainerLow)
                    .frame(width: 188, height: 188)
                    .overlay(ProgressView())
            }

            Text(L.t("Muestra este código para recibir una transferencia.",
                     "Show this code to receive a transfer."))
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                filaDato(L.t("Titular", "Holder"), cuenta.titular)
                Divider()
                filaDato(L.t("Celular", "Phone"), cuenta.celularLegible)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.28), lineWidth: 0.5)
        )
    }

    private func selectorBilletera(_ opcion: BilleteraPago) -> some View {
        let seleccionada = billeteraCobro == opcion

        return Button {
            guard !seleccionada else { return }
            AppHaptics.selection()
            withAnimation(.easeInOut(duration: 0.18)) {
                billeteraCobro = opcion
            }
            actualizarQR()
        } label: {
            HStack(spacing: 8) {
                MarcaBilletera(billetera: opcion, altura: 40)
                Text(opcion.nombre)
                    .font(.bodySmMedium)
                    .foregroundStyle(.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: seleccionada ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(seleccionada ? opcion.colorMarca : Color.outlineVariant)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(seleccionada
                          ? opcion.colorMarca.opacity(0.10)
                          : Color.surfaceContainerLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(seleccionada ? opcion.colorMarca : Color.outlineVariant.opacity(0.35),
                            lineWidth: seleccionada ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Mostrar QR de (opcion.nombre)",
                                "Show (opcion.nombre) QR"))
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
    }

    private func actualizarQR() {
        qr = PagoQR.imagen(PagoQR.cargaUtil(cuenta: cuenta))
    }

    private func filaDato(_ etiqueta: String, _ valor: String) -> some View {
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
        .padding(.vertical, 10)
    }

    private var aviso: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appPrimary)
            Text(L.t("El formato del QR es el de un cobro real, pero la cuenta es de demostración: ninguna billetera lo leerá como un cobro válido y no se mueve dinero.",
                     "The QR format is that of a real payment, but the account is a demo: no wallet will read it as a valid charge and no money moves."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appPrimary.opacity(0.09))
        )
    }

    /// La otra mitad de la hoja: escanear el QR de quien cobra.
    private var seccionPagar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("PAGAR", "PAY"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            Button {
                AppHaptics.impact(.medium)
                escanear = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .bold))
                    Text(L.t("Escanear un QR", "Scan a QR"))
                        .font(.headlineSm)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primaryContainer))
            }
            .buttonStyle(PressableCapsuleStyle())

            Text(L.t("Escanea el QR del cobrador y se descuenta el pasaje (\(store.tarifaTexto)) del saldo de demostración.",
                     "Scan the collector's QR and the fare (\(store.tarifaTexto)) is deducted from the demo balance."))
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Logo de billetera

/// Logo de una billetera, con respaldo si el recurso todavía no está en el
/// catálogo de recursos.
///
/// Los recursos (`yape-logo`, `plin-logo`, en `Assets.xcassets/Marcas`) tienen
/// el lienzo recortado al dibujo. Se muestran siempre en una caja cuadrada para
/// que no vuelvan a encogerse por el espacio transparente del SVG.
struct MarcaBilletera: View {

    let billetera: BilleteraPago
    var altura: CGFloat = 30

    var body: some View {
        Group {
            if let logo = UIImage(named: billetera.assetLogo) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                // Sin archivo no se deja un hueco ni se inventa un logo: se
                // escribe el nombre sobre el color de marca, y el día que se
                // añada la imagen entra sola.
                Text(billetera.nombre)
                    .font(.system(size: max(11, altura * 0.45), weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(billetera.colorMarca))
            }
        }
        .frame(width: altura, height: altura)
        .accessibilityHidden(true)
    }
}
