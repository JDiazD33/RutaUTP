//
//  ObservationPublishing.swift
//  RutaUTP
//
//  Contrato utilizado para publicar observaciones de ubicación.
//
//  Una observación representa la ubicación anónima de un pasajero
//  que probablemente está dentro de una unidad de transporte.
//  No representa por sí sola la posición confirmada de un bus.
//
//  El backend será responsable de validar y combinar observaciones
//  antes de producir una posición vehicular estimada.
//

import Foundation
import CoreLocation

/// Estado actual de la conexión utilizada para publicar observaciones.
enum ObservationPublisherState: Equatable {

    /// El publicador todavía no inició una sesión.
    case inactive

    /// Se está intentando establecer la conexión MQTT.
    case connecting

    /// La conexión con el broker está disponible.
    case connected

    /// La conexión o publicación presentó un error.
    case failed(String)
}

/// Contrato de un componente capaz de publicar observaciones.
///
/// Está aislado en el actor principal porque será controlado por
/// `PassiveTrackingCoordinator`, que también funciona en `MainActor`.
@MainActor
protocol ObservationPublishing: AnyObject {

    /// Estado actual de la conexión.
    var state: ObservationPublisherState { get }

    /// Inicia una sesión anónima de contribución.
    ///
    /// - Parameters:
    ///   - sessionID: Identificador temporal generado para el viaje.
    ///   - linea: Línea GTFS que el detector considera candidata.
    func start(
        sessionID: String,
        linea: String
    )

    /// Procesa una ubicación autorizada por el detector.
    ///
    /// - Parameters:
    ///   - location: Lectura original producida por Core Location.
    ///   - routeID: Identificador interno de la ruta GTFS coincidente.
    ///   - activity: Actividad física detectada por Core Motion.
    func publish(
        location: CLLocation,
        routeID: String,
        activity: DetectedMotionActivity
    )

    /// Finaliza la sesión y desconecta el cliente MQTT.
    func stop()
}
