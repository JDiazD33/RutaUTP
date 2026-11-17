//
//  RouteChangePresentation.swift
//  RutaUTP
//
//  Presentación y geometría compartidas de los cambios de ruta confirmados:
//  Reportar, Seguridad y el mapa principal usan los mismos motivos y tramos.
//

import SwiftUI
import CoreLocation

/// Motivos de un reporte. El valor crudo es el código del canal MQTT.
enum MotivoCambioRuta: String, CaseIterable, Identifiable {
    case obras = "works", cierre = "closure", desvio = "detour"
    case trafico = "traffic", choque = "crash"

    var id: String { rawValue }

    /// Rótulo corto para elegir el motivo.
    var titulo: String {
        switch self {
        case .obras: return L.t("Obras", "Roadworks")
        case .cierre: return L.t("Cierre", "Closure")
        case .desvio: return L.t("Desvío", "Detour")
        case .trafico: return L.t("Tráfico", "Traffic")
        case .choque: return L.t("Choque", "Crash")
        }
    }

    /// Rótulo de un aviso ya confirmado.
    var tituloAviso: String {
        switch self {
        case .obras: return L.t("Obras en la vía", "Roadworks")
        case .cierre: return L.t("Vía cerrada", "Road closed")
        case .desvio: return L.t("Desvío de ruta", "Route detour")
        case .trafico: return L.t("Tráfico intenso", "Heavy traffic")
        case .choque: return L.t("Choque en la vía", "Crash on the road")
        }
    }

    var icono: String {
        switch self {
        case .obras: return "cone.fill"
        case .cierre: return "xmark.octagon.fill"
        case .desvio: return "arrow.triangle.branch"
        case .trafico: return "car.2.fill"
        case .choque: return "exclamationmark.triangle.fill"
        }
    }

    /// Un tono por motivo, sin dos rojos: el cierre es rojo, el choque naranja
    /// y las obras ámbar. Cada tono mantiene contraste con el icono blanco.
    var tinta: Color {
        switch self {
        case .obras: return Color(light: "#7A5C00", dark: "#FFD54F")
        case .cierre: return Color(light: "#B42330", dark: "#FF9A9F")
        case .desvio: return Color(light: "#075DB5", dark: "#8EC8FF")
        case .trafico: return Color(light: "#6D3FB8", dark: "#C7A6FF")
        case .choque: return Color(light: "#B4470B", dark: "#FFA466")
        }
    }

    /// Obras, cierres y desvíos alteran el recorrido de una línea: admiten el
    /// tramo que deja de atender y la vía por la que pasa ahora. El tráfico y
    /// los choques son de la vía y afectan a cualquier línea que pase por ahí.
    var cambiaRecorrido: Bool { self != .trafico && self != .choque }
}

extension RouteChangeAlert {
    /// Un motivo desconocido nunca llega aquí: el servicio lo descarta.
    var motivo: MotivoCambioRuta { MotivoCambioRuta(rawValue: reason) ?? .desvio }

    var coordenada: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    var coordenadaFin: CLLocationCoordinate2D? {
        guard let endLat, let endLon else { return nil }
        return CLLocationCoordinate2D(latitude: endLat, longitude: endLon)
    }

    /// «Ahora va por Av. Valderrama», si algún reporte indicó la vía.
    var textoVia: String? {
        guard let via = via?.trimmingCharacters(in: .whitespacesAndNewlines), !via.isEmpty else { return nil }
        return L.f("Ahora va por {0}", "Now runs along {0}", [via])
    }

    /// Incidencia generada por la presentación, no por la comunidad.
    var esSimulado: Bool { simulated == true }

    /// Las obras duran hasta el día siguiente: la hora sola sería ambigua.
    /// Una incidencia simulada no tiene cuentas ni vigencia real que mostrar.
    var detalleVigencia: String {
        if esSimulado {
            return L.t("Incidencia simulada para la presentación", "Simulated incident for the presentation")
        }
        let fecha = Date(timeIntervalSince1970: expiresAt)
        let estilo = Calendar.current.isDateInToday(fecha)
            ? Date.FormatStyle(date: .omitted, time: .shortened)
            : Date.FormatStyle().weekday(.abbreviated).hour().minute()
        return L.f("{0} cuentas · hasta {1}", "{0} accounts · until {1}", ["\(confirmations)",
            fecha.formatted(estilo.locale(FormatoFecha.localeActivo))])
    }
}

/// Geometría de un cambio sobre el recorrido de una línea.
enum TramoCambioRuta {
    /// Un tramo mayor no es un desvío: suele ser un recorrido de ida y vuelta
    /// donde los dos puntos cayeron en sentidos distintos.
    static let longitudMaxima: Double = 8_000
    /// Distancia a la que un aviso se considera sobre el recorrido dibujado.
    static let margen: Double = 150

    /// Parte del recorrido entre el inicio del cambio y el punto donde la
    /// línea lo retoma. `nil` si el aviso no trae punto final o no encaja.
    static func coordenadas(de aviso: RouteChangeAlert,
                            en shape: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
        guard let fin = aviso.coordenadaFin else { return nil }
        return coordenadas(desde: aviso.coordenada, hasta: fin, en: shape)
    }

    /// Parte del recorrido entre dos puntos, en el orden de viaje de la línea.
    static func coordenadas(desde inicio: CLLocationCoordinate2D, hasta fin: CLLocationCoordinate2D,
                            en shape: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
        guard let a = PolylineMatching.match(point: inicio, on: shape, thresholdMeters: 500),
              let b = PolylineMatching.match(point: fin, on: shape, thresholdMeters: 500),
              a.isOnRoute, b.isOnRoute else { return nil }
        let (primero, segundo) = a.progressFraction <= b.progressFraction ? (a, b) : (b, a)
        var puntos = [primero.snapped]
        if segundo.segmentIndex > primero.segmentIndex {
            puntos += shape[(primero.segmentIndex + 1)...segundo.segmentIndex]
        }
        puntos.append(segundo.snapped)
        guard puntos.count >= 2, PolylineMatching.totalLengthMeters(puntos) <= longitudMaxima else { return nil }
        return puntos
    }

    /// Indica si el aviso toca la parte del recorrido que el pasajero usa.
    ///
    /// - Parameters:
    ///   - recorrido: tramo que se recorre a bordo, no la línea completa.
    ///   - mismaRuta: el aviso se reportó sobre esta misma línea y ramal.
    static func afecta(_ aviso: RouteChangeAlert, tramo: [CLLocationCoordinate2D]?,
                       recorrido: [CLLocationCoordinate2D], mismaRuta: Bool) -> Bool {
        guard recorrido.count >= 2 else { return false }
        // Un atasco o un choque afectan a toda línea que pase por el punto.
        guard aviso.motivo.cambiaRecorrido else { return cerca(aviso.coordenada, de: recorrido) }
        guard mismaRuta else { return false }
        if cerca(aviso.coordenada, de: recorrido) { return true }
        if let fin = aviso.coordenadaFin, cerca(fin, de: recorrido) { return true }
        // El viaje empieza o termina dentro del tramo que ya no se atiende.
        guard let tramo, tramo.count >= 2, let subida = recorrido.first, let bajada = recorrido.last else {
            return false
        }
        return cerca(subida, de: tramo) || cerca(bajada, de: tramo)
    }

    private static func cerca(_ punto: CLLocationCoordinate2D,
                              de linea: [CLLocationCoordinate2D]) -> Bool {
        PolylineMatching.match(point: punto, on: linea, thresholdMeters: margen)?.isOnRoute == true
    }
}

// MARK: - Calle nueva de un desvío

extension RouteChangeAlert {
    /// Calle por la que va ahora la línea. Solo existe cuando dos cuentas
    /// grabaron a bordo trazos que coinciden; vacía en cualquier otro caso.
    var calleNueva: [CLLocationCoordinate2D] {
        guard motivo.cambiaRecorrido, let path,
              let puntos = PolilineaCodificada.decodificar(path), puntos.count >= 2 else { return [] }
        return puntos
    }
}

/// Polilínea codificada con el algoritmo de Google y precisión 1e-5: el mismo
/// formato que valida el backend en `route_changes.py`.
enum PolilineaCodificada {
    static func codificar(_ puntos: [CLLocationCoordinate2D]) -> String {
        var texto = String.UnicodeScalarView()
        var anterior = (lat: 0, lon: 0)
        for punto in puntos {
            let actual = (lat: Int((punto.latitude * 1e5).rounded()),
                          lon: Int((punto.longitude * 1e5).rounded()))
            for delta in [actual.lat - anterior.lat, actual.lon - anterior.lon] {
                var valor = delta < 0 ? ~(delta << 1) : delta << 1
                while valor >= 0x20 {
                    texto.append(Unicode.Scalar(UInt8((0x20 | (valor & 0x1F)) + 63)))
                    valor >>= 5
                }
                texto.append(Unicode.Scalar(UInt8(valor + 63)))
            }
            anterior = actual
        }
        return String(texto)
    }

    /// `nil` si el texto no es una polilínea completa con coordenadas válidas.
    static func decodificar(_ texto: String, maximoPuntos: Int = 200) -> [CLLocationCoordinate2D]? {
        let bytes = Array(texto.utf8)
        guard !bytes.isEmpty else { return nil }
        var indice = 0
        var lat = 0
        var lon = 0
        var puntos: [CLLocationCoordinate2D] = []
        while indice < bytes.count {
            var deltas = [0, 0]
            for componente in 0..<2 {
                var resultado = 0
                var desplazamiento = 0
                while true {
                    guard indice < bytes.count, desplazamiento <= 30 else { return nil }
                    let bloque = Int(bytes[indice]) - 63
                    indice += 1
                    guard (0...63).contains(bloque) else { return nil }
                    resultado |= (bloque & 0x1F) << desplazamiento
                    desplazamiento += 5
                    if bloque < 0x20 { break }
                }
                deltas[componente] = (resultado & 1) != 0 ? ~(resultado >> 1) : resultado >> 1
            }
            lat += deltas[0]
            lon += deltas[1]
            let punto = CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            guard (-90...90).contains(punto.latitude), (-180...180).contains(punto.longitude),
                  puntos.count < maximoPuntos else { return nil }
            puntos.append(punto)
        }
        return puntos
    }
}

/// Preparación del trazo grabado antes de enviarlo al servidor.
enum TrazoDesvio {
    /// El servidor admite 120 puntos; tras rellenar los saltos largos quedan
    /// como máximo unos 110.
    static let maximoPuntos = 90
    /// Separación máxima entre puntos enviados. El servidor rechaza saltos de
    /// más de 600 m como errores del GPS.
    static let pasoMaximo: Double = 450

    /// Douglas-Peucker sobre una proyección local en metros, suficiente para
    /// los pocos kilómetros de un desvío.
    static func simplificar(_ puntos: [CLLocationCoordinate2D], tolerancia: Double) -> [CLLocationCoordinate2D] {
        guard puntos.count > 2, let origen = puntos.first else { return puntos }
        let kLat = 110_574.0
        let kLon = 111_320.0 * cos(origen.latitude * .pi / 180)
        let plano = puntos.map { (x: ($0.longitude - origen.longitude) * kLon,
                                  y: ($0.latitude - origen.latitude) * kLat) }
        var conservar = [Bool](repeating: false, count: puntos.count)
        conservar[0] = true
        conservar[puntos.count - 1] = true
        var pendientes = [(0, puntos.count - 1)]
        while let rango = pendientes.popLast() {
            let (a, b) = rango
            guard b > a + 1 else { continue }
            var mayor = 0.0
            var indice = a
            for i in (a + 1)..<b {
                let separacion = distancia(plano[i], aSegmentoDe: plano[a], hasta: plano[b])
                if separacion > mayor {
                    mayor = separacion
                    indice = i
                }
            }
            if mayor > tolerancia {
                conservar[indice] = true
                pendientes.append((a, indice))
                pendientes.append((indice, b))
            }
        }
        return puntos.indices.filter { conservar[$0] }.map { puntos[$0] }
    }

    /// Trazo listo para el reporte: simplificado hasta caber en
    /// `maximoPuntos` y sin saltos mayores que `pasoMaximo`.
    static func preparar(_ puntos: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var tolerancia = 6.0
        var simple = simplificar(puntos, tolerancia: tolerancia)
        while simple.count > maximoPuntos, tolerancia < 300 {
            tolerancia *= 1.5
            simple = simplificar(puntos, tolerancia: tolerancia)
        }
        if simple.count > maximoPuntos { simple = PolylineMatching.decimate(simple, maxPoints: maximoPuntos) }
        guard let primero = simple.first else { return [] }
        var resultado = [primero]
        for (a, b) in zip(simple, simple.dropFirst()) {
            let partes = Int((PolylineMatching.distanceMeters(a, b) / pasoMaximo).rounded(.up))
            if partes > 1 {
                for i in 1..<partes {
                    let t = Double(i) / Double(partes)
                    resultado.append(CLLocationCoordinate2D(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t))
                }
            }
            resultado.append(b)
        }
        return resultado
    }

    private static func distancia(_ p: (x: Double, y: Double), aSegmentoDe a: (x: Double, y: Double),
                                  hasta b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let largo2 = dx * dx + dy * dy
        let t = largo2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / largo2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Detecta, durante un viaje declarado en «Estoy en un micro», el tramo en que
/// el micro sale de su recorrido y lo retoma más adelante: ese trazo es la
/// calle nueva. Solo conserva el tramo fuera del recorrido y lo suelta al
/// cerrarlo; el resto del viaje no se guarda.
struct TrazadorDesvio {
    struct Desvio: Identifiable, Equatable {
        let id = UUID()
        let routeID: String
        /// Puntos sobre el recorrido donde lo deja y donde lo retoma.
        let inicio: CLLocationCoordinate2D
        let fin: CLLocationCoordinate2D
        /// Trazo listo para enviar: empieza en `inicio` y termina en `fin`.
        let trazo: [CLLocationCoordinate2D]
        /// Punto más alejado del recorrido: el que mejor nombra la calle nueva.
        let masLejano: CLLocationCoordinate2D
        /// Metros recorridos fuera del recorrido habitual.
        let longitud: Double

        static func == (a: Desvio, b: Desvio) -> Bool { a.id == b.id }
    }

    /// Deja el recorrido tras `lecturasSalida` lecturas a más de esta distancia.
    static let distanciaSalida: Double = 60
    /// Lo retoma tras `lecturasRegreso` lecturas a esta distancia o menos.
    static let distanciaRegreso: Double = 35
    static let lecturasSalida = 3
    static let lecturasRegreso = 2
    /// Un apartamiento menor puede ser error del GPS o del trazado GTFS.
    static let desviacionMinima: Double = 80
    static let precisionMaxima: Double = 50
    static let separacionMinima: Double = 10
    static let longitudMaxima: Double = 8_000
    static let duracionMaxima: TimeInterval = 45 * 60
    /// Más rápido que esto entre dos lecturas es un salto del GPS.
    static let velocidadMaxima: Double = 40
    /// Distancia en línea recta entre salida y regreso que admite el servidor
    /// (entre 50 m y 5 km), con el mismo margen que el formulario.
    static let tramoMinimo: Double = 60
    static let tramoMaximo: Double = 4_950

    private var ultimoEnRuta: PolylineMatching.MatchResult?
    private var salida: PolylineMatching.MatchResult?
    private var lecturasFuera: [(coordenada: CLLocationCoordinate2D, distancia: Double)] = []
    private var trazo: [CLLocationCoordinate2D] = []
    private var regresos: [PolylineMatching.MatchResult] = []
    private var desviacion: Double = 0
    private var masLejano: CLLocationCoordinate2D?
    private var longitud: Double = 0
    private var inicioFuera: Date?
    private var ultimaLectura: CLLocation?

    /// `true` mientras graba un tramo fuera del recorrido.
    var grabando: Bool { salida != nil }

    mutating func reiniciar() { self = TrazadorDesvio() }

    /// Procesa una lectura del GPS. Devuelve el desvío cuando el micro vuelve
    /// a su recorrido más adelante de donde lo dejó.
    mutating func procesar(_ lectura: CLLocation, recorrido: [CLLocationCoordinate2D],
                           routeID: String) -> Desvio? {
        guard lectura.horizontalAccuracy >= 0, lectura.horizontalAccuracy <= Self.precisionMaxima,
              CLLocationCoordinate2DIsValid(lectura.coordinate),
              let match = PolylineMatching.match(point: lectura.coordinate, on: recorrido,
                                                 thresholdMeters: Self.distanciaRegreso) else { return nil }
        if let previa = ultimaLectura {
            let segundos = lectura.timestamp.timeIntervalSince(previa.timestamp)
            guard segundos > 0, lectura.distance(from: previa) <= Self.velocidadMaxima * segundos else {
                return nil
            }
        }
        ultimaLectura = lectura
        let distancia = match.distanceToRoute

        guard let salida else {
            if distancia <= Self.distanciaRegreso {
                ultimoEnRuta = match
                lecturasFuera.removeAll()
            } else if distancia > Self.distanciaSalida {
                lecturasFuera.append((lectura.coordinate, distancia))
                if lecturasFuera.count >= Self.lecturasSalida, let ultimoEnRuta {
                    empezar(desde: ultimoEnRuta, en: lectura.timestamp)
                }
            } else {
                lecturasFuera.removeAll()
            }
            return nil
        }

        if distancia <= Self.distanciaRegreso {
            regresos.append(match)
            return regresos.count >= Self.lecturasRegreso ? cerrar(desde: salida, routeID: routeID) : nil
        }
        regresos.removeAll()
        agregar(lectura.coordinate, distancia: distancia)
        if longitud > Self.longitudMaxima
            || lectura.timestamp.timeIntervalSince(inicioFuera ?? lectura.timestamp) > Self.duracionMaxima {
            // Demasiado largo para un desvío: probablemente ya es otro trayecto.
            let previa = ultimaLectura
            reiniciar()
            ultimaLectura = previa
        }
        return nil
    }

    private mutating func empezar(desde match: PolylineMatching.MatchResult, en fecha: Date) {
        salida = match
        trazo = [match.snapped]
        longitud = 0
        desviacion = 0
        masLejano = nil
        inicioFuera = fecha
        for lectura in lecturasFuera { agregar(lectura.coordenada, distancia: lectura.distancia) }
        lecturasFuera.removeAll()
    }

    private mutating func agregar(_ coordenada: CLLocationCoordinate2D, distancia: Double) {
        if distancia > desviacion {
            desviacion = distancia
            masLejano = coordenada
        }
        if let ultimo = trazo.last {
            let paso = PolylineMatching.distanceMeters(ultimo, coordenada)
            guard paso >= Self.separacionMinima else { return }
            longitud += paso
        }
        trazo.append(coordenada)
    }

    private mutating func cerrar(desde salida: PolylineMatching.MatchResult, routeID: String) -> Desvio? {
        let regreso = regresos[0]
        let completo = trazo + [regreso.snapped]
        let tramo = PolylineMatching.distanceMeters(salida.snapped, regreso.snapped)
        let valido = regreso.progressFraction > salida.progressFraction
            && (Self.tramoMinimo...Self.tramoMaximo).contains(tramo)
            && desviacion >= Self.desviacionMinima
        let lejano = masLejano
        // Ya está otra vez en el recorrido: el siguiente desvío puede empezar aquí.
        let enRuta = regresos.last
        let previa = ultimaLectura
        reiniciar()
        ultimoEnRuta = enRuta
        ultimaLectura = previa
        guard valido, let lejano else { return nil }
        return Desvio(routeID: routeID, inicio: salida.snapped, fin: regreso.snapped,
                      trazo: TrazoDesvio.preparar(completo), masLejano: lejano,
                      longitud: PolylineMatching.totalLengthMeters(completo))
    }
}
