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
/// - **Cobrar**: el QR de la cuenta propia, para que quien quiera transferir
///   solo tenga que escanearlo. Es la mitad que se enseña.
/// - **Pagar**: el lector, para escanear el QR del cobrador.
struct QRPasajeSheet: View {

    @ObservedObject var store: MonederoStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    private var apilarContenido: Bool { textSize >= .xxxLarge }

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
                        Button(L.t("Reintentar lectura", "Retry reading")) { store.reintentarLectura() }
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
                store.reintentarLectura()
                // QR estático (sin importe): quien paga escribe cuánto envía,
                // que es lo que se espera de un QR de cuenta personal.
                if qr == nil {
                    actualizarQR()
                }
            }
        }
        .seguirTemaForzado()
        .fullScreenCover(isPresented: $escanear) {
            EscanerQRView(errorPago: { store.errorParaCobrarPasaje($0) }) { importe in
                store.cobrarPasaje(importe)
            }
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

            (apilarContenido ? AnyLayout(VStackLayout(spacing: 10))
                              : AnyLayout(HStackLayout(spacing: 10))) {
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
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(L.f("Mostrar el QR de {0}", "Show the {0} QR", ["\(opcion.nombre)"]))
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
    }

    private func actualizarQR() {
        qr = PagoQR.imagen(PagoQR.cargaUtil(cuenta: cuenta))
    }

    private func filaDato(_ etiqueta: String, _ valor: String) -> some View {
        (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                          : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
            Text(etiqueta)
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if !apilarContenido { Spacer(minLength: 8) }
            Text(valor)
                .font(.bodySmMedium)
                .foregroundStyle(.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta)
        .accessibilityValue(valor)
    }

    private var aviso: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appAccent)
            Text(L.t("Es una demostración: el código lleva los datos de una cuenta inventada y ninguna app de pagos lo leerá como un cobro. No se mueve dinero real.",
                     "This is a demo: the code carries the details of a made-up account and no payment app will read it as a charge. No real money moves."))
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
                .foregroundStyle(.onPrimaryFill)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primaryContainer))
            }
            .buttonStyle(PressableCapsuleStyle())

            Text(L.f("Escanea el QR del cobrador y se descuenta el pasaje ({0}) del saldo de demostración.", "Scan the collector's QR and the fare ({0}) is deducted from the demo balance.", ["\(store.tarifaTexto)"]))
                .font(.bodyXs)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
