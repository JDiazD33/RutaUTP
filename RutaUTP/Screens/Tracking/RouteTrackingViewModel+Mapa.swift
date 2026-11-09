//
//  RouteTrackingViewModel+Mapa.swift
//  RutaUTP
//
//  Flota y negocios que Tracking dibuja sobre el mapa.
//

import Foundation
import CoreLocation

extension RouteTrackingViewModel {

    // MARK: - Vehículos (VehicleTrackingProviding)

    func iniciarVehiculos(token: Int) {
        vehiculoTask?.cancel()
        let stream = vehicleProvider.positions()
        vehiculoTask = Task { @MainActor [weak self] in
            for await _ in stream {
                guard !Task.isCancelled, let self, self.startGuard.isCurrent(token) else { break }
                self.aplicarSnapshotVehiculos()
            }
        }
        vehicleProvider.start()
    }

    func aplicarSnapshotVehiculos(force: Bool = false) {
        // Consumir el estado autorizado actual, no el valor que AsyncStream
        // pudo entregar antes de una revocación o de volver a primer plano.
        let current = vehicleProvider.positionsForPresentation()
        guard let visibles = presentacionFlota.preparar(current,
            rutasPermitidas: TransporteApp.busesUTPActivos ? idsRutasDisponibles : nil,
            force: force) else { return }
        if presentacionFlota.debeLimpiarSeleccion(vehiculoSeleccionado,
            id: vehiculoSeleccionadoID, en: visibles) {
            vehiculoSeleccionadoID = nil
        }
        velocidadesVehiculos = presentacionFlota.velocidades(para: visibles,
            fuente: fuenteVehiculos, anteriores: velocidadesVehiculos)
        vehiculos = visibles
    }

    /// Registra el centro y el radio visibles del mapa. Solo cuenta como
    /// cambio si se desplazó ≥120 m o si el zoom varió lo suficiente: así un
    /// gesto pequeño no dispara una consulta.
    func actualizarViewport(center: CLLocationCoordinate2D, radius: Double) {
        let moved = businessMapCenter.map {
            NegociosService.distanciaMetros($0, center) >= 120
        } ?? true
        let zoomChanged = abs(radius - businessMapRadius) >= max(50, businessMapRadius * 0.1)
        guard moved || zoomChanged else { return }
        businessMapCenter = center
        businessMapRadius = radius
        businessViewportRevision += 1
    }

    /// Recalcula las burbujas visibles alrededor del viewport actual.
    ///
    /// `force` salta el filtro de distancia (lo usa el refresco con retardo
    /// que agrupa movimientos rápidos del mapa).
    func refrescarNegocios(force: Bool = false) {
        let pos = businessMapCenter ?? posicion ?? TransporteApp.referenciaInicio
        if !force, let ultimo = ultimoRefreshNegocios,
           NegociosService.distanciaMetros(ultimo, pos) < 120 { return }
        ultimoRefreshNegocios = pos
        let nuevos = NegociosService.shared.distribuidos(cercaDe: pos,
                                                        radioMetros: businessMapRadius,
                                                        limite: 14)
        if nuevos.map(\.id) != negociosCerca.map(\.id) {
            negociosCerca = nuevos
        }
    }
}

/// Estado privado de presentación, sin lectores ni acceso al viaje o al proveedor.
/// Recibe snapshots ya autorizados. RouteTrackingViewModel conserva la única
/// copia observable y publica primero selección, luego velocidades y flota.
@MainActor
struct PresentacionFlotaTracking {
    private var snapshotAnterior:
        [String: (coord: CLLocationCoordinate2D, t: TimeInterval, identity: VehiclePresentationIdentity)] = [:]
    private var publicationGate = VehiclePresentationUpdateGate()

    mutating func preparar(_ current: [VehiclePosition], rutasPermitidas: Set<String>?,
                          force: Bool) -> [VehiclePosition]? {
        // nil no restringe rutas; un catálogo vacío retira toda la flota UTP.
        let visibles = rutasPermitidas.map { ids in current.filter { ids.contains($0.routeId) } } ?? current
        // Incluso un refresco forzado actualiza la política antes de publicar.
        let publish = publicationGate.shouldPublish(visibles, at: ProcessInfo.processInfo.systemUptime)
        return force || publish ? visibles : nil
    }

    func debeLimpiarSeleccion(_ seleccionado: VehiclePosition?, id: String?,
                             en visibles: [VehiclePosition]) -> Bool {
        if let seleccionado {
            return !visibles.contains { $0.presentationIdentity == seleccionado.presentationIdentity }
        }
        return id != nil
    }

    mutating func velocidades(para visibles: [VehiclePosition], fuente: VehicleTrackingSource,
                             anteriores: [String: Double]) -> [String: Double] {
        let ids = Set(visibles.map(\.id))
        var speeds = anteriores.filter { ids.contains($0.key) }
        snapshotAnterior = snapshotAnterior.filter { ids.contains($0.key) }
        for vehicle in visibles {
            if fuente == .real {
                // Ruido GPS no significa movimiento ni velocidad desconocida.
                // En MQTT usar el valor recibido; nil conserva su ausencia.
                speeds[vehicle.id] = vehicle.reportedSpeedForPresentation
            } else if let previous = snapshotAnterior[vehicle.id],
                      previous.identity == vehicle.presentationIdentity {
                let delta = vehicle.timestamp - previous.t
                if delta > 0.2 {
                    speeds[vehicle.id] = max(0, PolylineMatching.distanceMeters(previous.coord, vehicle.coordinate) / delta)
                }
            } else {
                speeds[vehicle.id] = nil
            }
            snapshotAnterior[vehicle.id] = (vehicle.coordinate, vehicle.timestamp, vehicle.presentationIdentity)
        }
        return speeds
    }

    // Se mantienen separados para conservar el orden de liberación respecto
    // de las escrituras observables de velocidades y selección del modelo.
    mutating func limpiarHistorial() {
        snapshotAnterior = [:]
    }

    mutating func reiniciarPublicacion() {
        publicationGate = VehiclePresentationUpdateGate()
    }
}
