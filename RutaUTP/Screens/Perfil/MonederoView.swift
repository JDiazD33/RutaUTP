// Monedero y QR de demostración local, sin pagos ni validación de viajes.

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Tarjeta del monedero (va en la billetera del Perfil)

struct MonederoCard: View {

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
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)

            Text(store.saldoTexto)
                .font(.system(size: 26, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(L.t("≈ \(store.pasajesDisponibles) pasajes a \(store.tarifaTexto)",
                     "≈ \(store.pasajesDisponibles) fares at \(store.tarifaTexto)"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 8) {
                boton(L.t("Recargar", "Top up"), icono: "plus.circle.fill", accion: onRecargar)
                boton(L.t("QR demo", "Demo QR"), icono: "qrcode", accion: onMostrarQR)
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
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.white.opacity(0.22)))
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recarga (simulada)

struct RecargarSaldoSheet: View {

    @ObservedObject var store: MonederoStore
    @Environment(\.dismiss) private var dismiss
    @State private var elegido: Double = 10
    @State private var errorRecarga = false

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
            Text(L.t("Recarga de demostración: no se procesa ningún pago real. El saldo se guarda solo en este dispositivo.",
                     "Demo top-up: no real payment is processed. The balance is stored only on this device."))
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

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(importes, id: \.self) { importe in
                    let seleccionado = elegido == importe
                    Button {
                        AppHaptics.selection()
                        withAnimation(.easeInOut(duration: 0.18)) { elegido = importe }
                    } label: {
                        Text(String(format: "S/ %.0f", importe))
                            .font(.system(size: 18, weight: .heavy))
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

    private var movimientos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("MOVIMIENTOS RECIENTES", "RECENT ACTIVITY"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            VStack(spacing: 0) {
                ForEach(store.movimientos.prefix(5)) { movimiento in
                    HStack(spacing: 10) {
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
                        Spacer()
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
                Text(L.t("Recargar \(String(format: "S/ %.0f", elegido))",
                         "Top up \(String(format: "S/ %.0f", elegido))"))
                    .font(.headlineSm)
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

// MARK: - QR del pasaje

struct QRPasajeSheet: View {

    @ObservedObject var store: MonederoStore
    @Environment(\.dismiss) private var dismiss

    /// Código institucional del prototipo. Coincide con el del Carné Digital;
    /// sigue siendo un dato de demostración (ver A-01 de la auditoría).
    private let codigoEstudiante = "1234567"

    @State private var qr: UIImage?
    @State private var resultadoCobro: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    encabezado
                    codigoQR
                    aviso
                    if store.datosLocalesInvalidos {
                        Text(L.t("No se pudieron recuperar los datos del monedero. Las operaciones están bloqueadas y los datos originales se conservan.",
                                 "Wallet data could not be recovered. Operations are blocked and the original data has been preserved."))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    simulacion
                }
                .padding(20)
            }
            .navigationTitle(L.t("QR de demostración", "Demo QR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
            .onAppear {
                if qr == nil {
                    qr = Self.generarQR("RUTAUTP-DEMO|\(codigoEstudiante)")
                }
            }
        }
        .seguirTemaForzado()
    }

    private var encabezado: some View {
        VStack(spacing: 4) {
            Text(L.t("Código de muestra · no válido para viajar", "Sample code · not valid for travel"))
                .font(.headlineSm)
                .foregroundStyle(.onSurface)
                .multilineTextAlignment(.center)
            Text(L.t("Saldo de demostración: \(store.saldoTexto)",
                     "Demo balance: \(store.saldoTexto)"))
                .font(.bodySm)
                .monospacedDigit()
                .foregroundStyle(.onSurfaceVariant)
        }
    }

    private var codigoQR: some View {
        VStack(spacing: 10) {
            if let qr {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                    .accessibilityLabel(L.t("QR de demostración, no válido para viajar",
                                            "Demo QR, not valid for travel"))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surfaceContainerLow)
                    .frame(width: 244, height: 244)
                    .overlay(ProgressView())
            }

            Text(L.t("Código ficticio \(codigoEstudiante)", "Sample ID \(codigoEstudiante)"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
    }

    private var aviso: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appPrimary)
            Text(L.t("Este QR es una muestra fija. El botón solo descuenta saldo de demostración en este dispositivo: no lee el QR, no valida viajes ni mueve dinero real.",
                     "This QR is a fixed sample. The button only deducts demo balance on this device: it does not read the QR, validate trips or move real money."))
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

    /// Descuento local de demostración; no escanea ni valida el QR.
    private var simulacion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                AppHaptics.impact(.medium)
                let cobrado = store.cobrarPasaje()
                resultadoCobro = cobrado
                    ? L.t("Pasaje cobrado (simulado). Saldo: \(store.saldoTexto)",
                          "Fare charged (simulated). Balance: \(store.saldoTexto)")
                    : L.t("Saldo insuficiente. Recarga para continuar.",
                          "Not enough balance. Top up to continue.")
                if !cobrado { AppHaptics.warning() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(L.t("Simular pasaje · \(store.tarifaTexto)",
                             "Simulate fare · \(store.tarifaTexto)"))
                        .font(.bodySmMedium)
                }
                .foregroundStyle(.onSurface)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.outline.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.datosLocalesInvalidos)

            if let resultadoCobro {
                Text(resultadoCobro)
                    .font(.bodyXs)
                    .foregroundStyle(.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - QR

    /// QR con CoreImage, igual que el código de barras del Carné Digital: sin
    /// dependencias externas.
    private static func generarQR(_ texto: String) -> UIImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let salida = filtro.outputImage else { return nil }
        let escalada = salida.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(escalada, from: escalada.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
