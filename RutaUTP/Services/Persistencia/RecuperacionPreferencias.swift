import Foundation

/// Recuperación solicitada por el usuario desde una confirmación de la interfaz.
/// El archivo conserva los tipos originales, incluso si no son JSON legible.
enum RecuperacionPreferencias {
    enum Fallo: Error { case datosCambiaron }

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
