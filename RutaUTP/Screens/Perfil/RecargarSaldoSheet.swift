//
//  RecargarSaldoSheet.swift
//  RutaUTP
//
//  Hoja de recarga simulada del monedero.
//

import SwiftUI

/// Recarga con la composición de Apple Cash: el saldo es el protagonista y
/// cada elección se lee en grupos nativos. La acción principal vive al final
/// del contenido y se desplaza con él, como el resto del formulario.
struct RecargarSaldoSheet: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

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
            Form {
                Section {
                    encabezado
                        .listRowBackground(Color.clear)
                } footer: {
                    // El aviso va arriba y no escondido: la recarga no mueve dinero.
                    Text(L.t("Recarga de demostración: no se procesa ningún pago real ni se abre ninguna app de pagos. El saldo se guarda solo en este dispositivo.",
                             "Demo top-up: no real payment is processed and no payment app is opened. The balance is stored only on this device."))
                }

                if store.datosLocalesInvalidos {
                    Section {
                        Text(L.t("No se pudieron recuperar los datos del monedero. Las operaciones están bloqueadas y los datos originales se conservan.",
                                 "Wallet data could not be recovered. Operations are blocked and the original data has been preserved."))
                            .font(.subheadline)
                            .foregroundStyle(EstiloPreferencias.textoSecundario)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L.t("Reintentar lectura", "Retry reading")) { store.reintentarLectura() }
                    }
                }

                Section {
                    selectorImporte
                } header: {
                    Text(L.t("¿CUÁNTO QUIERES RECARGAR?", "HOW MUCH DO YOU WANT TO TOP UP?"))
                }

                Section {
                    ForEach(BilleteraPago.allCases) { opcion in
                        filaBilletera(opcion)
                    }
                } header: {
                    Text(L.t("PAGA CON", "PAY WITH"))
                }

                Section {
                    botonRecargar
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                if !store.movimientos.isEmpty {
                    Section {
                        ForEach(store.movimientos.prefix(5)) { movimiento in
                            filaMovimiento(movimiento)
                        }
                    } header: {
                        Text(L.t("MOVIMIENTOS RECIENTES", "RECENT ACTIVITY"))
                    }
                }
            }
            .estiloFormularioPreferencias()
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

    /// Saldo actual en grande y, debajo, el saldo que quedaría con el importe
    /// elegido. Es la misma tipografía del monedero del perfil.
    private var encabezado: some View {
        VStack(spacing: 6) {
            Text(L.t("SALDO DE DEMOSTRACIÓN", "DEMO BALANCE"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(EstiloPreferencias.textoSecundario)
            Text(store.saldoTexto)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(EstiloPreferencias.texto)
            Text(L.f("Saldo tras la recarga: {0}", "Balance after top-up: {0}",
                     [FormatoNumero.soles(store.saldo + elegido)]))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(EstiloPreferencias.textoSecundario)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Importes rápidos en cápsulas, como en Apple Cash. El elegido se rellena
    /// con el color de etiqueta, igual que la acción destacada del monedero.
    private var selectorImporte: some View {
        let columnas = textSize.isAccessibilitySize ? 1 : (apilarContenido ? 2 : 4)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnas),
                         spacing: 10) {
            ForEach(importes, id: \.self) { importe in
                botonImporte(importe)
            }
        }
        .padding(.vertical, 6)
    }

    private func botonImporte(_ importe: Double) -> some View {
        let seleccionado = elegido == importe

        return Button {
            guard !seleccionado else { return }
            AppHaptics.selection()
            withAnimation(reducirMovimiento ? nil : .snappy(duration: 0.2)) { elegido = importe }
        } label: {
            Text(FormatoNumero.soles(importe, decimales: 0))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(seleccionado ? Color(uiColor: .systemBackground) : EstiloPreferencias.texto)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(seleccionado ? Color(uiColor: .label) : Color(uiColor: .tertiarySystemGroupedBackground),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }

    /// Billeteras con las que se puede pagar la recarga.
    ///
    /// Es lo que se hace en Perú: se paga escaneando un QR. En la vida real eso
    /// es Yape o Plin; aquí se usan marcas propias («Yapo» y «Plun») para no
    /// apoyarse en marcas registradas ajenas. La demostración no abre ninguna
    /// app de pagos, así que la selección solo decide la marca de verificación
    /// y el texto del botón.
    private func filaBilletera(_ opcion: BilleteraPago) -> some View {
        let seleccionada = billetera == opcion

        return Button {
            guard !seleccionada else { return }
            AppHaptics.selection()
            billetera = opcion
        } label: {
            HStack(spacing: 12) {
                MarcaBilletera(billetera: opcion, altura: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(opcion.nombre)
                        .font(.body)
                        .foregroundStyle(EstiloPreferencias.texto)
                    Text(L.t("Billetera digital", "Digital wallet"))
                        .font(.subheadline)
                        .foregroundStyle(EstiloPreferencias.textoSecundario)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(seleccionada ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.f("Pagar con {0}", "Pay with {0}", ["\(opcion.nombre)"]))
        .accessibilityAddTraits(seleccionada ? [.isButton, .isSelected] : .isButton)
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
            Label(L.f("Recargar {0} con {1}", "Top up {0} with {1}",
                      ["\(FormatoNumero.soles(elegido, decimales: 0))", "\(billetera.nombre)"]),
                  systemImage: "plus.circle.fill")
        }
        .buttonStyle(BotonMonederoStyle(destacado: true))
        .disabled(store.datosLocalesInvalidos)
    }

    private func filaMovimiento(_ movimiento: MovimientoMonedero) -> some View {
        (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                          : AnyLayout(HStackLayout(spacing: 12))) {
            Image(systemName: movimiento.esRecarga ? "arrow.down.circle.fill" : "bus.fill")
                .font(.body)
                .foregroundStyle(movimiento.esRecarga ? AnyShapeStyle(.tint)
                                                      : AnyShapeStyle(EstiloPreferencias.textoSecundario))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(movimiento.descripcion)
                    .font(.body)
                    .foregroundStyle(EstiloPreferencias.texto)
                Text(FormatoFecha
                        .formateador(patron: "d MMM, HH:mm",
                                     locale: FormatoFecha.localeActivo)
                        .string(from: movimiento.fecha))
                    .font(.subheadline)
                    .foregroundStyle(EstiloPreferencias.textoSecundario)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !apilarContenido { Spacer(minLength: 8) }
            Text((movimiento.importe > 0 ? "+" : "−") + FormatoNumero.soles(abs(movimiento.importe)))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(movimiento.esRecarga ? AnyShapeStyle(.tint) : AnyShapeStyle(EstiloPreferencias.texto))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
