// ResultadoQR.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import Foundation

enum ErrorPagoQR: Equatable {
    case formatoNoReconocido
    case importeIlegible
    case monedaAmbigua
    case monedaNoIndicada
    case monedaNoAdmitida
    case importeInvalido

    var mensaje: String {
        switch self {
        case .formatoNoReconocido:
            return L.t("El código no tiene un formato de pago reconocido.",
                       "The code does not have a recognized payment format.")
        case .importeIlegible:
            return L.t("El código contiene un importe ilegible o ambiguo. No se puede pagar con esta lectura.",
                       "The code contains an unreadable or ambiguous amount. This reading can't be used to pay.")
        case .monedaAmbigua:
            return L.t("El QR repite la moneda. No se puede pagar con esta lectura.",
                       "The QR repeats the currency. This reading can't be used to pay.")
        case .monedaNoIndicada:
            return L.t("No se puede confirmar la moneda de este importe. Usa un QR en soles.",
                       "The currency of this amount cannot be confirmed. Use a QR in soles.")
        case .monedaNoAdmitida:
            return L.t("Este monedero demo solo admite soles. No se convierte la moneda del QR.",
                       "This demo wallet only accepts soles. The QR currency is not converted.")
        case .importeInvalido:
            return L.t("El importe del QR no es válido para este monedero. Usa una cantidad positiva en soles y sin fracciones de céntimo.",
                       "The QR amount is not valid for this wallet. Use a positive amount in soles with whole cents.")
        }
    }
}

/// Resultado de una lectura.
struct ResultadoQR: Identifiable, Equatable {
    /// Dos viajes pueden leer el mismo QR estático. La identidad pertenece a
    /// esta captura, no al texto ni al importe, y no se guarda en el monedero.
    let id = UUID()
    let texto: String
    let campos: PagoQR.CamposQR

    /// Política común para presentación y acción. PEN/604 son las dos formas
    /// admitidas para soles; no hay conversión. Solo un QR estático reconocido
    /// sin importe ni moneda puede conservar la tarifa local de la demo.
    @MainActor
    var errorParaPagoDemo: ErrorPagoQR? {
        guard campos.esPago else { return .formatoNoReconocido }
        guard !campos.importeInvalido else { return .importeIlegible }
        guard !campos.monedaInvalida else { return .monedaAmbigua }
        if let moneda = campos.monedaNormalizada {
            guard !moneda.isEmpty else { return .monedaNoIndicada }
            guard moneda == "PEN" || moneda == "604" else { return .monedaNoAdmitida }
        } else if campos.importe != nil {
            return .monedaNoIndicada
        }
        guard MonederoStore.importeValidoParaPasaje(campos.importe ?? MonederoStore.tarifaReferencia) != nil else {
            return .importeInvalido
        }
        return nil
    }

    @MainActor
    var importeParaPagoDemo: Double? {
        guard errorParaPagoDemo == nil else { return nil }
        return MonederoStore.importeValidoParaPasaje(campos.importe ?? MonederoStore.tarifaReferencia)
    }

    /// nil indica lectura no admitida: el callback ni siquiera se invoca.
    /// El monedero sigue decidiendo si puede debitar el importe autorizado.
    @MainActor
    func pagarDemo(onPagar: @MainActor (Double) -> Bool) -> Bool? {
        guard let importe = importeParaPagoDemo else { return nil }
        return onPagar(importe)
    }
}
