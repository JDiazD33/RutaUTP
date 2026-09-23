//
//  PagoQR.swift
//  RutaUTP
//
//  Carga útil y dibujo del QR de cobro del monedero.
//
//  La carga útil es **texto plano legible**: la primera línea dice a qué
//  billetera pertenece la cuenta (`DEMO YAPO`, `DEMO PLUN`) y debajo van los
//  datos como `clave: valor`. Así, quien lo escanee con cualquier lector ve algo
//  que se entiende.
//
//  **No usa el formato TLV del estándar interoperable (EMVCo), y es a
//  propósito.** Se probó y en la mano daba dos problemas: al escanearlo salía
//  una ristra de dígitos sin sentido, y el nombre con tilde viajaba como dos
//  bytes UTF-8 que los lectores que decodifican en otra codificación convertían
//  en un carácter de otro alfabeto («Joaquín» se veía «Joaqu铆n»). Por eso la
//  carga útil se genera **en ASCII puro** (`ascii(_:)`) y no lleva tildes.
//
//  El lector sí sabe interpretar un TLV de verdad, por si alguien escanea un QR
//  de pago real.
//
//  ─────────────────────────────────────────────────────────────────────────
//  IMPORTANTE — ESTO ES UNA DEMOSTRACIÓN
//
//  Las billeteras son propias («Yapo», «Plun») y `cuentaDemo` (titular y
//  celular) es inventada, así que ninguna app de pagos va a leer este QR como un
//  cobro. La interfaz lo dice en pantalla.
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

    /// Cuenta que recibe el dinero. Ver la nota del encabezado del archivo: el
    /// titular y el celular son inventados.
    static let cuentaDemo = CuentaCobro(
        titular: "Joaquín Díaz",
        celular: "999888777",
        ciudad: "Trujillo",
        billetera: .yape
    )

    // MARK: - Carga útil

    /// Carga útil del QR: texto legible, en ASCII.
    ///
    /// **Por qué ya no es TLV.** Antes se generaba la estructura del estándar
    /// interoperable (EMVCo). En la mano tenía dos problemas: al escanearlo con
    /// cualquier lector salía una ristra de dígitos sin sentido, y el nombre con
    /// tilde viajaba como dos bytes UTF-8 que los lectores que decodifican en
    /// otra codificación convertían en un carácter de otro alfabeto
    /// («Joaquín» se veía como «Joaqu铆n»). Como las billeteras son propias de
    /// la demo y ninguna app real va a leer este QR, lo que importa es que se
    /// entienda: la primera línea dice «DEMO YAPO» o «DEMO PLUN» y debajo van
    /// los datos de la cuenta.
    ///
    /// - Parameter importe: si se indica, se añade una línea con el monto.
    static func cargaUtil(
        cuenta: CuentaCobro = cuentaDemo,
        importe: Double? = nil
    ) -> String {
        var lineas = ["DEMO \(cuenta.billetera.nombre.uppercased())"]
        lineas.append("titular: \(ascii(cuenta.titular))")
        lineas.append("celular: \(cuenta.celular)")
        lineas.append("ciudad: \(ascii(cuenta.ciudad))")
        lineas.append("moneda: PEN")

        if let importe, importe.isFinite, importe > 0 {
            lineas.append(String(format: "importe: %.2f", importe))
        }

        return lineas.joined(separator: "\n")
    }

    /// Deja el texto en ASCII: quita tildes y descarta lo que no sea ASCII.
    ///
    /// Es lo que evita el fallo que se veía al escanear: una tilde son dos bytes
    /// UTF-8, y un lector que decodifique en otra codificación los convierte en
    /// un carácter de otro alfabeto. «Joaquín Díaz» pasa a «Joaquin Diaz».
    static func ascii(_ texto: String) -> String {
        texto
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isASCII }
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
        /// Billetera que emitió el código, si se pudo identificar («Yapo», «Plun»).
        var billetera: String?
        var titular: String?
        var ciudad: String?
        var celular: String?
        var importe: Double?
        var moneda: String?
        var pais: String?
        /// `true` si el código es de los nuestros: lo emite `cargaUtil`.
        var esDemo: Bool = false
        /// `true` si la carga útil tiene estructura de pago, no texto suelto.
        var esPago: Bool

        /// Importe listo para mostrar, con el símbolo del sol.
        var importeTexto: String? {
            guard let importe else { return nil }

            let simbolo = moneda == "604" || moneda == "PEN" ? "S/ " : ""

            return simbolo + String(format: "%.2f", importe)
        }
    }

    /// Interpreta la carga útil de un QR.
    ///
    /// Entiende dos formas y no lanza nunca: lo que no reconoce queda como
    /// texto suelto (`esPago == false`).
    ///
    /// 1. **La de la demo**, que es la que emite `cargaUtil`: primera línea
    ///    `DEMO <BILLETERA>` y después líneas `clave: valor`.
    /// 2. **Un QR de pago real**, con la estructura TLV del estándar
    ///    interoperable. El lector es una herramienta de la app, así que
    ///    conviene que sepa leer uno de verdad aunque nosotros no los generemos.
    static func leer(_ cargaUtil: String) -> CamposQR {
        let demo = leerDemo(cargaUtil)

        if demo.esPago {
            return demo
        }

        return leerTLV(cargaUtil)
    }

    /// Formato propio: `DEMO YAPO` en la primera línea y `clave: valor` debajo.
    private static func leerDemo(_ cargaUtil: String) -> CamposQR {
        var campos = CamposQR(esPago: false)

        let lineas = cargaUtil
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let primera = lineas.first, primera.hasPrefix("DEMO ") else {
            return campos
        }

        campos.esPago = true
        campos.esDemo = true
        campos.billetera = String(primera.dropFirst("DEMO ".count)).capitalized

        for linea in lineas.dropFirst() {
            let partes = linea.split(separator: ":", maxSplits: 1)

            guard partes.count == 2 else { continue }

            let clave = partes[0].trimmingCharacters(in: .whitespaces).lowercased()
            let valor = partes[1].trimmingCharacters(in: .whitespaces)

            switch clave {
            case "titular": campos.titular = valor
            case "celular": campos.celular = valor
            case "ciudad": campos.ciudad = valor
            case "moneda": campos.moneda = valor
            case "importe": campos.importe = Double(valor)
            default: break
            }
        }

        return campos
    }

    /// Interpreta una carga útil TLV (QR de pago real).
    ///
    /// Recorre los campos de primer nivel; el bloque `26` (cuenta) se abre
    /// aparte porque lleva sus propios subcampos.
    private static func leerTLV(_ cargaUtil: String) -> CamposQR {
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
