// Utilidad de macOS para preparar JPEG. No asigna rutas ni verifica datos o derechos.
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

struct FalloFoto: Error { let mensaje: String }

/// Retira EXIF/XMP e IPTC, incluidos los metadatos que ImageIO genera al codificar.
/// Conserva el perfil ICC, los datos de imagen y cualquier credito visible.
func sinMetadatosPrivados(_ datos: Data) throws -> Data {
    let bytes = [UInt8](datos)
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
        throw FalloFoto(mensaje: "El codificador no produjo un JPEG valido.")
    }
    var limpio = Data(bytes[0..<2])
    var posicion = 2
    while posicion < bytes.count {
        let inicio = posicion
        guard bytes[posicion] == 0xFF else { break }
        while posicion < bytes.count, bytes[posicion] == 0xFF { posicion += 1 }
        guard posicion < bytes.count else { break }
        let marcador = bytes[posicion]
        posicion += 1
        if marcador == 0xDA || marcador == 0xD9 {
            limpio.append(contentsOf: bytes[inicio...])
            return limpio
        }
        guard posicion + 2 <= bytes.count else { break }
        let longitud = Int(bytes[posicion]) * 256 + Int(bytes[posicion + 1])
        guard longitud >= 2, posicion + longitud <= bytes.count else { break }
        if marcador != 0xE1 && marcador != 0xED {
            limpio.append(contentsOf: bytes[inicio..<(posicion + longitud)])
        }
        posicion += longitud
    }
    throw FalloFoto(mensaje: "El codificador produjo un JPEG incompleto.")
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw FalloFoto(mensaje: "Uso: swift tools/preparar-foto-micro.swift entrada salida.jpg")
    }
    let entrada = URL(fileURLWithPath: CommandLine.arguments[1])
    let salida = URL(fileURLWithPath: CommandLine.arguments[2])
    guard salida.lastPathComponent.range(of: "^[a-z0-9][a-z0-9-]{0,79}\\.jpg$", options: .regularExpression) != nil,
          !FileManager.default.fileExists(atPath: salida.path),
          let source = CGImageSourceCreateWithURL(entrada as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) == 1 else {
        throw FalloFoto(mensaje: "Entrada invalida o destino existente. Usa un nombre como nuevo-california-c.jpg.")
    }
    var elegida: (Data, CGImage)?
    for pixels in [960, 800, 640, 512, 400] {
        guard let imagen = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), min(imagen.width, imagen.height) >= 200 else { continue }
        for quality in [0.82, 0.70, 0.58, 0.46] {
            let data = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            // Codifica los pixeles transformados y limpia los metadatos del JPEG final.
            CGImageDestinationAddImage(encoder, imagen, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(encoder) else { continue }
            let limpio = try sinMetadatosPrivados(data as Data)
            guard limpio.count <= 128 * 1024 else { continue }
            elegida = (limpio, imagen)
            break
        }
        if elegida != nil { break }
    }
    guard let (datos, imagen) = elegida else {
        throw FalloFoto(mensaje: "No se obtuvo una foto dentro de los limites de peso y dimensiones. Revisa el archivo original.")
    }
    try FileManager.default.createDirectory(at: salida.deletingLastPathComponent(), withIntermediateDirectories: true)
    try datos.write(to: salida, options: .withoutOverwriting)
    let metadata: [String: Any] = ["archivo": salida.lastPathComponent,
        "sha256": SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined(),
        "ancho": imagen.width, "alto": imagen.height, "bytes": datos.count]
    let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: json, as: UTF8.self))
} catch {
    let texto = (error as? FalloFoto)?.mensaje ?? error.localizedDescription
    FileHandle.standardError.write(Data(("error: " + texto + "\n").utf8))
    exit(1)
}
