//
//  VehicleTrackingProviding.swift
//  RutaUTP
//
//  Protocolo que abstrae "de dónde vienen las posiciones de vehículos"
//  para mostrar en el mapa. Permite cambiar entre simulación local y
//  backend real sin tocar MapaViewModel ni la vista que lo consume.
//
//  Decisión de diseño: AsyncStream (iOS 15+) en vez de Combine para que
//  el consumidor pueda iterar con `for await positions in provider.positions()`,
//  alineado con el resto async/await del módulo nuevo.
//

import Foundation

protocol VehicleTrackingProviding: AnyObject {
    /// Marca la fuente de los datos. Útil para badges en UI ("En vivo" real vs "Demo").
    var source: VehicleTrackingSource { get }

    /// Inicia la emisión de posiciones. Idempotente: llamar dos veces no duplica.
    func start()

    /// Detiene la emisión de posiciones. Libera timers/sockets.
    func stop()

    /// Stream de posiciones de vehículos en tiempo real.
    /// Se renueva en cada start/stop. El consumidor debe iterar con `for await`.
    func positions() -> AsyncStream<[VehiclePosition]>

    /// Snapshot síncrono de la última posición conocida de cada vehículo.
    /// Útil para acceso puntual sin colgarse a un stream.
    var currentPositions: [VehiclePosition] { get }
}
