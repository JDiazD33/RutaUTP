//
//  QRPasajeSheet.swift
//  RutaUTP
//
//  Hoja del QR de demostración para cobrar y pagar.
//
//  El QR y el lector viven en Services/Monedero/PagoQR.swift y
//  Screens/Perfil/EscanerQRView.swift; aquí solo está la interfaz.
//

import SwiftUI
import UIKit

/// La hoja tiene dos mitades y conviene no mezclarlas:
///
/// - **Pagar**: el lector, para escanear el QR del cobrador. Es la acción que
///   da nombre a la hoja, así que abre el formulario.
/// - **Cobrar**: el QR de la cuenta propia, para que quien quiera transferir
///   solo tenga que escanearlo. Es la mitad que se enseña.
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
            Form {
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
                    botonEscanear
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text(L.t("PAGAR", "PAY"))
                } footer: {
                    Text(L.f("Escanea el QR del cobrador y se descuenta el pasaje ({0}) del saldo de demostración.", "Scan the collector's QR and the fare ({0}) is deducted from the demo balance.", ["\(store.tarifaTexto)"]))
                }

                Section {
                    codigoDeCobro
                    Picker(L.t("Billetera digital", "Digital wallet"), selection: $billeteraCobro) {
                        ForEach(BilleteraPago.allCases) { opcion in
                            Text(opcion.nombre).tag(opcion)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint(L.t("Elige la billetera que quieres mostrar.",
                                           "Choose the wallet you want to show."))
                    LabeledContent(L.t("Titular", "Holder"), value: cuenta.titular)
                    LabeledContent(L.t("Celular", "Phone")) {
                        Text(cuenta.celularLegible).monospacedDigit()
                    }
                } header: {
                    Text(L.t("Mi QR para recibir", "My QR to receive"))
                } footer: {
                    Text(L.t("Es una demostración: el código lleva los datos de una cuenta inventada y ninguna app de pagos lo leerá como un cobro. No se mueve dinero real.",
                             "This is a demo: the code carries the details of a made-up account and no payment app will read it as a charge. No real money moves."))
                }
            }
            .estiloFormularioPreferencias()
            .navigationTitle(L.t("Pagar con QR", "Pay with QR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }
                }
            }
            .onAppear {
                store.reintentarLectura()
                // QR estático (sin importe): quien paga escribe cuánto envía,
                // que es lo que se espera de un QR de cuenta personal.
                if qr == nil {
                    actualizarQR()
                }
            }
            .onChange(of: billeteraCobro) { _, _ in
                AppHaptics.selection()
                actualizarQR()
            }
        }
        .seguirTemaForzado()
        .fullScreenCover(isPresented: $escanear) {
            EscanerQRView(errorPago: { store.errorParaCobrarPasaje($0) }) { importe in
                store.cobrarPasaje(importe)
            }
        }
    }

    /// La otra mitad de la hoja: escanear el QR de quien cobra.
    private var botonEscanear: some View {
        Button {
            AppHaptics.impact(.medium)
            escanear = true
        } label: {
            Label(L.t("Escanear un QR", "Scan a QR"), systemImage: "qrcode.viewfinder")
        }
        .buttonStyle(BotonMonederoStyle(destacado: true))
    }

    /// Marca, código y propósito en una sola pieza centrada. El QR va sobre
    /// blanco en los dos temas para que cualquier lector lo reconozca.
    private var codigoDeCobro: some View {
        VStack(spacing: 14) {
            MarcaBilletera(billetera: billeteraCobro, altura: 44)

            Group {
                if let qr {
                    Image(uiImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .accessibilityLabel(L.t("QR de cobro de demostración",
                                                "Demo payment QR"))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 220)
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )

            Text(L.t("Muestra este código para recibir una transferencia.",
                     "Show this code to receive a transfer."))
                .font(.footnote)
                .foregroundStyle(EstiloPreferencias.textoSecundario)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func actualizarQR() {
        qr = PagoQR.imagen(PagoQR.cargaUtil(cuenta: cuenta))
    }
}
