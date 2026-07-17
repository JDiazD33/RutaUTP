//
//  MapaViewModel.swift
//  RutaUTP
//
//  ViewModel del Mapa. Maneja:
//   - region (zoom al destino)
//   - textoBusqueda (binding del TextField)
//   - destinoSeleccionado (chip activo)
//   - busSimulados (6 puntos rojos animados alrededor del destino)
//
//  El timer se inicia al seleccionar destino y se detiene al limpiar
//  o al desaparecer la vista.
//

import SwiftUI
import MapKit
import Combine

// MARK: - Bus simulado
struct BusSimulado: Identifiable, Equatable {
    let id: Int
    var lat: Double
    var lon: Double
    let linea: String
    let colorBus: Color
    var angulo: Double
    let velocidad: Double
}

// MARK: - Destino chip
struct DestinoChip: Identifiable, Equatable {
    let id: Int
    let label: String
    let icon: String
    let lat: Double
    let lon: Double
}

// MARK: - Anotación unificada para el mapa
enum TipoAnotacion: Equatable {
    case utp
    case usuario
    case bus(String)
}

struct MapaAnotacion: Identifiable, Equatable {
    let id: Int
    let lat: Double
    let lon: Double
    let tipo: TipoAnotacion

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - ViewModel
final class MapaViewModel: ObservableObject {

    @Published var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )
    @Published var busSimulados: [BusSimulado] = []
    @Published var textoBusqueda: String = ""
    @Published var destinoSeleccionado: DestinoChip? = nil

    private var timer: Timer?

    // Destinos conocidos
    let destinos: [DestinoChip] = [
        DestinoChip(id: 1, label: "Casa",      icon: "house.fill",         lat: -8.1180, lon: -79.0350),
        DestinoChip(id: 2, label: "UTP",       icon: "graduationcap.fill", lat: -8.1116, lon: -79.0287),
        DestinoChip(id: 3, label: "Trabajo",   icon: "briefcase.fill",     lat: -8.1050, lon: -79.0200),
        DestinoChip(id: 4, label: "Centro",    icon: "building.2.fill",    lat: -8.1090, lon: -79.0270),
        DestinoChip(id: 5, label: "Huanchaco", icon: "water.waves",        lat: -8.0825, lon: -79.1197)
    ]

    // MARK: - Selección
    func seleccionar(destino: DestinoChip) {
        // Evitar re-spawn si ya está seleccionado
        if destinoSeleccionado?.id == destino.id { return }

        withAnimation(.spring(response: 0.5)) {
            destinoSeleccionado = destino
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: destino.lat, longitude: destino.lon),
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        }
        textoBusqueda = destino.label
        spawnBuses(alrededor: destino)
    }

    func buscarTexto(_ texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let match = destinos.first(where: {
            $0.label.lowercased().contains(t.lowercased())
        }) {
            seleccionar(destino: match)
        }
    }

    func limpiar() {
        textoBusqueda = ""
        destinoSeleccionado = nil
        busSimulados = []
        detenerAnimacion()
        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287),
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            )
        }
    }

    // MARK: - Spawn de buses
    private func spawnBuses(alrededor destino: DestinoChip) {
        detenerAnimacion()
        let lineas = ["B", "10", "4", "C", "7", "A"]
        busSimulados = (0..<6).map { i in
            let angulo = Double(i) * 60.0
            let radio = 0.008 + Double.random(in: 0...0.004)
            let rad = angulo * .pi / 180
            return BusSimulado(
                id: i,
                lat: destino.lat + sin(rad) * radio,
                lon: destino.lon + cos(rad) * radio,
                linea: lineas[i % lineas.count],
                colorBus: .appPrimary,
                angulo: angulo,
                velocidad: 0.0001 + Double.random(in: 0...0.00005)
            )
        }
        iniciarAnimacion()
    }

    // MARK: - Timer
    private func iniciarAnimacion() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                for i in self.busSimulados.indices {
                    let rad = self.busSimulados[i].angulo * .pi / 180
                    self.busSimulados[i].lat += sin(rad) * self.busSimulados[i].velocidad
                    self.busSimulados[i].lon += cos(rad) * self.busSimulados[i].velocidad
                    if Double.random(in: 0...1) < 0.002 {
                        self.busSimulados[i].angulo = Double.random(in: 0...360)
                    }
                }
            }
        }
    }

    func detenerAnimacion() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Anotaciones para el mapa
    func anotaciones() -> [MapaAnotacion] {
        var items: [MapaAnotacion] = [
            MapaAnotacion(id: -1, lat: -8.1116, lon: -79.0287, tipo: .utp),
            MapaAnotacion(id: -2, lat: -8.1180, lon: -79.0350, tipo: .usuario),
        ]
        for bus in busSimulados {
            items.append(MapaAnotacion(
                id: 1000 + bus.id,
                lat: bus.lat,
                lon: bus.lon,
                tipo: .bus(bus.linea)
            ))
        }
        return items
    }
}

