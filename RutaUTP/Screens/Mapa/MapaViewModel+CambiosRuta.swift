//
//  MapaViewModel+CambiosRuta.swift
//  RutaUTP
//
//  Cambios de ruta confirmados por la comunidad sobre el mapa principal:
//  qué avisos tocan la ruta mostrada y qué tramo deja de atenderse.
//

import Foundation
import CoreLocation

/// Aviso confirmado listo para dibujar: marcador y, si se conoce, el tramo
/// del recorrido habitual que la línea deja de atender y la calle nueva por
/// la que va ahora.
struct CambioRutaEnMapa: Identifiable {
    let aviso: RouteChangeAlert
    let tramo: [CLLocationCoordinate2D]
    var calleNueva: [CLLocationCoordinate2D] = []
    var id: String { aviso.id }
}

/// Avisos que se consultan a la vez en la hoja de detalle.
struct SeleccionCambiosRuta: Identifiable {
    let avisos: [RouteChangeAlert]
    var id: String { avisos.map(\.id).joined(separator: "|") }
}

extension MapaViewModel {
    /// Sin ruta ni viaje se muestran todos los avisos vigentes, con un tope
    /// para que una jornada con muchos reportes no cubra el mapa.
    static let maximoCambiosSinRuta = 40

    /// Instala los avisos vigentes y decide cuáles se dibujan.
    ///
    /// Con un viaje activo se muestran los de esa línea; con una ruta
    /// calculada, los que tocan lo que el pasajero recorre a bordo; sin
    /// ninguna de las dos, todos. Solo llegan aquí avisos ya confirmados por
    /// el quorum del servidor: un reporte aislado nunca se dibuja.
    func actualizarCambiosRuta(_ avisos: [RouteChangeAlert], rutaViaje: DetectionRouteGeometry?) {
        if cambiosRuta != avisos {
            cambiosRuta = avisos
            cambiosPorOpcion = [:]
        }
        var recorridos = rutasPorId.mapValues(\.shape)
        if let plan = itinerario {
            recorridos[plan.route.id] = plan.route.shape
            if let transfer = plan.transfer { recorridos[transfer.route.id] = transfer.route.shape }
        }
        if let rutaViaje { recorridos[rutaViaje.id] = rutaViaje.shape }

        let visibles: [RouteChangeAlert]
        if let rutaViaje {
            visibles = avisos.filter { aviso in
                let misma = aviso.routeId == rutaViaje.id
                return TramoCambioRuta.afecta(
                    aviso, tramo: misma ? TramoCambioRuta.coordenadas(de: aviso, en: rutaViaje.shape) : nil,
                    recorrido: rutaViaje.shape, mismaRuta: misma)
            }
        } else if let plan = itinerario {
            visibles = cambios(afectando: plan)
        } else {
            visibles = Array(avisos.prefix(Self.maximoCambiosSinRuta))
        }
        cambiosEnMapa = visibles.map { aviso in
            let tramo = recorridos[aviso.routeId].flatMap { TramoCambioRuta.coordenadas(de: aviso, en: $0) }
            return CambioRutaEnMapa(aviso: aviso, tramo: tramo ?? [], calleNueva: aviso.calleNueva)
        }
        // Un aviso que venció no debe seguir abierto como si estuviera vigente.
        if let abiertos = cambiosSeleccionados {
            let vigentes = abiertos.avisos.compactMap { abierto in avisos.first { $0.id == abierto.id } }
            if vigentes.isEmpty {
                cambiosSeleccionados = nil
            } else if vigentes != abiertos.avisos {
                cambiosSeleccionados = SeleccionCambiosRuta(avisos: vigentes)
            }
        }
    }

    /// Avisos confirmados que tocan los tramos en bus de una opción de ruta.
    ///
    /// La geometría a bordo de una opción no cambia al comprobar sus caminatas,
    /// así que el resultado se conserva hasta que cambian los avisos.
    func cambios(afectando plan: TransitItinerary) -> [RouteChangeAlert] {
        guard !cambiosRuta.isEmpty else { return [] }
        let ids: [String]
        if let guardados = cambiosPorOpcion[plan.optionID] {
            ids = guardados
        } else {
            var tramos = [(ruta: plan.route, recorrido: plan.busDibujo)]
            if let transfer = plan.transfer { tramos.append((transfer.route, transfer.busDibujo)) }
            ids = cambiosRuta.filter { aviso in
                tramos.contains { tramo in
                    let misma = aviso.routeId == tramo.ruta.id
                    return TramoCambioRuta.afecta(
                        aviso, tramo: misma ? TramoCambioRuta.coordenadas(de: aviso, en: tramo.ruta.shape) : nil,
                        recorrido: tramo.recorrido, mismaRuta: misma)
                }
            }.map(\.id)
            if cambiosPorOpcion.count > 200 { cambiosPorOpcion = [:] }
            cambiosPorOpcion[plan.optionID] = ids
        }
        return cambiosRuta.filter { ids.contains($0.id) }
    }

    /// Nombre visible de la línea de un aviso; vacío si no está en el catálogo.
    func nombreLinea(delCambio aviso: RouteChangeAlert) -> String {
        if let ruta = rutasPorId[aviso.routeId] { return ruta.lineaConLetra }
        if let plan = itinerario {
            if plan.route.id == aviso.routeId { return plan.route.lineaConLetra }
            if let transfer = plan.transfer, transfer.route.id == aviso.routeId {
                return transfer.route.lineaConLetra
            }
        }
        return ""
    }
}
