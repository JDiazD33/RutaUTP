//
//  MapaViewModel+Flota.swift
//  RutaUTP
//
//  Flota real del canal MQTT y posición de los buses en el mapa.
//

import Foundation
import MapKit

extension MapaViewModel {

    // MARK: - Flota real (canal MQTT)

    /// Arranca el consumo de posiciones observadas si hay broker configurado.
    ///
    /// Devuelve `true` si tomó el control de la flota, en cuyo caso el mapa no
    /// debe animar su propia simulación. Sin `MQTT_HOST`, `MQTT_USERNAME` y
    /// `MQTT_PASSWORD` no hay canal, y el mapa se comporta exactamente como
    /// antes: su flota animada sobre los shapes del feed.
    func iniciarFlotaReal() -> Bool {
        guard vehicleProvider == nil else { return true }
        guard let provider = crearProveedorReal(), provider.source == .real else { return false }

        invalidarConsultaLineas()
        busSimulationTask?.cancel()
        busSimulationTask = nil
        ultimoTickBuses = nil
        let revision = UUID()
        flotaRevision = revision
        vehicleProvider = provider
        fuenteFlota = .real
        ultimasPosicionesReales = nil
        flotaBuses = []
        busesAnimados = []
        busSeleccionado = nil
        cargandoLineas = true
        recargarLineas(cercaDe: busquedaResultado?.coordenada)

        let repositorio = repositorioGTFS
        let revisionConsultaCatalogo = lineasRevision
        vehicleTrackingTask = Task { @MainActor [weak self] in
            // El catálogo completo, no solo las líneas cercanas al ancla: un
            // vehículo observado puede venir de cualquiera de las 102 rutas.
            let feed: [RutaGTFS]?
            do {
                feed = try await repositorio.cargarRutas()
            } catch {
                guard !Task.isCancelled, let self, self.flotaRevision == revision,
                      self.fuenteFlota == .real else { return }
                if self.lineasRevision == revisionConsultaCatalogo {
                    self.errorLineas = (error as? FalloCargaGTFS) ?? FalloCargaGTFS(detalle: error.localizedDescription)
                }
                // Las posiciones observadas conservan su canal incluso si
                // no tenemos metadatos; no sustituirlas por una flota demo.
                feed = nil
            }
            guard !Task.isCancelled, self?.flotaRevision == revision,
                  self?.fuenteFlota == .real else { return }

            if let feed {
                self?.rutasPorId = Dictionary(
                    feed.map { ($0.id, $0) },
                    uniquingKeysWith: { primera, _ in primera }
                )
            }

            guard !Task.isCancelled else { return }
            provider.start()

            for await _ in provider.positions() {
                guard !Task.isCancelled, let self, self.flotaRevision == revision,
                      self.fuenteFlota == .real else { break }
                // Conservar recepción en las otras pestañas sin redibujar el
                // mapa oculto. Una retirada sí debe limpiar también su caché.
                if self.actividadVisual || !provider.keepsConnectionWhileMapHidden
                    || provider.currentPositions.isEmpty {
                    self.aplicarFlotaReal()
                }
            }
        }

        return true
    }

    /// Sustituye la flota del mapa por las posiciones que llegan del broker.
    ///
    /// Conserva procedencia, run y revisión además de los datos de presentación.
    /// La geometría va vacía: la posición MQTT la fija cada mensaje, sin avanzar
    /// mediante la animación local.
    func aplicarFlotaReal() {
        guard fuenteFlota == .real else { return }
        // El stream puede haber entregado un valor que una revocación posterior
        // ya retiró. Lo mismo ocurre con la caché al cambiar destino/catálogo.
        let posiciones = vehicleProvider?.positionsForPresentation() ?? []
        ultimasPosicionesReales = posiciones
        let anclaETA: CLLocationCoordinate2D = {
            if let anclaLineas {
                return CLLocationCoordinate2D(
                    latitude: anclaLineas.lat,
                    longitude: anclaLineas.lon
                )
            }
            return busquedaResultado?.coordenada ?? coordenadaInicio
        }()

        // UTP solo muestra unidades vinculadas a su catálogo institucional.
        let visibles = busesUTPActivos ? posiciones.filter { rutasPorId[$0.routeId] != nil } : posiciones
        flotaBuses = visibles.map { posicion in
            let ruta = rutasPorId[posicion.routeId]
            let eta = etaRealCache.minutes(position: posicion, target: anclaETA)

            return BusAnimado(
                id: "real-\(posicion.id)",
                linea: posicion.linea,
                rutaId: posicion.routeId,
                empresa: ruta?.empresa ?? L.t("Empresa no disponible", "Carrier unavailable"),
                tipo: "Bus",
                variante: ruta?.variante ?? "",
                minutosLlegada: eta,
                colorDeRuta: ruta?.color,
                lat: posicion.lat,
                lon: posicion.lon,
                heading: posicion.heading,
                rutaCoordenadas: [],
                acumulados: [],
                velocidadMS: posicion.speed >= 0 ? posicion.speed : 0,
                fuente: .real,
                dataOrigin: posicion.dataOrigin,
                simulationRunId: posicion.simulationRunId,
                controlRevision: posicion.controlRevision,
                backendVehicleID: posicion.id,
                scenarioOccupancy: posicion.scenarioOccupancy
            )
        }

        busesAnimados = flotaBuses

        // Si el vehículo abierto en el popup sigue existiendo, refrescarlo.
        if let seleccionado = busSeleccionado {
            busSeleccionado = flotaBuses.first { $0.presentationIdentity == seleccionado.presentationIdentity }
        }
        MQTTConfiguration.trialLog("map", ["received": posiciones.count,
            "fleet": flotaBuses.count, "selected": busSeleccionado == nil ? 0 : 1,
            "occupancyEmpty": flotaBuses.filter { $0.displayedScenarioOccupancy == .empty }.count,
            "occupancySpace": flotaBuses.filter { $0.displayedScenarioOccupancy == .space }.count,
            "occupancyFull": flotaBuses.filter { $0.displayedScenarioOccupancy == .full }.count])
    }

    func actualizarPosicionBuses() {
        guard fuenteFlota == .simulated else { return }
        // dt real entre ticks: la velocidad no depende de la cadencia del
        // timer ni de eventuales tirones del hilo principal.
        let ahora = Date()
        let dt: Double = ultimoTickBuses.map { min(ahora.timeIntervalSince($0), 1.0) } ?? 0
        ultimoTickBuses = ahora

        var huboCambioVisible = false

        for i in flotaBuses.indices {
            var bus = flotaBuses[i]
            let totalM = bus.longitudRutaM
            guard totalM > 10 else { continue }

            // Avance en METROS reales: velocidad crucero propia × tiempo.
            let avance = bus.velocidadMS * dt
            var d = bus.distanciaM + (bus.isMovingForward ? avance : -avance)

            // Extremo del recorrido: el vehículo regresa por el mismo
            // corredor (ida y vuelta), sin saltos en el mapa.
            if d >= totalM {
                d = totalM
                bus.isMovingForward = false
            } else if d <= 0 {
                d = 0
                bus.isMovingForward = true
            }
            // Medir desde la última instantánea visible, no desde el tick
            // anterior: los pasos menores de 1,5 m también deben acumularse.
            if busesAnimados.indices.contains(i), busesAnimados[i].rutaId == bus.rutaId {
                let publicado = busesAnimados[i]
                if abs(d - publicado.distanciaM) >= Self.metrosMinimosParaPublicar
                    || bus.isMovingForward != publicado.isMovingForward {
                    huboCambioVisible = true
                }
            } else {
                huboCambioVisible = true
            }
            bus.distanciaM = d
            bus.actualizarPosicion()
            flotaBuses[i] = bus
        }

        // La simulación avanza siempre; el estado publicado —y con él el
        // redibujado del mapa— solo cuando el movimiento acumulado se nota.
        guard huboCambioVisible else { return }
        busesAnimados = flotaBuses
    }
}
