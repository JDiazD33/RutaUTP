//
//  RecargarSaldoSheet.swift
//  RutaUTP
//
//  Hoja de recarga simulada del monedero.
//

import SwiftUI

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
                        Button(L.t("Reintentar lectura", "Retry reading")) { store.reintentarLectura() }
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
        .onAppear { store.reintentarLectura() }
        .alert(L.t("No se pudo recargar", "Unable to top up"), isPresented: $errorRecarga) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(store.datosLocalesInvalidos ? ErrorCobroPasaje.datosLocalesInvalidos.mensaje :
                 L.t("El importe debe ser válido y el saldo no puede superar S/ 1 000 000. No se hicieron cambios.",
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
                .foregroundStyle(Color.appAccent)
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
                        Text(FormatoNumero.soles(importe, decimales: 0))
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
        .accessibilityLabel(L.f("Pagar con {0}", "Pay with {0}", ["\(opcion.nombre)"]))
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
                            .foregroundStyle(movimiento.esRecarga ? Color.appAccent : Color.onSurfaceVariant)
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
                        Text((movimiento.importe > 0 ? "+" : "−") + FormatoNumero.soles(abs(movimiento.importe)))
                            .font(.bodySmMedium)
                            .monospacedDigit()
                            .foregroundStyle(movimiento.esRecarga ? Color.appAccent : Color.onSurface)
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
                Text(L.f("Recargar {0} con {1}", "Top up {0} with {1}", ["\(FormatoNumero.soles(elegido, decimales: 0))", "\(billetera.nombre)"]))
                    .font(.headlineSm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.onPrimaryFill)
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
