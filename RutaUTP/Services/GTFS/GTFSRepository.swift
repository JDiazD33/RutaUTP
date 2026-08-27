//
//  GTFSRepository.swift
//  RutaUTP
//
//  Carga el feed GTFS estático embebido (gtfs/*.txt) y lo convierte en
//  modelos de dominio `RutaGTFS`.
//
//  - La carga es async e idempotente (se parsea una sola vez).
//  - El feed es de Trujillo (coordenadas -8.04, -79.05).
//  - NO incluye GPS en vivo: ver comentario en GTFSModels.swift.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Repositorio
actor GTFSRepository {

    static let shared = GTFSRepository()

    /// Campus UTP Trujillo (Av. Nicolás de Piérola 1221).
    static let coordenadaUTP = CLLocationCoordinate2D(latitude: -8.098247879173792,
                                                      longitude: -79.03818104755645)

    private var cache: [RutaGTFS]?
    private var tareaCarga: Task<[RutaGTFS], Never>?

    /// Devuelve todas las rutas del feed, ordenadas por cercanía a UTP.
    func rutas() async -> [RutaGTFS] {
        if let cache { return cache }
        if let tareaCarga { return await tareaCarga.value }

        let tarea = Task<[RutaGTFS], Never> { [weak self] in
            let rutas = Self.parsearFeed()
            await self?.guardar(rutas)
            return rutas
        }
        tareaCarga = tarea
        let resultado = await tarea.value
        tareaCarga = nil
        return resultado
    }

    private func guardar(_ rutas: [RutaGTFS]) {
        cache = rutas
    }

    /// Las `n` rutas cuyo recorrido pasa más cerca del campus UTP.
    func rutasCercaDeUTP(n: Int) async -> [RutaGTFS] {
        Array(await rutas().prefix(n))
    }
}

// MARK: - Parseo del feed
extension GTFSRepository {

    static func parsearFeed() -> [RutaGTFS] {
        do {
            return try parsear()
        } catch {
            #if DEBUG
            print("[GTFS] Error parseando feed: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private static func parsear() throws -> [RutaGTFS] {
        // 1. Agencias
        let agency = try GTFSCSV.tabla("agency")
        let nombresAgencia = diccionario(agency.columna("agency_id"),
                                         agency.columna("agency_name"))

        // 2. Rutas
        let routes = try GTFSCSV.tabla("routes")
        let routeIds    = routes.columna("route_id")
        let routeAgency = routes.columna("agency_id")
        let routeShort  = routes.columna("route_short_name")
        let routeLong   = routes.columna("route_long_name")
        let routeColor  = routes.columna("route_color")

        // 3. Trips (en este feed: 1 trip por ruta, trip_id == route_id)
        let trips = try GTFSCSV.tabla("trips")
        let tripRoute = diccionario(trips.columna("trip_id"), trips.columna("route_id"))
        let tripShape = diccionario(trips.columna("trip_id"), trips.columna("shape_id"))
        // route_id → trip_id
        var routeTrip: [String: String] = [:]
        for (trip, route) in tripRoute { routeTrip[route] = trip }

        // 4. Shapes ordenados por secuencia
        let shapes = try GTFSCSV.tabla("shapes")
        var shapesPorId: [String: [Int: CLLocationCoordinate2D]] = [:]
        let shapeIds  = shapes.columna("shape_id")
        let shapeLats = shapes.columna("shape_pt_lat")
        let shapeLons = shapes.columna("shape_pt_lon")
        let shapeSeqs = shapes.columna("shape_pt_sequence")
        for i in 0..<shapes.rowCount {
            guard let lat = Double(shapeLats[i]), let lon = Double(shapeLons[i]),
                  let seq = Int(shapeSeqs[i]) else { continue }
            shapesPorId[shapeIds[i], default: [:]][seq] =
                CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // 5. Paraderos
        let stops = try GTFSCSV.tabla("stops")
        var paraderosPorId: [String: ParaderoGTFS] = [:]
        let stopIds    = stops.columna("stop_id")
        let stopNames  = stops.columna("stop_name")
        let stopLats   = stops.columna("stop_lat")
        let stopLons   = stops.columna("stop_lon")
        for i in 0..<stops.rowCount {
            guard let lat = Double(stopLats[i]), let lon = Double(stopLons[i]) else { continue }
            paraderosPorId[stopIds[i]] = ParaderoGTFS(id: stopIds[i], nombre: stopNames[i],
                                                      lat: lat, lon: lon)
        }

        // 6. Stop times: paradas ordenadas + duración por trip
        let stopTimes = try GTFSCSV.tabla("stop_times")
        var paradasPorTrip: [String: [(seq: Int, stopId: String, departure: Int)]] = [:]
        for i in 0..<stopTimes.rowCount {
            let tripId = stopTimes.columna("trip_id")[i]
            guard let seq = Int(stopTimes.columna("stop_sequence")[i]) else { continue }
            let stopId = stopTimes.columna("stop_id")[i]
            let dep = segundos(stopTimes.columna("departure_time")[i])
            paradasPorTrip[tripId, default: []].append((seq, stopId, dep))
        }

        // 7. Frecuencias (headway)
        let frequencies = try GTFSCSV.tabla("frequencies")
        var headwayPorTrip: [String: Int] = [:]
        let freqTrips = frequencies.columna("trip_id")
        let freqHeadways = frequencies.columna("headway_secs")
        for i in 0..<frequencies.rowCount {
            guard let h = Int(freqHeadways[i]) else { continue }
            headwayPorTrip[freqTrips[i]] = h
        }

        // 8. Tarifas: route_id → fare_id → precio
        let fareRules = try GTFSCSV.tabla("fare_rules")
        let fareAttr  = try GTFSCSV.tabla("fare_attributes")
        let precioPorFare = diccionario(fareAttr.columna("fare_id"),
                                        fareAttr.columna("price"))
        var precioPorRuta: [String: Double] = [:]
        for i in 0..<fareRules.rowCount {
            let ruta = fareRules.columna("route_id")[i]
            let fare = fareRules.columna("fare_id")[i]
            if let precio = Double(precioPorFare[fare] ?? "") {
                precioPorRuta[ruta] = precio
            }
        }

        // 9. Armar dominio
        var rutas: [RutaGTFS] = []
        rutas.reserveCapacity(routes.rowCount)

        for i in 0..<routes.rowCount {
            let routeId  = routeIds[i]
            let shortName = routeShort[i]
            let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: shortName)

            let tripId = routeTrip[routeId] ?? routeId
            let shapeId = tripShape[tripId] ?? routeId
            let shapePuntos = (shapesPorId[shapeId] ?? [:])
                .sorted { $0.key < $1.key }
                .map(\.value)

            let paradas = (paradasPorTrip[tripId] ?? [])
                .sorted { $0.seq < $1.seq }
            let paraderos = paradas.compactMap { paraderosPorId[$0.stopId] }

            // Duración del viaje según stop_times (última - primera salida)
            var duracionMin = 0
            if let primera = paradas.first?.departure, let ultima = paradas.last?.departure,
               ultima >= primera {
                duracionMin = Int((ultima - primera) / 60)
            }

            let headwayMin = (headwayPorTrip[tripId] ?? 0) / 60

            let colorHex = routeColor[i].isEmpty ? "00CC00" : routeColor[i]
            let recorrido = GTFSNombreParser.recorrido(longName: routeLong[i], shortName: shortName)

            let distanciaUTP = distanciaMinima(shapePuntos, a: coordenadaUTP)
            let longitudKm = longitudTotalKm(shapePuntos)

            rutas.append(RutaGTFS(
                id: routeId,
                linea: linea,
                variante: variante,
                recorrido: recorrido,
                empresa: nombresAgencia[routeAgency[i]] ?? "Transporte Trujillo",
                colorHex: colorHex,
                color: Color(hex: colorHex),
                shape: shapePuntos,
                paraderos: paraderos,
                duracionMin: duracionMin,
                headwayMin: headwayMin,
                precio: precioPorRuta[routeId] ?? 0,
                distanciaKm: longitudKm,
                distanciaUTPMetros: distanciaUTP
            ))
        }

        return rutas.sorted { $0.distanciaUTPMetros < $1.distanciaUTPMetros }
    }
}

// MARK: - Helpers
private extension GTFSRepository {

    static func diccionario(_ claves: [String], _ valores: [String]) -> [String: String] {
        var resultado: [String: String] = [:]
        for i in 0..<min(claves.count, valores.count) {
            resultado[claves[i]] = valores[i]
        }
        return resultado
    }

    /// "01:17:24" → 4644 segundos (tolera horas > 24 como GTFS permite).
    static func segundos(_ hhmmss: String) -> Int {
        let partes = hhmmss.split(separator: ":")
        guard partes.count == 3,
              let h = Int(partes[0]), let m = Int(partes[1]), let s = Int(partes[2]) else { return 0 }
        return h * 3600 + m * 60 + s
    }

    /// Distancia haversine en metros.
    static func distanciaMetros(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let radioTierra = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let latA = a.latitude * .pi / 180
        let latB = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(latA) * cos(latB) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radioTierra * asin(min(1, sqrt(h)))
    }

    static func distanciaMinima(_ puntos: [CLLocationCoordinate2D],
                                a destino: CLLocationCoordinate2D) -> Double {
        var minima = Double.greatestFiniteMagnitude
        for p in puntos {
            let d = distanciaMetros(p, destino)
            if d < minima { minima = d }
        }
        return minima == .greatestFiniteMagnitude ? 0 : minima
    }

    static func longitudTotalKm(_ puntos: [CLLocationCoordinate2D]) -> Double {
        guard puntos.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<puntos.count {
            total += distanciaMetros(puntos[i - 1], puntos[i])
        }
        return (total / 1000).rounded(toPlaces: 1)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
