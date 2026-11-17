//
//  RespaldoDatos.swift
//  RutaUTP
//
//  Respaldo manual de los datos del usuario y restauración de copias.
//
//  Las copias viven en `Documents/Recuperacion`, junto a las que crean las
//  secciones antes de reiniciar datos ilegibles (`RecuperacionPreferencias`),
//  y usan su mismo formato: `version`, `claves`, `valores` y `fecha`. Las
//  copias de esta pantalla añaden `tipo`. También se leen las copias antiguas
//  de líneas, con `clave` y `valor`.
//
//  Solo se restauran claves de `catalogo` y con el tipo esperado: un archivo
//  importado no puede escribir otras preferencias (credenciales, opciones de
//  depuración…). Antes de restaurar se guarda una copia automática de los
//  valores que se van a sustituir, de modo que la restauración se puede deshacer.
//  Inventario de claves: PERSISTENCIA.md.
//

import Foundation
import CoreFoundation

enum RespaldoDatos {

    // MARK: - Catálogo

    enum Categoria: String, CaseIterable, Identifiable, Sendable {
        case lugares, lineas, accesos, cupones, subidas, contacto, datosPersonales, preferencias

        var id: String { rawValue }

        var titulo: String {
            switch self {
            case .lugares: return L.t("Lugares guardados", "Saved places")
            case .lineas: return L.t("Líneas guardadas", "Saved lines")
            case .accesos: return L.t("Accesos de Seguridad", "Safety shortcuts")
            case .cupones: return L.t("Cupones guardados", "Saved coupons")
            case .subidas: return L.t("Lugares de subida", "Boarding spots")
            case .contacto: return L.t("Contacto de emergencia", "Emergency contact")
            case .datosPersonales: return L.t("Datos personales", "Personal details")
            case .preferencias: return L.t("Preferencias", "Preferences")
            }
        }

        var icono: String {
            switch self {
            case .lugares: return "bookmark.fill"
            case .lineas: return "point.topleft.down.to.point.bottomright.curvepath"
            case .accesos: return "square.grid.2x2"
            case .cupones: return "ticket"
            case .subidas: return "figure.stand"
            case .contacto: return "phone.circle"
            case .datosPersonales: return "person.text.rectangle"
            case .preferencias: return "gearshape"
            }
        }
    }

    enum TipoValor: Sendable {
        /// `Data` con un arreglo JSON (listas Codable de cada almacén).
        case listaJSON
        case texto
        case booleano
        case listaTextos
    }

    struct ClaveRespaldo: Sendable {
        let clave: String
        let tipo: TipoValor
        let categoria: Categoria
    }

    /// Claves que se respaldan y las únicas que se pueden restaurar. No incluye
    /// fotos (archivos), tarjetas, saldo del monedero, notificaciones (dependen
    /// de permisos del sistema) ni la temática, la sede o el modo Buses UTP,
    /// que Root normaliza en conjunto.
    static let catalogo: [ClaveRespaldo] = [
        ClaveRespaldo(clave: "lugares.guardados.v2", tipo: .listaJSON, categoria: .lugares),           // LugaresStore.key
        ClaveRespaldo(clave: "lineas.guardadas.v1", tipo: .listaJSON, categoria: .lineas),            // GuardadoViewModel
        ClaveRespaldo(clave: "seguridad.tiles.v1", tipo: .listaJSON, categoria: .accesos),            // SeguridadLugaresModel
        ClaveRespaldo(clave: "seguridad.tiles.orden.v1", tipo: .listaJSON, categoria: .accesos),
        ClaveRespaldo(clave: "negocios.cupones.guardados", tipo: .listaTextos, categoria: .cupones),  // NegociosService
        ClaveRespaldo(clave: "rutautp.boarding-place-notes.v1", tipo: .listaJSON, categoria: .subidas), // BoardingPlaceStore.key
        ClaveRespaldo(clave: "emergencia_nombre", tipo: .texto, categoria: .contacto),               // ContactoEmergencia
        ClaveRespaldo(clave: "emergencia_parentesco", tipo: .texto, categoria: .contacto),
        ClaveRespaldo(clave: "emergencia_numero", tipo: .texto, categoria: .contacto),
        ClaveRespaldo(clave: "emergencia_numeroAlternativo", tipo: .texto, categoria: .contacto),
        ClaveRespaldo(clave: "perfil_telefono", tipo: .texto, categoria: .datosPersonales),          // DatosPersonalesSheet
        ClaveRespaldo(clave: "perfil_correoPersonal", tipo: .texto, categoria: .datosPersonales),
        ClaveRespaldo(clave: "idioma.app", tipo: .texto, categoria: .preferencias),                   // IdiomaManager
        ClaveRespaldo(clave: "isDarkMode", tipo: .booleano, categoria: .preferencias),
        ClaveRespaldo(clave: "senias.modo.activado", tipo: .booleano, categoria: .preferencias),      // SeniasService.llaveModo
        ClaveRespaldo(clave: "perfil_compartirUbicacion", tipo: .booleano, categoria: .preferencias), // PreferenciasApp
        ClaveRespaldo(clave: "ciudadSeleccionada", tipo: .texto, categoria: .preferencias)           // CiudadSheet
    ]

    private static let catalogoPorClave: [String: ClaveRespaldo] =
        Dictionary(uniqueKeysWithValues: catalogo.map { ($0.clave, $0) })

    /// Las copias son pequeñas; un archivo mayor no es un respaldo de la app.
    static let limiteBytes = 2_000_000

    /// Avisa a las pantallas abiertas de que los datos cambiaron.
    static let restaurado = Notification.Name("respaldo.datos.restaurado")

    // MARK: - Contenido

    /// Valor ya validado. `ausente` solo aparece en copias automáticas: la
    /// clave no existía antes de restaurar y deshacer la vuelve a quitar.
    enum Valor: Sendable, Equatable {
        case datos(Data)
        case texto(String)
        case booleano(Bool)
        case textos([String])
        case ausente

        var objeto: Any? {
            switch self {
            case .datos(let valor): return valor
            case .texto(let valor): return valor
            case .booleano(let valor): return valor
            case .textos(let valor): return valor
            case .ausente: return nil
            }
        }
    }

    enum TipoCopia: Sendable, Equatable {
        case manual
        case automatica
        case importada
        /// Copia previa a reiniciar una sección (`accesos`, `cupones`, `subidas`, `lineas`…).
        case seccion(String)
    }

    struct Contenido: Sendable {
        let tipo: TipoCopia
        let fecha: Date?
        let entradas: [String: Valor]
        /// Claves desconocidas o con un tipo inesperado; no se restauran.
        let ignoradas: Int

        var titulo: String { RespaldoDatos.titulo(tipo) }

        var categorias: [Categoria] {
            let presentes = Set(entradas.keys.compactMap { catalogoPorClave[$0]?.categoria })
            return Categoria.allCases.filter { presentes.contains($0) }
        }

        func claves(de categorias: Set<Categoria>) -> [String] {
            entradas.keys.filter { clave in
                catalogoPorClave[clave].map { categorias.contains($0.categoria) } ?? false
            }.sorted()
        }

        /// Texto breve de lo que guarda una categoría, p. ej. «3 lugares».
        func resumen(_ categoria: Categoria) -> String {
            func lista(_ clave: String) -> Int? {
                switch entradas[clave] {
                case .datos(let datos)?: return RespaldoDatos.contarLista(datos)
                case .textos(let textos)?: return textos.count
                default: return nil
                }
            }
            func cantidad(_ n: Int, _ uno: (String, String), _ varios: (String, String)) -> String {
                n == 1 ? L.t(uno.0, uno.1) : L.f(varios.0, varios.1, ["\(n)"])
            }
            let quitar = L.t("Se quitará", "Will be removed")
            switch categoria {
            case .lugares:
                guard let n = lista("lugares.guardados.v2") else { return quitar }
                return cantidad(n, ("1 lugar", "1 place"), ("{0} lugares", "{0} places"))
            case .lineas:
                guard let n = lista("lineas.guardadas.v1") else { return quitar }
                return cantidad(n, ("1 línea", "1 line"), ("{0} líneas", "{0} lines"))
            case .accesos:
                guard let n = lista("seguridad.tiles.v1") ?? lista("seguridad.tiles.orden.v1") else { return quitar }
                return cantidad(n, ("1 acceso", "1 shortcut"), ("{0} accesos", "{0} shortcuts"))
            case .cupones:
                guard let n = lista("negocios.cupones.guardados") else { return quitar }
                return cantidad(n, ("1 cupón", "1 coupon"), ("{0} cupones", "{0} coupons"))
            case .subidas:
                guard let n = lista("rutautp.boarding-place-notes.v1") else { return quitar }
                return cantidad(n, ("1 lugar de subida", "1 boarding spot"), ("{0} lugares de subida", "{0} boarding spots"))
            case .contacto:
                if case .texto(let nombre)? = entradas["emergencia_nombre"],
                   !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nombre
                }
                let configurado = ["emergencia_numero", "emergencia_numeroAlternativo"].contains { clave in
                    if case .texto(let numero)? = entradas[clave] { return !numero.isEmpty }
                    return false
                }
                return configurado ? L.t("Configurado", "Set up") : L.t("Sin datos", "No data")
            case .datosPersonales:
                let n = ["perfil_telefono", "perfil_correoPersonal"].filter { entradas[$0] != nil }.count
                return cantidad(n, ("1 campo", "1 field"), ("{0} campos", "{0} fields"))
            case .preferencias:
                let nombres: [(String, String)] = [
                    ("idioma.app", L.t("Idioma", "Language")),
                    ("isDarkMode", L.t("Tema", "Theme")),
                    ("senias.modo.activado", L.t("Modo Señas", "Sign Language Mode")),
                    ("perfil_compartirUbicacion", L.t("Ubicación", "Location")),
                    ("ciudadSeleccionada", L.t("Ciudad", "City"))
                ]
                return nombres.filter { entradas[$0.0] != nil }.map { $0.1 }.joined(separator: ", ")
            }
        }
    }

    enum Fallo: Error {
        case archivoGrande, formatoNoValido, sinDatos
    }

    static func mensaje(_ error: Error) -> String {
        switch error as? Fallo {
        case .archivoGrande?:
            return L.t("El archivo es demasiado grande para ser un respaldo de RutaUTP.",
                       "The file is too large to be a RutaUTP backup.")
        case .formatoNoValido?:
            return L.t("El archivo no es un respaldo de RutaUTP o está dañado.",
                       "The file isn't a RutaUTP backup or is damaged.")
        case .sinDatos?:
            return L.t("No hay datos que guardar o restaurar.", "There's no data to save or restore.")
        case nil:
            return L.t("No se pudo completar la operación. Revisa el espacio disponible y que el iPhone esté desbloqueado.",
                       "The operation couldn't be completed. Check available storage and that the iPhone is unlocked.")
        }
    }

    static func titulo(_ tipo: TipoCopia) -> String {
        switch tipo {
        case .manual: return L.t("Respaldo manual", "Manual backup")
        case .automatica: return L.t("Copia previa a restaurar", "Copy before restoring")
        case .importada: return L.t("Respaldo importado", "Imported backup")
        case .seccion(let nombre):
            switch nombre {
            case "accesos": return L.t("Accesos de Seguridad antes de reiniciar", "Safety shortcuts before reset")
            case "cupones": return L.t("Cupones antes de reiniciar", "Coupons before reset")
            case "subidas": return L.t("Lugares de subida antes de reiniciar", "Boarding spots before reset")
            case "lineas": return L.t("Líneas antes de reiniciar", "Lines before reset")
            default: return L.t("Copia antes de reiniciar una sección", "Copy before resetting a section")
            }
        }
    }

    // MARK: - Carpeta

    static func carpeta(crear: Bool) throws -> URL {
        let documentos = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: crear)
        let directorio = documentos.appendingPathComponent("Recuperacion", isDirectory: true)
        if crear { try FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true) }
        return directorio
    }

    // MARK: - Crear

    /// Guarda los valores actuales del catálogo. Lanza `sinDatos` si no hay ninguno.
    @MainActor
    @discardableResult
    static func crearManual(defaults: UserDefaults = .standard) throws -> URL {
        let presentes = catalogo.map(\.clave).filter { defaults.object(forKey: $0) != nil }
        guard !presentes.isEmpty else { throw Fallo.sinDatos }
        return try escribirCopia(tipo: "manual", claves: presentes, defaults: defaults)
    }

    /// `claves` puede incluir claves ausentes: la copia las registra sin valor.
    @MainActor
    private static func escribirCopia(tipo: String, claves: [String], defaults: UserDefaults) throws -> URL {
        let valores = Dictionary(uniqueKeysWithValues: claves.compactMap { clave in
            defaults.object(forKey: clave).map { (clave, $0) }
        })
        let datos = try PropertyListSerialization.data(fromPropertyList: [
            "version": 1, "tipo": tipo, "claves": claves, "valores": valores, "fecha": Date()
        ], format: .binary, options: 0)
        let archivo = try carpeta(crear: true).appendingPathComponent("\(tipo)-\(UUID().uuidString).plist")
        try datos.write(to: archivo, options: [.atomic, .completeFileProtection])
        return archivo
    }

    // MARK: - Leer

    /// No modifica archivos ni preferencias; se puede llamar fuera de MainActor.
    static func leer(_ url: URL) throws -> Contenido {
        let valores = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard (valores.fileSize ?? 0) <= limiteBytes else { throw Fallo.archivoGrande }
        let datos = try Data(contentsOf: url)
        return try interpretar(datos, nombre: url.lastPathComponent, fechaArchivo: valores.contentModificationDate)
    }

    static func interpretar(_ datos: Data, nombre: String, fechaArchivo: Date?) throws -> Contenido {
        guard datos.count <= limiteBytes else { throw Fallo.archivoGrande }
        guard let raiz = (try? PropertyListSerialization.propertyList(from: datos, options: [], format: nil))
                as? [String: Any] else { throw Fallo.formatoNoValido }
        if let version = raiz["version"] as? Int, version != 1 { throw Fallo.formatoNoValido }

        var originales: [(clave: String, valor: Any?)] = []
        if let claves = raiz["claves"] as? [String] {
            let valores = raiz["valores"] as? [String: Any] ?? [:]
            originales = claves.map { ($0, valores[$0]) }
        } else if let clave = raiz["clave"] as? String {
            originales = [(clave, raiz["valor"])]
        } else {
            throw Fallo.formatoNoValido
        }

        let tipo = tipoCopia(nombre: nombre, declarado: raiz["tipo"] as? String)
        var entradas: [String: Valor] = [:]
        var ignoradas = 0
        for (clave, original) in originales {
            guard let definicion = catalogoPorClave[clave] else { ignoradas += 1; continue }
            guard let original else {
                if tipo == .automatica { entradas[clave] = .ausente }
                continue
            }
            guard let valor = validar(original, como: definicion.tipo) else { ignoradas += 1; continue }
            entradas[clave] = valor
        }
        return Contenido(tipo: tipo, fecha: raiz["fecha"] as? Date ?? fechaArchivo,
                         entradas: entradas, ignoradas: ignoradas)
    }

    /// El prefijo del archivo manda sobre el contenido: una copia importada
    /// sigue siéndolo aunque dentro diga que era automática.
    private static func tipoCopia(nombre: String, declarado: String?) -> TipoCopia {
        let prefijo = nombre.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        switch prefijo {
        case "importada": return .importada
        case "manual": return .manual
        case "automatica": return .automatica
        default:
            switch declarado {
            case "manual"?: return .manual
            case "automatica"?: return .automatica
            default: return .seccion(prefijo)
            }
        }
    }

    private static func validar(_ valor: Any, como tipo: TipoValor) -> Valor? {
        switch tipo {
        case .listaJSON:
            guard let datos = valor as? Data, contarLista(datos) != nil else { return nil }
            return .datos(datos)
        case .texto:
            guard let texto = valor as? String, texto.count <= 500 else { return nil }
            return .texto(texto)
        case .booleano:
            guard let numero = valor as? NSNumber, CFGetTypeID(numero) == CFBooleanGetTypeID() else { return nil }
            return .booleano(numero.boolValue)
        case .listaTextos:
            guard let textos = valor as? [String], textos.count <= 1_000 else { return nil }
            return .textos(textos)
        }
    }

    /// Elementos de una lista JSON; nil si no lo es.
    static func contarLista(_ datos: Data) -> Int? {
        ((try? JSONSerialization.jsonObject(with: datos)) as? [Any])?.count
    }

    // MARK: - Restaurar

    /// Restaura las categorías elegidas y devuelve la copia automática previa.
    @MainActor
    @discardableResult
    static func restaurar(_ contenido: Contenido, categorias: Set<Categoria>,
                          defaults: UserDefaults = .standard) throws -> URL {
        let claves = contenido.claves(de: categorias)
        guard !claves.isEmpty else { throw Fallo.sinDatos }
        // Si la copia previa falla, no se toca ningún valor actual.
        let previa = try escribirCopia(tipo: "automatica", claves: claves, defaults: defaults)
        for clave in claves {
            if let objeto = contenido.entradas[clave]?.objeto {
                defaults.set(objeto, forKey: clave)
            } else {
                defaults.removeObject(forKey: clave)
            }
        }
        refrescarAlmacenes(claves: claves, defaults: defaults)
        return previa
    }

    /// Los almacenes con caché en memoria releen lo restaurado; las vistas
    /// con @AppStorage se actualizan solas.
    @MainActor
    private static func refrescarAlmacenes(claves: [String], defaults: UserDefaults) {
        LugaresStore.invalidarCache()
        if claves.contains("idioma.app") {
            IdiomaManager.shared.seleccionar(codigo: defaults.string(forKey: "idioma.app") ?? "es")
        }
        NotificationCenter.default.post(name: NegociosService.cuponesActualizados, object: nil)
        NotificationCenter.default.post(name: restaurado, object: nil)
    }

    // MARK: - Importar y eliminar

    /// Copia un respaldo elegido en Archivos a la carpeta de la app.
    @discardableResult
    static func importar(desde origen: URL) throws -> URL {
        let acceso = origen.startAccessingSecurityScopedResource()
        defer { if acceso { origen.stopAccessingSecurityScopedResource() } }
        if let tamano = try? origen.resourceValues(forKeys: [.fileSizeKey]).fileSize, tamano > limiteBytes {
            throw Fallo.archivoGrande
        }
        let datos = try Data(contentsOf: origen)
        let contenido = try interpretar(datos, nombre: "importada", fechaArchivo: nil)
        guard !contenido.entradas.isEmpty else { throw Fallo.sinDatos }
        let destino = try carpeta(crear: true).appendingPathComponent("importada-\(UUID().uuidString).plist")
        try datos.write(to: destino, options: [.atomic, .completeFileProtection])
        return destino
    }

    /// Solo borra archivos de la carpeta de respaldos.
    static func eliminar(_ url: URL) throws {
        let directorio = try carpeta(crear: false).resolvingSymlinksInPath().path
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().path == directorio else {
            throw Fallo.formatoNoValido
        }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Resumen de datos actuales

    struct ResumenLocal: Equatable {
        var lugares = 0
        var lineas = 0
        var contactoConfigurado = false
    }

    @MainActor
    static func resumenLocal(defaults: UserDefaults = .standard) -> ResumenLocal {
        let lineas = (defaults.object(forKey: "lineas.guardadas.v1") as? Data).flatMap(contarLista) ?? 0
        let numero = defaults.string(forKey: ContactoEmergencia.claveNumero) ?? ""
        return ResumenLocal(lugares: LugaresStore.cargar().filter { !$0.esFijo }.count,
                            lineas: lineas,
                            contactoConfigurado: ContactoEmergencia.telefonoValido(numero) != nil)
    }
}
