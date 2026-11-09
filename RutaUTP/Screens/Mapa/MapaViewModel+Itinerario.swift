//
//  MapaViewModel+Itinerario.swift
//  RutaUTP
//
//  Cálculo del itinerario hacia un destino, alternativas y limpieza.
//

import Foundation
import MapKit

extension MapaViewModel {

    // MARK: - Caminata + recorrido GTFS + caminata al destino
    func calcularRutaHacia(_ destinoCoord: CLLocationCoordinate2D) {
        routeTask?.cancel()
        let revision = UUID()
        routeRevision = revision
        itinerarioInstalado = nil
        alternativasItinerario = []
        rutasDestacadas = []
        catalogoAlternativas = nil
        seleccionandoAlternativa = nil
        mensajeAlternativa = nil
        routePolyline = nil
        etaMinutos = nil
        mensajeRuta = nil
        calculandoItinerario = false
        guard !TransporteApp.rutasUTPPendientes else {
            mensajeRuta = TransporteApp.mensajePendiente
            return
        }
        guard let origen = userRealCoordinate else {
            mensajeRuta = L.t("Necesitamos tu ubicación para encontrar dónde subir. Activa el GPS y permite el acceso a la ubicación.",
                              "We need your location to find a boarding stop. Enable GPS and allow location access.")
            return
        }

        calculandoItinerario = true
        let repositorioGTFS = repositorioGTFS
        routeTask = Task { @MainActor [weak self] in
            let catalog: GTFSRouteCatalog
            do {
                catalog = try await repositorioGTFS.cargarCatalogo(reintentar: true)
            } catch {
                guard !Task.isCancelled, let self, self.routeRevision == revision else { return }
                self.mensajeRuta = ((error as? FalloCargaGTFS)
                    ?? FalloCargaGTFS(detalle: error.localizedDescription)).mensajeUsuario
                self.calculandoItinerario = false
                return
            }
            guard let self, !Task.isCancelled, self.routeRevision == revision else { return }
            defer {
                if self.routeRevision == revision { self.calculandoItinerario = false }
            }
            // Misma política del Tracking: hasta `radioBusquedaRuta` a pie en
            // cada extremo.
            let radio = Self.radioBusquedaRuta
            let options = await TransitPlanner.shared.options(in: catalog, origin: origen,
                destination: destinoCoord, radius: radio)
            guard !Task.isCancelled, self.routeRevision == revision else { return }
            self.catalogoAlternativas = catalog
            self.alternativasItinerario = options.alternatives
            self.rutasDestacadas = options.highlights
            let nearest = options.alternatives.map { plan in
                (plan: plan, walk: plan.walkToBoardMeters,
                 journey: plan.estimatedJourneySeconds, id: plan.optionID)
            }.sorted { lhs, rhs in
                if lhs.walk != rhs.walk { return lhs.walk < rhs.walk }
                if lhs.journey != rhs.journey { return lhs.journey < rhs.journey }
                return lhs.id.lexicographicallyPrecedes(rhs.id)
            }.map(\.plan)
            var checked = Set<[String]>()
            // Si la subida más cercana no cumple Directions, reintentar por
            // cercanía; no saltar a la más rápida con una caminata mucho mayor.
            let recommended = options.highlights.filter { $0.categories.contains(.recommended) }.map(\.plan)
            for candidate in recommended + nearest {
                guard checked.insert(candidate.optionID).inserted else { continue }
                guard checked.count <= 4 else { break }
                let plan = await candidate.withWalkingDirections(using: self.routeService)
                guard !Task.isCancelled, self.routeRevision == revision else { return }
                let installed = InstalledTransitItinerary(plan: plan)
                let metrics = installed.metrics
                guard metrics.walkToBoardMeters <= radio, metrics.walkToDestinationMeters <= radio,
                      metrics.walkingWithinTransferLimit else {
                    self.alternativasItinerario.removeAll { $0.optionID == candidate.optionID }
                    self.rutasDestacadas.removeAll { $0.plan.optionID == candidate.optionID }
                    continue
                }
                if !self.rutasDestacadas.contains(where: { $0.categories.contains(.recommended) }) {
                    let previous = self.categorias(de: plan)
                    self.rutasDestacadas.removeAll { $0.plan.optionID == plan.optionID }
                    let categories = TransitRouteCategory.allCases.filter {
                        $0 == .recommended || $0 == .closestBoarding || previous.contains($0)
                    }
                    self.rutasDestacadas.insert(TransitRouteHighlight(plan: plan, categories: categories), at: 0)
                    self.rutasDestacadas = Array(self.rutasDestacadas.prefix(3))
                }
                self.instalarItinerario(installed)
                return
            }
            if !self.alternativasItinerario.isEmpty {
                self.mensajeRuta = L.t("No pudimos confirmar la ruta recomendada. Revisa Otras rutas para elegir otra línea.",
                                      "We couldn't confirm the recommended route. Check Other routes to choose another line.")
            } else {
                self.mensajeRuta = L.f("No encontramos una ruta directa ni con un transbordo con paraderos a menos de {0} m de ambos extremos. Prueba otro destino.", "No direct or one-transfer route has stops within {0} m of both ends. Try another destination.", ["\(Int(radio))"])
            }
        }
    }

    /// Comprueba las caminatas de la línea elegida sin perder el plan anterior.
    /// Conserva los paraderos elegidos: una opción cercana no debe cambiar a
    /// otra subida más lejana al comprobar Directions.
    func seleccionarAlternativa(_ alternativa: TransitItinerary, diferir: Bool = false) {
        guard catalogoAlternativas != nil,
              let candidate = alternativasItinerario.first(where: { $0.optionID == alternativa.optionID }) else { return }
        if itinerario?.optionID == candidate.optionID {
            cancelarSeleccionAlternativa()
            return
        }
        routeTask?.cancel()
        let revision = UUID()
        routeRevision = revision
        seleccionandoAlternativa = candidate.optionID
        mensajeAlternativa = nil
        calculandoItinerario = true
        routeTask = Task { @MainActor [weak self] in
            // Una pasada rápida por varias tarjetas solo resuelve la última.
            if diferir {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let radio = Self.radioBusquedaRuta
            guard let self, !Task.isCancelled, self.routeRevision == revision else { return }
            defer {
                if self.routeRevision == revision {
                    self.calculandoItinerario = false
                    self.seleccionandoAlternativa = nil
                    self.routeTask = nil
                }
            }
            let plan = await candidate.withWalkingDirections(using: self.routeService)
            guard !Task.isCancelled, self.routeRevision == revision else { return }
            let installed = InstalledTransitItinerary(plan: plan)
            let metrics = installed.metrics
            guard metrics.walkToBoardMeters <= radio, metrics.walkToDestinationMeters <= radio,
                  metrics.walkingWithinTransferLimit else {
                self.mensajeAlternativa = L.t(
                    "La caminata de esta opción supera el límite permitido. Elige otra ruta.",
                    "This option's walking distance exceeds the allowed limit. Choose another route.")
                return
            }
            self.instalarItinerario(installed)
        }
    }

    func cancelarSeleccionAlternativa() {
        guard seleccionandoAlternativa != nil else { return }
        routeRevision = UUID()
        routeTask?.cancel()
        routeTask = nil
        seleccionandoAlternativa = nil
        calculandoItinerario = false
    }

    private func instalarItinerario(_ installed: InstalledTransitItinerary) {
        itinerarioInstalado = installed
        let plan = installed.plan
        if let index = alternativasItinerario.firstIndex(where: { $0.optionID == plan.optionID }) {
            alternativasItinerario[index] = plan
        } else {
            alternativasItinerario.append(plan)
        }
        if let index = rutasDestacadas.firstIndex(where: { $0.plan.optionID == plan.optionID }) {
            rutasDestacadas[index].plan = plan
        }
        let coordinates = plan.coordinates
        routePolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        etaMinutos = max(1, Int(ceil((installed.metrics.totalSeconds + plan.boardingWaitSeconds) / 60)))
        mensajeRuta = nil
        mensajeAlternativa = nil
        itinerarioFocusTick += 1
    }

    func limpiar() {
        invalidarSeleccionAnterior()
        textoBusqueda = ""
        destinoSeleccionado = nil
        busquedaResultado = nil
        sugerenciasBusqueda = []
        completer.queryFragment = ""
        routePolyline = nil
        etaMinutos = nil
        // Sin destino: volver a la sede o al punto disponible, sin elegir viaje.
        recargarLineas(cercaDe: nil)

        region = Self.regionDeReferencia(coordenadaInicio)
    }
}
