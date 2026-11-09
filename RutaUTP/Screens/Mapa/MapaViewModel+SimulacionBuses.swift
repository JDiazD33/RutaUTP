//
//  MapaViewModel+SimulacionBuses.swift
//  RutaUTP
//
//  Geometría y reparto de la flota simulada sobre los shapes del feed.
//  Solo construye la flota; el avance por tick vive en MapaViewModel.swift.
//

import MapKit

extension MapaViewModel {
    /// Construye un bus animado por ruta del feed.
    static func busesDesde(_ feed: [RutaGTFS],
                                   ancla: CLLocationCoordinate2D) -> [BusAnimado] {
        let n = max(feed.count, 1)
        return feed.enumerated().compactMap { index, ruta in
            // Sin geometría suficiente no hay nada que animar. Antes se caía a
            // un trazado de demostración, así que el mapa mostraba un bus
            // recorriendo una línea que no era la suya.
            let waypoints = decimarCoordenadas(ruta.shape, maximoPuntos: 240)
            guard waypoints.count >= 2 else { return nil }
            let acumulados = distanciasAcumuladas(waypoints)

            var bus = BusAnimado(
                id: "simulated-\(ruta.id)",
                linea: ruta.linea,
                rutaId: ruta.id,
                empresa: ruta.empresa,
                tipo: "Bus",
                variante: ruta.variante,
                minutosLlegada: max(1, 2 + index * max(1, ruta.headwayMin / n)),
                colorDeRuta: ruta.color,
                lat: waypoints[0].latitude,
                lon: waypoints[0].longitude,
                heading: 0,
                rutaCoordenadas: waypoints,
                acumulados: acumulados
            )

            // Nacimiento REPARTIDO por el corredor: se toma el tramo del
            // shape más cercano al punto consultado y cada vehículo arranca
            // de un punto distinto a su alrededor (±1.8 km), con dirección y
            // velocidad propias. Si varias líneas comparten avenida, quedan
            // escalonadas a lo largo de ella y no amontonadas en un punto.
            let idxAncla = waypointMasCercano(waypoints, a: ancla)
            let distanciaAnclaM = acumulados.isEmpty ? 0 : acumulados[idxAncla]
            // Fracciones de Fibonacci (0.618) escalonan los arranques de
            // forma determinista (~38% del rango entre vecinos); el jitter
            // aleatorio evita que dos recargas se vean idénticas.
            let fraccion = fmod(Double(index) * 0.6180339887, 1.0)
            let offsetM = fraccion * 3600 - 1800 + Double.random(in: -120...120)
            // Se envuelve módulo la longitud del recorrido (un vehículo en
            // otro ciclo de la línea) en vez de amontonar en los extremos.
            var d = distanciaAnclaM + offsetM
            let total = bus.longitudRutaM
            if total > 0 {
                d = d.truncatingRemainder(dividingBy: total)
                if d < 0 { d += total }
            }
            bus.distanciaM = d
            bus.velocidadMS = Double.random(in: 7...12)   // 25–43 km/h
            bus.isMovingForward = Bool.random()
            bus.actualizarPosicion()
            return bus
        }
    }

    /// Distancia acumulada (metros) de cada waypoint respecto al inicio.
    private static func distanciasAcumuladas(_ pts: [CLLocationCoordinate2D]) -> [Double] {
        guard !pts.isEmpty else { return [] }
        var acc: [Double] = [0]
        acc.reserveCapacity(pts.count)
        for j in 1..<pts.count {
            acc.append(acc[j - 1] + PolylineMatching.distanceMeters(pts[j - 1], pts[j]))
        }
        return acc
    }

    /// Índice del waypoint más cercano a un punto (distancia planar:
    /// solo sirve para elegir un índice, no para medir).
    private static func waypointMasCercano(_ puntos: [CLLocationCoordinate2D],
                                           a destino: CLLocationCoordinate2D) -> Int {
        var mejor = 0
        var mejorD = Double.greatestFiniteMagnitude
        for (i, p) in puntos.enumerated() {
            let d = (p.latitude - destino.latitude) * (p.latitude - destino.latitude)
                  + (p.longitude - destino.longitude) * (p.longitude - destino.longitude)
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    /// Reduce la densidad de un shape conservando el orden (perf del timer).
    private static func decimarCoordenadas(_ puntos: [CLLocationCoordinate2D],
                                           maximoPuntos: Int) -> [CLLocationCoordinate2D] {
        guard puntos.count > maximoPuntos else { return puntos }
        let paso = Double(puntos.count) / Double(maximoPuntos)
        var resultado: [CLLocationCoordinate2D] = []
        resultado.reserveCapacity(maximoPuntos)
        for j in 0..<maximoPuntos {
            resultado.append(puntos[min(Int(Double(j) * paso), puntos.count - 1)])
        }
        if let ultima = puntos.last, resultado.last?.latitude != ultima.latitude
                                                || resultado.last?.longitude != ultima.longitude {
            resultado.append(ultima)
        }
        return resultado
    }
}

extension MapaViewModel {

    // MARK: - Simulación de Buses Animados
    //
    // Los recorridos (shapes) son REALES del feed GTFS embebido; las
    // posiciones son SIMULADAS porque el feed estático no incluye GPS.
    // La simulación imita una flota real: vehículos repartidos por sus
    // corredores, con dirección y velocidad propias (25–43 km/h), que
    // avanzan metros reales sobre el shape según el tiempo transcurrido.
    func iniciarSimulacionBuses() {
        // Con broker configurado, el mapa muestra vehículos OBSERVADOS; sin él,
        // la flota que el propio mapa anima. Nunca las dos a la vez: cada línea
        // aparecería duplicada en el mapa.
        //
        // Cada consulta también verifica su fuente al completar: una tarea
        // iniciada antes de conectar MQTT no puede sustituir la flota real.
        if iniciarFlotaReal() { return }

        if fuenteFlota != .simulated {
            invalidarConsultaLineas()
            flotaBuses = []
            busesAnimados = []
            busSeleccionado = nil
            ultimasPosicionesReales = nil
        }
        fuenteFlota = .simulated

        // Al volver a la pantalla, conservar el destino elegido si lo hay.
        recargarLineas(cercaDe: busquedaResultado?.coordenada)

        simulacionBusesIniciada = true
        reanudarSimulacionBuses()
    }

    /// Pausa solo la simulación; no toca GPS, consultas ni el canal real.
    func actualizarActividadVisual(_ activa: Bool) {
        actividadVisual = activa
        if fuenteFlota == .real, vehicleProvider != nil { aplicarFlotaReal() }
        if activa {
            reanudarSimulacionBuses()
        } else {
            busSimulationTask?.cancel()
            busSimulationTask = nil
            ultimoTickBuses = nil
        }
    }

    private func reanudarSimulacionBuses() {
        guard actividadVisual, simulacionBusesIniciada,
              !TransporteApp.rutasUTPPendientes,
              fuenteFlota == .simulated, busSimulationTask == nil else { return }
        ultimoTickBuses = nil
        // Bucle de simulación aislado al hilo principal. Antes era un `Timer`
        // que despachaba un bloque a la cola principal en cada tick — veinte
        // por segundo — sin aislamiento verificable ni cancelación estructurada.
        busSimulationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self, self.actividadVisual else { return }
                self.actualizarPosicionBuses()
            }
        }
    }

    /// Recarga las líneas del panel según un punto de interés: el destino
    /// seleccionado (chip, Guardado, búsqueda) o la referencia de inicio.
    /// Solo la demo genera unidades desde el feed. En modo real el catálogo
    /// describe recorridos, y las posiciones provienen exclusivamente del canal.
    func recargarLineas(cercaDe ancla: CLLocationCoordinate2D?, reintentar: Bool = false) {
        let punto = ancla ?? coordenadaInicio
        let clave = (lat: punto.latitude, lon: punto.longitude)
        if !reintentar, let previa = anclaLineas,
           abs(previa.lat - clave.lat) < 1e-9,
           abs(previa.lon - clave.lon) < 1e-9 { return }
        anclaLineas = clave

        lineasTask?.cancel()
        lineasTask = nil
        let revision = UUID()
        lineasRevision = revision
        // Retirar el filtro anterior mientras se consulta el nuevo destino.
        // Un snapshot recibido durante esta espera solo actualiza la flota.
        rutasCercanas = []
        if fuenteFlota == .real {
            if ultimasPosicionesReales != nil {
                aplicarFlotaReal()
            }
        }

        let fuenteConsulta = fuenteFlota
        let repositorio = repositorioGTFS
        cargandoLineas = true
        errorLineas = nil
        lineasTask = Task { @MainActor [weak self] in
            // 400 m cubre "pasa por la puerta"; si el punto quedó algo
            // alejado del recorrido se amplía a 800 m antes de declarar
            // que no pasa ninguna línea.
            //
            // OJO: este 800 NO es `radioBusquedaRuta`. Aquí se pregunta qué
            // líneas pasan por el punto (la lista de transportes cercanos);
            // allí se pregunta qué paraderos sirven para un viaje concreto.
            // Subir este valor sí tendría efecto, pero llenaría el panel de
            // líneas cercanas con rutas que no pasan por donde está la persona.
            let feed: [RutaGTFS]
            var catalogoRecuperado: [RutaGTFS]?
            do {
                feed = try await repositorio.consultarRutasQuePasanPorConAmpliacion(
                    punto, reintentar: reintentar)
                guard !Task.isCancelled else { return }
                if reintentar, fuenteConsulta == .real {
                    catalogoRecuperado = try await repositorio.cargarRutas()
                }
            } catch {
                guard !Task.isCancelled, let self, self.lineasRevision == revision,
                      self.fuenteFlota == fuenteConsulta, self.anclaLineas?.lat == clave.lat,
                      self.anclaLineas?.lon == clave.lon else { return }
                self.errorLineas = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
                self.cargandoLineas = false
                self.lineasTask = nil
                return
            }
            // El usuario pudo cambiar de destino mientras consultaba.
            guard !Task.isCancelled, let self, self.lineasRevision == revision,
                  self.fuenteFlota == fuenteConsulta, self.anclaLineas?.lat == clave.lat,
                  self.anclaLineas?.lon == clave.lon else { return }

            var ids = Set<String>()
            self.rutasCercanas = feed.filter { !$0.id.isEmpty && $0.shape.count >= 2 && ids.insert($0.id).inserted }
            if let catalogo = catalogoRecuperado {
                self.rutasPorId = Dictionary(catalogo.map { ($0.id, $0) },
                                            uniquingKeysWith: { primera, _ in primera })
                if self.ultimasPosicionesReales != nil { self.aplicarFlotaReal() }
            }
            if fuenteConsulta == .simulated {
                self.flotaBuses = Self.busesDesde(self.rutasCercanas, ancla: punto)
                self.busesAnimados = self.flotaBuses
                self.busSeleccionado = nil
            }
            self.cargandoLineas = false
            self.lineasTask = nil
        }
    }

    func reintentarCatalogo() {
        let ancla = anclaLineas.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        recargarLineas(cercaDe: ancla, reintentar: true)
    }

    func invalidarConsultaLineas() {
        lineasRevision = UUID()
        lineasTask?.cancel()
        lineasTask = nil
        anclaLineas = nil
        rutasCercanas = []
        cargandoLineas = false
        errorLineas = nil
    }

    func detenerSimulacionBuses() {
        simulacionBusesIniciada = false
        invalidarConsultaLineas()
        flotaRevision = UUID()
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil

        // El canal real se cierra con la pantalla. Sin esto, salir del mapa
        // dejaría la suscripción MQTT viva consumiendo batería y red.
        vehicleTrackingTask?.cancel()
        vehicleTrackingTask = nil
        vehicleProvider?.stop()
        vehicleProvider = nil
        ultimasPosicionesReales = nil
        if fuenteFlota == .real {
            flotaBuses = []
            busesAnimados = []
            busSeleccionado = nil
        }
    }
}
