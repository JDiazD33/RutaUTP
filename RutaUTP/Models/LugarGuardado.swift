//
//  LugarGuardado.swift
//

import Foundation
import CoreLocation

enum CategoriaLugar: String, CaseIterable, Identifiable, Codable {
    case universidad = "Universidad"
    case hogar        = "Hogar"
    case trabajo      = "Trabajo"
    case estudios     = "Estudios"
    case salud        = "Salud"
    case tienda       = "Tienda"
    case mercado      = "Mercado"
    case centroComercial = "Centro comercial"
    case restaurante  = "Restaurante"
    case cafeteria    = "Cafetería"
    case parque       = "Parque"
    case gimnasio     = "Gimnasio"
    case plaza        = "Plaza"
    case playa        = "Playa"
    case paradero     = "Paradero"
    case personalizado = "Personalizado"
    case otro         = "Otro"

    var id: String { rawValue }

    /// Texto visible. El `rawValue` se persiste dentro de `LugarGuardado`, así
    /// que se mantiene como clave estable y NO se traduce: cambiarlo
    /// invalidaría los lugares ya guardados.
    var label: String {
        switch self {
        case .universidad: return L.t("Universidad", "University")
        case .hogar:       return L.t("Hogar", "Home")
        case .trabajo:     return L.t("Trabajo", "Work")
        case .estudios:    return L.t("Estudios", "Study")
        case .salud:       return L.t("Salud", "Health")
        case .tienda:      return L.t("Tienda", "Store")
        case .mercado:     return L.t("Mercado", "Market")
        case .centroComercial: return L.t("Centro comercial", "Shopping mall")
        case .restaurante: return L.t("Restaurante", "Restaurant")
        case .cafeteria:   return L.t("Cafetería", "Café")
        case .parque:      return L.t("Parque", "Park")
        case .gimnasio:    return L.t("Gimnasio", "Gym")
        case .plaza:       return L.t("Plaza", "Square")
        case .playa:       return L.t("Playa", "Beach")
        case .paradero:    return L.t("Paradero", "Bus stop")
        case .personalizado: return L.t("Personalizado", "Custom")
        case .otro:        return L.t("Otro", "Other")
        }
    }

    var icono: String {
        switch self {
        case .universidad: return "graduationcap.fill"
        case .hogar:       return "house.fill"
        case .trabajo:     return "briefcase.fill"
        case .estudios:    return "books.vertical.fill"
        case .salud:       return "cross.case.fill"
        case .tienda:      return "storefront.fill"
        case .mercado:     return "basket.fill"
        case .centroComercial: return "bag.fill"
        case .restaurante: return "fork.knife"
        case .cafeteria:   return "cup.and.saucer.fill"
        case .parque:      return "tree.fill"
        case .gimnasio:    return "dumbbell.fill"
        case .plaza:       return "building.columns.fill"
        case .playa:       return "water.waves"
        case .paradero:    return "bus.fill"
        case .personalizado: return "star.fill"
        case .otro:        return "mappin.circle.fill"
        }
    }
}

/// Símbolos locales disponibles para personalizar un lugar, con etiquetas
/// traducidas. Los valores persistidos son nombres estables de SF Symbols.
struct IconoLugar: Identifiable {
    let id: String
    let nombre: String

    static var opciones: [IconoLugar] {
        CategoriaLugar.allCases.filter { $0 != .personalizado }
            .map { IconoLugar(id: $0.icono, nombre: $0.label) } + [
            IconoLugar(id: "heart.fill", nombre: L.t("Corazón", "Heart")),
            IconoLugar(id: "star.fill", nombre: L.t("Estrella", "Star")),
            IconoLugar(id: "flag.fill", nombre: L.t("Bandera", "Flag")),
            IconoLugar(id: "person.2.fill", nombre: L.t("Personas", "People")),
            IconoLugar(id: "building.2.fill", nombre: L.t("Edificio", "Building")),
            IconoLugar(id: "book.closed.fill", nombre: L.t("Biblioteca", "Library")),
            IconoLugar(id: "pills.fill", nombre: L.t("Farmacia", "Pharmacy")),
            IconoLugar(id: "bed.double.fill", nombre: L.t("Hotel", "Hotel")),
            IconoLugar(id: "cart.fill", nombre: L.t("Compras", "Shopping")),
            IconoLugar(id: "car.fill", nombre: L.t("Auto", "Car")),
            IconoLugar(id: "airplane", nombre: L.t("Avión", "Airplane")),
            IconoLugar(id: "tram.fill", nombre: L.t("Tren", "Train")),
            IconoLugar(id: "bicycle", nombre: L.t("Bicicleta", "Bicycle")),
            IconoLugar(id: "figure.run", nombre: L.t("Correr", "Running")),
            IconoLugar(id: "soccerball", nombre: L.t("Fútbol", "Soccer")),
            IconoLugar(id: "pawprint.fill", nombre: L.t("Mascota", "Pet")),
            IconoLugar(id: "leaf.fill", nombre: L.t("Naturaleza", "Nature")),
            IconoLugar(id: "mountain.2.fill", nombre: L.t("Montaña", "Mountain")),
            IconoLugar(id: "sun.max.fill", nombre: L.t("Sol", "Sun")),
            IconoLugar(id: "moon.stars.fill", nombre: L.t("Noche", "Night")),
            IconoLugar(id: "music.note", nombre: L.t("Música", "Music")),
            IconoLugar(id: "film.fill", nombre: L.t("Cine", "Cinema")),
            IconoLugar(id: "gamecontroller.fill", nombre: L.t("Juegos", "Games")),
            IconoLugar(id: "gift.fill", nombre: L.t("Regalo", "Gift")),
            IconoLugar(id: "camera.fill", nombre: L.t("Cámara", "Camera")),
            IconoLugar(id: "scissors", nombre: L.t("Peluquería", "Hair salon")),
            IconoLugar(id: "wrench.and.screwdriver.fill", nombre: L.t("Taller", "Workshop")),
            IconoLugar(id: "banknote.fill", nombre: L.t("Dinero", "Money"))
        ]
    }
}

struct LugarGuardado: Identifiable, Equatable, Codable {
    let id: UUID
    var nombre: String
    var direccion: String
    var categoria: CategoriaLugar
    var esFrecuente: Bool
    var lat: Double?
    var lon: Double?
    var paraderoID: String?
    /// Opcional para seguir leyendo los lugares guardados antes del selector.
    var iconoPersonalizado: String?

    /// Lugares fijos de la app (ej. campus UTP): no se pueden eliminar.
    ///
    /// Es un campo PERSISTIDO, no derivado del nombre. Antes se calculaba con
    /// `nombre == "UTP"`, lo que ataba la invariante al texto visible: cambiar
    /// el nombre del lugar —o traducirlo— lo convertía en borrable. Además el
    /// nombre es un dato del prototipo y va a cambiar.
    var esFijo: Bool

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Los paraderos anteriores conservan su categoría e identificador persistidos.
    var esParadero: Bool { categoria == .paradero || paraderoID != nil }

    var icono: String {
        iconoPersonalizado ?? (esParadero ? CategoriaLugar.paradero.icono : categoria.icono)
    }

    /// Criterio compartido por Seguridad y el selector de destinos del mapa.
    /// El catálogo reconoce los guardados anteriores a la incorporación del ID.
    func esParaderoGuardado(en catalogo: [ParaderoGTFS]) -> Bool {
        !esFijo && (esParadero || catalogo.contains { corresponde(al: $0) })
    }

    init(id: UUID = UUID(),
         nombre: String,
         direccion: String,
         categoria: CategoriaLugar,
         esFrecuente: Bool = false,
         lat: Double? = nil,
         lon: Double? = nil,
         esFijo: Bool = false,
         paraderoID: String? = nil,
         iconoPersonalizado: String? = nil) {
        self.id = id
        self.nombre = nombre
        self.direccion = direccion
        self.categoria = categoria
        self.esFrecuente = esFrecuente
        self.lat = lat
        self.lon = lon
        self.esFijo = esFijo
        self.paraderoID = paraderoID
        self.iconoPersonalizado = iconoPersonalizado
    }

    /// Compatibilidad con los paraderos guardados antes de persistir su ID.
    func corresponde(al paradero: ParaderoGTFS) -> Bool {
        if paraderoID == paradero.id { return true }
        return nombre == paradero.nombre && coordinate.map {
            PolylineMatching.distanceMeters($0, paradero.coordinate) < 5
        } == true
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id, nombre, direccion, categoria, esFrecuente, lat, lon, esFijo, paraderoID, iconoPersonalizado
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self, forKey: .id)
        nombre      = try c.decode(String.self, forKey: .nombre)
        direccion   = try c.decode(String.self, forKey: .direccion)
        categoria   = try c.decode(CategoriaLugar.self, forKey: .categoria)
        esFrecuente = try c.decodeIfPresent(Bool.self, forKey: .esFrecuente) ?? false
        lat         = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon         = try c.decodeIfPresent(Double.self, forKey: .lon)
        paraderoID  = try c.decodeIfPresent(String.self, forKey: .paraderoID)
        iconoPersonalizado = try c.decodeIfPresent(String.self, forKey: .iconoPersonalizado)
        // Ausente en datos guardados por versiones anteriores: `LugaresStore`
        // los migra al cargar.
        esFijo      = try c.decodeIfPresent(Bool.self, forKey: .esFijo) ?? false
    }
}

/// Referencia persistida a una línea del feed GTFS (solo el route_id;
/// el resto se resuelve desde GTFSRepository al mostrar).
struct LineaGuardadaRef: Identifiable, Codable, Equatable {
    let routeId: String
    var id: String { routeId }
}
