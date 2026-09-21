//
//  PagoQR.swift
//  RutaUTP
//
//  Carga útil y dibujo del QR de cobro del monedero.
//
//  La carga útil sigue la estructura TLV del estándar de QR interoperable
//  (EMVCo, modalidad «presentado por el comercio»), que es el formato que usan
//  Yape y Plin para cobrar: campos de dos dígitos (identificador + longitud) y
//  un CRC16-CCITT como último campo.
//
//  ─────────────────────────────────────────────────────────────────────────
//  IMPORTANTE — ESTO ES UNA DEMOSTRACIÓN
//
//  El FORMATO es el real; los DATOS no. `cuentaDemo` (titular y celular) y
//  `guiaCuentaDemo` son inventados, así que ninguna billetera va a interpretar
//  este QR como un cobro válido. Para que cobre de verdad hay que sustituir los
//  tres por los que entregue el proveedor y ajustar la carga útil a lo que
//  documente su API. La interfaz lo dice en pantalla.
//  ─────────────────────────────────────────────────────────────────────────
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Billetera con la que se cobra o se paga.
///
/// Las marcas son propias de la demo a propósito (ver `nombre`): la aplicación
/// no usa logotipos ni nombres de marcas registradas ajenas.
enum BilleteraPago: String, CaseIterable, Identifiable {
    case yape
    case plin

    var id: String { rawValue }

    /// Nombre visible en la interfaz.
    ///
    /// NO es el de la billetera real: se muestran marcas propias («Yapo»,
    /// «Plun») para no apoyarse en marcas registradas ajenas. El caso del enum
    /// y el recurso del catálogo conservan el nombre del archivo original
    /// (`yape-logo`, `plin-logo`), que es como están guardados.
    var nombre: String {
        switch self {
        case .yape: return "Yapo"
        case .plin: return "Plun"
        }
    }

    /// Recurso de `Assets.xcassets`. Si todavía no se ha añadido la imagen, la
    /// interfaz dibuja el nombre sobre el color de marca en lugar de dejar un
    /// hueco roto (ver `MarcaBilletera`).
    var assetLogo: String {
        switch self {
        case .yape: return "yape-logo"
        case .plin: return "plin-logo"
        }
    }

    /// Color de marca para acentos, bordes y respaldo del logo.
    ///
    /// No sustituye a la imagen: los colores oficiales viven en el archivo.
    /// Esto solo hace que la tarjeta se reconozca mientras no esté.
    var colorMarca: Color {
        switch self {
        case .yape: return Color(light: "#7C1FA0", dark: "#C77CE0")
        case .plin: return Color(light: "#00939F", dark: "#5FD9E4")
        }
    }
}

/// Datos de la cuenta que recibe el dinero.
struct CuentaCobro: Equatable {
    var titular: String
    /// Celular asociado a la billetera. Solo dígitos.
    var celular: String
    var ciudad: String
    var billetera: BilleteraPago

    /// Celular agrupado de tres en tres: "999888777" → "999 888 777".
    var celularLegible: String {
        let digitos = String(celular.filter { $0.isNumber })

        guard !digitos.isEmpty else { return "" }

        var grupos: [String] = []
        var indice = digitos.startIndex

        while indice < digitos.endIndex {
            let fin = digitos.index(indice, offsetBy: 3, limitedBy: digitos.endIndex)
                ?? digitos.endIndex
            grupos.append(String(digitos[indice..<fin]))
            indice = fin
        }

        return grupos.joined(separator: " ")
    }
}

enum PagoQR {

    // MARK: - Datos de demostración

    /// Cuenta que recibe el dinero. Ver la nota del encabezado del archivo:
    /// el titular, el celular y la guía son inventados.
    static let cuentaDemo = CuentaCobro(
        titular: "Joaquín Díaz",
        celular: "999888777",
        ciudad: "Trujillo",
        billetera: .yape
    )

    /// Identificador de cuenta del estándar. Inventado: sustituir por el que
    /// asigne la billetera.
    private static let guiaCuentaDemo = "PE.RUTAUTP.DEMO"

    // MARK: - Carga útil

    /// Carga útil TLV del QR.
    ///
    /// - Parameter importe: `nil` genera un QR **estático**, el que se enseña
    ///   para que quien pague escriba cuánto quiere enviar. Con importe se marca
    ///   como dinámico y se añade el campo `54` con el monto.
    static func cargaUtil(
        cuenta: CuentaCobro = cuentaDemo,
        importe: Double? = nil
    ) -> String {
        // La billetera forma parte del identificador de demostración para que
        // cambiar entre Yapo y Plun produzca también un QR distinto.
        let guiaBilletera = guiaCuentaDemo + "." + cuenta.billetera.rawValue.uppercased()
        var cuerpo = campo("00", "01")                        // versión del formato
        cuerpo += campo("01", importe == nil ? "11" : "12")   // estático / dinámico
        cuerpo += campo("26", campo("00", guiaBilletera) + campo("01", cuenta.celular))
        cuerpo += campo("53", "604")                          // moneda: sol
        if let importe, importe.isFinite, importe > 0 {
            cuerpo += campo("54", String(format: "%.2f", importe))
        }
        cuerpo += campo("58", "PE")                           // país
        cuerpo += campo("59", String(cuenta.titular.prefix(25)))
        cuerpo += campo("60", String(cuenta.ciudad.prefix(15)))
        cuerpo += "6304"                                      // cabecera del CRC

        return cuerpo + crc16(cuerpo)
    }

    /// Un campo TLV: identificador (2) + longitud (2) + valor.
    ///
    /// La longitud son **bytes UTF-8**, que es la unidad en la que después se
    /// recorre la cadena al leerla. Se expresa en dos dígitos, así que un valor
    /// de más de 99 bytes no cabe: se recorta en vez de escribir una longitud
    /// inválida.
    private static func campo(_ identificador: String, _ valor: String) -> String {
        let bytes = valor.utf8.count

        guard bytes <= 99 else {
            return identificador + String(format: "%02d", 0)
        }

        return identificador + String(format: "%02d", bytes) + valor
    }

    /// CRC16-CCITT (polinomio 0x1021, valor inicial 0xFFFF), el que exige el
    /// estándar para el último campo del QR.
    static func crc16(_ texto: String) -> String {
        var crc: UInt16 = 0xFFFF

        for byte in texto.utf8 {
            crc ^= UInt16(byte) << 8

            for _ in 0..<8 {
                // El desplazamiento descarta el bit alto por sí solo; no hace
                // falta enmascarar el resultado.
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }

        return String(format: "%04X", crc)
    }

    // MARK: - Dibujo

    /// Dibuja la carga útil como QR.
    ///
    /// - Parameter escala: píxeles por módulo. Con 12 sale una imagen de unos
    ///   500 px, de sobra para pantalla y para imprimir.
    static func imagen(_ cargaUtil: String, escala: CGFloat = 12) -> UIImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(cargaUtil.utf8)
        // Nivel Q (25 % de recuperación): aguanta mejor una pantalla con brillo
        // o un lector algo torcido que el nivel M.
        filtro.correctionLevel = "Q"

        guard let salida = filtro.outputImage else { return nil }

        let escalada = salida.transformed(by: CGAffineTransform(scaleX: escala, y: escala))

        guard let cg = CIContext().createCGImage(escalada, from: escalada.extent) else {
            return nil
        }

        return UIImage(cgImage: cg)
    }

    // MARK: - Lectura

    /// Lo que se pudo entender de un QR leído.
    struct CamposQR: Equatable {
        var titular: String?
        var ciudad: String?
        var celular: String?
        var importe: Double?
        var moneda: String?
        var pais: String?
        /// `true` si la carga útil tiene estructura de pago, no texto suelto.
        var esPago: Bool

        /// Importe listo para mostrar, con el símbolo del sol.
        var importeTexto: String? {
            guard let importe else { return nil }

            let simbolo = moneda == "604" ? "S/ " : ""

            return simbolo + String(format: "%.2f", importe)
        }
    }

    /// Interpreta una carga útil TLV.
    ///
    /// Recorre los campos de primer nivel; el bloque `26` (cuenta) se abre
    /// aparte porque lleva sus propios subcampos. Un QR que no sea TLV válido
    /// devuelve `esPago == false` y ningún campo: nunca lanza.
    static func leer(_ cargaUtil: String) -> CamposQR {
        var campos = CamposQR(esPago: false)

        let nivel1 = camposTLV(cargaUtil)

        // La versión de formato y el CRC son lo que distingue un QR de pago de
        // cualquier otro código (una URL, un texto suelto).
        guard nivel1["00"] == "01", nivel1["63"] != nil else {
            return campos
        }

        campos.esPago = true
        campos.titular = nivel1["59"]
        campos.ciudad = nivel1["60"]
        campos.pais = nivel1["58"]
        campos.moneda = nivel1["53"]

        if let texto = nivel1["54"], let valor = Double(texto) {
            campos.importe = valor
        }

        if let cuenta = nivel1["26"] {
            campos.celular = camposTLV(cuenta)["01"]
        }

        return campos
    }

    /// Campos TLV de primer nivel.
    ///
    /// Recorre **bytes** UTF-8, que es la unidad en la que está expresada la
    /// longitud de cada campo. Hacerlo sobre caracteres descuadraría en cuanto
    /// un valor llevara una tilde, como el nombre del titular.
    static func camposTLV(_ texto: String) -> [String: String] {
        let bytes = Array(texto.utf8)
        var campos: [String: String] = [:]
        var indice = 0

        while indice + 4 <= bytes.count {
            guard
                let identificador = cadena(bytes[indice..<(indice + 2)]),
                let textoLongitud = cadena(bytes[(indice + 2)..<(indice + 4)]),
                let longitud = Int(textoLongitud)
            else {
                break
            }

            let inicio = indice + 4

            guard longitud >= 0, inicio + longitud <= bytes.count else {
                break
            }

            if let valor = cadena(bytes[inicio..<(inicio + longitud)]) {
                campos[identificador] = valor
            }

            indice = inicio + longitud
        }

        return campos
    }

    private static func cadena(_ bytes: ArraySlice<UInt8>) -> String? {
        String(bytes: bytes, encoding: .utf8)
    }
}
