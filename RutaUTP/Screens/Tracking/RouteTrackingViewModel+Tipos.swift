//
//  RouteTrackingViewModel+Tipos.swift
//  RutaUTP
//
//  Tipos del modelo de Tracking: destinos del demo, estado de navegación,
//  preferencias persistidas y resumen del viaje terminado.
//

import Foundation
import CoreLocation

extension RouteTrackingViewModel {

    // MARK: - Destinos del demo (sede y referencias del Mapa)

    struct DestinoDemo: Identifiable, Equatable {
        let id: Int
        private let etiquetaOriginal: String
        var label: String {
            if let fijo = DestinosFijos.todos.first(where: { $0.id == id && $0.coordinate.latitude == coordinate.latitude && $0.coordinate.longitude == coordinate.longitude }) {
                return fijo.label
            }
            return etiquetaOriginal
        }
        let icon: String
        let coordinate: CLLocationCoordinate2D

        init(id: Int, label: String, icon: String, coordinate: CLLocationCoordinate2D) {
            self.id = id
            self.etiquetaOriginal = label
            self.icon = icon
            self.coordinate = coordinate
        }

        static func == (lhs: DestinoDemo, rhs: DestinoDemo) -> Bool { lhs.id == rhs.id }
    }

    /// Propiedad CALCULADA, no almacenada: el label sale en el idioma activo
    /// en cada lectura. Antes era un `let` evaluado al crear el VM y dependía
    /// de que RootView reconstruyera el árbol al cambiar de idioma; al quitar
    /// ese `.id()`, un `let` habría quedado congelado en el idioma de arranque.
    /// Las referencias y sus claves señables viven en `DestinosFijos`,
    /// compartido con el Mapa: antes estaban escritos literales en los dos.
    var destinos: [DestinoDemo] {
        let referencias = DestinosFijos.todos.filter { TransporteApp.utpComoReferencia || $0.id != 1 }.map {
            DestinoDemo(id: $0.id, label: $0.label, icon: $0.icono,
                        coordinate: $0.coordinate)
        }
        guard let sede = TransporteApp.sedeVisible else { return referencias }
        return [DestinoDemo(id: CatalogoSedesTrabajo.idChipSede, label: sede.nombre,
                            icon: "building.2.fill", coordinate: sede.coordinate)] + referencias
    }

    // MARK: - Estado de navegación (igual a NavegacionRutaView)

    enum Estado: Equatable {
        case esperandoGPS
        case sinPermiso
        case listo                    // GPS OK, sin viaje iniciado
        case enRuta
        case fueraDeRuta(metros: Double)
        case cercaDestino
        case finalizado
    }

    /// Preferencias del modo demo que sobreviven a salir de la pantalla.
    ///
    /// RootView conserva este modelo al cambiar de pantalla. UserDefaults
    /// mantiene radio y velocidad también al reiniciar la app o crear un modelo
    /// nuevo; la sesión del viaje permanece solo en memoria.
    enum Preferencia: String {
        case radio = "tracking.radioParadero"
        case velocidad = "tracking.velocidadDemo"

        /// Opciones compartidas por la validación y los controles de la vista.
        var valoresPermitidos: [Double] {
            switch self {
            // 1 600 m llega donde el mapa principal ya llega por defecto
            // (`MapaViewModel.radioBusquedaRuta`). Con el tope en 800 el
            // Tracking no encontraba rutas que el mapa sí mostraba, y parecía
            // un fallo del modo de demostración en lugar de un radio corto.
            case .radio: return [200, 500, 800, 1600]
            case .velocidad: return [1, 3, 10]
            }
        }

        var porDefecto: Double {
            switch self {
            case .radio: return 500
            case .velocidad: return 1
            }
        }
    }

    /// Métricas del viaje terminado (las muestra la card de llegada).
    struct ResumenViaje: Equatable {
        let duracionS: TimeInterval
        let distanciaM: Double
        let puntos: Int
        let velocidadKmh: Double
    }
}
