import Foundation

/// Metadatos del archivo, sin interpretar ni aplicar las preferencias copiadas.
struct ArchivoRecuperacion: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let fecha: Date?
    let bytes: Int?
}

/// Recuperación solicitada por el usuario desde una confirmación de la interfaz.
/// El archivo conserva los tipos originales, incluso si no son JSON legible.
enum RecuperacionPreferencias {
    enum Fallo: Error { case datosCambiaron, directorioInvalido }

    /// Relee el directorio en cada apertura, también para copias del formato
    /// antiguo de líneas o archivos ilegibles que todavía se pueden exportar.
    /// La E/S no ocupa MainActor y no crea/modifica archivos ni preferencias.
    static func listar(directorio: URL? = nil) async throws -> [ArchivoRecuperacion] {
        let lectura = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let carpeta = try directorio ?? FileManager.default.url(for: .documentDirectory,
                in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("Recuperacion", isDirectory: true)
            let propiedades: Set<URLResourceKey> = [
                .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey
            ]
            let archivos: [URL]
            do {
                let raiz = try carpeta.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard raiz.isDirectory == true, raiz.isSymbolicLink != true else {
                    throw Fallo.directorioInvalido
                }
                archivos = try FileManager.default.contentsOfDirectory(at: carpeta,
                    includingPropertiesForKeys: Array(propiedades), options: [.skipsHiddenFiles])
            } catch {
                if esArchivoAusente(error) { return [ArchivoRecuperacion]() }
                throw error
            }
            var copias: [ArchivoRecuperacion] = []
            for archivo in archivos where archivo.pathExtension.lowercased() == "plist" {
                try Task.checkCancellation()
                let valores: URLResourceValues
                do { valores = try archivo.resourceValues(forKeys: propiedades) }
                catch {
                    // Una copia retirada mientras se lista no oculta las demás.
                    if esArchivoAusente(error) { continue }
                    throw error
                }
                guard valores.isRegularFile == true, valores.isSymbolicLink != true else { continue }
                copias.append(ArchivoRecuperacion(url: archivo,
                    fecha: valores.contentModificationDate, bytes: valores.fileSize))
            }
            try Task.checkCancellation()
            return copias.sorted {
                let izquierda = $0.fecha ?? .distantPast
                let derecha = $1.fecha ?? .distantPast
                if izquierda != derecha { return izquierda > derecha }
                return $0.url.lastPathComponent < $1.url.lastPathComponent
            }
        }
        return try await withTaskCancellationHandler {
            try await lectura.value
        } onCancel: {
            lectura.cancel()
        }
    }

    private static func esArchivoAusente(_ error: Error) -> Bool {
        let fallo = error as NSError
        return fallo.domain == NSCocoaErrorDomain
            && (fallo.code == NSFileReadNoSuchFileError || fallo.code == NSFileNoSuchFileError)
    }

    @MainActor
    static func reiniciar(claves: [String], valoresNuevos: [String: Any],
                          nombre: String, defaults: UserDefaults,
                          crearRespaldo: ((Data) throws -> URL)? = nil) throws -> URL {
        let originales = Dictionary(uniqueKeysWithValues: claves.compactMap { clave in
            defaults.object(forKey: clave).map { (clave, $0) }
        })
        let copia = try PropertyListSerialization.data(fromPropertyList: [
            "version": 1, "claves": claves, "valores": originales, "fecha": Date()
        ], format: .binary, options: 0)
        let archivo: URL
        if let crearRespaldo {
            archivo = try crearRespaldo(copia)
        } else {
            let directorio = try FileManager.default.url(for: .documentDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Recuperacion", isDirectory: true)
            try FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
            archivo = directorio.appendingPathComponent("\(nombre)-\(UUID().uuidString).plist")
            try copia.write(to: archivo, options: [.atomic, .completeFileProtection])
        }
        // No sustituir datos reparados o cambiados mientras se creaba la copia.
        // Esto no constituye una transacción entre procesos de UserDefaults.
        guard claves.allSatisfy({ clave in
            let actual = defaults.object(forKey: clave)
            if let original = originales[clave] as? NSObject {
                return actual.map { original.isEqual($0) } ?? false
            }
            return actual == nil
        }) else { throw Fallo.datosCambiaron }

        for clave in claves {
            if let nuevo = valoresNuevos[clave] { defaults.set(nuevo, forKey: clave) }
            else { defaults.removeObject(forKey: clave) }
        }
        return archivo
    }
}
