//
//  PolylineMatching.swift
//  RutaUTP
//
//  Funciones PURAS de matching de polyline (snap-to-road, desvíos).
//  Sin UIKit, sin SwiftUI, sin CoreLocation en las firmas (usamos solo
//  CLLocation para el struct en una entrada). 100% testeables.
//
//  Algoritmo de snap-to-road / desvío:
//   1. Para cada segmento de la polyline, calculamos la projección
//      ortogonal del punto del usuario sobre esa línea (es decir,
//      el closest-point-on-segment).
//   2. Si la distancia al closest point < umbral, consideramos que el
//      usuario está ON-ROUTE y el segmento activo es ese.
//   3. Si la distancia al closest point en TODOS los segmentos > umbral,
//      consideramos DESVÍO.
//   4. El progreso se mide como fracción 0..1 a lo largo de la polyline,
//      sumando longitudes de segmentos previos + la parte del segmento actual.
//

import Foundation
import CoreLocation
import MapKit

enum PolylineMatching {

    // MARK: - Tipos de salida

    struct MatchResult: Equatable {
        /// Index del segmento de la polyline donde se proyectó el punto.
        public let segmentIndex: Int
        /// Punto proyectado sobre la polyline (lat/lon).
        public let snapped: CLLocationCoordinate2D
        /// Distancia del punto del usuario al snapped, en metros.
        public let distanceToRoute: Double
        /// Progreso 0...1 a lo largo de toda la polyline.
        public let progressFraction: Double
        /// True si distanceToRoute <= threshold.
        public let isOnRoute: Bool

        // CLLocationCoordinate2D no es Equatable → implementación manual.
        public static func == (lhs: MatchResult, rhs: MatchResult) -> Bool {
            lhs.segmentIndex == rhs.segmentIndex &&
            lhs.snapped.latitude == rhs.snapped.latitude &&
            lhs.snapped.longitude == rhs.snapped.longitude &&
            lhs.distanceToRoute == rhs.distanceToRoute &&
            lhs.progressFraction == rhs.progressFraction &&
            lhs.isOnRoute == rhs.isOnRoute
        }
    }

    // MARK: - Match

    /// Proyecta `point` sobre la secuencia de coordenadas `polyline` y devuelve
    /// el mejor matcheo.
    /// - Parameters:
    ///   - point: ubicación del usuario.
    ///   - polyline: coordenadas ordenadas de la polyline.
    ///   - thresholdMeters: distancia máxima (m) para considerar on-route.
    static func match(point: CLLocationCoordinate2D,
                      on polyline: [CLLocationCoordinate2D],
                      thresholdMeters: Double = 20.0) -> MatchResult? {

        guard polyline.count >= 2 else { return nil }
        var best: (index: Int, snapped: CLLocationCoordinate2D, dist: Double)? = nil
        var accumulatedLength: Double = 0
        var prefixLengthAtBest: Double = 0
        var lengthAtBest: Double = 0

        for i in 0..<(polyline.count - 1) {
            let a = polyline[i]
            let b = polyline[i + 1]

            let seg = closestPointOnSegment(p: point, a: a, b: b)
            if best == nil || seg.distance < best!.dist {
                best = (i, seg.point, seg.distance)
                prefixLengthAtBest = accumulatedLength
                lengthAtBest = seg.alongLength
            }
            accumulatedLength += seg.segLength
        }

        guard let result = best else { return nil }
        let totalLength = accumulatedLength // al finalit del bucle = longitud total

        var progressFraction: Double
        if totalLength > 0 {
            progressFraction = (prefixLengthAtBest + lengthAtBest) / totalLength
            progressFraction = min(max(progressFraction, 0), 1)
        } else {
            progressFraction = 0
        }

        return MatchResult(
            segmentIndex: result.index,
            snapped: result.snapped,
            distanceToRoute: result.dist,
            progressFraction: progressFraction,
            isOnRoute: result.dist <= thresholdMeters
        )
    }

    /// Versión conveniencia usando MKPolyline (extrae sus coords).
    static func match(point: CLLocationCoordinate2D,
                      on polyline: MKPolyline,
                      thresholdMeters: Double = 20.0) -> MatchResult? {
        let coords = coordinates(from: polyline)
        return match(point: point, on: coords, thresholdMeters: thresholdMeters)
    }

    // MARK: - Desvío

    /// Dado el último matcheo y la distancia recorrida desde el último recálculo,
    /// decide si es necesario recalcular.
    static func shouldRecalculate(lastMatch: MatchResult?,
                                  consecutiveOffRouteCount: Int,
                                  thresholdCount: Int = 3) -> Bool {
        // Disparar recálculo si tuvimos `thresholdCount` muestras seguidas
        // fuera de ruta (smoothing: una sola muestra fueraNO recalc).
        if lastMatch == nil { return true }
        return consecutiveOffRouteCount >= thresholdCount
    }

    // MARK: - Extracción de coordenadas de MKPolyline

    /// Devuelve los [CLLocationCoordinate2D] de un MKPolyline.
    static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: polyline.pointCount)
        // NSRange bridge: en iOS 0..<n se convierte implicitamente, pero
        // explicit evita ambiguedad en compiladores strict.
        let range = NSRange(location: 0, length: polyline.pointCount)
        polyline.getCoordinates(&coords, range: range)
        return coords
    }

    // MARK: - Decimación y longitudes

    /// Reduce la densidad de puntos conservando el orden y el punto final.
    /// Útil para matching en tiempo real (menos segmentos por fix) y para
    /// animaciones, sin pérdida visual perceptible.
    static func decimate(_ puntos: [CLLocationCoordinate2D],
                         maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard puntos.count > maxPoints, maxPoints >= 2 else { return puntos }
        let paso = Double(puntos.count) / Double(maxPoints)
        var resultado = (0..<maxPoints).map {
            puntos[min(Int(Double($0) * paso), puntos.count - 1)]
        }
        if let ultima = puntos.last {
            resultado[resultado.count - 1] = ultima
        }
        return resultado
    }

    /// Longitud total de la polyline en metros (suma haversine por segmento).
    static func totalLengthMeters(_ puntos: [CLLocationCoordinate2D]) -> Double {
        guard puntos.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<puntos.count {
            total += distanceMeters(puntos[i - 1], puntos[i])
        }
        return total
    }

    // MARK: - Distancias (haversine) y proyecciones

    /// Distancia en metros entre dos coords (haversine). Sin depender de CLLocation涨幅.
    static func distanceMeters(_ a: CLLocationCoordinate2D,
                               _ b: CLLocationCoordinate2D) -> Double {
        // Usamos CLLocation.distance(from:) — internamente usa haversine.
        let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return la.distance(from: lb)
    }

    /// Distancia perpendicular de punto `p` al segmento `a-b` (en metros,
    /// sobre la proyección equirectangular aproximada, lo suficiente para
    /// detección de desvíos urbanos < 100m).
    private struct ClosestPointResult {
        let point: CLLocationCoordinate2D
        let distance: Double       // metros de p al closest point
        let alongLength: Double    // longitud desde a hasta el closest point
        let segLength: Double      // longitud total del segmento a-b
    }

    private static func closestPointOnSegment(p: CLLocationCoordinate2D,
                                              a: CLLocationCoordinate2D,
                                              b: CLLocationCoordinate2D) -> ClosestPointResult {
        // Convertimos a un plano local en metros usando un eje aproximadamente
        // constante a la latitud de A. Suficiente para segmentos < 5km.
        let lat0 = a.latitude
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(lat0 * .pi / 180.0)

        let ax = a.longitude * metersPerDegLon
        let ay = a.latitude  * metersPerDegLat
        let bx = b.longitude * metersPerDegLon
        let by = b.latitude  * metersPerDegLat
        let px = p.longitude * metersPerDegLon
        let py = p.latitude  * metersPerDegLat

        let dx = bx - ax
        let dy = by - ay
        let segLen2 = dx*dx + dy*dy
        guard segLen2 > 0 else {
            // a == b: el "segmento" es un punto. closest es a.
            let d = distanceMeters(p, a)
            return ClosestPointResult(point: a, distance: d, alongLength: 0, segLength: 0)
        }
        // Parametro t (fracción a lo largo de a-b), clampeado a [0,1].
        var t = ((px - ax) * dx + (py - ay) * dy) / segLen2
        t = min(max(t, 0), 1)

        let closestX = ax + t * dx
        let closestY = ay + t * dy
        let closest = CLLocationCoordinate2D(
            latitude: closestY / metersPerDegLat,
            longitude: closestX / metersPerDegLon
        )
        let dist = sqrt((px-closestX)*(px-closestX) + (py-closestY)*(py-closestY))
        let segLen = sqrt(segLen2)
        let along = t * segLen
        return ClosestPointResult(point: closest, distance: dist, alongLength: along, segLength: segLen)
    }
}
