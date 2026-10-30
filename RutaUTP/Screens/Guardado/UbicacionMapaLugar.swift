//
//  UbicacionMapaLugar.swift
//  RutaUTP
//
//  Lectura puntual de la ubicación para las hojas de alta de lugar.
//
//  La comparten AddLugarSheet y MapaElegirExpandido.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Una lectura puntual del servicio compartido. La cámara y el pin elegido
/// son estados distintos; una respuesta tardía no deshace un gesto del mapa.
@MainActor
final class UbicacionMapaLugar: ObservableObject {
    @Published private(set) var centro: CLLocationCoordinate2D?
    @Published private(set) var revisionCamara = 0
    @Published private(set) var buscando = false
    @Published private(set) var aviso: String?
    private var tarea: Task<Void, Never>?
    private var revision = UUID()
    private var inicioSolicitado = false
    private var huboInteraccion = false

    deinit { tarea?.cancel() }

    func iniciar(desde service: LocationServiceProtocol) {
        guard !inicioSolicitado else { return }
        inicioSolicitado = true
        if service.authorizationStatus.isAuthorized,
           let lectura = (service as? LocationService)?.lastKnownLocation,
           UbicacionPuntual.esValida(lectura, ahora: Date(), antiguedadMaxima: 30,
                                   precisionMaxima: 3_000) {
            centro = lectura.coordinate
            revisionCamara &+= 1
        }
        buscar(desde: service, automatico: true)
    }

    func buscar(desde service: LocationServiceProtocol, automatico: Bool = false) {
        guard !automatico || !huboInteraccion else { return }
        cancelar()
        buscando = true
        aviso = nil
        let solicitud = revision
        tarea = Task { @MainActor [weak self] in
            // Centrar admite la ubicación aproximada de iOS, como los otros
            // selectores. Esta lectura nunca guarda ni reemplaza el pin.
            let lectura = await UbicacionPuntual.obtener(desde: service, antiguedadMaxima: 30,
                                                       precisionMaxima: 3_000)
            guard let self, !Task.isCancelled, self.revision == solicitud else { return }
            self.tarea = nil
            self.buscando = false
            if let lectura {
                self.centro = lectura.coordinate
                self.revisionCamara &+= 1
            } else {
                self.aviso = service.authorizationStatus.isDenied
                    ? L.t("Activa la ubicación de la app en Ajustes para centrar el mapa.", "Enable the app's location access in Settings to center the map.")
                    : L.t("No pudimos obtener tu ubicación. Vuelve a tocar la flecha.", "We couldn't get your location. Tap the arrow again.")
            }
        }
    }

    func interactuar() {
        huboInteraccion = true
        cancelar()
        aviso = nil
    }

    func cancelar() {
        revision = UUID()
        tarea?.cancel()
        tarea = nil
        if buscando { buscando = false }
    }
}
