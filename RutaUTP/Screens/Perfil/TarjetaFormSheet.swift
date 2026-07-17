//
//  TarjetaFormSheet.swift
//  RutaUTP
//
//  CORREGIDO V3: Sheet para agregar metodo de pago.
//  - 4 campos: numero, titular, vencimiento, CVV
//  - Numero formateado como 0000 0000 0000 0000
//  - Vencimiento como MM/AA
//  - CVV como SecureField
//

import SwiftUI

struct TarjetaFormSheet: View {
    var onGuardar: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cardNumber: String = ""
    @State private var cardholder: String = ""
    @State private var expiry: String = ""
    @State private var cvv: String = ""

    private var formValido: Bool {
        cardNumber.filter { $0.isNumber }.count == 16 &&
        !cardholder.trimmingCharacters(in: .whitespaces).isEmpty &&
        expiry.filter { $0.isNumber }.count == 4 &&
        cvv.filter { $0.isNumber }.count >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Icono header
                    HStack {
                        Spacer()
                        ZStack {
                            Circle().fill(Color.secondary.opacity(0.12)).frame(width: 64, height: 64)
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)

                    Text("Agregar metodo de pago")
                        .font(.headlineMd)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Numero de tarjeta
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Numero de tarjeta", systemImage: "number")
                            .font(.labelCapsMd)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)
                        TextField("0000 0000 0000 0000", text: $cardNumber)
                            .keyboardType(.numberPad)
                            .font(.bodyLg)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                            .onChange(of: cardNumber) { newValue in
                                cardNumber = formatCardNumber(newValue)
                            }
                    }

                    // Titular
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Titular de la tarjeta", systemImage: "person")
                            .font(.labelCapsMd)
                            .foregroundStyle(.onSurfaceVariant)
                            .appTracking(AppTracking.wideLabel)
                        TextField("Nombre como aparece en la tarjeta", text: $cardholder)
                            .textInputAutocapitalization(.words)
                            .font(.bodyMd)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                    }

                    // Vencimiento + CVV
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Vencimiento", systemImage: "calendar")
                                .font(.labelCapsMd)
                                .foregroundStyle(.onSurfaceVariant)
                                .appTracking(AppTracking.wideLabel)
                            TextField("MM/AA", text: $expiry)
                                .keyboardType(.numberPad)
                                .font(.bodyMd)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                                .onChange(of: expiry) { newValue in
                                    expiry = formatExpiry(newValue)
                                }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label("CVV", systemImage: "lock")
                                .font(.labelCapsMd)
                                .foregroundStyle(.onSurfaceVariant)
                                .appTracking(AppTracking.wideLabel)
                            SecureField("123", text: $cvv)
                                .keyboardType(.numberPad)
                                .font(.bodyMd)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
                                .onChange(of: cvv) { newValue in
                                    cvv = String(newValue.filter { $0.isNumber }.prefix(4))
                                }
                        }
                    }

                    Spacer().frame(height: 8)

                    // Boton Guardar
                    Button {
                        onGuardar(cardNumber)
                        dismiss()
                    } label: {
                        Text("Guardar tarjeta")
                            .font(.headlineSm)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(formValido ? Color.appPrimary : Color.appPrimary.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!formValido)

                    // Boton Cancelar
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancelar")
                            .font(.bodyMdMedium)
                            .foregroundStyle(.onSurfaceVariant)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
    }

    // MARK: - Formateo
    private func formatCardNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(16))
        var result = ""
        for (index, char) in limited.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }

    private func formatExpiry(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(4))
        if limited.count >= 3 {
            let month = limited.prefix(2)
            let year = limited.suffix(limited.count - 2)
            return "\(month)/\(year)"
        }
        return limited
    }
}

#Preview {
    TarjetaFormSheet(onGuardar: { _ in })
}

