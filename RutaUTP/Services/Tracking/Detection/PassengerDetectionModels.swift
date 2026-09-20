//
//  PassengerDetectionModels.swift
//  RutaUTP
//
//  Modelos puros utilizados por el sistema de detección pasiva.
//
//  Este archivo separa dos conceptos:
//  1. La actividad física observada por Core Motion.
//  2. El estado de viaje inferido por nuestras reglas.
//
//  Estos modelos no acceden directamente al GPS, Core Motion,
//  MQTT ni la interfaz. Por eso pueden probarse con XCTest.
//

import Foundation

/// Estado estimado del usuario dentro del proceso de abordaje.
///
/// Este valor no procede directamente de un sensor. Es una inferencia
/// generada por `PassengerDetectionEngine` utilizando actividad física,
/// velocidad, cercanía a una ruta, dirección y proximidad a paraderos.
enum PassengerDetectionState: String, Codable, Equatable {

    /// No existe evidencia suficiente de aproximación o viaje.
    case idle

    /// El usuario camina o permanece quieto cerca de un paradero.
    ///
    /// Este estado no permite transmitir una ubicación como pasajero.
    case approachingStop

    /// Se detectó movimiento vehicular compatible con una ruta,
    /// pero todavía faltan muestras para confirmar el abordaje.
    case boardingCandidate

    /// Varias muestras consecutivas indican que el usuario
    /// probablemente está dentro de un vehículo de transporte.
    ///
    /// Este es el único estado que puede autorizar publicaciones MQTT.
    case onboard

    /// Después de estar a bordo se detectaron muestras caminando
    /// o corriendo. El sistema espera más evidencia antes de concluir
    /// que el usuario bajó del vehículo.
    case alightingCandidate
}

/// Actividad física clasificada por Core Motion.
///
/// Este valor representa una observación del sistema operativo.
/// Por sí solo no demuestra que el usuario esté dentro de un bus.
enum DetectedMotionActivity: String, Codable, Equatable {

    /// El dispositivo permanece prácticamente inmóvil.
    case stationary

    /// El sistema estima que el usuario está caminando.
    case walking

    /// El sistema estima que el usuario está corriendo.
    case running

    /// El dispositivo se desplaza dentro de algún vehículo.
    ///
    /// Puede tratarse de bus, automóvil, taxi u otro vehículo.
    /// Los filtros GTFS deben determinar si coincide con una ruta.
    case automotive

    /// El sistema estima un desplazamiento en bicicleta.
    case cycling

    /// Core Motion no dispone de evidencia suficiente o reportó
    /// una clasificación con confianza baja.
    case unknown
}

    /// Muestra completa que consume el motor de detección.
    ///
    /// Combina información procedente del GPS, Core Motion y GTFS.
    /// Todas las distancias se expresan en metros.
struct PassengerDetectionSample: Equatable {

    /// Instante de captura en formato UNIX, expresado en segundos.
    let timestamp: TimeInterval

    /// Velocidad estimada por GPS en metros por segundo.
    let speed: Double

    /// Margen de error horizontal reportado por GPS, en metros.
    ///
    /// Cuanto menor sea el valor, mayor es la precisión.
    let horizontalAccuracy: Double

    /// Distancia entre la ubicación y el shape GTFS más próximo.
    let distanceToRoute: Double

    /// Diferencia angular entre el rumbo del dispositivo y el sentido
    /// de la ruta, expresada entre 0 y 180 grados.
    let headingDifference: Double

    /// Distancia al paradero GTFS más próximo, en metros.
    let distanceToNearestStop: Double

    /// Actividad física identificada por Core Motion.
    let motionActivity: DetectedMotionActivity
}

/// Resultado generado después de procesar una muestra.
struct PassengerDetectionDecision: Equatable {

    /// Estado inferido después de analizar la muestra actual.
    let state: PassengerDetectionState

    /// Indica si la muestra puede enviarse como una observación MQTT.
    ///
    /// Solo debe ser verdadero cuando el estado sea `.onboard`.
    let shouldPublish: Bool

    /// Es verdadero únicamente en la transición donde se confirma
    /// un posible abordaje.
    let didConfirmBoarding: Bool

    /// Es verdadero únicamente en la transición donde se confirma
    /// un posible descenso.
    let didConfirmAlighting: Bool
}

/// Umbrales configurables utilizados por el detector.
///
/// Se mantienen agrupados para poder experimentar con diferentes valores
/// sin modificar el algoritmo. Esto también facilitará comparar precisión,
/// falsos positivos y falsos negativos en el artículo científico.
struct PassengerDetectionThresholds {

    /// Máximo error horizontal aceptado, en metros.
    let maximumAccuracy: Double

    /// Máxima separación permitida entre el usuario y el shape GTFS.
    let maximumDistanceToRoute: Double

    /// Máxima diferencia permitida entre el rumbo del usuario y la ruta.
    let maximumHeadingDifference: Double

    /// Distancia máxima para considerar que el usuario está cerca
    /// de un paradero.
    let maximumDistanceToStop: Double

    /// Velocidad mínima considerada vehicular, en metros por segundo.
    let minimumVehicleSpeed: Double

    /// Velocidad máxima aceptada para transporte urbano,
    /// en metros por segundo.
    let maximumVehicleSpeed: Double

    /// Número de muestras vehiculares consecutivas necesarias
    /// para confirmar el abordaje.
    let boardingEvidenceRequired: Int

    /// Número de muestras caminando o corriendo necesarias
    /// para confirmar el descenso.
    let alightingEvidenceRequired: Int

    /// Configuración inicial del MVP.
    ///
    /// Estos valores son hipótesis técnicas y deberán validarse
    /// mediante pruebas de campo.
    static let `default` = PassengerDetectionThresholds(
        maximumAccuracy: 50,
        maximumDistanceToRoute: 40,
        maximumHeadingDifference: 45,
        maximumDistanceToStop: 80,
        minimumVehicleSpeed: 4,
        maximumVehicleSpeed: 30,
        boardingEvidenceRequired: 3,
        alightingEvidenceRequired: 4
    )
}
