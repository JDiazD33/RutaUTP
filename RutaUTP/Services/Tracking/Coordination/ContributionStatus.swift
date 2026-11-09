//
//  ContributionStatus.swift
//  RutaUTP
//
//  Estado de presentación de la contribución pasiva.
//

import Foundation

/// Estado de presentación; no cambia valores persistidos ni mensajes MQTT.
enum ContributionStatus {
    case disabled, tripEnded, mqttNotConfigured, feedPending, preparing, needsPermission
    case catalogFailure(FalloCargaGTFS?), emptyCatalog, analyzing, noNearbyRoutes
    case waitingForLine(String), probableBoarding(String), detected(String), possibleBoarding(String)
    case alightingTripEnded, alighting, mqttTest(String), pausedBackground
    case noTrip, approachingStop, possibleAlighting

    var message: String {
        switch self {
        case .disabled:
            return L.t("Contribución desactivada", "Contribution off")
        case .waitingForLine(let line):
            return L.f("Esperando detectar el viaje en la línea {0}", "Waiting to detect a trip on line {0}", ["\(line)"])
        case .tripEnded:
            return L.t("Viaje terminado. Indica tu próximo micro para volver a ayudar.", "Trip ended. Select your next bus to contribute again.")
        case .mqttNotConfigured:
            return L.t("Canal MQTT no configurado", "MQTT channel not configured")
        case .feedPending:
            return TransporteApp.mensajePendiente
        case .preparing:
            return L.t("Preparando detección pasiva", "Preparing passive detection")
        case .needsPermission:
            return L.t("Se necesita permiso de ubicación", "Location permission is required")
        case .catalogFailure(let error):
            return error?.mensajeUsuario ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
        case .emptyCatalog:
            return L.t("El catálogo GTFS no contiene rutas", "The GTFS catalog contains no routes")
        case .analyzing:
            return L.t("Analizando movilidad", "Analysing movement")
        case .noNearbyRoutes:
            return L.t("Sin rutas próximas", "No nearby routes")
        case .probableBoarding(let line):
            return L.f("Abordaje probable: línea {0}", "Probable boarding: line {0}", [line])
        case .alightingTripEnded:
            return L.t("Descenso detectado. Viaje terminado.", "Alighting detected. Trip ended.")
        case .alighting:
            return L.t("Descenso detectado", "Alighting detected")
        case .mqttTest(let line):
            return L.f("Prueba MQTT activa: línea {0}", "MQTT test active: line {0}", [line])
        case .pausedBackground:
            return L.t("Publicación pausada: app en segundo plano", "Uploads paused: app in background")
        case .detected(let line):
            return L.f("Viaje detectado en {0}", "Trip detected on {0}", ["\(line)"])
        case .noTrip:
            return L.t("Sin viaje detectado", "No trip detected")
        case .approachingStop:
            return L.t("Cerca de un paradero", "Near a stop")
        case .possibleBoarding(let line):
            return L.f("Posible abordaje en {0}", "Possible boarding on {0}", ["\(line)"])
        case .possibleAlighting:
            return L.t("Comprobando posible descenso", "Checking possible alighting")
        }
    }
}
