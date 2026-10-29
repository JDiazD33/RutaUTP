//
//  MapaViewModel+Busqueda.swift
//  RutaUTP
//
//  Búsqueda de texto, sugerencias de MapKit y selección de destino.
//  El estado compartido sigue en MapaViewModel.swift.
//

import SwiftUI
import MapKit

extension MapaViewModel {
    // MARK: - Búsqueda en tiempo real
    //
    // NO vuelve a asignar `textoBusqueda`: el TextField ya está enlazado a esa
    // propiedad. Reasignarla desde aquí creaba un doble camino sobre el mismo
    // estado y lanzaba consultas de autocompletado incluso cuando el texto lo
    // había puesto el propio código (al elegir un chip o un resultado). El
    // filtro por foco lo aplica la vista, que es quien lo conoce.
    func actualizarTextoBusqueda(_ nuevoTexto: String) {
        let t = nuevoTexto.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            sugerenciasBusqueda = []
            completer.queryFragment = ""
        } else {
            completer.queryFragment = t
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sugerenciasBusqueda = self.completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("[MapaViewModel] MKLocalSearchCompleter error: \(error.localizedDescription)")
        #endif
    }

    // MARK: - Selección y Búsqueda de Destino
    func seleccionar(destino: DestinoChip) {
        invalidarSeleccionAnterior()
        sugerenciasBusqueda = []
        destinoSeleccionado = destino
        let destCoord = CLLocationCoordinate2D(latitude: destino.lat, longitude: destino.lon)
        busquedaResultado = (titulo: destino.label, coordenada: destCoord)
        textoBusqueda = destino.label

        region = MKCoordinateRegion(
            center: destCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
        destinoFocusTick += 1
        calcularRutaHacia(destCoord)
        recargarLineas(cercaDe: destCoord)
    }

    func seleccionarSugerencia(_ completion: MKLocalSearchCompletion) {
        invalidarSeleccionAnterior()
        let revision = selectionRevision
        sugerenciasBusqueda = []
        textoBusqueda = completion.title
        buscando = true

        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        activeSearch = search

        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.selectionRevision == revision else { return }
                self.activeSearch = nil
                self.buscando = false
                if let mapItem = response?.mapItems.first {
                    self.seleccionarLugar(
                        titulo: mapItem.name ?? completion.title,
                        coordenada: mapItem.placemark.coordinate
                    )
                }
            }
        }
    }

    func buscarTexto(_ texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sugerenciasBusqueda = []

        if let match = destinos.first(where: {
            $0.label.compare(t, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            seleccionar(destino: match)
            return
        }

        invalidarSeleccionAnterior()
        let revision = selectionRevision
        buscando = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = t
        request.region = region

        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.selectionRevision == revision else { return }
                self.activeSearch = nil
                self.buscando = false
                if let mapItem = response?.mapItems.first {
                    self.seleccionarLugar(
                        titulo: mapItem.name ?? t,
                        coordenada: mapItem.placemark.coordinate
                    )
                }
            }
        }
    }

    func seleccionarLugar(titulo: String, coordenada: CLLocationCoordinate2D) {
        invalidarSeleccionAnterior()
        textoBusqueda = titulo
        destinoSeleccionado = nil
        busquedaResultado = (titulo: titulo, coordenada: coordenada)

        region = MKCoordinateRegion(
            center: coordenada,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
        destinoFocusTick += 1
        calcularRutaHacia(coordenada)
        recargarLineas(cercaDe: coordenada)
    }
}
