import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct FichaMicroVerificada {
    let identidad: IdentidadMicro
    let vinculo: VinculoMicro
    let foto: CGImage
}

struct FichaReferenciaMicro {
    let referencia: ReferenciaFotoMicro
    let foto: CGImage
}

/// Solo lee recursos de la app. No descarga, inventa asociaciones ni escribe datos.
actor CatalogoMicrosService {
    static let shared = CatalogoMicrosService()
    private var cargado = false
    private var identidades: [String: IdentidadMicro] = [:]
    private var vinculos: [String: [VinculoMicro]] = [:]
    private var referencias: [String: ReferenciaFotoMicro] = [:]
    private final class FotoCache {
        let imagen: CGImage
        init(_ imagen: CGImage) { self.imagen = imagen }
    }
    private let fotos: NSCache<NSString, FotoCache> = {
        let cache = NSCache<NSString, FotoCache>()
        cache.totalCostLimit = 6 * 1024 * 1024
        cache.countLimit = 8
        return cache
    }()

    func ficha(para referencia: ReferenciaMicroGTFS, subida: String? = nil,
               bajada: String? = nil, ahora: Date = .now) -> FichaMicroVerificada? {
        cargarCatalogo()
        let candidatos = (vinculos[referencia.routeID] ?? []).filter {
            $0.referenciaGTFS == referencia && $0.cubre(subida: subida, bajada: bajada)
                && verificacionVigente($0.verificacion, ahora: ahora)
        }
        // Ida, vuelta y brazos pueden compartir ruta. Nunca elegir el primer
        // registro por orden si dos carteles cubren el mismo tramo.
        guard !Task.isCancelled, candidatos.count == 1, let vinculo = candidatos.first,
              let identidad = identidades[vinculo.identidadID],
              identidad.empresa == referencia.empresa,
              identidad.letra == GTFSNombreParser.identificacionTransporte(
                linea: referencia.linea, variante: referencia.variante).letra,
              let imagen = foto(identidad.foto), !Task.isCancelled else { return nil }
        return FichaMicroVerificada(identidad: identidad, vinculo: vinculo, foto: imagen)
    }

    func fotoReferencia(para ruta: ReferenciaMicroGTFS, ahora: Date = .now) -> FichaReferenciaMicro? {
        cargarCatalogo()
        guard !Task.isCancelled, let referencia = referencias[ruta.routeID],
              referencia.referenciaGTFS == ruta,
              let revisado = dia(referencia.fechaRevision),
              ahora.timeIntervalSince1970.isFinite,
              (0...4_133_980_799).contains(ahora.timeIntervalSince1970),
              revisado <= Int(floor(ahora.timeIntervalSince1970 / 86_400)),
              let url = URL(string: referencia.fuenteURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil,
              let imagen = foto(referencia.foto), !Task.isCancelled else { return nil }
        return FichaReferenciaMicro(referencia: referencia, foto: imagen)
    }

    private func cargarCatalogo() {
        guard !cargado else { return }
        cargado = true
        guard let url = Bundle.main.url(forResource: "catalogo", withExtension: "json", subdirectory: "micros"),
              let datos = try? Data(contentsOf: url), datos.count <= 256 * 1024,
              let catalogo = try? JSONDecoder().decode(CatalogoMicros.self, from: datos),
              catalogo.version == 1, catalogo.identidades.count <= 200, catalogo.vinculos.count <= 500,
              Set(catalogo.identidades.map(\.id)).count == catalogo.identidades.count,
              Set(catalogo.identidades.map { $0.foto.archivo }).count <= 48 else { return }
        let fotosReferencia = catalogo.referenciasFotograficas ?? []
        guard fotosReferencia.count <= 500,
              Set(fotosReferencia.map { $0.referenciaGTFS.routeID }).count == fotosReferencia.count,
              Set(catalogo.identidades.map { $0.foto.archivo } + fotosReferencia.map { $0.foto.archivo }).count <= 48 else { return }
        for identidad in catalogo.identidades {
            guard textoValido(identidad.id, limite: 80), textoValido(identidad.letra, limite: 20),
                  textoValido(identidad.empresa, limite: 160), (1...5).contains(identidad.colores.count),
                  identidad.colores.allSatisfy({ $0.hex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else { return }
        }
        for vinculo in catalogo.vinculos {
            guard catalogo.identidades.contains(where: { $0.id == vinculo.identidadID }),
                  vinculo.desdeIndice >= 0, vinculo.hastaIndice > vinculo.desdeIndice,
                  vinculo.hastaIndice < vinculo.referenciaGTFS.paraderos.count,
                  textoValido(vinculo.cartelDestino, limite: 160) else { return }
        }
        for referencia in fotosReferencia {
            let identificacion = GTFSNombreParser.identificacionTransporte(
                linea: referencia.referenciaGTFS.linea, variante: referencia.referenciaGTFS.variante)
            guard !identificacion.letra.isEmpty,
                  referencia.codigoFuente == identificacion.codigo + " " + identificacion.letra,
                  referencia.derechos == "pendiente" || referencia.derechos == "autorizado",
                  let revisado = dia(referencia.fechaRevision) else { return }
            if let fechaFoto = referencia.fechaFoto {
                guard let fotografiado = dia(fechaFoto), fotografiado <= revisado else { return }
            }
        }
        identidades = Dictionary(uniqueKeysWithValues: catalogo.identidades.map { ($0.id, $0) })
        vinculos = Dictionary(grouping: catalogo.vinculos, by: { $0.referenciaGTFS.routeID })
        referencias = Dictionary(uniqueKeysWithValues: fotosReferencia.map { ($0.referenciaGTFS.routeID, $0) })
    }

    private func foto(_ foto: IdentidadMicro.Foto) -> CGImage? {
        guard foto.archivo.range(of: "^[a-z0-9][a-z0-9-]{0,79}\\.jpg$", options: .regularExpression) != nil,
              foto.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              (200...960).contains(foto.ancho), (200...960).contains(foto.alto),
              textoValido(foto.credito, limite: 200), textoValido(foto.autorizacion, limite: 500) else { return nil }
        let clave = (foto.archivo + ":" + foto.sha256) as NSString
        if let entrada = fotos.object(forKey: clave) { return entrada.imagen }
        let nombre = String(foto.archivo.dropLast(4))
        guard let url = Bundle.main.url(forResource: nombre, withExtension: "jpg", subdirectory: "micros/fotos"),
              let atributos = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = atributos[.size] as? NSNumber, bytes.intValue <= 128 * 1024,
              let datos = try? Data(contentsOf: url), datos.count <= 128 * 1024,
              SHA256.hash(data: datos).map({ String(format: "%02x", $0) }).joined() == foto.sha256,
              let source = CGImageSourceCreateWithData(datos as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let ancho = properties[kCGImagePropertyPixelWidth] as? Int,
              let alto = properties[kCGImagePropertyPixelHeight] as? Int,
              ancho == foto.ancho, alto == foto.alto,
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              let imagen = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 960,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        fotos.setObject(FotoCache(imagen), forKey: clave, cost: imagen.bytesPerRow * imagen.height)
        return imagen
    }

    private func verificacionVigente(_ verificacion: VinculoMicro.Verificacion, ahora: Date) -> Bool {
        guard verificacion.estado == "verificado",
              textoValido(verificacion.fuente, limite: 500), textoValido(verificacion.verificadoPor, limite: 160),
              let desde = dia(verificacion.fecha), let hasta = dia(verificacion.vigenteHasta),
              ahora.timeIntervalSince1970.isFinite,
              (0...4_133_980_799).contains(ahora.timeIntervalSince1970) else { return false }
        let hoy = Int(floor(ahora.timeIntervalSince1970 / 86_400))
        return desde <= hoy && hoy <= hasta && desde <= hasta
    }

    private func dia(_ texto: String) -> Int? {
        guard texto.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let partes = texto.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3, (1970...2100).contains(partes[0]) else { return nil }
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(secondsFromGMT: 0)!
        let componentes = DateComponents(year: partes[0], month: partes[1], day: partes[2])
        guard let fecha = calendario.date(from: componentes),
              calendario.dateComponents([.year, .month, .day], from: fecha).year == partes[0],
              calendario.component(.month, from: fecha) == partes[1], calendario.component(.day, from: fecha) == partes[2] else { return nil }
        return Int(floor(fecha.timeIntervalSince1970 / 86_400))
    }

    private func textoValido(_ texto: String, limite: Int) -> Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && texto.count <= limite
    }
}
