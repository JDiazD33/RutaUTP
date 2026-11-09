//
//  RouteTrackingViewModel+Recorrido.swift
//  RutaUTP
//
//  Geometría del recorrido instalado, salidas formateadas y modo demo
//  que simula el avance sobre la ruta calculada.
//

import Foundation
import CoreLocation
import MapKit

extension RouteTrackingViewModel {

    // MARK: - Geometría del recorrido

    func instalarShape(_ coords: [CLLocationCoordinate2D]) {
        polyCoords = coords // conservar esquinas: no atravesar manzanas
        distanciasAcumuladas = [0]
        for i in 1..<polyCoords.count {
            distanciasAcumuladas.append(
                distanciasAcumuladas[i - 1] + PolylineMatching.distanceMeters(polyCoords[i - 1], polyCoords[i])
            )
        }
        distanciaTotalM = distanciasAcumuladas.last ?? 0
        demoProgreso = progreso
        ultimoFraccionPolyline = 0
        rutaRecorrida = nil
        rutaRestante = routePolyline
        // Ritmo real de simulación: distancia total / ETA de la ruta
        // (línea GTFS o MapKit). Es "a como vamos": micro urbano ≈ 20-25 km/h.
        if let eta = etaTotalSeg, eta > 10 {
            velocidadSimMs = max(1.2, distanciaTotalM / eta)
        } else {
            velocidadSimMs = 6.0
        }
    }

    /// Divide la polyline en tramo recorrido / restante según `progreso`.
    /// Se refresca cada ~0.5% de avance (o al 100%) para no reconstruir
    /// MKPolylines en cada tick del GPS/demo.
    func refrescarPolylinesProgreso() {
        guard polyCoords.count >= 2,
              let total = distanciasAcumuladas.last, total > 0 else { return }
        guard progreso >= 0.999 || abs(progreso - ultimoFraccionPolyline) >= 0.005 else { return }
        ultimoFraccionPolyline = progreso

        let objetivo = total * min(max(progreso, 0), 1)
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        let punto = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t)

        var recorridas = Array(polyCoords[0...bajo])
        recorridas.append(punto)
        rutaRecorrida = recorridas.count >= 2
            ? MKPolyline(coordinates: recorridas, count: recorridas.count) : nil

        var restantes = [punto]
        restantes.append(contentsOf: polyCoords[alto...])
        rutaRestante = restantes.count >= 2
            ? MKPolyline(coordinates: restantes, count: restantes.count) : nil
    }

    // MARK: - Salidas formateadas (mismo estilo de NavegacionRutaView)

    var minutosRestantes: Int {
        guard etaTotalSeg != nil else { return 0 }
        return max(0, Int(ceil(remainingSeconds / 60)))
    }

    var distanciaRestanteTexto: String {
        distanciaRestanteM >= 1000
            ? FormatoNumero.decimal(distanciaRestanteM / 1000) + " km"
            : "\(Int(distanciaRestanteM)) m"
    }

    /// Ritmo real de la ruta activa, para el caption del selector 1×/3×/10×.
    var velocidadSimKmh: Int {
        Int((velocidadSimMs * 3.6).rounded())
    }

    // MARK: - Modo demo (simulación de avance sobre la ruta calculada)

    func iniciarDemoSimulado() {
        guard tripInProgress, polyCoords.count >= 2 else {
            modoDemo = false
            return
        }
        detenerDemoSimulado()
        demoProgreso = progreso
        reanudarDemoSimulado()
    }

    /// La pausa visual conserva sesión, progreso y modo demo.
    func actualizarActividadVisual(_ activa: Bool) {
        actividadVisual = activa
        if fuenteVehiculos == .real { aplicarSnapshotVehiculos(force: true) }
        (vehicleProvider as? SimulatedTrackingProvider)?.actualizarActividadVisual(activa)
        if activa { reanudarDemoSimulado() } else { detenerDemoSimulado() }
    }

    private func reanudarDemoSimulado() {
        guard actividadVisual, modoDemo, tripInProgress, estado != .finalizado,
              polyCoords.count >= 2, demoTask == nil else { return }
        // Una sola tarea que duerme entre pasos. Antes era un `Timer` que
        // creaba un `Task` nuevo por tick — doce por segundo — solo para saltar
        // al hilo principal.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self, self.actividadVisual else { return }
                guard let total = self.distanciasAcumuladas.last, total > 1 else { continue }
                // Avance por METROS reales: velocidad real de la ruta (m/s)
                // × multiplicador elegido. 1× = ritmo real de la línea.
                let speed: Double
                switch self.journeyLeg {
                case .riding: speed = self.itinerary?.busSpeed ?? 6
                case .ridingSecond: speed = self.itinerary?.transfer?.busSpeed ?? 6
                default: speed = 1.4
                }
                let deltaMetros = speed * self.velocidadDemo * 0.08
                self.demoProgreso = min(1.0, self.demoProgreso + deltaMetros / total)
                let coord = self.coordenadaEnFraccion(self.demoProgreso)
                let siguiente = self.coordenadaEnFraccion(min(1.0, self.demoProgreso + 0.002))
                let degrees = atan2((siguiente.longitude - coord.longitude) * cos(coord.latitude * .pi / 180),
                                    siguiente.latitude - coord.latitude) * 180 / .pi
                let rumbo = (degrees + 360).truncatingRemainder(dividingBy: 360)
                self.procesar(coordenada: coord, rumbo: rumbo)
            }
        }
    }

    func detenerDemoSimulado() {
        demoTask?.cancel()
        demoTask = nil
    }

    /// Coordenada sobre el shape a una fracción 0...1 (búsqueda binaria).
    private func coordenadaEnFraccion(_ fraccion: Double) -> CLLocationCoordinate2D {
        guard polyCoords.count >= 2,
              let ultima = distanciasAcumuladas.last else {
            return posicion ?? CLLocationCoordinate2D()
        }
        let objetivo = max(0, min(1, fraccion)) * ultima
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longitudSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longitudSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longitudSeg : 0
        let a = polyCoords[bajo], b = polyCoords[alto]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}
